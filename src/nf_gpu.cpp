// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Jonuffy
#include "nf.h"

#include <algorithm>
#include <cstdio>
#include <iterator>

#if !defined(NF_NO_D3D)
  #ifndef WIN32_LEAN_AND_MEAN
    #define WIN32_LEAN_AND_MEAN
  #endif
  #include <windows.h>
  #include <dxgi1_6.h>
  #include <wrl/client.h>
  using Microsoft::WRL::ComPtr;
#endif

namespace nf {
namespace {

constexpr uint32_t kVendorNvidia = 0x10DE;
constexpr uint32_t kVendorAmd    = 0x1002;
constexpr uint32_t kVendorIntel  = 0x8086;

struct IdRange {
    uint32_t lo;
    uint32_t hi;
    Tier     tier;
};

constexpr IdRange kNvidiaDiesWithoutTensorCores[] = {
    { 0x1F80, 0x1FFF, Tier::Unsupported },
    { 0x2180, 0x21FF, Tier::Unsupported },
};

constexpr IdRange kNvidiaArchitectures[] = {
    { 0x1E00, 0x1E9F, Tier::Turing    },
    { 0x1F00, 0x1F7F, Tier::Turing    },
    { 0x2200, 0x25FF, Tier::Ampere    },
    { 0x2600, 0x28FF, Tier::Ada       },
    { 0x2900, 0x2FFF, Tier::Blackwell },
};

constexpr IdRange kAmdArchitectures[] = {
    { 0x7440, 0x744F, Tier::RDNA3 },
    { 0x7470, 0x747F, Tier::RDNA3 },
    { 0x7480, 0x748F, Tier::RDNA3 },
    { 0x7500, 0x759F, Tier::RDNA4 },
};

bool inRange(const IdRange* table, size_t n, uint32_t id) {
    for (size_t i = 0; i < n; ++i)
        if (id >= table[i].lo && id <= table[i].hi) return true;
    return false;
}

Tier lookup(const IdRange* table, size_t n, uint32_t id) {
    for (size_t i = 0; i < n; ++i)
        if (id >= table[i].lo && id <= table[i].hi) return table[i].tier;
    return Tier::Unsupported;
}

}

Tier classifyByDeviceId(uint32_t vendorId, uint32_t deviceId) {
    if (vendorId == kVendorNvidia) {
        if (inRange(kNvidiaDiesWithoutTensorCores,
                    std::size(kNvidiaDiesWithoutTensorCores), deviceId))
            return Tier::Unsupported;

        return lookup(kNvidiaArchitectures, std::size(kNvidiaArchitectures), deviceId);
    }

    if (vendorId == kVendorAmd)
        return lookup(kAmdArchitectures, std::size(kAmdArchitectures), deviceId);

    if (vendorId == kVendorIntel)
        return Tier::Unsupported;

    return Tier::Unsupported;
}

#if !defined(NF_NO_D3D)

GpuInfo detectGpu(uint64_t adapterLuid) {
    GpuInfo info;

    ComPtr<IDXGIFactory6> factory;
    if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) return info;

    ComPtr<IDXGIAdapter1> adapter, best;
    DXGI_ADAPTER_DESC1    bestDesc {};
    uint64_t              bestVram = 0;

    for (UINT i = 0; factory->EnumAdapters1(i, &adapter) != DXGI_ERROR_NOT_FOUND; ++i) {
        DXGI_ADAPTER_DESC1 desc {};
        if (FAILED(adapter->GetDesc1(&desc)))        continue;
        if (desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) continue;

        const uint64_t luid = (uint64_t(desc.AdapterLuid.HighPart) << 32) |
                               uint32_t(desc.AdapterLuid.LowPart);

        if (adapterLuid != 0 && luid == adapterLuid) {
            best = adapter; bestDesc = desc; break;
        }
        if (desc.DedicatedVideoMemory > bestVram) {
            bestVram = desc.DedicatedVideoMemory;
            best     = adapter;
            bestDesc = desc;
        }
    }
    if (!best) return info;

    info.vendorId  = bestDesc.VendorId;
    info.deviceId  = bestDesc.DeviceId;
    info.vramBytes = bestDesc.DedicatedVideoMemory;

