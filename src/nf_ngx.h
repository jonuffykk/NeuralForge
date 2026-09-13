// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Jonuffy
#pragma once

#ifndef WIN32_LEAN_AND_MEAN
  #define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <d3d11.h>
#include <d3d12.h>

#include <cstdint>

namespace nf::ngx {

enum Result : int {
    Result_Success                = 1,
    Result_Fail                   = static_cast<int>(0xBAD00000),
    Result_FeatureNotSupported    = static_cast<int>(0xBAD00001),
    Result_PlatformError          = static_cast<int>(0xBAD00002),
    Result_FeatureAlreadyExists   = static_cast<int>(0xBAD00003),
    Result_FeatureNotFound        = static_cast<int>(0xBAD00004),
    Result_InvalidParameter       = static_cast<int>(0xBAD00005),
    Result_ScratchBufferTooSmall  = static_cast<int>(0xBAD00006),
    Result_NotInitialized         = static_cast<int>(0xBAD00007),
    Result_UnsupportedInputFormat = static_cast<int>(0xBAD00008),
};

constexpr bool succeeded(Result r) { return r == Result_Success; }

enum Feature : int {
    Feature_SuperSampling            = 1,
    Feature_InPainting               = 2,
    Feature_ImageSuperResolution     = 3,
    Feature_SlowMotion               = 4,
    Feature_VideoSuperResolution     = 5,
    Feature_ImageSignalProcessing    = 6,
    Feature_DeepResolve              = 7,
    Feature_FrameGeneration          = 8,
    Feature_DeepDVC                  = 9,
    Feature_RayReconstruction        = 10,
    Feature_SuperSamplingDenoising   = 11,
    Feature_NeuralRendering_Unverified = 18,
};

struct Version { uint32_t value; };

constexpr Version kSdkVersion { 0x0000014 };

class Parameter {
public:
    virtual void Set(const char* name, unsigned long long value)  = 0;
    virtual void Set(const char* name, float value)               = 0;
    virtual void Set(const char* name, double value)              = 0;
    virtual void Set(const char* name, unsigned int value)        = 0;
    virtual void Set(const char* name, int value)                 = 0;
    virtual void Set(const char* name, ID3D11Resource* value)     = 0;
    virtual void Set(const char* name, ID3D12Resource* value)     = 0;
    virtual void Set(const char* name, void* value)               = 0;

    virtual Result Get(const char* name, unsigned long long* out) const = 0;
    virtual Result Get(const char* name, float* out)               const = 0;
    virtual Result Get(const char* name, double* out)              const = 0;
    virtual Result Get(const char* name, unsigned int* out)        const = 0;
    virtual Result Get(const char* name, int* out)                 const = 0;
    virtual Result Get(const char* name, ID3D11Resource** out)     const = 0;
    virtual Result Get(const char* name, ID3D12Resource** out)     const = 0;
    virtual Result Get(const char* name, void** out)               const = 0;

