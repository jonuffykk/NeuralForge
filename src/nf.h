// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Jonuffy
#pragma once
#include <cstdint>
#include <memory>
#include <string>

namespace nf {

enum class Tier : uint8_t {
    Unsupported = 0,
    RDNA3       = 1,
    Turing      = 2,
    Ampere      = 3,
    RDNA4       = 4,
    Ada         = 5,
    Blackwell   = 6,
};

enum class Vendor    : uint8_t { Unknown, Nvidia, Amd, Intel };
enum class Backend   : uint8_t { None, NgxFp8, NgxFp16, DirectML, Hip };
enum class Placement : uint8_t { PostSR, PreSR, Deferred };

enum class GraphicsApi : uint8_t { D3D12, D3D11 };

enum class MotionSource : uint8_t { Engine, OpticalFlow, None };

struct DeviceHandles {
    GraphicsApi api            = GraphicsApi::D3D12;
    void*       device         = nullptr;
    void*       queueOrContext = nullptr;
    void*       bridgeDevice   = nullptr;
    void*       bridgeQueue    = nullptr;

    bool needsBridge() const { return api == GraphicsApi::D3D11; }
    bool valid()       const { return device != nullptr; }
};

constexpr uint32_t kMaxModels = 8;
constexpr uint32_t kModelAuto = 0xFFFFFFFFu;

struct Intensity {
    float structure = 1.0f;
    float tone      = 1.0f;
};

struct IntensitySet {
    Intensity global;
    Intensity skin;
    Intensity foliage;
};

struct Extent2D {
    uint32_t width  = 0;
    uint32_t height = 0;

    constexpr uint64_t pixels() const { return uint64_t(width) * height; }
    constexpr bool     valid()  const { return width && height; }
};

struct FrameInputs {
    void*        color         = nullptr;
    void*        motionVectors = nullptr;
    void*        depth         = nullptr;
    Extent2D     renderExtent;
    Extent2D     outputExtent;
    float        jitterX       = 0.0f;
    float        jitterY       = 0.0f;
    float        mvScaleX      = 1.0f;
    float        mvScaleY      = 1.0f;
    bool         resetHistory  = false;
    uint64_t     frameIndex    = 0;
    MotionSource motionSource  = MotionSource::Engine;
};

struct FrameStats {
    float    inferenceMs    = 0.0f;
    float    compositeMs    = 0.0f;
    float    totalMs        = 0.0f;
    uint32_t passesExecuted = 0;
    uint32_t tilesEvaluated = 0;
    uint32_t tilesTotal     = 0;
    bool     wasReprojected = false;
    bool     historyReset   = false;
    float    effectiveScale = 1.0f;
};

struct GpuInfo {
    Vendor      vendor    = Vendor::Unknown;
    Tier        tier      = Tier::Unsupported;
    uint32_t    vendorId  = 0;
    uint32_t    deviceId  = 0;
    uint64_t    vramBytes = 0;
    std::string name;
    bool        identifiedByHeuristicOnly = false;

    bool supportsFp8() const {
        return tier == Tier::Blackwell || tier == Tier::Ada || tier == Tier::RDNA4;
    }
    bool hasVendorRuntime() const {
        return vendor == Vendor::Nvidia && tier >= Tier::Turing;
    }
    bool canRun() const { return tier != Tier::Unsupported; }
};

Tier        classifyByDeviceId(uint32_t vendorId, uint32_t deviceId);
Backend     selectBackend(const GpuInfo&, bool allowFp16, bool preferHip);
float       costMultiplier(Tier, Backend);
std::string explainSelection(const GpuInfo&, Backend);

#if !defined(NF_NO_D3D)
GpuInfo detectGpu(uint64_t adapterLuid = 0);
#endif

struct Config {
    bool         enabled   = true;
    Backend      backend   = Backend::None;
    uint32_t     model     = kModelAuto;
    IntensitySet intensity {};
    Placement    placement = Placement::Deferred;

    float    workingScale       = 1.0f;
    uint32_t passes             = 1;
    bool     selectiveMultipass = true;
    float    tileThreshold      = 0.02f;
    uint32_t cadence            = 1;

    bool  autoTune = true;
    float budgetMs = 2.0f;

    bool blockOnAntiCheat     = true;
    bool allowFp16Fallback    = true;
    bool requireMotionVectors = true;
    bool allowD3D11Bridge     = true;
    bool allowOpticalFlow     = false;

    std::string runtimePath;

    uint32_t overlayHotkey = 0x2D;
    bool     showStats     = false;

