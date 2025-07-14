/*
 *  BGCore
 *  
 *  Sources may not be modified, distributed, copied, or compiled
 *  in partial or in full, without explicit written approval from
 *  Bight Interactive Inc.
 *
 *  Copyright 2006-2011 Bight Interactive Inc. All rights reserved.
 *
 */


precision mediump float;
precision mediump int;

varying vec2 v_texCoord;
varying vec2 v_texCoord2;
varying vec2 v_Depth;

uniform lowp vec4 vec4Param1;

//needed for knowing NDC (Normalized Device Coordinates - passed in from Game)
uniform lowp vec2 OneOverScreenDims;


#ifdef DIFFUSETEXTURE
uniform lowp sampler2D diffuseTexture;
#endif

#ifdef BLENDTEXTURE
uniform lowp sampler2D blendTexture;
#endif

#ifdef DIFFUSEVERTEX
varying lowp vec4 v_vertexColour;
#endif

#ifdef DIFFUSEUNIFORM
uniform lowp vec4 diffuseColour;
#endif

#ifdef ALPHA_TEST
uniform float gAlphaTestVal;
#endif 

lowp vec4 GetDiffuseColour()
{
	lowp vec4 lColour; 
	#ifdef DIFFUSETEXTURE
		
		// Get the colour from the texture
		lColour = texture2D(diffuseTexture, v_texCoord);
		#ifdef USING_SINGLE_COMPONENT_DIFFUSE_TEXTURE
			lColour.rgb = vec3(1.0, 1.0, 1.0);
		#endif
		
		#ifdef DIFFUSEVERTEX
			lColour *= v_vertexColour;
		#endif
		#ifdef DIFFUSEUNIFORM
			lColour *= diffuseColour;
		#endif
	#elif defined(DIFFUSEVERTEX)
		lColour = v_vertexColour;
	#elif defined(DIFFUSEUNIFORM)
		lColour = diffuseColour;
	#else
		lColour = vec4(1.0, 1.0, 1.0, 1.0);
	#endif
	return lColour;
}

#if defined(BLENDTEXTURE)
lowp vec4 GetBlendColour()
{
	lowp vec4 lBlendColour;
	lBlendColour = texture2D(blendTexture, v_texCoord);
	#ifdef USING_SINGLE_COMPONENT_BLEND_TEXTURE
		lBlendColour.rgb = lowp vec3(1.0, 1.0, 1.0);
	#endif
		
	return lBlendColour;
}
#endif

// The following functions are from:
//http://lolengine.net/blog/2013/07/27/rgb-to-hsv-in-glsl
vec3 rgb2hsv(vec3 c)
{
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = c.g < c.b ? vec4(c.bg, K.wz) : vec4(c.gb, K.xy);
    vec4 q = c.r < p.x ? vec4(p.xyw, c.r) : vec4(c.r, p.yzx);

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void main()
{
	lowp vec4 lDiffuseColour = GetDiffuseColour();
	
#if defined (ALPHA_TEST)
	if(lDiffuseColour.a < gAlphaTestVal)
		discard;
#endif
	
#ifdef BLENDTEXTURE
	lowp vec4 lBlendColour = GetBlendColour();
	lDiffuseColour += ((lBlendColour * 0.30) - 0.15);
	lDiffuseColour.a *= lBlendColour.a;
#endif

        //calculate NDC
	vec2 NDC = gl_FragCoord.xy * OneOverScreenDims;
	NDC *= 2.0;
	NDC -= 1.0;
	NDC.y = NDC.y / OneOverScreenDims.y * OneOverScreenDims.x;

	float distSq = NDC.x*NDC.x + NDC.y*NDC.y;

	// Heavy bands, but much slower
	//lDiffuseColour.r = sin((distSq)*10.0 - 1.6 + 2.6) * lDiffuseColour.a;
	//lDiffuseColour.g = sin((distSq)*10.0 + 2.0 + 2.6) * lDiffuseColour.a;
	//lDiffuseColour.b = sin((distSq)*10.0 + 0.2 + 2.6) * lDiffuseColour.a;

	// Fast, but numbers aren't balanced right, just get a lot of fuzz
	//lDiffuseColour.r = (distSq)*1.5 * lDiffuseColour.a;
	//lDiffuseColour.g = (1.0-abs(distSq - 0.70)*1.5) * lDiffuseColour.a;
	//lDiffuseColour.b = (1.0-abs(distSq - 0.85)*1.5) * lDiffuseColour.a;

	vec3 hsvColor = vec3( (distSq * vec4Param1.w) + vec4Param1.x, vec4Param1.y, vec4Param1.z );
	lDiffuseColour.rgb = hsv2rgb(hsvColor) * lDiffuseColour.a;
	
	gl_FragColor = lDiffuseColour;
}

