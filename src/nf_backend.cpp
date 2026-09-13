// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Jonuffy
#include "nf.h"

#if !defined(NF_NO_D3D)
  #include "nf_ngx.h"
#endif

#include <algorithm>
#include <string>

namespace nf {

namespace {
constexpr uint64_t kApplicationId       = 0x4E465247ull;
constexpr uint64_t kResidentWeightsFp8  = 180ull << 20;
constexpr uint64_t kResidentWeightsFp16 = 340ull << 20;
}

#if !defined(NF_NO_D3D)

namespace ngx {
namespace {

template <typename Fn>
void bind(HMODULE module, const char* name, Fn& out) {
    out = reinterpret_cast<Fn>(reinterpret_cast<void*>(GetProcAddress(module, name)));
}

HMODULE tryLoad(const wchar_t* directory) {
    if (directory && *directory) {
        std::wstring candidate = directory;
        if (candidate.back() != L'\\') candidate += L'\\';
        candidate += L"nvngx.dll";

        if (HMODULE m = LoadLibraryW(candidate.c_str())) return m;
    }

    for (const wchar_t* name : { L"nvngx.dll", L"_nvngx.dll" }) {
        if (HMODULE m = GetModuleHandleW(name)) return m;
        if (HMODULE m = LoadLibraryW(name))     return m;
    }
    return nullptr;
}

} // namespace

const char* resultToString(Result r) {
    switch (r) {
        case Result_Success:                return "success";
        case Result_FeatureNotSupported:    return "feature not supported on this hardware or driver";
        case Result_PlatformError:          return "platform error inside the runtime";
        case Result_FeatureAlreadyExists:   return "feature already exists";
        case Result_FeatureNotFound:        return "feature not found";
        case Result_InvalidParameter:       return "invalid parameter";
        case Result_ScratchBufferTooSmall:  return "scratch buffer too small";
        case Result_NotInitialized:         return "runtime not initialised";
        case Result_UnsupportedInputFormat: return "unsupported input format";
        default:                            return "unknown failure";
    }
}

bool loadApi(Api& api, const wchar_t* preferredDirectory, std::string* error) {
    unloadApi(api);

    api.module = tryLoad(preferredDirectory);
    if (!api.module) {
        if (error)
            *error = "nvngx.dll could not be loaded. It ships with the NVIDIA driver; "
                     "if this is an NVIDIA system, the driver may be too old.";
        return false;
    }

    bind(api.module, "NVSDK_NGX_D3D12_Init",                    api.d3d12Init);
    bind(api.module, "NVSDK_NGX_D3D12_Shutdown1",               api.d3d12Shutdown);
    bind(api.module, "NVSDK_NGX_D3D12_GetCapabilityParameters", api.d3d12GetCapabilityParameters);
    bind(api.module, "NVSDK_NGX_D3D12_AllocateParameters",      api.d3d12AllocateParameters);
    bind(api.module, "NVSDK_NGX_D3D12_DestroyParameters",       api.d3d12DestroyParameters);
    bind(api.module, "NVSDK_NGX_D3D12_GetScratchBufferSize",    api.d3d12GetScratchBufferSize);
    bind(api.module, "NVSDK_NGX_D3D12_CreateFeature",           api.d3d12CreateFeature);
    bind(api.module, "NVSDK_NGX_D3D12_ReleaseFeature",          api.d3d12ReleaseFeature);
    bind(api.module, "NVSDK_NGX_D3D12_EvaluateFeature",         api.d3d12EvaluateFeature);

    bind(api.module, "NVSDK_NGX_D3D11_Init",                    api.d3d11Init);
    bind(api.module, "NVSDK_NGX_D3D11_Shutdown1",               api.d3d11Shutdown);
    bind(api.module, "NVSDK_NGX_D3D11_GetCapabilityParameters", api.d3d11GetCapabilityParameters);
    bind(api.module, "NVSDK_NGX_D3D11_AllocateParameters",      api.d3d11AllocateParameters);
    bind(api.module, "NVSDK_NGX_D3D11_DestroyParameters",       api.d3d11DestroyParameters);
    bind(api.module, "NVSDK_NGX_D3D11_GetScratchBufferSize",    api.d3d11GetScratchBufferSize);
    bind(api.module, "NVSDK_NGX_D3D11_CreateFeature",           api.d3d11CreateFeature);
    bind(api.module, "NVSDK_NGX_D3D11_ReleaseFeature",          api.d3d11ReleaseFeature);
    bind(api.module, "NVSDK_NGX_D3D11_EvaluateFeature",         api.d3d11EvaluateFeature);

    if (!api.loadedD3D12() && !api.loadedD3D11()) {
        unloadApi(api);
        if (error)
            *error = "nvngx.dll loaded but exports no usable NGX entry points.";
        return false;
    }

    return true;
}

void unloadApi(Api& api) {
    api = Api {};
}

} // namespace ngx

namespace {

std::wstring widen(const std::string& s) {
    if (s.empty()) return {};
    const int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
    std::wstring out(static_cast<size_t>(n), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, out.data(), n);
    if (!out.empty() && out.back() == L'\0') out.pop_back();
    return out;
}

std::wstring directoryOf(const std::wstring& path) {
    const size_t slash = path.find_last_of(L"\\/");
    return slash == std::wstring::npos ? std::wstring {} : path.substr(0, slash);
}

class GpuTimer {
public:
    bool initialise(ID3D12Device* device, ID3D12CommandQueue* queue) {
        if (!device || !queue) return false;

        D3D12_QUERY_HEAP_DESC heapDesc {};
        heapDesc.Type  = D3D12_QUERY_HEAP_TYPE_TIMESTAMP;
        heapDesc.Count = kSlots;
        if (FAILED(device->CreateQueryHeap(&heapDesc, IID_PPV_ARGS(&m_heap)))) return false;

        D3D12_HEAP_PROPERTIES heapProps {};
        heapProps.Type = D3D12_HEAP_TYPE_READBACK;

        D3D12_RESOURCE_DESC bufferDesc {};
        bufferDesc.Dimension        = D3D12_RESOURCE_DIMENSION_BUFFER;
        bufferDesc.Width            = kSlots * sizeof(uint64_t);
        bufferDesc.Height           = 1;
        bufferDesc.DepthOrArraySize = 1;
        bufferDesc.MipLevels        = 1;
        bufferDesc.Format           = DXGI_FORMAT_UNKNOWN;
        bufferDesc.SampleDesc.Count = 1;
        bufferDesc.Layout           = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;

        if (FAILED(device->CreateCommittedResource(
                &heapProps, D3D12_HEAP_FLAG_NONE, &bufferDesc,
                D3D12_RESOURCE_STATE_COPY_DEST, nullptr, IID_PPV_ARGS(&m_readback))))
            return false;

        if (FAILED(queue->GetTimestampFrequency(&m_frequency)) || m_frequency == 0)
            return false;

        return true;
    }

