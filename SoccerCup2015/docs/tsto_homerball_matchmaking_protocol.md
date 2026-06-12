# Tap Ball / Soccer Cup 2015 — Matchmaking protocol (`/mh/match`)

Reference for implementing Homerball (Tap Ball) matchmaking on a private TSTO
server. RE'd from the **4.15 client** (`libscorpio`, `BightGames::GameClient::findMatch`
/ `FindMatchTask`) and verified live against the C++ server. Includes **Django**
examples that fit `workingpyserver/springfield/mh/`.

> **TL;DR — it is ASYNCHRONOUS PvP.** The opponent never plays live. The client
> asks the server for an opponent, the server returns **a snapshot of some other
> player's town** (their roster), and the game's AI plays that roster as the
> "passive" team. The opponent does **not** need to be online. The result is
> later delivered to the opponent as a **friend-event** so it shows in their
> Career Stats (`PassiveMatches`).

---

## 1. Endpoints

| Method   | Path                                        | Meaning                              |
| -------- | ------------------------------------------- | ------------------------------------ |
| `POST`   | `/mh/match`  ·  `/mh/match/`                 | **findMatch** — return an opponent   |
| `DELETE` | `/mh/match/<category>/<landId>/`            | **unregister** — leaving matchmaking |

The client registers + requests in a single `POST` (each findMatch re-registers
the caller). The `DELETE` fires when the match ends / the player backs out — it
is **not** a find; just answer `200` empty. (On a catch-all `Any` route the
`DELETE` will wrongly run a find and re-match a random town — guard on the method.)

Content types: request `application/x-protobuf`, response `application/x-protobuf`.

Auth: standard `mh` headers (`nucleus_token` / `mh_auth_params` = `AT0:…`,
`mh_uid`, `mh_session_key`, `currentClientSessionId`). Resolve the caller the
same way the other `mh` views do — via `currentClientSessionId` → `DeviceToken`.

---

## 2. Request — `MatchmakingRegistration`

The POST body is a serialized **`Data.ExtraLandMessage.MatchmakingRegistration`**
(sent on its own, not wrapped):

```proto
// LandData.proto
message ExtraLandMessage {
  // ...
  message MatchmakingRegistration {
    optional string category = 1;          // e.g. "Homerball2015"
    repeated .Data.NameValue params = 2;   // match criteria
  }
}
// Common.proto
message NameValue {
  optional string name  = 1;
  optional string value = 2;
}
```

For Homerball the only registered param is **`team_rating`** — the caller's
team strength, defined in `june2015_matchmakingconfig.xml` as:

```
team_rating = TopAthleteOne + TopAthleteTwo + TopAthleteThree + TopAthleteFour
```

