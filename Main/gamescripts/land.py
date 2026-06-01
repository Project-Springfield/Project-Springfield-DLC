import xml.etree.ElementTree as ET
import numpy as np
import argparse
from pathlib import Path


# Parse arguments.
parser = argparse.ArgumentParser(
    description="""
    Simple script for helping with editing the landinfo.xml file. It creates a csv spreadsheet which it
    can be edited and the contents can be used to update landinfo.xml.
    """,
    # formatter_class=argparse.ArgumentDefaultsHelpFormatter,
)

parser.add_argument(
    "-r",
    "--reverse",
    help="If set, use the landinfo.csv file to update landinfo.xml.",
    action="store_true",
)

args = parser.parse_args()


if args.reverse is False:

    landfile = Path("landinfo.xml")
    if landfile.exists() is True:
        tree = ET.parse(landfile)
        root = tree.getroot()

        land = next(root.iter("LandCost"))
        width = land.get("width")
        height = land.get("height")
        value = [i.strip().strip("*:") for i in land.get("value").split(',')]

        if value and value[-1] == "":
            value.pop()

        data = np.flip(np.array(value, dtype=str).reshape(int(height), int(width)).transpose(), 0)
        np.savetxt('landinfo.csv', data, fmt = '%s')

else:
    landfile = Path("landinfo.xml")
    landcsv = Path("landinfo.csv")

    if landfile.exists() is True and landcsv.exists() is True:
        data = np.loadtxt(landcsv, dtype="str")
        width = data.shape[0]
        height = data.shape[1]

        value = [f"*:{i}" for i in np.flip(data, 0).transpose().flatten()]
        reference = np.argwhere(data == "h_s2_5")
        offset_x = reference[0][0] + 1 - width
        offset_y = -(reference[0][1] + 4)

        tree = ET.parse(landfile)
        root = tree.getroot()

        land = next(root.iter("LandBlockSize"))
        land.set("x", str(width))
        land.set("y", str(height))

        land = next(root.iter("LandBlockPosition"))
        land.set("x", str(offset_x))
        land.set("y", str(offset_y))

        land = next(root.iter("LandCost"))
        land.set("width", str(width))
        land.set("height", str(height))
        land.set("value", ", ".join(value))

        for element in root.find("LandInfo").iter("RoadMap"):
            if element.attrib["layer"] != "0":
                element.set("size", f"{width + offset_x},{height}")


        tree.write(landfile)
