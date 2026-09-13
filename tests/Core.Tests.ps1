#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'installer\NeuralForge.Core.ps1')

$Script:Checks   = 0
$Script:Failures = 0

function Assert-That {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Because
    )

    $Script:Checks++
    if (-not $Condition) {
        $Script:Failures++
        Write-Host "  FAIL  $Because" -ForegroundColor Red
    }
}

function Assert-Equal {
    param($Expected, $Actual, [Parameter(Mandatory)][string]$Because)

    $Script:Checks++
    if ($Expected -ne $Actual) {
        $Script:Failures++
        Write-Host "  FAIL  $Because (expected '$Expected', got '$Actual')" -ForegroundColor Red
    }
}

function Test-Section { param([string]$Name) Write-Host "`n$Name" }

Write-Host 'NeuralForge installer tests'

Test-Section 'GPU tiering'

Assert-Equal 'Blackwell'   (Get-NfTier 0x10DE 0x2B85) 'RTX 5090 is Blackwell'
Assert-Equal 'Ada'         (Get-NfTier 0x10DE 0x2684) 'RTX 4090 is Ada'
Assert-Equal 'Ampere'      (Get-NfTier 0x10DE 0x2204) 'RTX 3090 is Ampere'
Assert-Equal 'Turing'      (Get-NfTier 0x10DE 0x1E04) 'RTX 2080 Ti is Turing'
Assert-Equal 'Turing'      (Get-NfTier 0x10DE 0x1F02) 'RTX 2070 is Turing'

Assert-Equal 'Unsupported' (Get-NfTier 0x10DE 0x1F9D) 'GTX 1650 has no tensor cores'
Assert-Equal 'Unsupported' (Get-NfTier 0x10DE 0x2184) 'GTX 1660 has no tensor cores'
Assert-Equal 'Unsupported' (Get-NfTier 0x10DE 0x1F82) 'TU117 has no tensor cores'
Assert-Equal 'Unsupported' (Get-NfTier 0x10DE 0x21C4) 'TU116 has no tensor cores'
Assert-Equal 'Unsupported' (Get-NfTier 0x10DE 0x1B80) 'GTX 1080 is Pascal'

Assert-Equal 'RDNA4'       (Get-NfTier 0x1002 0x7550) 'RX 9070 is RDNA 4'
Assert-Equal 'RDNA3'       (Get-NfTier 0x1002 0x744C) 'RX 7900 is RDNA 3'
Assert-Equal 'Unsupported' (Get-NfTier 0x1002 0x73BF) 'RX 6900 is RDNA 2'
Assert-Equal 'Unsupported' (Get-NfTier 0x8086 0x56A0) 'Intel Arc reports unsupported'

Test-Section 'Tier table parity with the C++ classifier'

foreach ($tier in @('Blackwell', 'Ada', 'Ampere', 'Turing', 'RDNA4', 'RDNA3', 'Unsupported')) {
    Assert-That ($Script:NfTierInfo.Contains($tier)) "tier table has an entry for $tier"
}

Assert-That ($Script:NfTierInfo['Blackwell'].Cost -lt $Script:NfTierInfo['Ada'].Cost) `
    'Blackwell is cheaper than Ada'
Assert-That ($Script:NfTierInfo['Ada'].Cost -lt $Script:NfTierInfo['Ampere'].Cost) `
    'Ada is cheaper than Ampere'
Assert-That ($Script:NfTierInfo['Ampere'].Cost -lt $Script:NfTierInfo['Turing'].Cost) `
    'Ampere is cheaper than Turing'
Assert-That ($Script:NfTierInfo['Ampere'].Budget -gt $Script:NfTierInfo['Blackwell'].Budget) `
    'slower tiers get a wider budget'
Assert-That ($Script:NfTierInfo['Ampere'].Scale -lt $Script:NfTierInfo['Blackwell'].Scale) `
    'slower tiers start at a lower working scale'

Test-Section 'PE import parsing'

$knownDx12Consumer = Join-Path $env:SystemRoot 'System32\dxgi.dll'
if (Test-Path -LiteralPath $knownDx12Consumer) {
    $imports = @(Get-NfExeImports -Path $knownDx12Consumer)
    Assert-That ($imports.Count -gt 0) 'dxgi.dll reports at least one import'
    Assert-That ($imports -contains 'api-ms-win-crt-runtime-l1-1-0.dll' -or
                 $imports -contains 'ntdll.dll' -or
                 $imports.Count -gt 3) 'dxgi.dll imports look like a real import table'
}

$notAnExe = Join-Path $root 'README.md'
Assert-Equal 0 (@(Get-NfExeImports -Path $notAnExe)).Count 'a text file yields no imports'
Assert-Equal 0 (@(Get-NfExeImports -Path (Join-Path $root 'does-not-exist.exe'))).Count `
    'a missing file yields no imports and does not throw'

Test-Section 'Config read and write'

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("nf_cfg_{0}.ini" -f [guid]::NewGuid())
@'
[Performance]
AutoTune             = true
BudgetMs             = 2.0
WorkingScale         = 1.0
'@ | Set-Content -LiteralPath $tmp -Encoding utf8

