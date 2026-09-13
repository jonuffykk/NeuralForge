# SPDX-License-Identifier: MIT
cmake_minimum_required(VERSION 3.21)

project(NeuralForge
    VERSION     0.1.0
    LANGUAGES   CXX
    DESCRIPTION "Unified DLSS-5 neural rendering runtime")

option(NF_WITH_IMGUI    "Build the in-game overlay"            ON)
option(NF_WITH_NVAPI    "Use NVAPI for authoritative GPU ID"   OFF)
option(NF_WITH_AGS      "Use AMD AGS for authoritative GPU ID" OFF)
option(NF_WITH_DIRECTML "Build the DirectML portable backend"  ON)
option(NF_BUILD_TESTS   "Build unit tests"                     ON)
option(NF_BUILD_MODULE  "Build the injectable DLL"             ON)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Vendor-neutral. Builds and tests on any platform with a C++20 compiler.
set(NF_PORTABLE_SOURCES
    src/nf_gpu.cpp
    src/nf_config.cpp
    src/nf_schedule.cpp)

# Needs D3D12 and the Windows SDK.
set(NF_MODULE_SOURCES
    src/nf_backend.cpp
    src/nf_pipeline.cpp
    src/nf_hook.cpp
    src/nf_overlay.cpp)

set(NF_SHADER src/nf_residual.hlsl)

set(NF_SHADER_ENTRIES
    CS_Extract CS_BlurBand CS_Reproject CS_Composite CS_CompactTiles)

if(NF_BUILD_MODULE AND WIN32)
    find_program(NF_DXC dxc HINTS "$ENV{WindowsSdkVerBinPath}/x64" "$ENV{VULKAN_SDK}/Bin")

    if(NF_DXC)
        set(NF_SHADER_OUTPUTS "")
        foreach(entry ${NF_SHADER_ENTRIES})
            set(out "${CMAKE_BINARY_DIR}/shaders/${entry}.dxil")
            add_custom_command(
                OUTPUT  ${out}
                COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_BINARY_DIR}/shaders"
                COMMAND ${NF_DXC} -T cs_6_6 -E ${entry} -WX -O3 -Fo ${out}
                        "${CMAKE_SOURCE_DIR}/${NF_SHADER}"
                DEPENDS "${CMAKE_SOURCE_DIR}/${NF_SHADER}"
                COMMENT "dxc ${entry}"
                VERBATIM)
            list(APPEND NF_SHADER_OUTPUTS ${out})
        endforeach()
        add_custom_target(nf_shaders DEPENDS ${NF_SHADER_OUTPUTS})
    else()
        message(WARNING "dxc not found. Shaders will not compile; install the Windows SDK.")
        add_custom_target(nf_shaders)
    endif()

    add_library(NeuralForge SHARED
        ${NF_PORTABLE_SOURCES} ${NF_MODULE_SOURCES} ${NF_SHADER})

    add_dependencies(NeuralForge nf_shaders)
    set_source_files_properties(${NF_SHADER} PROPERTIES HEADER_FILE_ONLY TRUE)

    set_target_properties(NeuralForge PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

    target_include_directories(NeuralForge PRIVATE src)
    target_link_libraries(NeuralForge PRIVATE d3d12 dxgi dxguid)
    target_compile_definitions(NeuralForge PRIVATE
        WIN32_LEAN_AND_MEAN NOMINMAX NF_VERSION="${PROJECT_VERSION}")

    if(MSVC)
        target_compile_options(NeuralForge PRIVATE
            /W4 /permissive- /Zc:preprocessor $<$<CONFIG:Release>:/O2 /GL>)
        target_link_options(NeuralForge PRIVATE $<$<CONFIG:Release>:/LTCG>)
    endif()

    if(NF_WITH_IMGUI AND EXISTS "${CMAKE_SOURCE_DIR}/third_party/imgui/imgui.h")
        target_compile_definitions(NeuralForge PRIVATE NF_WITH_IMGUI)
        target_include_directories(NeuralForge PRIVATE third_party/imgui)
        target_sources(NeuralForge PRIVATE
            third_party/imgui/imgui.cpp
            third_party/imgui/imgui_draw.cpp
            third_party/imgui/imgui_tables.cpp
            third_party/imgui/imgui_widgets.cpp
            third_party/imgui/backends/imgui_impl_dx12.cpp
            third_party/imgui/backends/imgui_impl_win32.cpp)
    endif()

    if(NF_WITH_DIRECTML)
        target_compile_definitions(NeuralForge PRIVATE NF_WITH_DIRECTML)
        target_link_libraries(NeuralForge PRIVATE directml)
    endif()
    if(NF_WITH_NVAPI)
        target_compile_definitions(NeuralForge PRIVATE NF_WITH_NVAPI)
        target_link_libraries(NeuralForge PRIVATE nvapi64)
    endif()
    if(NF_WITH_AGS)
        target_compile_definitions(NeuralForge PRIVATE NF_WITH_AGS)
        target_link_libraries(NeuralForge PRIVATE amd_ags_x64)
    endif()
endif()

# Most of the project is vendor-neutral, so the tests need no GPU, no runtime
# and no game. NF_NO_D3D compiles out the only parts that need the Windows SDK.
if(NF_BUILD_TESTS)
    enable_testing()

    add_executable(nf_tests tests/nf_tests.cpp ${NF_PORTABLE_SOURCES})
    target_include_directories(nf_tests PRIVATE src)
    target_compile_definitions(nf_tests PRIVATE NF_NO_D3D)

    if(MSVC)
        target_compile_options(nf_tests PRIVATE /W4 /permissive-)
    else()
        target_compile_options(nf_tests PRIVATE -Wall -Wextra)
    endif()

    add_test(NAME nf_tests COMMAND nf_tests)
endif()

message(STATUS "NeuralForge ${PROJECT_VERSION}  module=${NF_BUILD_MODULE} tests=${NF_BUILD_TESTS}")
message(STATUS "No vendor runtime is bundled. See runtimes/README.md.")