    void release() {
        if (m_readback) { m_readback->Release(); m_readback = nullptr; }
        if (m_heap)     { m_heap->Release();     m_heap     = nullptr; }
    }

    void begin(ID3D12GraphicsCommandList* cmd) {
        if (m_heap && cmd) cmd->EndQuery(m_heap, D3D12_QUERY_TYPE_TIMESTAMP, 0);
    }

    void end(ID3D12GraphicsCommandList* cmd) {
        if (!m_heap || !cmd) return;
        cmd->EndQuery(m_heap, D3D12_QUERY_TYPE_TIMESTAMP, 1);
        cmd->ResolveQueryData(m_heap, D3D12_QUERY_TYPE_TIMESTAMP, 0, kSlots, m_readback, 0);
        m_pending = true;
    }

    float readMilliseconds() {
        if (!m_pending || !m_readback) return -1.0f;

        void* mapped = nullptr;
        D3D12_RANGE range { 0, kSlots * sizeof(uint64_t) };
        if (FAILED(m_readback->Map(0, &range, &mapped)) || !mapped) return -1.0f;

        const uint64_t* stamps = static_cast<const uint64_t*>(mapped);
        const uint64_t  begin  = stamps[0];
        const uint64_t  end    = stamps[1];
        m_readback->Unmap(0, nullptr);

        if (end <= begin) return -1.0f;
        return float(double(end - begin) / double(m_frequency) * 1000.0);
    }

private:
    static constexpr UINT kSlots = 2;

