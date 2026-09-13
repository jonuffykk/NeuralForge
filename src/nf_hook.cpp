// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Jonuffy
#ifndef WIN32_LEAN_AND_MEAN
  #define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include "nf.h"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <fstream>
#include <mutex>
#include <string>

namespace nf {
namespace {

std::once_flag            gInitOnce;
std::unique_ptr<Pipeline> gPipeline;
Config                    gConfig;
std::string               gModuleDir;
bool                      gRefusedToLoad = false;
std::string               gRefusalReason;

const wchar_t* kAntiCheatModuleNames[] = {
    L"EasyAntiCheat.dll", L"EasyAntiCheat_x64.dll",
    L"BEClient.dll",      L"BEClient_x64.dll",
    L"vgk.sys",           L"vgc.exe",
    L"anticheat.dll",     L"PnkBstrA.exe",
};

std::string toLower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(),
                   [](unsigned char c) { return char(std::tolower(c)); });
    return s;
}

std::string hostExecutableName() {
    char path[MAX_PATH] {};
    GetModuleFileNameA(nullptr, path, MAX_PATH);

    const char* back  = std::strrchr(path, '\\');
    const char* fwd   = std::strrchr(path, '/');
    const char* slash = back > fwd ? back : fwd;

    return toLower(slash ? slash + 1 : path);
}

bool anyAntiCheatModuleIsResident() {
    for (const wchar_t* name : kAntiCheatModuleNames)
        if (GetModuleHandleW(name)) return true;
    return false;
}

bool executableIsOnDenylist(const std::string& exe) {
    std::ifstream f(gModuleDir + "\\configs\\anticheat_denylist.txt");
    if (!f) return false;

    std::string line;
    while (std::getline(f, line)) {
        const auto comment = line.find('#');
        if (comment != std::string::npos) line.erase(comment);

        line.erase(line.find_last_not_of(" \t\r\n") + 1);
        line.erase(0, line.find_first_not_of(" \t"));

        if (!line.empty() && toLower(line) == exe) return true;
    }
    return false;
}

bool passesSafetyGate(std::string* reason) {
    if (!gConfig.blockOnAntiCheat) return true;

    if (anyAntiCheatModuleIsResident()) {
        *reason = "an anti-cheat module is loaded in this process. NeuralForge "
                  "will not initialise. Injecting a renderer modification into a "
                  "protected multiplayer title risks your account.";
        return false;
    }

    if (executableIsOnDenylist(hostExecutableName())) {
        *reason = "this executable is on the NeuralForge denylist. Refusing to load.";
        return false;
    }

    return true;
}

void initialiseOnce() {
    std::string warnings;
    gConfig.loadFromFile(gModuleDir + "\\configs\\neuralforge.ini", &warnings);

    if (!passesSafetyGate(&gRefusalReason)) {
        gRefusedToLoad = true;
        return;
    }

    gPipeline = std::make_unique<Pipeline>();
}

FrameInputs normaliseFromDlss(const void* args);
FrameInputs normaliseFromFsr (const void* args);
FrameInputs normaliseFromXess(const void* args);

bool onUpscalerDispatch(const DeviceHandles& handles, void* cmdList,
                        const FrameInputs& in, void* srOutput) {
    if (gRefusedToLoad || !gPipeline) return false;

    if (!gPipeline->isActive()) {
        std::string err;
        if (!gPipeline->initialise(handles, gConfig, &err)) {
            OutputDebugStringA(("[NeuralForge] " + err + "\n").c_str());
            gRefusedToLoad = true;
            gRefusalReason = err;
            return false;
        }
        OutputDebugStringA(("[NeuralForge] " +
                            std::string(gPipeline->statusLine()) + "\n").c_str());
    }

    return gPipeline->execute(cmdList, in, srOutput);
}

}

extern "C" __declspec(dllexport) const char* NfStatus() {
    if (gRefusedToLoad)
        return gRefusalReason.empty() ? "refused to load" : gRefusalReason.c_str();
    if (!gPipeline)
        return "not initialised";
    return gPipeline->statusLine();
}

extern "C" __declspec(dllexport) int NfReloadConfig() {
    std::string warnings;
    if (!gConfig.loadFromFile(gModuleDir + "\\configs\\neuralforge.ini", &warnings))
        return 0;

    if (gPipeline) gPipeline->applyConfig(gConfig);
    return 1;
}

}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID) {
    switch (reason) {
        case DLL_PROCESS_ATTACH: {
            DisableThreadLibraryCalls(module);

            char path[MAX_PATH] {};
            GetModuleFileNameA(module, path, MAX_PATH);
            if (char* slash = std::strrchr(path, '\\')) *slash = '\0';
            nf::gModuleDir = path;

            std::call_once(nf::gInitOnce, nf::initialiseOnce);
            break;
        }
        case DLL_PROCESS_DETACH:
            if (nf::gPipeline) nf::gPipeline->shutdown();
            break;
        default:
            break;
    }
    return TRUE;
}
