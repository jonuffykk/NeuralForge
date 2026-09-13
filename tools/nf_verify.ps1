#Requires -Version 5.1
<#
.SYNOPSIS
    Runs every check CI runs, locally, in one command.
#>

[CmdletBinding()]
param([switch]$SkipBuild)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$root     = Split-Path $PSScriptRoot -Parent
$failures = @()

function Step {
    param([string]$Name, [scriptblock]$Body)

    Write-Host ''
    Write-Host "  $Name" -ForegroundColor Cyan

    try {
        $emitted = @(& $Body)
        $result  = if ($emitted.Count) { $emitted[-1] } else { $false }

        if ($result -isnot [bool] -or -not $result) {
            $script:failures += $Name
            Write-Host "    FAILED" -ForegroundColor Red
        }
    } catch {
        $script:failures += $Name
        Write-Host "    FAILED  $_" -ForegroundColor Red
    }
}

Write-Host ''
Write-Host '  NeuralForge verification' -ForegroundColor White

if (-not $SkipBuild) {
    Step 'Build and C++ tests' {
        Push-Location $root
        try {
            $out = & (Join-Path $root 'build.ps1') 2>&1
            $warnings = @($out | Select-String -Pattern 'warning|aviso')
            if ($warnings) {
                $warnings | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
                return $false
            }
            $passed = $out | Select-String -Pattern '100% tests passed'
            if (-not $passed) { $out | Select-Object -Last 10; return $false }

            $checks = $out | Select-String -Pattern '(\d+) checks, (\d+) failures'
            Write-Host "    clean build, zero warnings" -ForegroundColor Green
            if ($checks) { Write-Host "    $($checks.Matches[0].Value)" -ForegroundColor Green }
            return $true
        } finally { Pop-Location }
    }

    Step 'Shaders compiled' {
        $expected = @('CS_Extract','CS_BlurBand','CS_Reproject','CS_Composite','CS_CompactTiles')
        $missing  = @($expected | Where-Object { -not (Test-Path (Join-Path $root "build\shaders\$_.dxil")) })
        if ($missing) { Write-Host "    missing: $($missing -join ', ')" -ForegroundColor Red; return $false }
        Write-Host "    all $($expected.Count) compiled" -ForegroundColor Green
        return $true
    }

    Step 'Multi-config generator lands outputs in the same place' {
        $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
        if (-not (Test-Path $vswhere)) {
            Write-Host '    skipped, no Visual Studio installer found' -ForegroundColor Yellow
            return $true
        }

        $vs = & $vswhere -latest -products * `
                -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
                -property installationPath
        if (-not $vs) {
            Write-Host '    skipped, no C++ toolset' -ForegroundColor Yellow
            return $true
        }

        $cmakeDir = "$vs\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin"
        if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) { $env:PATH = "$cmakeDir;$env:PATH" }

        $out = Join-Path $root 'build-multiconfig'
        Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue

        $generator = if ($vs -match '2026|\\18\\') { 'Visual Studio 18 2026' } else { 'Visual Studio 17 2022' }

        & cmake -S $root -B $out -G $generator -A x64 `
                -DNF_BUILD_MODULE=ON -DNF_WITH_IMGUI=OFF -DNF_WITH_DIRECTML=OFF `
                -DNF_REQUIRE_SHADERS=ON 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    configure failed with $generator" -ForegroundColor Red
            return $false
        }

        & cmake --build $out --config Release 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    build failed with $generator" -ForegroundColor Red
            return $false
        }

        $dll = Join-Path $out 'bin\NeuralForge.dll'
        if (-not (Test-Path $dll)) {
            Write-Host '    NeuralForge.dll is not in bin/. A configuration subdirectory was added.' -ForegroundColor Red
            Get-ChildItem (Join-Path $out 'bin') -Recurse -File -ErrorAction SilentlyContinue |
                ForEach-Object { Write-Host "      found $($_.FullName)" -ForegroundColor Red }
            return $false
        }

        Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    $generator puts the module in bin/ like Ninja does" -ForegroundColor Green
        return $true
    }
}

Step 'Installer tests' {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\Core.Tests.ps1') 2>&1
    $summary = $out | Select-String -Pattern '(\d+) checks, (\d+) failures'
    if (-not $summary) { $out | Select-Object -Last 10; return $false }
    Write-Host "    $($summary.Matches[0].Value)" -ForegroundColor Green
    return ($summary.Matches[0].Groups[2].Value -eq '0')
}

Step 'Scripts parse' {
    $bad = @()
    foreach ($f in @(Get-ChildItem $root -Recurse -Filter *.ps1 -File)) {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
        if ($errors) { $bad += "$($f.Name): $($errors[0].Message)" }
    }
    if ($bad) { $bad | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }; return $false }
    Write-Host "    every script parses" -ForegroundColor Green
    return $true
}

Step 'Installer window loads' {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $txt = Get-Content (Join-Path $root 'installer\NeuralForge.ps1') -Raw
    if ($txt -notmatch "(?s)\`$Script:Xaml = @'\r?\n(.*?)\r?\n'@") {
        Write-Host '    XAML block not found' -ForegroundColor Red; return $false
    }
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$Matches[1])
    $win    = [Windows.Markup.XamlReader]::Load($reader)

    $required = @('GpuName','GpuTier','GameGrid','Detail','Status','Install','Uninstall',
                  'Rescan','AddFolder','Structure','Tone','Budget','Scale','Passes',
                  'Cadence','Selective','AutoTune','RuntimeStatus','BuildStatus')
    $missing = @($required | Where-Object { -not $win.FindName($_) })
    if ($missing) { Write-Host "    missing: $($missing -join ', ')" -ForegroundColor Red; return $false }
    Write-Host "    $($required.Count) controls resolve" -ForegroundColor Green
    return $true
}

Step 'No comments beyond licence headers' {
    $bad = @()
    foreach ($f in @(Get-ChildItem (Join-Path $root 'src') -File) +
                   @(Get-ChildItem (Join-Path $root 'tests') -Filter *.cpp -File)) {
        $lines = Get-Content $f.FullName
        $comments = @($lines | Where-Object { $_.TrimStart().StartsWith('//') })
        if ($comments.Count -ne 2) { $bad += "$($f.Name): $($comments.Count)" }
        if ($lines[0] -notmatch 'SPDX-License-Identifier: MIT') { $bad += "$($f.Name): no SPDX" }
        if ($lines[1] -notmatch 'Copyright \(c\) 2026 Jonuffy') { $bad += "$($f.Name): no copyright" }
    }
    if ($bad) { $bad | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }; return $false }
    Write-Host "    every source file has exactly its two-line header" -ForegroundColor Green
    return $true
}

Step 'No vendor binaries' {
    $patterns = @('nvngx*', '*.nfw', 'libxess*', 'amd_fidelityfx*', '*.onnx', '*.trt')
    $hits = @()
    foreach ($p in $patterns) {
        $hits += @(Get-ChildItem $root -Recurse -Filter $p -File -ErrorAction SilentlyContinue |
                   Where-Object { $_.FullName -notmatch '\\(\.git|build)\\' })
    }
    $big = @(Get-ChildItem $root -Recurse -File -ErrorAction SilentlyContinue |
             Where-Object { $_.Length -gt 20MB -and $_.FullName -notmatch '\\(\.git|build)\\' })

    if ($hits -or $big) {
        ($hits + $big) | ForEach-Object { Write-Host "    $($_.Name)" -ForegroundColor Red }
        return $false
    }
    Write-Host "    clean" -ForegroundColor Green
    return $true
}

Step 'Documentation links' {
    $docs = @(Get-ChildItem $root -Recurse -Filter *.md -File |
              Where-Object { $_.FullName -notmatch '\\(\.git|build|third_party)\\' })
    $broken = @()

    foreach ($d in $docs) {
        $text = [System.IO.File]::ReadAllText($d.FullName, [System.Text.Encoding]::UTF8)
        foreach ($m in [regex]::Matches($text, '\]\((?!https?:|#)([^)#]+)')) {
            $target   = $m.Groups[1].Value.Trim()
            $resolved = Join-Path $d.DirectoryName $target
            if (-not (Test-Path -LiteralPath $resolved)) { $broken += "$($d.Name) -> $target" }
        }
    }

    if ($broken) { $broken | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }; return $false }
    Write-Host "    every relative link resolves across $($docs.Count) files" -ForegroundColor Green
    return $true
}

Step 'Prose style' {
    $docs = @(Get-ChildItem $root -Recurse -Filter *.md -File |
              Where-Object { $_.FullName -notmatch '\\(\.git|build|third_party)\\' })
    $dashes = 0
    foreach ($d in $docs) {
        $text = [System.IO.File]::ReadAllText($d.FullName, [System.Text.Encoding]::UTF8)
        $dashes += ([regex]::Matches($text, '[\u2013\u2014]')).Count
    }
    if ($dashes -gt 0) { Write-Host "    $dashes em or en dashes remain" -ForegroundColor Red; return $false }
    Write-Host "    no em or en dashes across $($docs.Count) documents" -ForegroundColor Green
    return $true
}

Step 'Tier tables agree' {
    $cpp = Get-Content (Join-Path $root 'src\nf_gpu.cpp') -Raw
    $ps1 = Get-Content (Join-Path $root 'installer\NeuralForge.Core.ps1') -Raw

    $cppRanges = @([regex]::Matches($cpp, '\{\s*0x([0-9A-F]{4}),\s*0x([0-9A-F]{4})') |
                   ForEach-Object { "$($_.Groups[1].Value)-$($_.Groups[2].Value)" })
    $psRanges  = @([regex]::Matches($ps1, 'Lo = 0x([0-9A-F]{4}); Hi = 0x([0-9A-F]{4})') |
                   ForEach-Object { "$($_.Groups[1].Value)-$($_.Groups[2].Value)" })

    $onlyCpp = @($cppRanges | Where-Object { $psRanges -notcontains $_ })
    $onlyPs  = @($psRanges  | Where-Object { $cppRanges -notcontains $_ })

    if ($onlyCpp -or $onlyPs) {
        if ($onlyCpp) { Write-Host "    only in C++: $($onlyCpp -join ', ')" -ForegroundColor Red }
        if ($onlyPs)  { Write-Host "    only in PowerShell: $($onlyPs -join ', ')" -ForegroundColor Red }
        return $false
    }
    Write-Host "    $($cppRanges.Count) device ID ranges match in both implementations" -ForegroundColor Green
    return $true
}

Write-Host ''
if ($failures.Count -eq 0) {
    Write-Host '  Everything passes.' -ForegroundColor Green
    Write-Host ''
    exit 0
}

Write-Host "  $($failures.Count) failed: $($failures -join ', ')" -ForegroundColor Red
Write-Host ''
exit 1