    ID3D12QueryHeap* m_heap      = nullptr;
    ID3D12Resource*  m_readback  = nullptr;
    uint64_t         m_frequency = 0;
    bool             m_pending   = false;
};

class NgxBackend final : public IBackend {
public:
    explicit NgxBackend(Backend kind) : m_kind(kind) {}
    ~NgxBackend() override { shutdown(); }

    bool initialise(const DeviceHandles& handles, const GpuInfo& gpu,
                    const std::string& runtimePath, std::string* error) override
    {
        m_gpu     = gpu;
        m_handles = handles;

        if (!gpu.hasVendorRuntime()) {
            if (error) *error = "vendor runtime requested on a non-NVIDIA adapter";
            return false;
        }
        if (m_kind == Backend::NgxFp8 && !gpu.supportsFp8()) {
            if (error) *error = "FP8 path requested on silicon without FP8 tensor cores";
            return false;
        }
        if (!handles.valid()) {
            if (error) *error = "no graphics device supplied";
            return false;
        }

        const std::wstring runtimeWide = widen(runtimePath);
        const std::wstring dataPath    = runtimeWide.empty() ? std::wstring(L".")
                                                             : directoryOf(runtimeWide);

        if (!ngx::loadApi(m_api, dataPath.c_str(), error)) return false;

        return (m_handles.api == GraphicsApi::D3D12)
                 ? initialiseD3D12(dataPath, error)
                 : initialiseD3D11(dataPath, error);
    }

    void shutdown() override {
        if (m_handle) {
            if (m_handles.api == GraphicsApi::D3D12 && m_api.d3d12ReleaseFeature)
                m_api.d3d12ReleaseFeature(m_handle);
            else if (m_api.d3d11ReleaseFeature)
                m_api.d3d11ReleaseFeature(m_handle);
            m_handle = nullptr;
        }

        if (m_params) {
            if (m_handles.api == GraphicsApi::D3D12 && m_api.d3d12DestroyParameters)
                m_api.d3d12DestroyParameters(m_params);
            else if (m_api.d3d11DestroyParameters)
                m_api.d3d11DestroyParameters(m_params);
            m_params = nullptr;
        }

        if (m_scratch) { m_scratch->Release(); m_scratch = nullptr; }
        m_timer.release();

        if (m_initialised) {
            if (m_handles.api == GraphicsApi::D3D12 && m_api.d3d12Shutdown)
                m_api.d3d12Shutdown(static_cast<ID3D12Device*>(m_handles.device));
            else if (m_api.d3d11Shutdown)
                m_api.d3d11Shutdown();
            m_initialised = false;
        }

        ngx::unloadApi(m_api);
    }

    bool evaluate(CommandList cmd, const Dispatch& d) override {
        if (!m_params || !cmd) return false;

        if (!m_handle && !ensureFeature(cmd, d, &m_lastError)) return false;

        applyDispatchParameters(d);

        if (m_handles.api == GraphicsApi::D3D12) {
            auto* list = static_cast<ID3D12GraphicsCommandList*>(cmd);

            m_lastMs = m_timer.readMilliseconds();
            m_timer.begin(list);

            const ngx::Result r =
                m_api.d3d12EvaluateFeature(list, m_handle, m_params, nullptr);

            m_timer.end(list);

            if (!ngx::succeeded(r)) { m_lastError = ngx::resultToString(r); return false; }
            return true;
        }

        auto* ctx = static_cast<ID3D11DeviceContext*>(cmd);
        const ngx::Result r = m_api.d3d11EvaluateFeature(ctx, m_handle, m_params, nullptr);

        if (!ngx::succeeded(r)) { m_lastError = ngx::resultToString(r); return false; }
        return true;
    }

