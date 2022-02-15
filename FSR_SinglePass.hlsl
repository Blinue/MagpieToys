// 将 EASU 和 RCAS 合并
// 性能不如两个单独的 Pass！
// 此文件不能在 Magpie 中使用

cbuffer cb : register(b0) {
	float inputWidth;
	float inputHeight;
	float outputWidth;
	float outputHeight;
	float4 sharpness;	// 对齐 32 位边界
	uint4 viewport;
};

SamplerState sam : register(s0);

Texture2D INPUT : register(t0);
RWTexture2D<float4> OUTPUT : register(u0);

#define THREAD_GROUP_SIZE 128
#define BLOCK_WIDTH 32
#define BLOCK_HEIGHT 24
#define PAD_SIZE_ORIGIN 4
#define PAD_SIZE_EASU 2
#define TILE_PITCH_ORIGIN (BLOCK_WIDTH + PAD_SIZE_ORIGIN)
#define TILE_PITCH_EASU (BLOCK_WIDTH + PAD_SIZE_EASU)
groupshared float3 shOriginPixels[TILE_PITCH_ORIGIN * (BLOCK_HEIGHT + PAD_SIZE_ORIGIN)];
groupshared float3 shEasuPixels[TILE_PITCH_EASU * (BLOCK_HEIGHT + PAD_SIZE_EASU)];


#define LoadFromShOriginPixels(posX, posY) (shOriginPixels[(posY) * TILE_PITCH_ORIGIN + (posX)])
#define LoadFromShEasuPixels(posX, posY) (shEasuPixels[(posY) * TILE_PITCH_EASU + (posX)])

#define min3(a, b, c) min(a, min(b, c))
#define max3(a, b, c) max(a, max(b, c))

// This is set at the limit of providing unnatural results for sharpening.
#define FSR_RCAS_LIMIT (0.25-(1.0/16.0))


// Filtering for a given tap for the scalar.
void FsrEasuTap(
	inout float3 aC, // Accumulated color, with negative lobe.
	inout float aW, // Accumulated weight.
	float2 off, // Pixel offset from resolve position to tap.
	float2 dir, // Gradient direction.
	float2 len, // Length.
	float lob, // Negative lobe strength.
	float clp, // Clipping point.
	float3 c // Tap color.
) {
	// Rotate offset by direction.
	float2 v;
	v.x = (off.x * (dir.x)) + (off.y * dir.y);
	v.y = (off.x * (-dir.y)) + (off.y * dir.x);
	// Anisotropy.
	v *= len;
	// Compute distance^2.
	float d2 = v.x * v.x + v.y * v.y;
	// Limit to the window as at corner, 2 taps can easily be outside.
	d2 = min(d2, clp);
	// Approximation of lanczos2 without sin() or rcp(), or sqrt() to get x.
	//  (25/16 * (2/5 * x^2 - 1)^2 - (25/16 - 1)) * (1/4 * x^2 - 1)^2
	//  |_______________________________________|   |_______________|
	//                   base                             window
	// The general form of the 'base' is,
	//  (a*(b*x^2-1)^2-(a-1))
	// Where 'a=1/(2*b-b^2)' and 'b' moves around the negative lobe.
	float wB = 2.0f / 5.0f * d2 - 1;
	float wA = lob * d2 - 1;
	wB *= wB;
	wA *= wA;
	wB = 25.0f / 16.0f * wB - (25.0f / 16.0f - 1.0f);
	float w = wB * wA;
	// Do weighted average.
	aC += c * w;
	aW += w;
}

