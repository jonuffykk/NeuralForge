// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Jonuffy
#include "nf.h"

#include <cmath>
#include <cstdio>

using namespace nf;

namespace {

int gFailures = 0;
int gChecks   = 0;

void check(bool ok, const char* expr, const char* file, int line) {
    ++gChecks;
    if (!ok) {
        ++gFailures;
        std::printf("  FAIL  %s:%d  %s\n", file, line, expr);
    }
}

#define CHECK(x) check((x), #x, __FILE__, __LINE__)

void section(const char* name) { std::printf("\n%s\n", name); }

GpuInfo gpuFor(Tier t, Vendor v) {
    GpuInfo g;
    g.tier   = t;
    g.vendor = v;
    return g;
}

void testGpuTiering() {
    section("GPU tiering");

    CHECK(classifyByDeviceId(0x10DE, 0x2B85) == Tier::Blackwell);
    CHECK(classifyByDeviceId(0x10DE, 0x2684) == Tier::Ada);
    CHECK(classifyByDeviceId(0x10DE, 0x2204) == Tier::Ampere);
    CHECK(classifyByDeviceId(0x10DE, 0x1E04) == Tier::Turing);
    CHECK(classifyByDeviceId(0x10DE, 0x1F02) == Tier::Turing);

    CHECK(classifyByDeviceId(0x10DE, 0x2184) == Tier::Unsupported);
    CHECK(classifyByDeviceId(0x10DE, 0x1F9D) == Tier::Unsupported);
    CHECK(classifyByDeviceId(0x10DE, 0x1F82) == Tier::Unsupported);
    CHECK(classifyByDeviceId(0x10DE, 0x21C4) == Tier::Unsupported);

    CHECK(classifyByDeviceId(0x10DE, 0x1B80) == Tier::Unsupported);
    CHECK(classifyByDeviceId(0x10DE, 0x1C03) == Tier::Unsupported);

    CHECK(classifyByDeviceId(0x1002, 0x7550) == Tier::RDNA4);
    CHECK(classifyByDeviceId(0x1002, 0x744C) == Tier::RDNA3);
    CHECK(classifyByDeviceId(0x1002, 0x73BF) == Tier::Unsupported);
    CHECK(classifyByDeviceId(0x8086, 0x56A0) == Tier::Unsupported);
}

void testBackendSelection() {
    section("Backend selection");

    CHECK(selectBackend(gpuFor(Tier::Blackwell, Vendor::Nvidia), true, true) == Backend::NgxFp8);
    CHECK(selectBackend(gpuFor(Tier::Ada,       Vendor::Nvidia), true, true) == Backend::NgxFp8);

    CHECK(selectBackend(gpuFor(Tier::Ampere, Vendor::Nvidia), true,  true) == Backend::NgxFp16);
    CHECK(selectBackend(gpuFor(Tier::Turing, Vendor::Nvidia), true,  true) == Backend::NgxFp16);
    CHECK(selectBackend(gpuFor(Tier::Ampere, Vendor::Nvidia), false, true) == Backend::None);

    CHECK(selectBackend(gpuFor(Tier::RDNA4, Vendor::Amd), true, true)  == Backend::Hip);
    CHECK(selectBackend(gpuFor(Tier::RDNA4, Vendor::Amd), true, false) == Backend::DirectML);

    CHECK(selectBackend(gpuFor(Tier::Unsupported, Vendor::Nvidia), true, true) == Backend::None);

    CHECK(!explainSelection(gpuFor(Tier::Unsupported, Vendor::Nvidia), Backend::None).empty());
    CHECK(!explainSelection(gpuFor(Tier::Blackwell,   Vendor::Nvidia), Backend::NgxFp8).empty());
}

void testCostModel() {
    section("Cost model");

    CHECK(costMultiplier(Tier::Blackwell, Backend::NgxFp8)  < costMultiplier(Tier::Ada,    Backend::NgxFp8));
    CHECK(costMultiplier(Tier::Ada,       Backend::NgxFp8)  < costMultiplier(Tier::Ampere, Backend::NgxFp16));
    CHECK(costMultiplier(Tier::Ampere,    Backend::NgxFp16) < costMultiplier(Tier::Turing, Backend::NgxFp16));
    CHECK(costMultiplier(Tier::Unsupported, Backend::None) == 0.0f);
    CHECK(costMultiplier(Tier::Ampere, Backend::NgxFp16) >
          costMultiplier(Tier::Ampere, Backend::NgxFp8) * 1.9f);
}

void testLadder() {
    section("Quality ladder");

    uint32_t n = 0;
    const Rung* rungs = Scheduler::ladder(&n);
    CHECK(n > 0);

    for (uint32_t i = 1; i < n; ++i) {
        const float above = rungCost(rungs[i - 1], true, 0.22f);
        const float here  = rungCost(rungs[i],     true, 0.22f);
        check(here < above, "rung cost strictly decreasing", __FILE__, __LINE__);
    }

    for (uint32_t i = 0; i < n; ++i) {
        CHECK(rungs[i].cadence <= 2);
        CHECK(rungs[i].workingScale >= 0.40f);
        CHECK(rungs[i].workingScale <= 1.00f);
        CHECK(rungs[i].passes >= 1 && rungs[i].passes <= 3);
        CHECK(rungs[i].label != nullptr);
    }
}

void testRungCost() {
    section("Rung cost");

    const Rung full { 1.00f, 1, 1, "full" };
    const Rung half { 0.50f, 1, 1, "half" };
    CHECK(std::fabs(rungCost(half, true, 0.22f) - rungCost(full, true, 0.22f) * 0.25f) < 1e-5f);

    const Rung cad2 { 1.00f, 1, 2, "cadence 2" };
    CHECK(std::fabs(rungCost(cad2, true, 0.22f) - rungCost(full, true, 0.22f) * 0.5f) < 1e-5f);

    const Rung two { 1.00f, 2, 1, "two pass" };
    CHECK(rungCost(two, true,  0.22f) < rungCost(two, false, 0.22f));
    CHECK(rungCost(two, false, 0.22f) == 2.0f);
}

void testAlignment() {
    section("Alignment");

    CHECK(alignDown(1920, 8) == 1920);
    CHECK(alignDown(1921, 8) == 1920);
    CHECK(alignDown(1927, 8) == 1920);
    CHECK(alignDown(7,    8) == 8);
    CHECK(alignDown(0,    8) == 8);
    CHECK(alignDown(100,  0) == 100);
}

void testConfigSanitise() {
    section("Config clamping");

    Config c;
    c.workingScale  = 5.0f;
    c.passes        = 99;
    c.cadence       = 99;
    c.budgetMs      = -3.0f;
    c.tileThreshold = 100.0f;
    c.intensity.global.structure = 99.0f;
    c.intensity.skin.tone        = -5.0f;
    c.model         = 1000;
    c.sanitise();

    CHECK(c.workingScale <= 1.0f && c.workingScale >= 0.40f);
    CHECK(c.passes  >= 1 && c.passes  <= 3);
    CHECK(c.cadence >= 1 && c.cadence <= 4);
    CHECK(c.budgetMs > 0.0f);
    CHECK(c.tileThreshold <= 1.0f);
    CHECK(c.intensity.global.structure <= 2.0f);
    CHECK(c.intensity.skin.tone >= 0.0f);
    CHECK(c.model == kModelAuto);
}

void testResolveAuto() {
    section("Per-tier defaults");

    auto resolved = [](Tier t, Vendor v) {
        Config  c;
        GpuInfo g = gpuFor(t, v);
        resolveAuto(c, g);
        return c;
    };

    const Config blackwell = resolved(Tier::Blackwell, Vendor::Nvidia);
    const Config ampere    = resolved(Tier::Ampere,    Vendor::Nvidia);
    const Config rdna3     = resolved(Tier::RDNA3,     Vendor::Amd);

    CHECK(ampere.workingScale < blackwell.workingScale);
    CHECK(ampere.budgetMs     > blackwell.budgetMs);
    CHECK(rdna3.workingScale  < ampere.workingScale);
    CHECK(rdna3.budgetMs      > ampere.budgetMs);

    Config  post; post.placement = Placement::PostSR;
    GpuInfo amp = gpuFor(Tier::Ampere, Vendor::Nvidia);
    resolveAuto(post, amp);
    CHECK(post.placement == Placement::Deferred);

    Config  postAda; postAda.placement = Placement::PostSR;
    GpuInfo ada = gpuFor(Tier::Ada, Vendor::Nvidia);
    resolveAuto(postAda, ada);
    CHECK(postAda.placement == Placement::PostSR);

    Config  none;
    GpuInfo bad = gpuFor(Tier::Unsupported, Vendor::Unknown);
    resolveAuto(none, bad);
    CHECK(none.enabled == false);
}

void testAutotuner() {
    section("Autotuner");

    Config c;
    c.autoTune = true;
    c.budgetMs = 2.0f;

    Scheduler sched;
    sched.configure(c, Tier::Ampere, Backend::NgxFp16, true);

    FrameInputs in;
    in.renderExtent = { 1920, 1080 };
    in.outputExtent = { 2560, 1440 };

    const int startRung = sched.currentRung();
    for (int i = 0; i < 30; ++i) sched.plan(in, 8.0f);
    CHECK(sched.currentRung() > startRung);

    const int loweredRung = sched.currentRung();
    sched.plan(in, 0.1f);
    CHECK(sched.currentRung() == loweredRung);

    Config capped;
    capped.autoTune     = true;
    capped.workingScale = 0.75f;
    capped.passes       = 1;

    Scheduler capSched;
    capSched.configure(capped, Tier::Ada, Backend::NgxFp8, true);

    uint32_t n = 0;
    const Rung* rungs = Scheduler::ladder(&n);
    for (int i = 0; i < 500; ++i) capSched.plan(in, 0.01f);
    CHECK(rungs[capSched.currentRung()].workingScale <= 0.75f + 1e-3f);
}

void testCadenceAndReset() {
    section("Cadence and history reset");

    Config c;
    c.autoTune = false;
    c.cadence  = 2;

    Scheduler sched;
    sched.configure(c, Tier::Blackwell, Backend::NgxFp8, true);

    FrameInputs in;
    in.renderExtent = { 1920, 1080 };
    in.outputExtent = { 1920, 1080 };

    Schedule s = sched.plan(in, -1.0f);
    CHECK(s.evaluateThisFrame);
    CHECK(s.resetState);

    in.resetHistory = true;
    s = sched.plan(in, 1.0f);
    CHECK(s.evaluateThisFrame);
    CHECK(s.resetState);
    in.resetHistory = false;

    in.renderExtent = { 2560, 1440 };
    s = sched.plan(in, 1.0f);
    CHECK(s.evaluateThisFrame);
    CHECK(s.resetState);

    CHECK(s.networkExtent.width  % 8 == 0);
    CHECK(s.networkExtent.height % 8 == 0);
    CHECK(s.networkExtent.width  <= in.renderExtent.width);

    Config greedy;
    greedy.autoTune = false;
    greedy.cadence  = 4;

    Scheduler greedySched;
    greedySched.configure(greedy, Tier::Turing, Backend::NgxFp16, true);

    FrameInputs g;
    g.renderExtent = { 1280, 720 };
    g.outputExtent = { 1920, 1080 };

    int evaluated = 0;
    for (int i = 0; i < 20; ++i)
        if (greedySched.plan(g, 1.0f).evaluateThisFrame) ++evaluated;

    CHECK(evaluated >= 10);
}

}

int main() {
    std::printf("NeuralForge unit tests\n");

    testGpuTiering();
    testBackendSelection();
    testCostModel();
    testLadder();
    testRungCost();
    testAlignment();
    testConfigSanitise();
    testResolveAuto();
    testAutotuner();
    testCadenceAndReset();

    std::printf("\n%d checks, %d failures\n", gChecks, gFailures);
    return gFailures == 0 ? 0 : 1;
}
