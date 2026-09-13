// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Jonuffy
#include "nf.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <fstream>
#include <sstream>

namespace nf {
namespace {

std::string trim(std::string s) {
    auto notSpace = [](unsigned char c) { return !std::isspace(c); };
    s.erase(s.begin(), std::find_if(s.begin(), s.end(), notSpace));
    s.erase(std::find_if(s.rbegin(), s.rend(), notSpace).base(), s.end());
    return s;
}

std::string lower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(),
                   [](unsigned char c) { return char(std::tolower(c)); });
    return s;
}

bool parseBool(const std::string& v, bool fallback) {
    const std::string s = lower(v);
    if (s == "true"  || s == "1" || s == "yes" || s == "on")  return true;
    if (s == "false" || s == "0" || s == "no"  || s == "off") return false;
    return fallback;
}

float parseFloat(const std::string& v, float fallback, bool* ok) {
    char* end = nullptr;
    const float f = std::strtof(v.c_str(), &end);
    const bool good = end && end != v.c_str();
    if (ok) *ok = good;
    return good ? f : fallback;
}

uint32_t parseUint(const std::string& v, uint32_t fallback, bool* ok) {
    char* end = nullptr;
    const unsigned long u = std::strtoul(v.c_str(), &end, 0);
    const bool good = end && end != v.c_str();
    if (ok) *ok = good;
    return good ? uint32_t(u) : fallback;
}

Placement parsePlacement(const std::string& v, Placement fallback) {
    const std::string s = lower(v);
    if (s == "deferred" || s == "residual") return Placement::Deferred;
    if (s == "presr"    || s == "pre")      return Placement::PreSR;
    if (s == "postsr"   || s == "post")     return Placement::PostSR;
    return fallback;
}

Backend parseBackend(const std::string& v, Backend fallback) {
    const std::string s = lower(v);
    if (s == "auto")     return Backend::None;
    if (s == "fp8")      return Backend::NgxFp8;
    if (s == "fp16")     return Backend::NgxFp16;
    if (s == "directml") return Backend::DirectML;
    if (s == "hip")      return Backend::Hip;
    return fallback;
}

const char* placementName(Placement p) {
    switch (p) {
        case Placement::PreSR:  return "presr";
        case Placement::PostSR: return "postsr";
        default:                return "deferred";
    }
}

const char* backendName(Backend b) {
    switch (b) {
        case Backend::NgxFp8:   return "fp8";
        case Backend::NgxFp16:  return "fp16";
        case Backend::DirectML: return "directml";
        case Backend::Hip:      return "hip";
        default:                return "auto";
    }
}

}

void Config::sanitise() {
    workingScale  = std::clamp(workingScale,  0.40f,  1.00f);
    passes        = std::clamp(passes,        1u,     3u);
    cadence       = std::clamp(cadence,       1u,     4u);
    budgetMs      = std::clamp(budgetMs,      0.25f,  20.0f);
    tileThreshold = std::clamp(tileThreshold, 0.001f, 1.0f);

    auto clampPair = [](Intensity& i) {
        i.structure = std::clamp(i.structure, 0.0f, 2.0f);
        i.tone      = std::clamp(i.tone,      0.0f, 2.0f);
    };
    clampPair(intensity.global);
    clampPair(intensity.skin);
    clampPair(intensity.foliage);

    if (model != kModelAuto && model >= kMaxModels) model = kModelAuto;
}

bool Config::loadFromFile(const std::string& path, std::string* warnings) {
    std::ifstream f(path);
    if (!f) return false;

    std::ostringstream warn;
    std::string        line;

    while (std::getline(f, line)) {
        line = trim(line);
        if (line.empty() || line[0] == ';' || line[0] == '#') continue;
        if (line.front() == '[' && line.back() == ']')        continue;

        const auto eq = line.find('=');
        if (eq == std::string::npos) { warn << "malformed line ignored: " << line << "\n"; continue; }

        const std::string key = lower(trim(line.substr(0, eq)));
        const std::string val = trim(line.substr(eq + 1));
        bool ok = true;

        if      (key == "enabled")            enabled            = parseBool(val, enabled);
        else if (key == "backend")            backend            = parseBackend(val, backend);
        else if (key == "model")              model              = (lower(val) == "auto")
                                                                     ? kModelAuto
                                                                     : parseUint(val, model, &ok);
        else if (key == "placement")          placement          = parsePlacement(val, placement);
        else if (key == "workingscale")       workingScale       = parseFloat(val, workingScale, &ok);
        else if (key == "passes")             passes             = parseUint(val, passes, &ok);
        else if (key == "cadence")            cadence            = parseUint(val, cadence, &ok);
        else if (key == "selectivemultipass") selectiveMultipass = parseBool(val, selectiveMultipass);
        else if (key == "tilethreshold")      tileThreshold      = parseFloat(val, tileThreshold, &ok);
        else if (key == "autotune")           autoTune           = parseBool(val, autoTune);
        else if (key == "budgetms")           budgetMs           = parseFloat(val, budgetMs, &ok);
        else if (key == "structure")          intensity.global.structure  = parseFloat(val, intensity.global.structure, &ok);
        else if (key == "tone")               intensity.global.tone       = parseFloat(val, intensity.global.tone, &ok);
        else if (key == "skinstructure")      intensity.skin.structure    = parseFloat(val, intensity.skin.structure, &ok);
        else if (key == "skintone")           intensity.skin.tone         = parseFloat(val, intensity.skin.tone, &ok);
        else if (key == "foliagestructure")   intensity.foliage.structure = parseFloat(val, intensity.foliage.structure, &ok);
        else if (key == "foliagetone")        intensity.foliage.tone      = parseFloat(val, intensity.foliage.tone, &ok);
        else if (key == "blockonanticheat")   blockOnAntiCheat   = parseBool(val, blockOnAntiCheat);
        else if (key == "allowfp16fallback")  allowFp16Fallback  = parseBool(val, allowFp16Fallback);
        else if (key == "requiremotionvectors") requireMotionVectors = parseBool(val, requireMotionVectors);
        else if (key == "allowd3d11bridge")   allowD3D11Bridge   = parseBool(val, allowD3D11Bridge);
        else if (key == "allowopticalflow")   allowOpticalFlow   = parseBool(val, allowOpticalFlow);
        else if (key == "runtimepath")        runtimePath        = val;
        else if (key == "overlayhotkey")      overlayHotkey      = parseUint(val, overlayHotkey, &ok);
        else if (key == "showstats")          showStats          = parseBool(val, showStats);
        else { warn << "unknown key ignored: " << key << "\n"; continue; }

        if (!ok) warn << "unparseable value for " << key << ": " << val << "\n";
    }

    sanitise();
    if (warnings) *warnings = warn.str();
    return true;
}