// Accumulate direction and length.
void FsrEasuSet(
	inout float2 dir,
	inout float len,
	float2 pp,
	bool biS, bool biT, bool biU, bool biV,
	float lA, float lB, float lC, float lD, float lE) {
	// Compute bilinear weight, branches factor out as predicates are compiler time immediates.
	//  s t
	//  u v
	float w = 0;
	if (biS)
		w = (1 - pp.x) * (1 - pp.y);
	if (biT)
		w = pp.x * (1 - pp.y);
	if (biU)
		w = (1.0 - pp.x) * pp.y;
	if (biV)
		w = pp.x * pp.y;
	// Direction is the '+' diff.
	//    a
	//  b c d
	//    e
	// Then takes magnitude from abs average of both sides of 'c'.
	// Length converts gradient reversal to 0, smoothly to non-reversal at 1, shaped, then adding horz and vert terms.
	float dc = lD - lC;
	float cb = lC - lB;
	float lenX = max(abs(dc), abs(cb));
	lenX = rcp(lenX);
	float dirX = lD - lB;
	dir.x += dirX * w;
	lenX = saturate(abs(dirX) * lenX);
	lenX *= lenX;
	len += lenX * w;
	// Repeat for the y axis.
	float ec = lE - lC;
	float ca = lC - lA;
	float lenY = max(abs(ec), abs(ca));
	lenY = rcp(lenY);
	float dirY = lE - lA;
	dir.y += dirY * w;
	lenY = saturate(abs(dirY) * lenY);
	lenY *= lenY;
	len += lenY * w;
}