    virtual void Reset() = 0;
};

struct Handle { unsigned int id; };

using ProgressCallback = void (*)(float progress, bool& shouldCancel);

constexpr const char* kParamWidth              = "Width";
constexpr const char* kParamHeight             = "Height";
constexpr const char* kParamOutWidth           = "OutWidth";
constexpr const char* kParamOutHeight          = "OutHeight";
constexpr const char* kParamColor              = "Color";
constexpr const char* kParamOutput             = "Output";
constexpr const char* kParamMotionVectors      = "MotionVectors";
constexpr const char* kParamDepth              = "Depth";
constexpr const char* kParamExposureTexture    = "ExposureTexture";
constexpr const char* kParamJitterOffsetX      = "Jitter.Offset.X";
constexpr const char* kParamJitterOffsetY      = "Jitter.Offset.Y";
constexpr const char* kParamMvScaleX           = "MV.Scale.X";
constexpr const char* kParamMvScaleY           = "MV.Scale.Y";
constexpr const char* kParamReset              = "Reset";
constexpr const char* kParamScratchBuffer      = "Scratch";
constexpr const char* kParamScratchBufferSize  = "Scratch.SizeInBytes";
constexpr const char* kParamCreationNodeMask   = "CreationNodeMask";
constexpr const char* kParamVisibilityNodeMask = "VisibilityNodeMask";
constexpr const char* kParamModel              = "Model";

constexpr const char* kParamNrModel_Unverified          = "NR.Model";
constexpr const char* kParamNrStructure_Unverified      = "NR.StructureIntensity";
constexpr const char* kParamNrTone_Unverified           = "NR.ToneIntensity";
constexpr const char* kParamNrSkinStructure_Unverified  = "NR.Skin.Structure";
constexpr const char* kParamNrSkinTone_Unverified       = "NR.Skin.Tone";
constexpr const char* kParamNrPassIndex_Unverified      = "NR.PassIndex";
constexpr const char* kParamNrAvailable_Unverified      = "NR.Available";
constexpr const char* kParamNrModelCount_Unverified     = "NR.ModelCount";

struct Api {
    HMODULE module = nullptr;

    Result (*d3d12Init)(unsigned long long appId, const wchar_t* dataPath,
                        ID3D12Device* device, Version sdk) = nullptr;
    Result (*d3d12Shutdown)(ID3D12Device* device) = nullptr;
    Result (*d3d12GetCapabilityParameters)(Parameter** out) = nullptr;
    Result (*d3d12AllocateParameters)(Parameter** out) = nullptr;
    Result (*d3d12DestroyParameters)(Parameter* params) = nullptr;
    Result (*d3d12GetScratchBufferSize)(Feature feature, const Parameter* params,
                                        size_t* outBytes) = nullptr;
    Result (*d3d12CreateFeature)(ID3D12GraphicsCommandList* cmd, Feature feature,
                                 Parameter* params, Handle** out) = nullptr;
    Result (*d3d12ReleaseFeature)(Handle* handle) = nullptr;
    Result (*d3d12EvaluateFeature)(ID3D12GraphicsCommandList* cmd, const Handle* handle,
                                   const Parameter* params, ProgressCallback cb) = nullptr;

    Result (*d3d11Init)(unsigned long long appId, const wchar_t* dataPath,
                        ID3D11Device* device, Version sdk) = nullptr;
    Result (*d3d11Shutdown)() = nullptr;
    Result (*d3d11GetCapabilityParameters)(Parameter** out) = nullptr;
    Result (*d3d11AllocateParameters)(Parameter** out) = nullptr;
    Result (*d3d11DestroyParameters)(Parameter* params) = nullptr;
    Result (*d3d11GetScratchBufferSize)(Feature feature, const Parameter* params,
                                        size_t* outBytes) = nullptr;
    Result (*d3d11CreateFeature)(ID3D11DeviceContext* ctx, Feature feature,
                                 Parameter* params, Handle** out) = nullptr;
    Result (*d3d11ReleaseFeature)(Handle* handle) = nullptr;
    Result (*d3d11EvaluateFeature)(ID3D11DeviceContext* ctx, const Handle* handle,
                                   const Parameter* params, ProgressCallback cb) = nullptr;

    bool loadedD3D12() const {
        return d3d12Init && d3d12GetCapabilityParameters && d3d12AllocateParameters &&
               d3d12CreateFeature && d3d12EvaluateFeature && d3d12ReleaseFeature;
    }
    bool loadedD3D11() const {
        return d3d11Init && d3d11GetCapabilityParameters && d3d11AllocateParameters &&
               d3d11CreateFeature && d3d11EvaluateFeature && d3d11ReleaseFeature;
    }
};

bool        loadApi(Api& api, const wchar_t* preferredDirectory, std::string* error);
void        unloadApi(Api& api);
const char* resultToString(Result r);

} // namespace nf::ngx