    void onResolutionChanged(Extent2D render, Extent2D output) override {
        m_render = render;
        m_output = output;

        if (!m_handle) return;

        if (m_handles.api == GraphicsApi::D3D12 && m_api.d3d12ReleaseFeature)
            m_api.d3d12ReleaseFeature(m_handle);
        else if (m_api.d3d11ReleaseFeature)
            m_api.d3d11ReleaseFeature(m_handle);

        m_handle = nullptr;
    }

    Backend  kind()                 const override { return m_kind; }
    uint32_t modelCount()           const override { return m_modelCount; }
    uint64_t vramBytes()            const override { return m_vram; }
    float    lastGpuMs()            const override { return m_lastMs; }
    bool     carriesTemporalState() const override { return true; }

    const char* modelName(uint32_t i) const override {
        static const char* kNames[] = { "A", "B", "C", "D", "E", "F", "G", "H" };
        return i < m_modelCount ? kNames[std::min<uint32_t>(i, 7)] : "invalid";
    }

private:
    bool initialiseD3D12(const std::wstring& dataPath, std::string* error) {
        if (!m_api.loadedD3D12()) {
            if (error) *error = "the loaded nvngx.dll exports no D3D12 entry points";
            return false;
        }

        auto* device = static_cast<ID3D12Device*>(m_handles.device);
        auto* queue  = static_cast<ID3D12CommandQueue*>(m_handles.queueOrContext);

        ngx::Result r = m_api.d3d12Init(kApplicationId, dataPath.c_str(),
                                        device, ngx::kSdkVersion);
        if (!ngx::succeeded(r)) {
            if (error) *error = std::string("NGX D3D12 init failed: ") + ngx::resultToString(r);
            return false;
        }
        m_initialised = true;

        ngx::Parameter* capabilities = nullptr;
        r = m_api.d3d12GetCapabilityParameters(&capabilities);
        if (!ngx::succeeded(r) || !capabilities) {
            if (error) *error = std::string("NGX capability query failed: ") + ngx::resultToString(r);
            return false;
        }

        if (!featureIsAvailable(capabilities, error)) return false;
        readModelCount(capabilities);

        r = m_api.d3d12AllocateParameters(&m_params);
        if (!ngx::succeeded(r) || !m_params) {
            if (error) *error = std::string("NGX parameter allocation failed: ") + ngx::resultToString(r);
            return false;
        }

        if (queue) m_timer.initialise(device, queue);

        m_vram = (m_kind == Backend::NgxFp16) ? kResidentWeightsFp16 : kResidentWeightsFp8;
        return true;
    }

    bool initialiseD3D11(const std::wstring& dataPath, std::string* error) {
        if (!m_api.loadedD3D11()) {
            if (error)
                *error = "the loaded nvngx.dll exports no D3D11 entry points, so this "
                         "DirectX 11 title needs the D3D12 bridge instead";
            return false;
        }

        auto* device = static_cast<ID3D11Device*>(m_handles.device);

        ngx::Result r = m_api.d3d11Init(kApplicationId, dataPath.c_str(),
                                        device, ngx::kSdkVersion);
        if (!ngx::succeeded(r)) {
            if (error) *error = std::string("NGX D3D11 init failed: ") + ngx::resultToString(r);
            return false;
        }
        m_initialised = true;

        ngx::Parameter* capabilities = nullptr;
        r = m_api.d3d11GetCapabilityParameters(&capabilities);
        if (!ngx::succeeded(r) || !capabilities) {
            if (error) *error = std::string("NGX capability query failed: ") + ngx::resultToString(r);
            return false;
        }

        if (!featureIsAvailable(capabilities, error)) return false;
        readModelCount(capabilities);

        r = m_api.d3d11AllocateParameters(&m_params);
        if (!ngx::succeeded(r) || !m_params) {
            if (error) *error = std::string("NGX parameter allocation failed: ") + ngx::resultToString(r);
            return false;
        }

        m_vram = (m_kind == Backend::NgxFp16) ? kResidentWeightsFp16 : kResidentWeightsFp8;
        return true;
    }