float3 FsrEasuF(float2 pp, uint2 fp) {
	// 12-tap kernel.
	//    b c
	//  e f g h
	//  i j k l
	//    n o
	float3 bc = LoadFromShOriginPixels(fp.x, fp.y - 1);
	float3 cc = LoadFromShOriginPixels(fp.x + 1, fp.y - 1);
	float3 ec = LoadFromShOriginPixels(fp.x - 1, fp.y);
	float3 fc = LoadFromShOriginPixels(fp.x, fp.y);
	float3 gc = LoadFromShOriginPixels(fp.x + 1, fp.y);
	float3 hc = LoadFromShOriginPixels(fp.x + 2, fp.y);
	float3 ic = LoadFromShOriginPixels(fp.x - 1, fp.y + 1);
	float3 jc = LoadFromShOriginPixels(fp.x, fp.y + 1);
	float3 kc = LoadFromShOriginPixels(fp.x + 1, fp.y + 1);
	float3 lc = LoadFromShOriginPixels(fp.x + 2, fp.y + 1);
	float3 nc = LoadFromShOriginPixels(fp.x, fp.y + 2);
	float3 oc = LoadFromShOriginPixels(fp.x + 1, fp.y + 2);

	// Rename.
	float bL = bc.b * 0.5 + (bc.r * 0.5 + bc.g);
	float cL = cc.b * 0.5 + (cc.r * 0.5 + cc.g);
	float iL = ic.b * 0.5 + (ic.r * 0.5 + ic.g);
	float jL = jc.b * 0.5 + (jc.r * 0.5 + jc.g);
	float fL = fc.b * 0.5 + (fc.r * 0.5 + fc.g);
	float eL = ec.b * 0.5 + (ec.r * 0.5 + ec.g);
	float kL = kc.b * 0.5 + (kc.r * 0.5 + kc.g);
	float lL = lc.b * 0.5 + (lc.r * 0.5 + lc.g);
	float hL = hc.b * 0.5 + (hc.r * 0.5 + hc.g);
	float gL = gc.b * 0.5 + (gc.r * 0.5 + gc.g);
	float oL = oc.b * 0.5 + (oc.r * 0.5 + oc.g);
	float nL = nc.b * 0.5 + (nc.r * 0.5 + nc.g);
	// Accumulate for bilinear interpolation.
	float2 dir = 0;
	float len = 0;
	FsrEasuSet(dir, len, pp, true, false, false, false, bL, eL, fL, gL, jL);
	FsrEasuSet(dir, len, pp, false, true, false, false, cL, fL, gL, hL, kL);
	FsrEasuSet(dir, len, pp, false, false, true, false, fL, iL, jL, kL, nL);
	FsrEasuSet(dir, len, pp, false, false, false, true, gL, jL, kL, lL, oL);
	//------------------------------------------------------------------------------------------------------------------------------
		// Normalize with approximation, and cleanup close to zero.
	float2 dir2 = dir * dir;
	float dirR = dir2.x + dir2.y;
	bool zro = dirR < 1.0f / 32768.0f;
	dirR = rsqrt(dirR);
	dirR = zro ? 1 : dirR;
	dir.x = zro ? 1 : dir.x;
	dir *= dirR;
	// Transform from {0 to 2} to {0 to 1} range, and shape with square.
	len = len * 0.5;
	len *= len;
	// Stretch kernel {1.0 vert|horz, to sqrt(2.0) on diagonal}.
	float stretch = (dir.x * dir.x + dir.y * dir.y) * rcp(max(abs(dir.x), abs(dir.y)));
	// Anisotropic length after rotation,
	//  x := 1.0 lerp to 'stretch' on edges
	//  y := 1.0 lerp to 2x on edges
	float2 len2 = { 1 + (stretch - 1) * len, 1 - 0.5 * len };
	// Based on the amount of 'edge',
	// the window shifts from +/-{sqrt(2.0) to slightly beyond 2.0}.
	float lob = 0.5 + ((1.0 / 4.0 - 0.04) - 0.5) * len;
	// Set distance^2 clipping point to the end of the adjustable window.
	float clp = rcp(lob);
	//------------------------------------------------------------------------------------------------------------------------------
		// Accumulation mixed with min/max of 4 nearest.
		//    b c
		//  e f g h
		//  i j k l
		//    n o
	float3 min4 = min(min3(fc, gc, jc), kc);
	float3 max4 = max(max3(fc, gc, jc), kc);
	// Accumulation.
	float3 aC = 0;
	float aW = 0;
	FsrEasuTap(aC, aW, float2(0.0, -1.0) - pp, dir, len2, lob, clp, bc); // b
	FsrEasuTap(aC, aW, float2(1.0, -1.0) - pp, dir, len2, lob, clp, cc); // c
	FsrEasuTap(aC, aW, float2(-1.0, 1.0) - pp, dir, len2, lob, clp, ic); // i
	FsrEasuTap(aC, aW, float2(0.0, 1.0) - pp, dir, len2, lob, clp, jc); // j
	FsrEasuTap(aC, aW, float2(0.0, 0.0) - pp, dir, len2, lob, clp, fc); // f
	FsrEasuTap(aC, aW, float2(-1.0, 0.0) - pp, dir, len2, lob, clp, ec); // e
	FsrEasuTap(aC, aW, float2(1.0, 1.0) - pp, dir, len2, lob, clp, kc); // k
	FsrEasuTap(aC, aW, float2(2.0, 1.0) - pp, dir, len2, lob, clp, lc); // l
	FsrEasuTap(aC, aW, float2(2.0, 0.0) - pp, dir, len2, lob, clp, hc); // h
	FsrEasuTap(aC, aW, float2(1.0, 0.0) - pp, dir, len2, lob, clp, gc); // g
	FsrEasuTap(aC, aW, float2(1.0, 2.0) - pp, dir, len2, lob, clp, oc); // o
	FsrEasuTap(aC, aW, float2(0.0, 2.0) - pp, dir, len2, lob, clp, nc); // n
//------------------------------------------------------------------------------------------------------------------------------
	// Normalize and dering.
	return min(max4, max(min4, aC * rcp(aW)));
}