    char name[256] {};
    WideCharToMultiByte(CP_UTF8, 0, bestDesc.Description, -1,
                        name, sizeof(name) - 1, nullptr, nullptr);
    info.name = name;

    switch (info.vendorId) {
        case kVendorNvidia: info.vendor = Vendor::Nvidia; break;
        case kVendorAmd:    info.vendor = Vendor::Amd;    break;
        case kVendorIntel:  info.vendor = Vendor::Intel;  break;
        default:            info.vendor = Vendor::Unknown;break;
    }

    info.tier                      = classifyByDeviceId(info.vendorId, info.deviceId);
    info.identifiedByHeuristicOnly = true;
    return info;
}

#endif

Backend selectBackend(const GpuInfo& gpu, bool allowFp16, bool preferHip) {
    if (!gpu.canRun()) return Backend::None;

    if (gpu.hasVendorRuntime()) {
        if (gpu.supportsFp8()) return Backend::NgxFp8;
        return allowFp16 ? Backend::NgxFp16 : Backend::None;
    }

    if (gpu.vendor == Vendor::Amd)
        return preferHip ? Backend::Hip : Backend::DirectML;

    return Backend::None;
}

float costMultiplier(Tier tier, Backend backend) {
    constexpr float kFp16RequantisationPenalty = 2.00f;
    constexpr float kDirectMlDispatchOverhead  = 1.35f;

    float base;
    switch (tier) {
        case Tier::Blackwell: base =  1.0f; break;
        case Tier::Ada:       base =  1.6f; break;
        case Tier::Ampere:    base =  4.5f; break;
        case Tier::Turing:    base =  9.0f; break;
        case Tier::RDNA4:     base =  6.0f; break;
        case Tier::RDNA3:     base = 12.0f; break;
        default:              return 0.0f;
    }

    if (backend == Backend::NgxFp16)  base *= kFp16RequantisationPenalty;
    if (backend == Backend::DirectML) base *= kDirectMlDispatchOverhead;
    return base;
}

std::string explainSelection(const GpuInfo& gpu, Backend chosen) {
    const char* tierName = "unknown";
    switch (gpu.tier) {
        case Tier::Blackwell:   tierName = "Blackwell (RTX 50)"; break;
        case Tier::Ada:         tierName = "Ada (RTX 40)";       break;
        case Tier::Ampere:      tierName = "Ampere (RTX 30)";    break;
        case Tier::Turing:      tierName = "Turing (RTX 20)";    break;
        case Tier::RDNA4:       tierName = "RDNA 4 (RX 9000)";   break;
        case Tier::RDNA3:       tierName = "RDNA 3 (RX 7000)";   break;
        case Tier::Unsupported: tierName = "unsupported";        break;
    }

    char buf[512];
    switch (chosen) {
        case Backend::NgxFp8:
            std::snprintf(buf, sizeof buf,
                "%s: vendor runtime, native FP8. Weights used as shipped. "
                "Expect about %.1fx the cost of an RTX 50.",
                tierName, costMultiplier(gpu.tier, chosen));
            break;
        case Backend::NgxFp16:
            std::snprintf(buf, sizeof buf,
                "%s: vendor runtime, FP16 requantised. This silicon has no FP8 "
                "tensor path, so expect about %.0fx the cost of an RTX 50 and "
                "roughly double the weight footprint. Lower WorkingScale.",
                tierName, costMultiplier(gpu.tier, chosen));
            break;
        case Backend::DirectML:
        case Backend::Hip:
            std::snprintf(buf, sizeof buf,
                "%s: portable %s reimplementation, about %.0fx the cost of an "
                "RTX 50. Experimental, not a playable configuration.",
                tierName, chosen == Backend::Hip ? "HIP" : "DirectML",
                costMultiplier(gpu.tier, chosen));
            break;
        default:
            std::snprintf(buf, sizeof buf,
                "%s: no tensor units, so a 148M-parameter network has nowhere to "
                "run. This is a hardware limit, not a setting.", tierName);
            break;
    }
    return buf;
}

}
