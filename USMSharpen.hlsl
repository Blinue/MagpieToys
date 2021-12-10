// 使用非锐化掩膜(Unsharp masking)锐化图像
// https://en.wikipedia.org/wiki/Unsharp_masking

//!MAGPIE EFFECT
//!VERSION 1
//!OUTPUT_WIDTH INPUT_WIDTH
//!OUTPUT_HEIGHT INPUT_HEIGHT

//!CONSTANT
//!VALUE INPUT_PT_X
float inputPtX;

//!CONSTANT
//!VALUE INPUT_PT_Y
float inputPtY;

//!CONSTANT
//!DEFAULT 0.5
//!MIN 0
float sharpness;

//!CONSTANT
//!DEFAULT 0.1
//!MIN 0
//!MAX 1
float threshold;

//!TEXTURE
Texture2D INPUT;

//!SAMPLER
//!FILTER POINT
SamplerState sam;


//!PASS 1
//!BIND INPUT

const static float3x3 _rgb2yuv = {
	0.299, 0.587, 0.114,
	-0.169, -0.331, 0.5,
	0.5, -0.419, -0.081
};

const static float3x3 _yuv2rgb = {
	1, -0.00093, 1.401687,
	1, -0.3437, -0.71417,
	1, 1.77216, 0.00099
};

float getY(float4 rgba) {
	return 0.299f * rgba.x + 0.587f * rgba.y + 0.114f * rgba.z;
}

float4 Pass1(float2 pos) {
	float3 curYuv = mul(_rgb2yuv, INPUT.Sample(sam, pos).rgb) + float3(0, 0.5, 0.5);
	
	// [tl, tc, tr]
	// [ml, mc, mr]
	// [bl, bc, br]
	float tl = getY(INPUT.Sample(sam, pos + float2(-inputPtX, -inputPtY)));
	float ml = getY(INPUT.Sample(sam, pos + float2(-inputPtX, 0)));
	float bl = getY(INPUT.Sample(sam, pos + float2(-inputPtX, inputPtY)));
	float tc = getY(INPUT.Sample(sam, pos + float2(0, -inputPtY)));
	float mc = curYuv.x;
	float bc = getY(INPUT.Sample(sam, pos + float2(0, inputPtY)));
	float tr = getY(INPUT.Sample(sam, pos + float2(inputPtX, -inputPtY)));
	float mr = getY(INPUT.Sample(sam, pos + float2(inputPtX, 0)));
	float br = getY(INPUT.Sample(sam, pos + float2(inputPtX, inputPtY)));
	
	float blurred = (tl + 2 * tc + tr + 2 * ml + 4 * mc + 2 * mr + bl + 2 * bc + br) / 16;
	
	float dif = curYuv.x - blurred;
	if(dif > threshold) {
		curYuv.x = saturate(curYuv.x + dif * sharpness);
	}
	
	return float4(mul(_yuv2rgb, curYuv - float3(0, 0.5, 0.5)), 1);
}
