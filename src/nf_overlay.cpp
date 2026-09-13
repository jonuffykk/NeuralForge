// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Jonuffy
#include "nf.h"

#if defined(NF_WITH_IMGUI)
  #include <imgui.h>
#endif

namespace nf {

#if defined(NF_WITH_IMGUI)

namespace {

void help(const char* text) {
    ImGui::SameLine();
    ImGui::TextDisabled("(?)");
    if (ImGui::IsItemHovered()) {
        ImGui::BeginTooltip();
        ImGui::PushTextWrapPos(ImGui::GetFontSize() * 32.0f);
        ImGui::TextUnformatted(text);
        ImGui::PopTextWrapPos();
        ImGui::EndTooltip();
    }
}

void drawHardware(const Pipeline& p) {
    const GpuInfo& gpu = p.gpu();

    ImGui::TextUnformatted(gpu.name.c_str());
    if (gpu.heuristic) {
        ImGui::TextColored({1.0f, 0.75f, 0.2f, 1.0f},
            "Identified by device ID heuristic.");
        help("NVAPI and AGS were unavailable, so the architecture name came from "
             "the PCI device ID. Capability gating still applies, so this affects "
             "reporting rather than safety.");
    }
    ImGui::Separator();
    ImGui::TextWrapped("%s", p.statusLine());
}

void drawLook(Config& cfg, bool& dirty) {
    ImGui::SeparatorText("Look");

    dirty |= ImGui::SliderFloat("Structure", &cfg.intensity.global.structure, 0.0f, 2.0f, "%.2f");
    help("High-frequency response: contact shadows, ambient occlusion, subsurface "
         "scattering, sheen. 0 is an exact no-op, 1 is the runtime's native "
         "strength. Above about 1.4 it starts fighting the game's art direction.");

    dirty |= ImGui::SliderFloat("Tone", &cfg.intensity.global.tone, 0.0f, 2.0f, "%.2f");
    help("Low-frequency response: broad lighting and colour. Set this to 0 to keep "
         "the game's exact colours while still getting structural detail from the "
         "slider above. Good starting point for a title with a deliberate grade.");

    if (ImGui::TreeNode("Per-material overrides")) {
        ImGui::TextDisabled("Multipliers on the global values above.");
        dirty |= ImGui::SliderFloat("Skin structure",    &cfg.intensity.skin.structure,    0.0f, 2.0f, "%.2f");
        dirty |= ImGui::SliderFloat("Skin tone",         &cfg.intensity.skin.tone,         0.0f, 2.0f, "%.2f");
        help("Faces are where the enhancement is most visible and most often "
             "unwanted. Skin structure around 0.6 with the environment at 1.0 is "
             "the adjustment most people settle on.");
        dirty |= ImGui::SliderFloat("Foliage structure", &cfg.intensity.foliage.structure, 0.0f, 2.0f, "%.2f");
        dirty |= ImGui::SliderFloat("Foliage tone",      &cfg.intensity.foliage.tone,      0.0f, 2.0f, "%.2f");
        ImGui::TreePop();
    }
}

void drawPerformance(const Pipeline& p, Config& cfg, bool& dirty) {
    const FrameStats& st = p.stats();
    const Scheduler&  sc = p.tuner();

    ImGui::SeparatorText("Performance");

    ImGui::Text("Stage cost: %.2f ms", st.totalMs);
    ImGui::SameLine();
    ImGui::TextDisabled("(inference %.2f + composite %.2f)", st.inferenceMs, st.compositeMs);

    dirty |= ImGui::Checkbox("Auto-tune", &cfg.autoTune);
    help("Holds the stage inside the frame budget by walking a fixed quality "
         "ladder. Your manual settings become the ceiling: it will go cheaper "
         "than you asked to protect the budget, never more expensive.");

    dirty |= ImGui::SliderFloat("Frame budget (ms)", &cfg.budgetMs, 0.25f, 20.0f, "%.2f");

    if (cfg.autoTune) {
        ImGui::TextColored({0.5f, 0.85f, 1.0f, 1.0f}, "Active rung: %s", sc.rungLabel());
        ImGui::TextDisabled("Sliders below are upper bounds while auto-tune is on.");
    }

    ImGui::BeginDisabled(cfg.autoTune);

    dirty |= ImGui::SliderFloat("Working scale", &cfg.workingScale, 0.40f, 1.0f, "%.2f");
    help("Resolution the network runs at, relative to render resolution. Cost "
         "falls with the square. Quality falls far more slowly because only the "
         "residual is consumed and a residual is band-limited. 0.75 is close to "
         "free; 0.50 is visible but still better than turning the stage off.");

    int passes = int(cfg.passes);
    if (ImGui::SliderInt("Passes", &passes, 1, 3)) { cfg.passes = uint32_t(passes); dirty = true; }

    dirty |= ImGui::Checkbox("Selective refinement", &cfg.selectiveMultipass);
    help("Restricts passes 2 and 3 to tiles the first pass actually changed, "
         "usually 15 to 30 percent of them. A second pass then costs about a "
         "fifth of the first rather than doubling it.");

    int cadence = int(cfg.cadence);
    if (ImGui::SliderInt("Cadence", &cadence, 1, 4)) { cfg.cadence = uint32_t(cadence); dirty = true; }
    if (cfg.cadence > 2) {
        ImGui::TextColored({1.0f, 0.4f, 0.4f, 1.0f},
            "Cadence above 2 is not recommended on this backend.");
        help("The vendor runtime carries recurrent temporal state between "
             "evaluations. Skipping frames leaves it stale, and past two frames "
             "the staleness compounds into visible beating. NeuralForge clamps "
             "this unless the active backend reconstructs state explicitly.");
    }

    ImGui::EndDisabled();

    if (st.wasReprojected)
        ImGui::TextDisabled("This frame: residual reprojected, network not evaluated.");
    if (st.passesExecuted)
        ImGui::TextDisabled("Passes: %u   Tiles: %u / %u",
                            st.passesExecuted, st.tilesEvaluated, st.tilesTotal);
}

}

void drawOverlay(Pipeline& pipeline, Config& cfg) {
    if (!ImGui::Begin("NeuralForge")) { ImGui::End(); return; }

    bool dirty = false;
    drawHardware(pipeline);

    if (!pipeline.isActive()) {
        ImGui::TextColored({1.0f, 0.4f, 0.4f, 1.0f}, "Neural rendering is not running.");
        ImGui::TextWrapped("%s", pipeline.statusLine());
        ImGui::End();
        return;
    }

    dirty |= ImGui::Checkbox("Enabled", &cfg.enabled);
    drawLook(cfg, dirty);
    drawPerformance(pipeline, cfg, dirty);

    if (dirty) pipeline.applyConfig(cfg);
    ImGui::End();
}

#else

void drawOverlay(Pipeline&, Config&) {}

#endif

}
