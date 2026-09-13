// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Jonuffy
cbuffer NFConstants : register(b0)
{
    uint2  gLowResExtent;      // network / render-res working extent
    uint2  gHighResExtent;     // output extent

    float2 gLowToHigh;         // gHighResExtent / gLowResExtent
    float2 gMotionScale;       // multiply raw MV by this to get low-res pixels

    float  gStructure;         // global high-frequency intensity
    float  gTone;              // global low-frequency intensity
    float  gSkinStructure;     // multiplier on skin-classified pixels
    float  gSkinTone;

    float  gFoliageStructure;
    float  gFoliageTone;
    float  gTileThreshold;     // residual energy above which a tile is "hot"
    uint   gTileSize;

    float  gReprojectFade;     // 0..1, confidence decay per skipped frame
    float  gDisoccludeSigma;   // luma delta at which we declare disocclusion
    uint   gFrameIndex;
    uint   gFlags;             // see NF_FLAG_*
};

#define NF_FLAG_HAS_DEPTH      (1u << 0)
#define NF_FLAG_HAS_SEMANTIC   (1u << 1)
#define NF_FLAG_MV_IS_JITTERED (1u << 2)

static const float kEps = 1e-4f;

float Luma(float3 c) { return dot(c, float3(0.2126f, 0.7152f, 0.0722f)); }

float3 EncodeRatio(float3 nr, float3 base)
{
    float3 r = log2(max(nr, kEps)) - log2(max(base, kEps));
    return clamp(r, -4.0f, 4.0f);
}

float3 ApplyRatio(float3 base, float3 ratio, float intensity)
{
    return base * exp2(ratio * intensity);
}

Texture2D<float4>   tNeuralOutput  : register(t0);   // network result, low res
Texture2D<float4>   tGameColour    : register(t1);   // untouched game colour, low res
RWTexture2D<float4> uResidual      : register(u0);   // rgb = log ratio, a = confidence
RWTexture2D<uint>   uTileEnergy    : register(u1);   // one texel per tile

groupshared float gsEnergy[64];

[numthreads(8, 8, 1)]
void CS_Extract(uint3 tid : SV_DispatchThreadID, uint gi : SV_GroupIndex, uint3 gid : SV_GroupID)
{
    float energy = 0.0f;
    float3 ratio = 0.0f.xxx;

    if (all(tid.xy < gLowResExtent))
    {
        float3 nr   = tNeuralOutput.Load(int3(tid.xy, 0)).rgb;
        float3 base = tGameColour  .Load(int3(tid.xy, 0)).rgb;

        ratio  = EncodeRatio(nr, base);
        energy = dot(abs(ratio), (1.0f / 3.0f).xxx);

        uResidual[tid.xy] = float4(ratio, 1.0f);
    }

    gsEnergy[gi] = energy;
    GroupMemoryBarrierWithGroupSync();

    [unroll]
    for (uint s = 32; s > 0; s >>= 1)
    {
        if (gi < s) gsEnergy[gi] += gsEnergy[gi + s];
        GroupMemoryBarrierWithGroupSync();
    }

    if (gi == 0)
    {
        const float mean = gsEnergy[0] / 64.0f;
        InterlockedMax(uTileEnergy[gid.xy / max(1u, gTileSize / 8u)],
                       uint(saturate(mean) * 65535.0f));
    }
}

Texture2D<float4>   tResidualIn  : register(t0);
RWTexture2D<float4> uResidualOut : register(u0);

cbuffer BlurConstants : register(b1) { int2 gDirection; };

static const float kGaussian[5] = { 0.2270270270f, 0.1945945946f,
                                    0.1216216216f, 0.0540540541f,
                                    0.0162162162f };

[numthreads(8, 8, 1)]
void CS_BlurBand(uint3 tid : SV_DispatchThreadID)
{
    if (any(tid.xy >= gLowResExtent)) return;

    float4 sum = tResidualIn.Load(int3(tid.xy, 0)) * kGaussian[0];

    [unroll]
    for (int i = 1; i < 5; ++i)
    {
        int2 o = gDirection * i;
        int2 a = clamp(int2(tid.xy) + o, int2(0, 0), int2(gLowResExtent) - 1);
        int2 b = clamp(int2(tid.xy) - o, int2(0, 0), int2(gLowResExtent) - 1);
        sum += (tResidualIn.Load(int3(a, 0)) + tResidualIn.Load(int3(b, 0))) * kGaussian[i];
    }

    uResidualOut[tid.xy] = sum;
}

Texture2D<float4>   tPrevResidual : register(t0);
Texture2D<float2>   tMotion       : register(t1);
Texture2D<float4>   tCurrColour   : register(t2);
Texture2D<float4>   tPrevColour   : register(t3);
RWTexture2D<float4> uCurrResidual : register(u0);

SamplerState sLinearClamp : register(s0);

