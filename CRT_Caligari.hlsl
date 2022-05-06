// CRT-Caligari
// 移植自 https://github.com/libretro/common-shaders/blob/master/crt/shaders/crt-caligari.cg
// 要求整数倍缩放

/*
	Phosphor shader - Copyright (C) 2011 caligari.

	Ported by Hyllian.

   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License
   as published by the Free Software Foundation; either version 2
   of the License, or (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

*/


//!MAGPIE EFFECT
//!VERSION 2


//!PARAMETER
//!DEFAULT 0.5
//!MIN 0.1
//!MAX 1.5
float spotWidth;

//!PARAMETER
//!DEFAULT 0.5
//!MIN 0.1
//!MAX 1.5
float spotHeight;

//!PARAMETER
//!DEFAULT 1.45
//!MIN 1
//!MAX 2
float colorBoost;

//!PARAMETER
//!DEFAULT 2.4
//!MIN 0
//!MAX 5
float inputGamma;

//!PARAMETER
//!DEFAULT 2.2
//!MIN 0
//!MAX 5
float outputGamma;


//!TEXTURE
Texture2D INPUT;

//!SAMPLER
//!FILTER POINT
SamplerState sam;


//!PASS 1
//!STYLE PS
//!IN INPUT

#define GAMMA_IN(color)     pow(color, inputGamma)
#define GAMMA_OUT(color)    pow(color, 1.0 / outputGamma)

#define TEX2D(coords)	GAMMA_IN( INPUT.SampleLevel(sam, coords, 0) )

// Macro for weights computing
#define WEIGHT(w) \
	if(w>1.0) w=1.0; \
	w = 1.0 - w * w; \
	w = w * w;

float4 Pass1(float2 pos) {
	const float2 inputPt = GetInputPt();

	float2 onex = float2(inputPt.x, 0.0);
	float2 oney = float2(0.0, inputPt.y);

	float2 coords = pos * GetInputSize();
	float2 pixel_center = floor(coords) + 0.5f;
	float2 texture_coords = pixel_center * inputPt;

	float4 color = TEX2D(texture_coords);

	float dx = coords.x - pixel_center.x;

	float h_weight_00 = dx / spotWidth;
	WEIGHT(h_weight_00);

	color *= h_weight_00;

	// get closest horizontal neighbour to blend
	float2 coords01;
	if (dx > 0.0) {
		coords01 = onex;
		dx = 1.0 - dx;
	} else {
		coords01 = -onex;
		dx = 1.0 + dx;
	}
	float4 colorNB = TEX2D(texture_coords + coords01);

	float h_weight_01 = dx / spotWidth;
	WEIGHT(h_weight_01);

	color = color + colorNB * h_weight_01;

	//////////////////////////////////////////////////////
	// Vertical Blending
	float dy = coords.y - pixel_center.y;
	float v_weight_00 = dy / spotHeight;
	WEIGHT(v_weight_00);
	color *= v_weight_00;

	// get closest vertical neighbour to blend
	float2 coords10;
	if (dy > 0.0) {
		coords10 = oney;
		dy = 1.0 - dy;
	} else {
		coords10 = -oney;
		dy = 1.0 + dy;
	}
	colorNB = TEX2D(texture_coords + coords10);

	float v_weight_10 = dy / spotHeight;
	WEIGHT(v_weight_10);

	color += colorNB * v_weight_10 * h_weight_00;

	colorNB = TEX2D(texture_coords + coords01 + coords10);

	color += colorNB * v_weight_10 * h_weight_01;

	color *= colorBoost;

	return clamp(GAMMA_OUT(color), 0.0, 1.0);
}