float3 FsrRcasF(uint2 pos) {
	// Algorithm uses minimal 3x3 pixel neighborhood.
	//    b 
	//  d e f
	//    h
	float3 b = LoadFromShEasuPixels(pos.x, pos.y - 1);
	float3 d = LoadFromShEasuPixels(pos.x - 1, pos.y);
	float3 e = LoadFromShEasuPixels(pos.x, pos.y);
	float3 f = LoadFromShEasuPixels(pos.x + 1, pos.y);
	float3 h = LoadFromShEasuPixels(pos.x, pos.y + 1);

	// Rename (32-bit) or regroup (16-bit).
	float bR = b.r;
	float bG = b.g;
	float bB = b.b;
	float dR = d.r;
	float dG = d.g;
	float dB = d.b;
	float eR = e.r;
	float eG = e.g;
	float eB = e.b;
	float fR = f.r;
	float fG = f.g;
	float fB = f.b;
	float hR = h.r;
	float hG = h.g;
	float hB = h.b;

	float nz;

	// Luma times 2.
	float bL = bB * 0.5 + (bR * 0.5 + bG);
	float dL = dB * 0.5 + (dR * 0.5 + dG);
	float eL = eB * 0.5 + (eR * 0.5 + eG);
	float fL = fB * 0.5 + (fR * 0.5 + fG);
	float hL = hB * 0.5 + (hR * 0.5 + hG);

	// Noise detection.
	nz = 0.25 * bL + 0.25 * dL + 0.25 * fL + 0.25 * hL - eL;
	nz = saturate(abs(nz) * rcp(max3(max3(bL, dL, eL), fL, hL) - min3(min3(bL, dL, eL), fL, hL)));
	nz = -0.5 * nz + 1.0;

	// Min and max of ring.
	float mn4R = min(min3(bR, dR, fR), hR);
	float mn4G = min(min3(bG, dG, fG), hG);
	float mn4B = min(min3(bB, dB, fB), hB);
	float mx4R = max(max3(bR, dR, fR), hR);
	float mx4G = max(max3(bG, dG, fG), hG);
	float mx4B = max(max3(bB, dB, fB), hB);
	// Immediate constants for peak range.
	float2 peakC = { 1.0, -1.0 * 4.0 };
	// Limiters, these need to be high precision RCPs.
	float hitMinR = min(mn4R, eR) * rcp(4.0 * mx4R);
	float hitMinG = min(mn4G, eG) * rcp(4.0 * mx4G);
	float hitMinB = min(mn4B, eB) * rcp(4.0 * mx4B);
	float hitMaxR = (peakC.x - max(mx4R, eR)) * rcp(4.0 * mn4R + peakC.y);
	float hitMaxG = (peakC.x - max(mx4G, eG)) * rcp(4.0 * mn4G + peakC.y);
	float hitMaxB = (peakC.x - max(mx4B, eB)) * rcp(4.0 * mn4B + peakC.y);
	float lobeR = max(-hitMinR, hitMaxR);
	float lobeG = max(-hitMinG, hitMaxG);
	float lobeB = max(-hitMinB, hitMaxB);
	float lobe = max(-FSR_RCAS_LIMIT, min(max3(lobeR, lobeG, lobeB), 0)) * sharpness.x;

	// Apply noise removal.
	lobe *= nz;

	// Resolve, which needs the medium precision rcp approximation to avoid visible tonality changes.
	float rcpL = rcp(4.0 * lobe + 1.0);
	float3 c = {
		(lobe * bR + lobe * dR + lobe * hR + lobe * fR + eR) * rcpL,
		(lobe * bG + lobe * dG + lobe * hG + lobe * fG + eG) * rcpL,
		(lobe * bB + lobe * dB + lobe * hB + lobe * fB + eB) * rcpL
	};

	return c;
}


