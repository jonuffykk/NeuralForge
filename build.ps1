<#
.SYNOPSIS
    Build NeuralForge. Finds Visual Studio and its bundled CMake and Ninja for
    you, so there is nothing to install and no developer prompt to open.

.PARAMETER TestsOnly
    Build and run only the vendor-neutral tests. Needs no Windows SDK.

.PARAMETER Config
    Debug or Release. Default Release.

.EXAMPLE
    .\build.ps1
    .\build.ps1 -TestsOnly
#>

[CmdletBinding()]
param(
    [switch]$TestsOnly,
    [ValidateSet('Debug', 'Release')]
    [string]$Config = 'Release'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host ''
Write-Host '  NeuralForge build' -ForegroundColor Cyan
Write-Host ''

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    throw "Visual Studio Installer not found. Install Visual Studio 2022 or the Build Tools with the C++ workload."
}

$vs = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
if (-not $vs) {
    throw "No Visual Studio installation with the C++ toolset found. Add the 'Desktop development with C++' workload."
}
Write-Host "  toolchain  $vs" -ForegroundColor Gray

$cmakeDir = "$vs\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin"
$ninjaDir = "$vs\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja"
$vcvars   = "$vs\VC\Auxiliary\Build\vcvars64.bat"

# Prefer the bundled tools, but do not shadow a newer CMake already on PATH.
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) { $env:PATH = "$cmakeDir;$env:PATH" }
if (-not (Get-Command ninja -ErrorAction SilentlyContinue)) { $env:PATH = "$ninjaDir;$env:PATH" }

$module = if ($TestsOnly) { 'OFF' } else { 'ON' }
$args   = "-S . -B build -G Ninja -DCMAKE_BUILD_TYPE=$Config -DNF_BUILD_MODULE=$module"

Write-Host "  config     $Config, module=$module" -ForegroundColor Gray
Write-Host ''

& cmd /c "`"$vcvars`" >nul 2>&1 && cmake $args && cmake --build build && ctest --test-dir build --output-on-failure"
if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host '  Build failed.' -ForegroundColor Red
    Write-Host ''
    exit $LASTEXITCODE
}

Write-Host ''
Write-Host '  Done.' -ForegroundColor Green
if (-not $TestsOnly -and (Test-Path 'build\bin')) {
    Get-ChildItem 'build\bin' | ForEach-Object {
        Write-Host ("    {0}  {1:N0} KB" -f $_.Name, ($_.Length / 1KB)) -ForegroundColor Gray
    }
    Write-Host ''
    Write-Host '  Install with:  .\installer\NeuralForge.ps1' -ForegroundColor Gray
}
Write-Host ''