Assert-Equal 'true' (Get-NfConfigValue -Path $tmp -Key 'AutoTune')     'reads a boolean'
Assert-Equal '2.0'  (Get-NfConfigValue -Path $tmp -Key 'BudgetMs')     'reads a float'
Assert-Equal 'fallback' (Get-NfConfigValue -Path $tmp -Key 'Nope' -Default 'fallback') `
    'missing key returns the default'

[void](Set-NfConfigValue -Path $tmp -Values @{ BudgetMs = '4.0'; Passes = '2' })
Assert-Equal '4.0' (Get-NfConfigValue -Path $tmp -Key 'BudgetMs') 'updates an existing key'
Assert-Equal '2'   (Get-NfConfigValue -Path $tmp -Key 'Passes')   'appends a missing key'
Assert-Equal 'true' (Get-NfConfigValue -Path $tmp -Key 'AutoTune') 'leaves other keys alone'

Remove-Item -LiteralPath $tmp -Force

Test-Section 'Game classification'

$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ("nf_game_{0}" -f [guid]::NewGuid())
New-Item -ItemType Directory -Path $fixture -Force | Out-Null

$stub = Join-Path $env:SystemRoot 'System32\dxgi.dll'

$tinyApp = Test-NfGame -Path $fixture -Name 'TinyApp' -Source 'Folder'
Assert-That ($null -eq $tinyApp) 'an empty folder is not a game'

Copy-Item -LiteralPath $stub -Destination (Join-Path $fixture 'TestGame.exe') -Force
$smallExe = Test-NfGame -Path $fixture -Name 'TestGame' -Source 'Folder'
Assert-That ($null -eq $smallExe) 'a lone small executable is not a game'

$fs = [System.IO.File]::Open((Join-Path $fixture 'TestGame.exe'), 'Open', 'Write')
$fs.SetLength(12MB)
$fs.Close()

'stub' | Set-Content -LiteralPath (Join-Path $fixture 'steam_api64.dll')

$plain = Test-NfGame -Path $fixture -Name 'TestGame' -Source 'Folder'
Assert-That ($null -ne $plain) 'a large executable beside an engine runtime is a game'
Assert-That ($plain.Status -in @('No motion vectors', 'Ready via bridge')) `
    'a game with no upscaler is flagged for synthesised motion vectors'

$electron = Join-Path ([System.IO.Path]::GetTempPath()) ("nf_app_{0}" -f [guid]::NewGuid())
New-Item -ItemType Directory -Path $electron -Force | Out-Null
Copy-Item -LiteralPath $stub -Destination (Join-Path $electron 'Chatty.exe') -Force
$fs = [System.IO.File]::Open((Join-Path $electron 'Chatty.exe'), 'Open', 'Write')
$fs.SetLength(90MB)
$fs.Close()
'stub' | Set-Content -LiteralPath (Join-Path $electron 'steam_api64.dll')
'stub' | Set-Content -LiteralPath (Join-Path $electron 'icudtl.dat')

Assert-That ($null -eq (Test-NfGame -Path $electron -Name 'Chatty' -Source 'Folder')) `
    'an Electron application is not listed as a game'
Remove-Item -LiteralPath $electron -Recurse -Force

Assert-That ($null -eq (Test-NfGame -Path $fixture -Name 'Realtek Audio Driver' -Source 'Installed')) `
    'a known application name is not listed as a game'

'stub' | Set-Content -LiteralPath (Join-Path $fixture 'nvngx_dlss.dll')
$withDlss = Test-NfGame -Path $fixture -Name 'TestGame' -Source 'Folder'
Assert-That ($withDlss.Upscalers -match 'DLSS') 'DLSS runtime is detected'

'stub' | Set-Content -LiteralPath (Join-Path $fixture 'EasyAntiCheat_x64.dll')
$withAntiCheat = Test-NfGame -Path $fixture -Name 'TestGame' -Source 'Folder'
Assert-Equal 'Blocked' $withAntiCheat.Status 'anti-cheat blocks regardless of everything else'
Assert-That ($withAntiCheat.Blocker -match 'anti-cheat') 'the blocker explains why'

Remove-Item -LiteralPath $fixture -Recurse -Force

Assert-That ($null -eq (Test-NfGame -Path (Join-Path $root 'no-such-folder') -Name 'x')) `
    'a missing folder yields no game'

Test-Section 'Scanner'

$games = @(Get-NfGames)
Assert-That ($games -is [array]) 'the scanner always returns an array'

foreach ($g in $games) {
    Assert-That ($g.Status -in @('Ready', 'Ready via bridge', 'No motion vectors',
                                 'Unsupported API', 'Blocked')) `
        "$($g.Name) has a known status"
    Assert-That ([bool]$g.Path) "$($g.Name) has a path"
    Assert-That ($g.Route -in @('native', 'bridge', 'none')) "$($g.Name) has a known route"
    Assert-That ((Test-Path -LiteralPath $g.Path)) "$($g.Name) path exists"
    if ($g.Status -ne 'Ready') {
        Assert-That ([bool]$g.Blocker) "$($g.Name) explains why it is not Ready"
    }
}

$paths = @($games | ForEach-Object { $_.Path.ToLower() })
Assert-Equal $paths.Count (@($paths | Select-Object -Unique)).Count 'no duplicate game paths'

Test-Section 'Runtime status'

$rt = Get-NfRuntimeStatus
Assert-That ($null -ne $rt) 'runtime status is always reported'
Assert-That ([bool]$rt.Message) 'runtime status carries a message'
if (-not $rt.Present) {
    Assert-That (-not $rt.Valid) 'an absent runtime is never reported as valid'
}

Write-Host ''
if ($Script:Failures -eq 0) {
    Write-Host "$($Script:Checks) checks, 0 failures" -ForegroundColor Green
    exit 0
}

Write-Host "$($Script:Checks) checks, $($Script:Failures) failures" -ForegroundColor Red
exit 1