[numthreads(THREAD_GROUP_SIZE, 1, 1)]
void main(uint3 LocalThreadId : SV_GroupThreadID, uint3 WorkGroupId : SV_GroupID, uint3 Dtid : SV_DispatchThreadID) {
	// Figure out the range of pixels from input image that would be needed to be loaded for this thread-block
	const uint dstBlockX = BLOCK_WIDTH * WorkGroupId.x;
	const uint dstBlockY = BLOCK_HEIGHT * WorkGroupId.y;

	float2 rcpScale = { inputWidth / outputWidth, inputHeight / outputHeight };

	const int srcBlockStartX = int(floor((dstBlockX + 0.5f) * rcpScale.x - 0.5f)) - 2;
	const int srcBlockStartY = int(floor((dstBlockY + 0.5f) * rcpScale.y - 0.5f)) - 2;
	const int srcBlockEndX = int(ceil((dstBlockX + BLOCK_WIDTH + 0.5f) * rcpScale.x - 0.5f)) + 2;
	const int srcBlockEndY = int(ceil((dstBlockY + BLOCK_HEIGHT + 0.5f) * rcpScale.y - 0.5f)) + 2;

	uint numTilePixelsX = srcBlockEndX - srcBlockStartX;
	uint numTilePixelsY = srcBlockEndY - srcBlockStartY;

	// round-up load region to even size since we're loading in 2x2 batches
	numTilePixelsX += numTilePixelsX & 0x1;
	numTilePixelsY += numTilePixelsY & 0x1;
	const uint numTilePixels = numTilePixelsX * numTilePixelsY;

	for (uint i = LocalThreadId.x * 2; i < numTilePixels / 2; i += THREAD_GROUP_SIZE * 2) {
		const uint2 pos = uint2(i % numTilePixelsX, i / numTilePixelsX * 2);

		const float tx = ((srcBlockStartX + pos.x) + 0.5f) / inputWidth;
		const float ty = ((srcBlockStartY + pos.y) + 0.5f) / inputHeight;

		const float4 sr = INPUT.GatherRed(sam, float2(tx, ty));
		const float4 sg = INPUT.GatherGreen(sam, float2(tx, ty));
		const float4 sb = INPUT.GatherBlue(sam, float2(tx, ty));

		const uint idx = pos.y * TILE_PITCH_ORIGIN + pos.x;
		shOriginPixels[idx] = float3(sr.w, sg.w, sb.w);
		shOriginPixels[idx + 1] = float3(sr.z, sg.z, sb.z);
		shOriginPixels[idx + TILE_PITCH_ORIGIN] = float3(sr.x, sg.x, sb.x);
		shOriginPixels[idx + TILE_PITCH_ORIGIN + 1] = float3(sr.y, sg.y, sb.y);
	}

	GroupMemoryBarrierWithGroupSync();

	// Output integer position to a pixel position in viewport.
	float4 con0 = { rcpScale, 0.5 * rcpScale - 0.5 };

	for (i = LocalThreadId.x; i < TILE_PITCH_EASU * (BLOCK_HEIGHT + PAD_SIZE_EASU); i += THREAD_GROUP_SIZE) {
		const uint2 pos = uint2(i % TILE_PITCH_EASU, i / TILE_PITCH_EASU);

		// Get position of 'f'.
		float2 pp = (uint2(dstBlockX - 1, dstBlockY - 1) + pos) * con0.xy + con0.zw;
		uint2 fp = (uint2)floor(pp);
		pp -= fp;
		fp -= int2(srcBlockStartX, srcBlockStartY);

		shEasuPixels[pos.y * TILE_PITCH_EASU + pos.x] = FsrEasuF(pp, fp);
	}

	GroupMemoryBarrierWithGroupSync();

	for (i = LocalThreadId.x; i < BLOCK_WIDTH * BLOCK_HEIGHT; i += THREAD_GROUP_SIZE) {
		const uint2 pos = uint2(i % BLOCK_WIDTH, i / BLOCK_WIDTH);

		const uint2 outputPos = uint2(dstBlockX, dstBlockY) + pos + viewport.xy;
		if (outputPos.x >= viewport.z || outputPos.y >= viewport.w) {
			continue;
		}

		OUTPUT[outputPos] = float4(FsrRcasF(pos + 1), 1);
	}
}
