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

uniform lowp vec4 vec4Param1; // Color to colorize
uniform lowp vec4 vec4Param2; // X is the min hue range and Y is the max hue range to exclude from colorizing

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
    
    float min = min( min(lDiffuseColour.r, lDiffuseColour.g), lDiffuseColour.b );
    float max = max( max(lDiffuseColour.r, lDiffuseColour.g), lDiffuseColour.b );
    
    float delta = max - min;
    float s = max != 0.0 ? delta / max : 0.0;
    
    vec2 diff = lDiffuseColour.gg - lDiffuseColour.rb;
    if( diff.x < vec4Param2.x || diff.y < vec4Param2.y || s < vec4Param2.z )
    {
        lDiffuseColour.rgb = lDiffuseColour.rgb * vec4Param1.rgb;
    }
	
	gl_FragColor = lDiffuseColour;
}