bool Config::saveToFile(const std::string& path) const {
    std::ofstream f(path, std::ios::trunc);
    if (!f) return false;

    f << "; NeuralForge configuration. See docs/PERFORMANCE_GUIDE.md\n\n"
      << "[General]\n"
      << "Enabled              = " << (enabled ? "true" : "false") << "\n"
      << "Backend              = " << backendName(backend)         << "\n"
      << "Model                = " << (model == kModelAuto ? std::string("auto")
                                                           : std::to_string(model)) << "\n"
      << "Placement            = " << placementName(placement)     << "\n\n"
      << "[Look]\n"
      << "Structure            = " << intensity.global.structure   << "\n"
      << "Tone                 = " << intensity.global.tone        << "\n"
      << "SkinStructure        = " << intensity.skin.structure     << "\n"
      << "SkinTone             = " << intensity.skin.tone          << "\n"
      << "FoliageStructure     = " << intensity.foliage.structure  << "\n"
      << "FoliageTone          = " << intensity.foliage.tone       << "\n\n"
      << "[Performance]\n"
      << "AutoTune             = " << (autoTune ? "true" : "false")<< "\n"
      << "BudgetMs             = " << budgetMs                     << "\n"
      << "WorkingScale         = " << workingScale                 << "\n"
      << "Passes               = " << passes                       << "\n"
      << "Cadence              = " << cadence                      << "\n"
      << "SelectiveMultipass   = " << (selectiveMultipass ? "true" : "false") << "\n"
      << "TileThreshold        = " << tileThreshold                << "\n\n"
      << "[Safety]\n"
      << "BlockOnAntiCheat     = " << (blockOnAntiCheat ? "true" : "false")   << "\n"
      << "AllowFp16Fallback    = " << (allowFp16Fallback ? "true" : "false")  << "\n"
      << "RequireMotionVectors = " << (requireMotionVectors ? "true" : "false") << "\n"
      << "AllowD3D11Bridge     = " << (allowD3D11Bridge ? "true" : "false")     << "\n"
      << "AllowOpticalFlow     = " << (allowOpticalFlow ? "true" : "false")     << "\n"
      << "RuntimePath          = " << runtimePath                               << "\n\n"
      << "[UI]\n"
      << "OverlayHotkey        = " << overlayHotkey                << "\n"
      << "ShowStats            = " << (showStats ? "true" : "false") << "\n";

    return bool(f);
}

void resolveAuto(Config& cfg, const GpuInfo& gpu) {
    if (cfg.backend == Backend::None)
        cfg.backend = selectBackend(gpu, cfg.allowFp16Fallback, true);

    const bool untouchedScale  = (cfg.workingScale == 1.0f);
    const bool untouchedBudget = (cfg.budgetMs     == 2.0f);

    switch (gpu.tier) {
        case Tier::Blackwell:
            break;
        case Tier::Ada:
            if (untouchedBudget) cfg.budgetMs = 2.5f;
            break;
        case Tier::Ampere:
            if (untouchedScale)  cfg.workingScale = 0.75f;
            if (untouchedBudget) cfg.budgetMs     = 4.0f;
            break;
        case Tier::Turing:
        case Tier::RDNA4:
            if (untouchedScale)  cfg.workingScale = 0.65f;
            if (untouchedBudget) cfg.budgetMs     = 6.0f;
            break;
        case Tier::RDNA3:
            if (untouchedScale)  cfg.workingScale = 0.50f;
            if (untouchedBudget) cfg.budgetMs     = 8.0f;
            break;
        case Tier::Unsupported:
            cfg.enabled = false;
            break;
    }

    if (cfg.placement == Placement::PostSR && gpu.tier < Tier::Ada)
        cfg.placement = Placement::Deferred;

    cfg.sanitise();
}

}