    bool featureIsAvailable(ngx::Parameter* capabilities, std::string* error) {
        int available = 0;
        const ngx::Result r =
            capabilities->Get(ngx::kParamNrAvailable_Unverified, &available);

        if (!ngx::succeeded(r) || available == 0) {
            if (error)
                *error = "this driver and runtime report no neural rendering feature. "
                         "NeuralForge does not ship the runtime; see runtimes/README.md.";
            return false;
        }
        return true;
    }

    void readModelCount(ngx::Parameter* capabilities) {
        unsigned int count = 0;
        if (ngx::succeeded(capabilities->Get(ngx::kParamNrModelCount_Unverified, &count)) &&
            count > 0 && count <= kMaxModels) {
            m_modelCount = count;
        }
    }

    bool ensureFeature(CommandList cmd, const Dispatch& d, std::string* error) {
        if (m_handle) return true;
        if (!m_params) return false;

        m_params->Set(ngx::kParamWidth,     static_cast<unsigned int>(d.extent.width));
        m_params->Set(ngx::kParamHeight,    static_cast<unsigned int>(d.extent.height));
        m_params->Set(ngx::kParamOutWidth,  static_cast<unsigned int>(d.extent.width));
        m_params->Set(ngx::kParamOutHeight, static_cast<unsigned int>(d.extent.height));
        m_params->Set(ngx::kParamCreationNodeMask,   1u);
        m_params->Set(ngx::kParamVisibilityNodeMask, 1u);

        if (m_handles.api == GraphicsApi::D3D12) {
            if (!allocateScratch(d, error)) return false;

            const ngx::Result r = m_api.d3d12CreateFeature(
                static_cast<ID3D12GraphicsCommandList*>(cmd),
                ngx::Feature_NeuralRendering_Unverified, m_params, &m_handle);

            if (!ngx::succeeded(r)) {
                if (error) *error = std::string("feature creation refused: ") + ngx::resultToString(r);
                return false;
            }
            return true;
        }

        const ngx::Result r = m_api.d3d11CreateFeature(
            static_cast<ID3D11DeviceContext*>(cmd),
            ngx::Feature_NeuralRendering_Unverified, m_params, &m_handle);

        if (!ngx::succeeded(r)) {
            if (error) *error = std::string("feature creation refused: ") + ngx::resultToString(r);
            return false;
        }
        return true;
    }

    bool allocateScratch(const Dispatch& d, std::string* error) {
        if (m_scratch || !m_api.d3d12GetScratchBufferSize) return true;

        size_t bytes = 0;
        const ngx::Result r = m_api.d3d12GetScratchBufferSize(
            ngx::Feature_NeuralRendering_Unverified, m_params, &bytes);

        if (!ngx::succeeded(r) || bytes == 0) return true;

        auto* device = static_cast<ID3D12Device*>(m_handles.device);

        D3D12_HEAP_PROPERTIES heapProps {};
        heapProps.Type = D3D12_HEAP_TYPE_DEFAULT;

        D3D12_RESOURCE_DESC desc {};
        desc.Dimension        = D3D12_RESOURCE_DIMENSION_BUFFER;
        desc.Width            = bytes;
        desc.Height           = 1;
        desc.DepthOrArraySize = 1;
        desc.MipLevels        = 1;
        desc.Format           = DXGI_FORMAT_UNKNOWN;
        desc.SampleDesc.Count = 1;
        desc.Layout           = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
        desc.Flags            = D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS;

        if (FAILED(device->CreateCommittedResource(
                &heapProps, D3D12_HEAP_FLAG_NONE, &desc,
                D3D12_RESOURCE_STATE_UNORDERED_ACCESS, nullptr, IID_PPV_ARGS(&m_scratch)))) {
            if (error) *error = "could not allocate the NGX scratch buffer";
            return false;
        }

        m_params->Set(ngx::kParamScratchBuffer,     m_scratch);
        m_params->Set(ngx::kParamScratchBufferSize, static_cast<unsigned int>(bytes));
        (void)d;
        return true;
    }

