// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Jonuffy
#include "nf.h"

#include <algorithm>
#include <cmath>
#include <iterator>

namespace nf {
namespace {

constexpr uint32_t kMaxCadenceWithCarriedTemporalState = 2;

constexpr Rung kLadderOrderedByDescendingQuality[] = {
    { 1.00f, 3, 1, "Ultra (1.00x, 3 pass, every frame)"   },
    { 1.00f, 2, 1, "Quality (1.00x, 2 pass, every frame)" },
    { 1.00f, 1, 1, "Reference (1.00x, 1 pass)"            },
    { 0.85f, 1, 1, "Balanced (0.85x, 1 pass)"             },
    { 0.75f, 1, 1, "Performance (0.75x, 1 pass)"          },
    { 0.75f, 1, 2, "Ultra Perf (0.75x, every 2nd frame)"  },
    { 0.65f, 1, 2, "Salvage (0.65x, every 2nd frame)"     },
    { 0.55f, 1, 2, "Last Ditch (0.55x, every 2nd frame)"  },
    { 0.50f, 1, 2, "Floor (0.50x, every 2nd frame)"       },
};

constexpr int kLadderCount = int(std::size(kLadderOrderedByDescendingQuality));

constexpr uint32_t kFramesOverBudgetBeforeStepDown  = 6;
constexpr uint32_t kFramesUnderBudgetBeforeStepUp   = 90;
constexpr float    kHeadroomRequiredToStepUp        = 0.70f;
constexpr float    kMeasurementSmoothing            = 0.15f;
constexpr float    kTypicalHotTileFraction          = 0.22f;
constexpr uint32_t kNetworkExtentAlignment          = 8;

}

uint32_t alignDown(uint32_t v, uint32_t a) {
    if (a == 0) return v;
    const uint32_t r = (v / a) * a;
    return r < a ? a : r;
}

float rungCost(const Rung& r, bool selective, float tileFraction) {
    const float extraPasses = float(r.passes - 1);
    const float passFactor  = selective ? (1.0f + extraPasses * tileFraction)
                                        : float(r.passes);
    return r.workingScale * r.workingScale * passFactor / float(std::max(1u, r.cadence));
}

const Rung* Scheduler::ladder(uint32_t* count) {
    if (count) *count = uint32_t(kLadderCount);
    return kLadderOrderedByDescendingQuality;
}

void Scheduler::configure(const Config& cfg, Tier tier, Backend backend,
                          bool backendCarriesTemporalState) {
    m_cfg                  = cfg;
    m_tier                 = tier;
    m_backend              = backend;
    m_carriesTemporalState = backendCarriesTemporalState;
    m_costSeed             = costMultiplier(tier, backend);

    m_minRung = 0;
    for (int i = 0; i < kLadderCount; ++i) {
        const Rung& r = kLadderOrderedByDescendingQuality[i];
        if (r.workingScale <= cfg.workingScale + 1e-3f &&
            r.passes       <= cfg.passes &&
            r.cadence      <= std::max(1u, cfg.cadence)) {
            m_minRung = i;
            break;
        }
    }

    if (m_carriesTemporalState && m_cfg.cadence > kMaxCadenceWithCarriedTemporalState)
        m_cfg.cadence = kMaxCadenceWithCarriedTemporalState;

    m_rung = m_minRung;
    reset();
}

void Scheduler::reset() {
    m_overBudget = m_underBudget = 0;
    m_emaMs      = -1.0f;
    m_lastEval   = 0;
    m_frame      = 0;
}

const char* Scheduler::rungLabel() const {
    return kLadderOrderedByDescendingQuality[std::clamp(m_rung, 0, kLadderCount - 1)].label;
}

void Scheduler::stepDown() {
    if (m_rung < kLadderCount - 1) {
        ++m_rung;
        m_overBudget = m_underBudget = 0;
    }
}

void Scheduler::stepUp() {
    if (m_rung > m_minRung) {
        --m_rung;
        m_overBudget = m_underBudget = 0;
    }
}

Schedule Scheduler::plan(const FrameInputs& in, float measuredMs) {
    Schedule s;
    ++m_frame;

    const bool resolutionChanged =
        in.renderExtent.width  != m_lastRender.width ||
        in.renderExtent.height != m_lastRender.height;
    m_lastRender = in.renderExtent;

    if (m_cfg.autoTune && measuredMs >= 0.0f) {
        m_emaMs = (m_emaMs < 0.0f)
                    ? measuredMs
                    : m_emaMs + kMeasurementSmoothing * (measuredMs - m_emaMs);

        if (m_emaMs > m_cfg.budgetMs) {
            ++m_overBudget;
            m_underBudget = 0;
            if (m_overBudget >= kFramesOverBudgetBeforeStepDown) stepDown();
        } else if (m_emaMs < m_cfg.budgetMs * kHeadroomRequiredToStepUp) {
            ++m_underBudget;
            m_overBudget = 0;
            if (m_underBudget >= kFramesUnderBudgetBeforeStepUp) stepUp();
        } else {
            if (m_overBudget)  --m_overBudget;
            if (m_underBudget) --m_underBudget;
        }
    }

    const Rung& r = kLadderOrderedByDescendingQuality[std::clamp(m_rung, 0, kLadderCount - 1)];
    s.rung            = m_rung;
    s.workingScale    = r.workingScale;
    s.passes          = r.passes;
    s.cadence         = r.cadence;
    s.selectiveRefine = m_cfg.selectiveMultipass;

    s.networkExtent.width = alignDown(
        uint32_t(std::lround(in.renderExtent.width * r.workingScale)), kNetworkExtentAlignment);
    s.networkExtent.height = alignDown(
        uint32_t(std::lround(in.renderExtent.height * r.workingScale)), kNetworkExtentAlignment);

    const bool cachedResidualIsUnusable =
        in.resetHistory || resolutionChanged || m_frame == 1;

    if (cachedResidualIsUnusable) {
        s.evaluateThisFrame = true;
        s.resetState        = true;
    } else {
        s.evaluateThisFrame = (m_frame - m_lastEval) >= r.cadence;
        s.resetState        = false;
    }

    if (s.evaluateThisFrame) m_lastEval = m_frame;

    m_predictedMs = m_costSeed * rungCost(r, s.selectiveRefine, kTypicalHotTileFraction);
    return s;
}

}
