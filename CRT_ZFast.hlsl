// CRT-ZFast
// 移植自 https://github.com/libretro/glsl-shaders/blob/master/crt/shaders/zfast_crt.glsl
// 只支持整数倍缩放

/*
	zfast_crt_standard - A simple, fast CRT shader.
	Copyright (C) 2017 Greg Hogan (SoltanGris42)
	This program is free software; you can redistribute it and/or modify it
	under the terms of the GNU General Public License as published by the Free
	Software Foundation; either version 2 of the License, or (at your option)
	any later version.
Notes:  This shader does scaling with a weighted linear filter for adjustable
	sharpness on the x and y axes based on the algorithm by Inigo Quilez here:
	http://http://www.iquilezles.org/www/articles/texture/texture.htm
	but modified to be somewhat sharper.  Then a scanline effect that varies
	based on pixel brighness is applied along with a monochrome aperture mask.
	This shader runs at 60fps on the Raspberry Pi 3 hardware at 2mpix/s
	resolutions (1920x1080 or 1600x1200).
*/

//!MAGPIE EFFECT
//!VERSION 2


//!PARAMETER
//!DEFAULT 1
//!MIN 0
//!MAX 1
int fineMask;

//!PARAMETER
//!DEFAULT 0.3
//!MIN 0
//!MAX 1
float blurScaleX;

//!PARAMETER
//!DEFAULT 6
//!MIN 0
//!MAX 10
float lowLumScan;

//!PARAMETER
//!DEFAULT 8
//!MIN 0
//!MAX 50
float hiLumScan;

//!PARAMETER
//!DEFAULT 1.25
//!MIN 0.5
//!MAX 1.5
float brightBoost;

//!PARAMETER
//!DEFAULT 0.25
//!MIN 0
//!MAX 1
float maskDark;

//!PARAMETER
//!DEFAULT 0.8
//!MIN 0
//!MAX 1
float maskFade;


//!TEXTURE
Texture2D INPUT;

//!SAMPLER
//!FILTER LINEAR
SamplerState sam;


//!PASS 1
//!STYLE PS
//!IN INPUT

float4 Pass1(float2 pos) {
	//This is just like "Quilez Scaling" but sharper
	float2 p = pos * GetInputSize();
	float2 i = floor(p) + 0.50;
	float2 f = p - i;
	p = (i + 4.0 * f * f * f) * GetInputPt();
	p.x = lerp(p.x, pos.x, blurScaleX);
	float Y = f.y * f.y;
	float YY = Y * Y;

	float whichmask;
	float mask;

	if (fineMask != 0) {
		whichmask = frac(floor(pos.x * GetOutputSize().x) * -0.4999);
		mask = 1.0 + float(whichmask < 0.5) * -maskDark;
	} else {
		whichmask = frac(floor(pos.x * GetOutputSize().x) * -0.3333);
		mask = 1.0 + float(whichmask <= 0.33333) * -maskDark;
	}

	float3 colour = INPUT.SampleLevel(sam, p, 0).rgb;

	float scanLineWeight = (brightBoost - lowLumScan * (Y - 2.05 * YY));
	float scanLineWeightB = 1.0 - hiLumScan * (YY - 2.8 * YY * Y);

	return float4(colour.rgb * lerp(scanLineWeight * mask, scanLineWeightB, dot(colour.rgb, 0.3333 * maskFade)), 1.0);
}
