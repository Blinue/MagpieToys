// 曼德博集合
// 移植自 https://www.shadertoy.com/view/sdKSD3

//!MAGPIE EFFECT
//!VERSION 1


//!CONSTANT
//!VALUE OUTPUT_WIDTH / OUTPUT_HEIGHT
float ratio;

//!CONSTANT
//!DYNAMIC
//!VALUE FRAME_COUNT
int frameCount;


//!PASS 1

int mandelbrot(float2 c) {
	float2 z = c;
	for (int i = 0; i < 1500; i++) {
		if (dot(z, z) > 4.0) return i;
		z = float2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
	}
	return 0;
}

float zoom(float t) {
	float a = floor(t / 24.0f);
	return (exp(-t + 24.0 * a) + exp(t - 24.0 - 24.0 * a));
}

float4 Pass1(float2 pos) {
	pos = pos * 2 - 1;
	pos.x *= ratio;

	float2 c = (pos * 2.0) * zoom(frameCount / 100.0f);
	c += float2(-1.253443441, 0.384693578);
	float iters = float(mandelbrot(c));

	float3 col = sin(float3(0.1, 0.2, 0.5) * float(iters));
	return float4(col, 1.0);
}
