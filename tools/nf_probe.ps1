#Requires -Version 5.1
<#
.SYNOPSIS
    Reports whether neural rendering can run on this machine, which backend
    would be selected, and what it will cost.

.DESCRIPTION
    Read-only. Touches no game files and changes no settings. Classification
    comes from the shared module the installer uses, so there is one tier table
    rather than two that can drift apart.

.PARAMETER CheckRuntime
    Also verify a runtime in runtimes/, including its Authenticode signature.

.PARAMETER Games
    Also list the games the installer would find.

.EXAMPLE
    .\nf_probe.ps1
    .\nf_probe.ps1 -CheckRuntime -Games
#>

[CmdletBinding()]
param(
    [switch]$CheckRuntime,
    [switch]$Games
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'installer\NeuralForge.Core.ps1')

function Write-Field {
    param([string]$Label, [string]$Value, [string]$Colour = 'Gray')
    Write-Host ("  {0,-20}" -f $Label) -NoNewline
    Write-Host $Value -ForegroundColor $Colour
}

Write-Host ''
Write-Host '  NeuralForge hardware probe' -ForegroundColor Cyan
Write-Host ''

$adapters = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
              Where-Object { $_.PNPDeviceID -match 'PCI\\VEN_' })

if ($adapters.Count -eq 0) {
    Write-Host '  No PCI display adapters found.' -ForegroundColor Red
    Write-Host ''
    exit 1
}

$anyViable = $false

foreach ($a in $adapters) {
    $vendorId = 0
    $deviceId = 0
    if ($a.PNPDeviceID -match 'VEN_([0-9A-Fa-f]{4})&DEV_([0-9A-Fa-f]{4})') {
        $vendorId = [Convert]::ToInt32($Matches[1], 16)
        $deviceId = [Convert]::ToInt32($Matches[2], 16)
    }

    $vendorName = switch ($vendorId) {
        0x10DE  { 'NVIDIA' }
        0x1002  { 'AMD'    }
        0x8086  { 'Intel'  }
        default { 'Unknown' }
    }

    $tier = Get-NfTier -VendorId $vendorId -DeviceId $deviceId
    $info = $Script:NfTierInfo[$tier]

    Write-Host "  $($a.Name)" -ForegroundColor White
    Write-Field 'Vendor / device' ('{0}  (0x{1:X4}:0x{2:X4})' -f $vendorName, $vendorId, $deviceId)
    Write-Field 'Driver'          $a.DriverVersion

    if ($tier -eq 'Unsupported') {
        Write-Field 'Tier' 'UNSUPPORTED' 'Red'
        Write-Host ''

        $isTensorlessTuring = $false
        foreach ($r in $Script:NfTensorlessNvidiaDies) {
            if ($vendorId -eq 0x10DE -and $deviceId -ge $r.Lo -and $deviceId -le $r.Hi) {
                $isTensorlessTuring = $true
            }
        }

        if ($isTensorlessTuring) {
            Write-Host '  This is a GTX 16xx-class part. It carries the Turing name'   -ForegroundColor Red
            Write-Host '  but ships no tensor cores at all, which is the specific'     -ForegroundColor Red
            Write-Host '  difference between a GTX 1660 and an RTX 2060.'              -ForegroundColor Red
        } else {
            Write-Host '  No matrix or tensor units on this adapter.'                  -ForegroundColor Red
        }

        Write-Host ''
        Write-Host '  A 148M-parameter network evaluated every frame has nowhere to'   -ForegroundColor Red
        Write-Host '  run on this silicon. This is a hardware limit, not a setting,'   -ForegroundColor Red
        Write-Host '  and NeuralForge refuses rather than hanging the game.'           -ForegroundColor Red
        Write-Host ''
        continue
    }

    $anyViable = $true

    $colour = if ($info.Cost -ge 12) { 'Red' } elseif ($info.Cost -ge 5) { 'Yellow' } else { 'Green' }

    Write-Field 'Tier'             ('{0}  ({1})' -f $tier, $info.Label) $colour
    Write-Field 'Relative cost'    ('{0:N1}x an RTX 50 at equal settings' -f $info.Cost) $colour
    Write-Field 'Suggested budget' ('{0:N1} ms' -f $info.Budget)
    Write-Field 'Suggested scale'  ('{0:N2}' -f $info.Scale)
    Write-Host ''
    Write-Host "  $($info.Verdict)" -ForegroundColor $colour
    Write-Host ''
}

if ($CheckRuntime) {
    Write-Host '  Runtime' -ForegroundColor Cyan
    $rt = Get-NfRuntimeStatus
    Write-Host "  $($rt.Message)" -ForegroundColor $(if ($rt.Valid) { 'Green' } else { 'Yellow' })

    if (-not $rt.Present) {
        Write-Host ''
        Write-Host '  NeuralForge does not ship the runtime and never will. Supply'    -ForegroundColor Gray
        Write-Host '  your own copy from software you already licence. See'            -ForegroundColor Gray
        Write-Host '  runtimes/README.md.'                                             -ForegroundColor Gray
    } elseif (-not $rt.Valid) {
        Write-Host ''
        Write-Host '  DO NOT USE THIS FILE. A genuine runtime is Authenticode-signed'  -ForegroundColor Red
        Write-Host '  by the vendor. An unsigned 158 MB DLL that loads into your game' -ForegroundColor Red
        Write-Host '  process is exactly the shape of a problem you do not want.'      -ForegroundColor Red
    }
    Write-Host ''
}

if ($Games) {
    Write-Host '  Games' -ForegroundColor Cyan
    Write-Host '  Scanning...' -ForegroundColor Gray

    $found = @(Get-NfGames)
    if ($found.Count -eq 0) {
        Write-Host '  None found.' -ForegroundColor Yellow
    } else {
        foreach ($g in $found) {
            $mark = switch ($g.Status) {
                'Ready'   { 'Green' }
                'Blocked' { 'Red' }
                default   { 'Yellow' }
            }
            Write-Host ('  {0,-38}' -f $g.Name) -NoNewline -ForegroundColor White
            Write-Host ('{0,-9}' -f $g.Api) -NoNewline -ForegroundColor Gray
            Write-Host $g.Status -ForegroundColor $mark
        }
    }
    Write-Host ''
}

if (-not $anyViable) {
    Write-Host '  Result: no adapter in this machine can run neural rendering.' -ForegroundColor Red
    Write-Host ''
    exit 2
}

Write-Host '  Reminders' -ForegroundColor Cyan
Write-Host '  Single-player titles only. NeuralForge refuses to load when it'
Write-Host '  detects anti-cheat, and that is not something to override.'
Write-Host '  The game needs a working DLSS, FSR or XeSS. That call is the'
Write-Host '  interception point, so without one there is no neural rendering.'
Write-Host '  You supply the runtime yourself. See runtimes/README.md.'
Write-Host ''
exit 0