    bool loadFromFile(const std::string& path, std::string* warnings = nullptr);
    bool saveToFile(const std::string& path) const;
    void sanitise();
};

void resolveAuto(Config&, const GpuInfo&);

struct Rung {
    float       workingScale;
    uint32_t    passes;
    uint32_t    cadence;
    const char* label;
};

struct Schedule {
    Extent2D networkExtent;
    uint32_t passes            = 1;
    uint32_t cadence           = 1;
    bool     evaluateThisFrame = true;
    bool     resetState        = false;
    bool     selectiveRefine   = true;
    float    workingScale      = 1.0f;
    int      rung              = 0;
};

uint32_t alignDown(uint32_t v, uint32_t a);
float    rungCost(const Rung&, bool selective, float tileFraction);

class Scheduler {
public:
    void     configure(const Config&, Tier, Backend, bool backendCarriesTemporalState);
    Schedule plan(const FrameInputs&, float measuredMs);
    void     reset();

    int         currentRung()  const { return m_rung; }
    int         ceilingRung()  const { return m_minRung; }
    const char* rungLabel()    const;
    float       predictedMs()  const { return m_predictedMs; }

    static const Rung* ladder(uint32_t* count);

private:
    void stepDown();
    void stepUp();

    Config   m_cfg {};
    Tier     m_tier              = Tier::Unsupported;
    Backend  m_backend           = Backend::None;
    bool     m_carriesTemporalState = true;

    int      m_rung    = 0;
    int      m_minRung = 0;

    uint32_t m_overBudget  = 0;
    uint32_t m_underBudget = 0;
    uint64_t m_frame       = 0;
    uint64_t m_lastEval    = 0;

    float    m_emaMs       = -1.0f;
    float    m_predictedMs = 0.0f;
    float    m_costSeed    = 1.0f;

    Extent2D m_lastRender {};
};

using CommandList = void*;

struct Dispatch {
    void*    inColor    = nullptr;
    void*    inMotion   = nullptr;
    void*    inDepth    = nullptr;
    void*    outColor   = nullptr;
    Extent2D extent;
    uint32_t model      = 0;
    uint32_t passIndex  = 0;
    bool     resetState = false;

    const uint32_t* tiles     = nullptr;
    uint32_t        tileCount = 0;
    uint32_t        tileSize  = 0;
};

class IBackend {
public:
    virtual ~IBackend() = default;

    virtual bool initialise(const DeviceHandles&, const GpuInfo&,
                            const std::string& runtimePath, std::string* error) = 0;
    virtual void shutdown() = 0;
    virtual bool evaluate(CommandList, const Dispatch&) = 0;
    virtual void onResolutionChanged(Extent2D render, Extent2D output) = 0;

    virtual Backend     kind()        const = 0;
    virtual uint32_t    modelCount()  const = 0;
    virtual const char* modelName(uint32_t) const = 0;
    virtual uint64_t    vramBytes()   const = 0;
    virtual float       lastGpuMs()   const = 0;
    virtual bool        carriesTemporalState() const = 0;
};

std::unique_ptr<IBackend> createBackend(Backend);

#if !defined(NF_NO_D3D)

class ResourcePool;

class Pipeline {
public:
    Pipeline();
    ~Pipeline();
    Pipeline(const Pipeline&)            = delete;
    Pipeline& operator=(const Pipeline&) = delete;

    bool initialise(const DeviceHandles&, const Config&, std::string* error);
    void shutdown();
    bool execute(CommandList, const FrameInputs&, void* srOutput, void* finalOutput = nullptr);
    void applyConfig(const Config&);

    const Config&     config()  const { return m_cfg; }
    const GpuInfo&    gpu()     const { return m_gpu; }
    const FrameStats& stats()   const { return m_stats; }
    const Scheduler&  tuner()   const { return m_sched; }
    IBackend*         backend() const { return m_backend.get(); }

    bool        isActive()   const { return m_active; }
    const char* statusLine() const { return m_status.c_str(); }

private:
    bool createBackendWithFallback(std::string* error);

    Config                        m_cfg {};
    GpuInfo                       m_gpu {};
    DeviceHandles                 m_device {};
    Scheduler                     m_sched {};
    FrameStats                    m_stats {};
    std::unique_ptr<IBackend>     m_backend;
    std::unique_ptr<ResourcePool> m_pool;

    bool        m_active = false;
    uint64_t    m_frame  = 0;
    float       m_lastMs = -1.0f;
    std::string m_status = "not initialised";
};

void drawOverlay(Pipeline&, Config&);

#endif

}