[numthreads(8, 8, 1)]
void CS_Reproject(uint3 tid : SV_DispatchThreadID)
{
    if (any(tid.xy >= gLowResExtent)) return;

    const float2 texel = 1.0f / float2(gLowResExtent);
    const float2 uv    = (float2(tid.xy) + 0.5f) * texel;

    float2 mv      = tMotion.Load(int3(tid.xy, 0)).xy * gMotionScale;
    float2 prevUV  = uv - mv * texel;

    if (any(prevUV < 0.0f) || any(prevUV > 1.0f))
    {
        uCurrResidual[tid.xy] = float4(0.0f.xxx, 0.0f);
        return;
    }

    float4 prev = tPrevResidual.SampleLevel(sLinearClamp, prevUV, 0);

    float lumaNow  = Luma(tCurrColour.Load(int3(tid.xy, 0)).rgb);
    float lumaThen = Luma(tPrevColour.SampleLevel(sLinearClamp, prevUV, 0).rgb);
    float delta    = abs(lumaNow - lumaThen) / max(lumaNow + lumaThen, kEps);

    float valid = 1.0f - smoothstep(gDisoccludeSigma * 0.5f, gDisoccludeSigma, delta);

    float confidence = prev.a * gReprojectFade * valid;

    if (confidence < 0.05f) confidence = 0.0f;

    uCurrResidual[tid.xy] = float4(prev.rgb * confidence, confidence);
}

Texture2D<float4>   tStructure   : register(t0);   // high-frequency band, low res
Texture2D<float4>   tTone        : register(t1);   // low-frequency band, low res
Texture2D<float4>   tLowResGuide : register(t2);   // low-res game colour
Texture2D<float4>   tSrOutput    : register(t3);   // upscaled game colour, high res
Texture2D<uint>     tSemantic    : register(t4);   // class id per pixel, low res
RWTexture2D<float4> uFinal       : register(u0);

#define NF_CLASS_DEFAULT 0u
#define NF_CLASS_SKIN    1u
#define NF_CLASS_FOLIAGE 2u

[numthreads(8, 8, 1)]
void CS_Composite(uint3 tid : SV_DispatchThreadID)
{
    if (any(tid.xy >= gHighResExtent)) return;

    const float3 base = tSrOutput.Load(int3(tid.xy, 0)).rgb;

    const float2 lowPos = (float2(tid.xy) + 0.5f) / gLowToHigh - 0.5f;
    const int2   lowBase = int2(floor(lowPos));
    const float2 frac    = lowPos - float2(lowBase);

    const float guideLuma = Luma(base);

    float3 structureSum = 0.0f.xxx;
    float3 toneSum      = 0.0f.xxx;
    float  confidence   = 0.0f;
    float  weightSum    = 0.0f;
    float  bilinearSum  = 0.0f;

    [unroll]
    for (int dy = 0; dy <= 1; ++dy)
    [unroll]
    for (int dx = 0; dx <= 1; ++dx)
    {
        const int2 p = clamp(lowBase + int2(dx, dy), int2(0, 0), int2(gLowResExtent) - 1);

        const float wx = dx ? frac.x : (1.0f - frac.x);
        const float wy = dy ? frac.y : (1.0f - frac.y);
        const float wBilinear = wx * wy;

        const float tapLuma = Luma(tLowResGuide.Load(int3(p, 0)).rgb);
        const float dLuma   = abs(tapLuma - guideLuma) / max(tapLuma + guideLuma, kEps);
        const float wRange  = exp2(-dLuma * dLuma * 16.0f);

        const float4 st = tStructure.Load(int3(p, 0));
        const float  w  = wBilinear * wRange * st.a;   // fold in confidence

        structureSum += st.rgb * w;
        toneSum      += tTone.Load(int3(p, 0)).rgb * wBilinear;  // unguided
        confidence   += st.a * wBilinear;
        weightSum    += w;
        bilinearSum  += wBilinear;
    }

    float3 structureBand = (weightSum > 1e-5f) ? structureSum / weightSum : 0.0f.xxx;
    float3 toneBand      = (bilinearSum > 1e-5f) ? toneSum / bilinearSum : 0.0f.xxx;
    confidence           = (bilinearSum > 1e-5f) ? confidence / bilinearSum : 0.0f;

    float sMul = 1.0f, tMul = 1.0f;
    if (gFlags & NF_FLAG_HAS_SEMANTIC)
    {
        const uint cls = tSemantic.Load(int3(clamp(lowBase, int2(0, 0),
                                                   int2(gLowResExtent) - 1), 0));
        if (cls == NF_CLASS_SKIN)    { sMul = gSkinStructure;    tMul = gSkinTone;    }
        if (cls == NF_CLASS_FOLIAGE) { sMul = gFoliageStructure; tMul = gFoliageTone; }
    }

    const float3 ratio = structureBand * (gStructure * sMul)
                       + toneBand      * (gTone      * tMul);

    uFinal[tid.xy] = float4(ApplyRatio(base, ratio, confidence), 1.0f);
}

Texture2D<uint>            tTileEnergy  : register(t0);
RWStructuredBuffer<uint>   uTileList    : register(u0);
RWByteAddressBuffer        uIndirectArgs: register(u1);

[numthreads(8, 8, 1)]
void CS_CompactTiles(uint3 tid : SV_DispatchThreadID)
{
    uint2 dims;
    tTileEnergy.GetDimensions(dims.x, dims.y);
    if (any(tid.xy >= dims)) return;

    const float energy = tTileEnergy.Load(int3(tid.xy, 0)) / 65535.0f;
    if (energy < gTileThreshold) return;

    uint slot;
    uIndirectArgs.InterlockedAdd(0, 1, slot);
    uTileList[slot] = (tid.y << 16) | tid.x;
}