(the sum of the levels of the player's 4 active athletes). Registration
requirements EA enforced (so a player is even eligible to be an opponent):
`HomerballPitch` built **and** the `CanPlayHomerball` shared variable true.

Parse it (Django):

```python
from protofiles import LandData_pb2

reg = LandData_pb2.ExtraLandMessage.MatchmakingRegistration()
reg.ParseFromString(request.body)            # body is the registration itself
category = reg.category                       # "Homerball2015"
team_rating = 0
for p in reg.params:
    if p.name == "team_rating":
        team_rating = int(p.value or 0)
```

---

## 3. Response — `MatchmakingResponseMessage`

Return the **opponent's whole town** (`LandMessage`) so the client can spawn
their roster as the passive team:

```proto
// MatchmakingData.proto
message MatchmakingResponseMessage {
  optional .Data.LandMessage matchedUserLand = 1;   // the opponent's town
  optional .Data.ErrorMessage error          = 2;   // omit on success
}
```

- **Success:** `200`, body = `MatchmakingResponseMessage{ matchedUserLand = <opponent town> }`.
- **No opponent available:** `404` with an empty body (client shows "couldn't find a match").

Build it (Django) — `MatchmakingData_pb2` is already generated:

```python
from protofiles import MatchmakingData_pb2, LandData_pb2

opp_land = LandData_pb2.LandMessage()
opp_land.ParseFromString(load_town(opponent_user))   # opponent_user.town bytes

resp = MatchmakingData_pb2.MatchmakingResponseMessage()
resp.matchedUserLand.CopyFrom(opp_land)
return HttpResponse(resp.SerializeToString(), content_type="application/x-protobuf")
```

---

## 4. Opponent selection (EA's model)

EA matched from a **pool of registered town snapshots**, picking one with a
**similar `team_rating`** — online status irrelevant. Recommended order:

1. **Eligible pool** = other users who have a saved town (and ideally a Homerball
   roster / `CanPlayHomerball`). Exclude the caller.
2. **Pick by closest `team_rating`** (a live/online player can be a tiebreaker
   or freshness boost, never a requirement).
3. **Fallbacks** so a match always boots: any town with real content → finally
   the caller's own town (it has the pitch, so the match still starts).

The town must have actual map content (placed buildings/characters) — a skeleton
starter town makes the client load an empty pitch.

---

## 5. Full Django view (`mh/views.py`)

```python
from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from django.views.decorators.csrf import csrf_exempt
from connect.models import DeviceToken, UserId
from protofiles import LandData_pb2, MatchmakingData_pb2
import uuid

def _team_rating(land: "LandData_pb2.LandMessage") -> int:
    """Opponent's team strength. Adapt to wherever you persist the Homerball
    shared vars (TopAthleteOne..Four). If you don't store them per-town yet,
    return 0 and matching degrades to 'any eligible town' — still correct."""
    return 0

@csrf_exempt
def find_match(request, *_args, **_kwargs):
    # DELETE /mh/match/<category>/<landId>/ -> unregister. Not a find.
    if request.method == "DELETE":
        return HttpResponse(status=200)

    # 1) Resolve caller (same pattern as users()/friendData()).
    caller = None
    try:
        sid = uuid.UUID(request.headers.get("currentClientSessionId"))
        caller = get_object_or_404(DeviceToken, current_client_session_id=sid).user
    except Exception:
        caller = None

    # 2) Read the caller's team_rating from the registration body.
    caller_rating = 0
    try:
        reg = LandData_pb2.ExtraLandMessage.MatchmakingRegistration()
        reg.ParseFromString(request.body)
        for p in reg.params:
            if p.name == "team_rating":
                caller_rating = int(p.value or 0)
    except Exception:
        pass

    # 3) Build the candidate pool: users with a saved town, excluding the caller.
    pool = UserId.objects.exclude(town="").exclude(town__isnull=True)
    if caller is not None:
        pool = pool.exclude(pk=caller.pk)

    # 4) Pick the closest team_rating that loads with real content.
    best, best_land, best_diff = None, None, None
    for u in pool.iterator():
        try:
            land = LandData_pb2.LandMessage()
            land.ParseFromString(load_town(u))
        except Exception:
            continue
        if not (land.buildingData or land.characterData):   # must have content
            continue
        diff = abs(_team_rating(land) - caller_rating)
        if best_diff is None or diff < best_diff:
            best, best_land, best_diff = u, land, diff

    # 5) Fallback: the caller's own town so the match always boots.
    if best_land is None and caller is not None:
        best_land = LandData_pb2.LandMessage()
        best_land.ParseFromString(load_town(caller))

    if best_land is None:
        return HttpResponse(status=404)   # no opponent -> client shows "no match"

    resp = MatchmakingData_pb2.MatchmakingResponseMessage()
    resp.matchedUserLand.CopyFrom(best_land)
    return HttpResponse(resp.SerializeToString(),
                        content_type="application/x-protobuf")
```

`mh/urls.py` — register all three shapes (catch-all so the `DELETE` suffix lands here):

```python
path("match",    views.find_match, name="find_match"),
path("match/",   views.find_match, name="find_match_slash"),
re_path(r"^match/.*$", views.find_match, name="find_match_any"),   # DELETE .../<cat>/<landId>/
# (add `from django.urls import re_path`)
```

---

## 6. Result write-back (so Career Stats fills)

This is what "completes" async PvP. After an away match the **client** emits the
result as a **friend-event** addressed to the opponent (`saveFriendAction
specialEvent="Homerball" buffer="PassiveMatches"` + `sendPeerNotification
PlayedOpponent`). Your server **already stores this** — it's the same path as
`event_user`:

```python
# /mh/games/bg_gameserver_plugin/event/<mayhem_id>/protoland/  (POST)
event_request = LandData_pb2.EventMessage()
event_request.ParseFromString(request.body)
event_request.id = str(uuid.uuid4())
event_request.fromPlayerId = str(mayhem_id)
target = get_object_or_404(UserId, mayhem_id=uuid.UUID(int=int(event_request.toPlayerId)))
events = LandData_pb2.EventsMessage()
events.ParseFromString(target.events)
events.event.extend([event_request])
target.events = events.SerializeToString()
target.save(update_fields=["events"])
```

So no extra server endpoint is needed for results — the opponent reads their
`events` on login and the `PassiveMatches` history (and Career Stats) fills in.
The remaining work is **client-side DLC**: re-emit `saveFriendAction` from the
match-end scripts (the restored event currently bypasses it).

---

## 7. Quick reference

| Thing                | Value                                                            |
| -------------------- | ---------------------------------------------------------------- |
| Category             | `Homerball2015`                                                  |
| Find request         | `POST /mh/match/` · body `ExtraLandMessage.MatchmakingRegistration` |
| Find response        | `MatchmakingResponseMessage{ matchedUserLand: LandMessage }`     |
| Unregister           | `DELETE /mh/match/<category>/<landId>/` → `200` empty            |
| Match param          | `team_rating` = sum of top-4 athlete levels                     |
| Eligibility          | has `HomerballPitch` + `CanPlayHomerball` (shared var)          |
| Online required?     | **No** — async; opponent is a stored town snapshot              |
| Result delivery      | friend-event → opponent's `user.events` (`PassiveMatches`)      |