    void applyDispatchParameters(const Dispatch& d) {
        m_params->Set(ngx::kParamWidth,  static_cast<unsigned int>(d.extent.width));
        m_params->Set(ngx::kParamHeight, static_cast<unsigned int>(d.extent.height));

        if (m_handles.api == GraphicsApi::D3D12) {
            m_params->Set(ngx::kParamColor,         static_cast<ID3D12Resource*>(d.inColor));
            m_params->Set(ngx::kParamOutput,        static_cast<ID3D12Resource*>(d.outColor));
            m_params->Set(ngx::kParamMotionVectors, static_cast<ID3D12Resource*>(d.inMotion));
            if (d.inDepth) m_params->Set(ngx::kParamDepth, static_cast<ID3D12Resource*>(d.inDepth));
        } else {
            m_params->Set(ngx::kParamColor,         static_cast<ID3D11Resource*>(d.inColor));
            m_params->Set(ngx::kParamOutput,        static_cast<ID3D11Resource*>(d.outColor));
            m_params->Set(ngx::kParamMotionVectors, static_cast<ID3D11Resource*>(d.inMotion));
            if (d.inDepth) m_params->Set(ngx::kParamDepth, static_cast<ID3D11Resource*>(d.inDepth));
        }

        m_params->Set(ngx::kParamNrModel_Unverified,     static_cast<unsigned int>(d.model));
        m_params->Set(ngx::kParamNrPassIndex_Unverified, static_cast<unsigned int>(d.passIndex));

        const bool isRefinementPassOfSameFrame = d.passIndex > 0;
        m_params->Set(ngx::kParamReset,
                      (d.resetState && !isRefinementPassOfSameFrame) ? 1 : 0);
    }

    Backend         m_kind;
    GpuInfo         m_gpu {};
    DeviceHandles   m_handles {};
    ngx::Api        m_api {};
    ngx::Handle*    m_handle  = nullptr;
    ngx::Parameter* m_params  = nullptr;
    ID3D12Resource* m_scratch = nullptr;
    GpuTimer        m_timer {};

    Extent2D    m_render {};
    Extent2D    m_output {};
    uint32_t    m_modelCount  = 3;
    uint64_t    m_vram        = 0;
    float       m_lastMs      = -1.0f;
    bool        m_initialised = false;
    std::string m_lastError;
};

} // namespace

#endif // NF_NO_D3D

namespace {

class PortableBackend final : public IBackend {
public:
    explicit PortableBackend(Backend kind) : m_kind(kind) {}

    bool initialise(const DeviceHandles&, const GpuInfo& gpu,
                    const std::string&, std::string* error) override
    {
        m_gpu = gpu;

        if (gpu.tier == Tier::Unsupported) {
            if (error) *error = "no matrix or tensor units on this adapter";
            return false;
        }
        if (error)
            *error = "portable backend needs locally converted weights. "
                     "See runtimes/README.md.";
        return false;
    }

    void shutdown() override {}
    bool evaluate(CommandList, const Dispatch&) override { return false; }
    void onResolutionChanged(Extent2D, Extent2D) override {}

    Backend  kind()                 const override { return m_kind; }
    uint32_t modelCount()           const override { return m_modelCount; }
    uint64_t vramBytes()            const override { return m_vram; }
    float    lastGpuMs()            const override { return m_lastMs; }
    bool     carriesTemporalState() const override { return false; }

    const char* modelName(uint32_t i) const override {
        static const char* kNames[] = { "A", "B", "C" };
        return i < m_modelCount ? kNames[i] : "invalid";
    }

private:
    Backend  m_kind;
    GpuInfo  m_gpu {};
    uint32_t m_modelCount = 3;
    uint64_t m_vram       = 0;
    float    m_lastMs     = -1.0f;
};

} // namespace

std::unique_ptr<IBackend> createBackend(Backend kind) {
    switch (kind) {
#if !defined(NF_NO_D3D)
        case Backend::NgxFp8:
        case Backend::NgxFp16:  return std::make_unique<NgxBackend>(kind);
#endif
        case Backend::DirectML:
        case Backend::Hip:      return std::make_unique<PortableBackend>(kind);
        default:                return nullptr;
    }
}

} // namespace nf
