// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Jonuffy
#include "nf.h"

#include <algorithm>

namespace nf {

class ResourcePool {
public:
    bool ensure(void* device, Extent2D low, Extent2D high, uint32_t tileSize);
    void release();

    Extent2D lowRes  {};
    Extent2D highRes {};

    void* neuralOutput  = nullptr;
    void* residualA     = nullptr;
    void* residualB     = nullptr;
    void* bandTone      = nullptr;
    void* bandStructure = nullptr;
    void* prevColour    = nullptr;
    void* tileEnergy    = nullptr;
    void* tileList      = nullptr;
    void* indirectArgs  = nullptr;

private:
    uint32_t m_tileSize = 0;
};

namespace {

constexpr uint32_t kTileEdgeInPixels = 16;

bool allocateRenderResolutionTargets(void* device, Extent2D low, Extent2D high) {
    (void)device;
    (void)low;
    (void)high;
    return true;
}

void dispatchResidualExtract(CommandList cmd, ResourcePool& pool, void* gameColour) {
    (void)cmd;
    (void)pool;
    (void)gameColour;
}

void dispatchBandSplit(CommandList cmd, ResourcePool& pool) {
    (void)cmd;
    (void)pool;
}

void dispatchResidualReprojection(CommandList cmd, ResourcePool& pool,
                                  const FrameInputs& in) {
    (void)cmd;
    (void)pool;
    (void)in;
}

void dispatchTileCompaction(CommandList cmd, ResourcePool& pool, float threshold) {
    (void)cmd;
    (void)pool;
    (void)threshold;
}

void dispatchComposite(CommandList cmd, ResourcePool& pool, const Config& cfg,
                       void* srOutput, void* finalOutput) {
    (void)cmd;
    (void)pool;
    (void)cfg;
    (void)srOutput;
    (void)finalOutput;
}

}

bool ResourcePool::ensure(void* device, Extent2D low, Extent2D high, uint32_t tileSize) {
    const bool unchanged =
        lowRes.width  == low.width  && lowRes.height  == low.height &&
        highRes.width == high.width && highRes.height == high.height &&
        m_tileSize    == tileSize;

    if (unchanged) return true;

    release();
    lowRes     = low;
    highRes    = high;
    m_tileSize = tileSize;

    return allocateRenderResolutionTargets(device, low, high);
}

void ResourcePool::release() {
    neuralOutput = residualA = residualB = bandTone = bandStructure = nullptr;
    prevColour = tileEnergy = tileList = indirectArgs = nullptr;
    lowRes = highRes = Extent2D {};
}

Pipeline::Pipeline()  : m_pool(std::make_unique<ResourcePool>()) {}
Pipeline::~Pipeline() { shutdown(); }

bool Pipeline::createBackendWithFallback(std::string* error) {
    Backend order[4] {};
    int     n = 0;

    const Backend preferred =
        (m_cfg.backend != Backend::None)
            ? m_cfg.backend
            : selectBackend(m_gpu, m_cfg.allowFp16Fallback, true);

    order[n++] = preferred;
    if (preferred == Backend::NgxFp8) order[n++] = Backend::NgxFp16;
    if (preferred == Backend::Hip)    order[n++] = Backend::DirectML;
    if (preferred == Backend::NgxFp16 && !m_cfg.allowFp16Fallback) n = 0;

    std::string lastError = "no backend available for this GPU";

    for (int i = 0; i < n; ++i) {
        if (order[i] == Backend::None) continue;

        auto candidate = createBackend(order[i]);
        if (!candidate) {
            lastError = "backend not compiled into this build";
            continue;
        }

        std::string err;
        if (candidate->initialise(m_device, m_gpu, m_cfg.runtimePath, &err)) {
            m_backend = std::move(candidate);
            return true;
        }
        lastError = err;
    }

    if (error) *error = lastError;
    return false;
}

bool Pipeline::initialise(const DeviceHandles& handles, const Config& cfg, std::string* error) {
    shutdown();

    m_device = handles;
    m_cfg    = cfg;
    m_cfg.sanitise();

    m_gpu = detectGpu();
    resolveAuto(m_cfg, m_gpu);

    if (!m_gpu.canRun()) {
        m_status = explainSelection(m_gpu, Backend::None);
        if (error) *error = m_status;
        return false;
    }

    if (!createBackendWithFallback(error)) {
        m_status = error ? *error : "backend initialisation failed";
        return false;
    }

    m_sched.configure(m_cfg, m_gpu.tier, m_backend->kind(),
                      m_backend->carriesTemporalState());

    m_status = explainSelection(m_gpu, m_backend->kind());
    m_active = true;
    m_frame  = 0;
    m_lastMs = -1.0f;
    return true;
}

void Pipeline::shutdown() {
    if (m_backend) {
        m_backend->shutdown();
        m_backend.reset();
    }
    if (m_pool) m_pool->release();

    m_active = false;
    m_status = "not initialised";
}

void Pipeline::applyConfig(const Config& cfg) {
    m_cfg = cfg;
    m_cfg.sanitise();
    resolveAuto(m_cfg, m_gpu);

    if (m_backend)
        m_sched.configure(m_cfg, m_gpu.tier, m_backend->kind(),
                          m_backend->carriesTemporalState());
}

bool Pipeline::execute(CommandList cmd, const FrameInputs& in,
                       void* srOutput, void* finalOutput) {
    if (!m_active || !m_cfg.enabled || !m_backend) return false;
    if (!srOutput || !in.color)                    return false;

    if (!in.motionVectors && in.motionSource != MotionSource::OpticalFlow) {
        if (m_cfg.requireMotionVectors) {
            m_status = "no motion vectors at this call site, stage disabled";
            return false;
        }
    }

    ++m_frame;
    const Schedule s = m_sched.plan(in, m_lastMs);

    if (!m_pool->ensure(m_device.device, s.networkExtent, in.outputExtent, kTileEdgeInPixels))
        return false;

    m_stats                = FrameStats {};
    m_stats.effectiveScale = s.workingScale;
    m_stats.historyReset   = s.resetState;

    if (s.evaluateThisFrame) {
        Dispatch d {};
        d.inColor    = in.color;
        d.inMotion   = in.motionVectors;
        d.inDepth    = in.depth;
        d.outColor   = m_pool->neuralOutput;
        d.extent     = s.networkExtent;
        d.model      = (m_cfg.model == kModelAuto) ? 0 : m_cfg.model;
        d.passIndex  = 0;
        d.resetState = s.resetState;
        d.tileSize   = kTileEdgeInPixels;

        if (!m_backend->evaluate(cmd, d)) return false;
        m_stats.passesExecuted = 1;

        dispatchResidualExtract(cmd, *m_pool, in.color);
        dispatchBandSplit(cmd, *m_pool);

        for (uint32_t pass = 1; pass < s.passes; ++pass) {
            if (s.selectiveRefine)
                dispatchTileCompaction(cmd, *m_pool, m_cfg.tileThreshold);

            d.passIndex  = pass;
            d.resetState = false;

            if (!m_backend->evaluate(cmd, d)) break;
            ++m_stats.passesExecuted;
        }
    } else {
        dispatchResidualReprojection(cmd, *m_pool, in);
        dispatchBandSplit(cmd, *m_pool);
        m_stats.wasReprojected = true;
    }

    dispatchComposite(cmd, *m_pool, m_cfg, srOutput, finalOutput);

    m_lastMs            = m_backend->lastGpuMs();
    m_stats.inferenceMs = std::max(0.0f, m_lastMs);
    m_stats.totalMs     = m_stats.inferenceMs + m_stats.compositeMs;

    std::swap(m_pool->residualA, m_pool->residualB);
    return true;
}

}
