// 沿着边框裁剪输入
// 默认四周各裁剪一个像素。如果需要更改裁剪的像素数，需要更改代码，不支持通过参数更改
// 注意：虽然画面被裁剪了，但光标区域没有被裁剪，裁剪太多会出现光标位置不准的问题

// 假设左上右下方向分别需要裁剪 {left}, {top}, {right}, {bottom} 个像素数
// 将第 13 行改为 //!OUTPUT_WIDTH INPUT_WIDTH - {left} - {right}
// 将第 14 行改为 //!OUTPUT_HEIGHT INPUT_HEIGHT - {top} - {bottom}
// 将第 17 行改为 #define LEFT {left}
// 将第 18 行改为 #define TOP {top}

//!MAGPIE EFFECT
//!VERSION 1
//!OUTPUT_WIDTH INPUT_WIDTH - 2
//!OUTPUT_HEIGHT INPUT_HEIGHT - 2

//!COMMON
#define LEFT 1
#define TOP 1

//!CONSTANT
//!VALUE INPUT_PT_X
float inputPtX;

//!CONSTANT
//!VALUE INPUT_PT_Y
float inputPtY;

//!CONSTANT
//!VALUE OUTPUT_WIDTH
float outputWidth;

//!CONSTANT
//!VALUE OUTPUT_HEIGHT
float outputHeight;


//!TEXTURE
Texture2D INPUT;

//!SAMPLER
//!FILTER POINT
SamplerState sam;


//!PASS 1
//!BIND INPUT

float4 Pass1(float2 pos) {
	float2 originPos = pos * float2(outputWidth, outputHeight) + float2(LEFT, TOP);
	return INPUT.Sample(sam, originPos * float2(inputPtX, inputPtY));
}
