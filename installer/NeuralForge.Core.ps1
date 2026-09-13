#Requires -Version 5.1
Set-StrictMode -Version Latest

$Script:NfRoot = Split-Path $PSScriptRoot -Parent

$Script:NfTensorlessNvidiaDies = @(
    @{ Lo = 0x1F80; Hi = 0x1FFF }
    @{ Lo = 0x2180; Hi = 0x21FF }
)

$Script:NfNvidiaArchitectures = @(
    @{ Lo = 0x1E00; Hi = 0x1E9F; Tier = 'Turing'    }
    @{ Lo = 0x1F00; Hi = 0x1F7F; Tier = 'Turing'    }
    @{ Lo = 0x2200; Hi = 0x25FF; Tier = 'Ampere'    }
    @{ Lo = 0x2600; Hi = 0x28FF; Tier = 'Ada'       }
    @{ Lo = 0x2900; Hi = 0x2FFF; Tier = 'Blackwell' }
)

$Script:NfAmdArchitectures = @(
    @{ Lo = 0x7440; Hi = 0x744F; Tier = 'RDNA3' }
    @{ Lo = 0x7470; Hi = 0x747F; Tier = 'RDNA3' }
    @{ Lo = 0x7480; Hi = 0x748F; Tier = 'RDNA3' }
    @{ Lo = 0x7500; Hi = 0x759F; Tier = 'RDNA4' }
)

$Script:NfTierInfo = [ordered]@{
    'Blackwell'   = @{ Cost = 1.0;  Budget = 2.0; Scale = 1.00; Label = 'RTX 50'
                       Verdict = 'Works as intended.' }
    'Ada'         = @{ Cost = 1.6;  Budget = 2.5; Scale = 1.00; Label = 'RTX 40'
                       Verdict = 'Genuinely good. Ada has FP8 tensor cores, so nothing is emulated.' }
    'Ampere'      = @{ Cost = 9.0;  Budget = 4.0; Scale = 0.75; Label = 'RTX 30'
                       Verdict = 'Playable with aggressive settings. No FP8 path on this silicon.' }
    'Turing'      = @{ Cost = 18.0; Budget = 6.0; Scale = 0.65; Label = 'RTX 20'
                       Verdict = 'Runs, but the stage will cost more than the rest of the frame.' }
    'RDNA4'       = @{ Cost = 6.0;  Budget = 6.0; Scale = 0.65; Label = 'RX 9000'
                       Verdict = 'Experimental. Around 33 fps at 1080p on a 9070 XT today.' }
    'RDNA3'       = @{ Cost = 12.0; Budget = 8.0; Scale = 0.50; Label = 'RX 7000'
                       Verdict = 'Research interest only.' }
    'Unsupported' = @{ Cost = 0.0;  Budget = 0.0; Scale = 0.00; Label = 'unsupported'
                       Verdict = 'No tensor cores. This is a hardware limit, not a setting.' }
}

$Script:NfUpscalerRuntimes = @{
    'nvngx_dlss.dll'             = 'DLSS'
    'nvngx_dlssg.dll'            = 'DLSS-FG'
    'nvngx_dlssd.dll'            = 'DLSS-RR'
    'libxess.dll'                = 'XeSS'
    'libxess_dx11.dll'           = 'XeSS'
    'amd_fidelityfx_dx12.dll'    = 'FSR'
    'amd_fidelityfx_vk.dll'      = 'FSR'
    'ffx_fsr2_api_dx12_x64.dll'  = 'FSR2'
    'ffx_backend_dx12_x64.dll'   = 'FSR3'
    'ffx_fsr3upscaler_x64.dll'   = 'FSR3'
}

$Script:NfAntiCheatFiles = @(
    'easyanticheat.dll', 'easyanticheat_x64.dll', 'easyanticheat_setup.exe',
    'beclient.dll', 'beclient_x64.dll', 'beservice.exe', 'battleye.dll',
    'vgc.exe', 'vgk.sys', 'pnkbstra.exe'
)

$Script:NfIgnoredExePatterns =
    '(?i)\\(redist|_?commonredist|directx|vcredist|dotnet|prereq|support|' +
    'engine\\binaries\\thirdparty)\\|(?i)(unins|setup|vcredist|dxsetup|' +
    'dotnetfx|oalinst|crashreport|launcher_helper|easyanticheat)'

$Script:NfGameAssetExtensions = @(
    '.pak', '.forge', '.big', '.bnk', '.arc', '.vpk', '.bsa', '.rpf', '.sga',
    '.cpk', '.upk', '.assets', '.resource', '.sarc', '.wad', '.pck', '.xnb',
    '.uasset', '.utoc', '.ucas', '.dat', '.bundle', '.sb', '.toc'
)

$Script:NfEngineMarkers = @(
    'unityplayer.dll', 'gameassembly.dll', 'steam_api64.dll', 'steam_api.dll',
    'galaxy64.dll', 'eossdk-win64-shipping.dll', 'binkw64.dll', 'bink2w64.dll',
    'fmod.dll', 'fmodstudio.dll', 'wwise.dll', 'xaudio2_9.dll',
    'gfsdk_aftermath_lib.x64.dll', 'physx3common_x64.dll', 'd3d12core.dll',
    'x3daudio1_7.dll', 'openvr_api.dll', 'discord_game_sdk.dll'
)

$Script:NfNonGamePathPatterns =
    '(?i)\\(windows|system32|syswow64|drivers|driverstore|windowsapps\\microsoft\.)' +
    '|(?i)\\(microsoft (visual studio|office|edge)|google\\chrome|mozilla|nodejs|' +
    'python|java|jdk|jre|git|docker|dotnet|powershell)\\'

$Script:NfChromiumMarkers = @(
    'icudtl.dat', 'v8_context_snapshot.bin', 'snapshot_blob.bin',
    'chrome_100_percent.pak', 'chrome_200_percent.pak', 'vk_swiftshader.dll',
    'app.asar', 'chrome_elf.dll', 'libcef.dll'
)

$Script:NfNonGameNamePatterns =
    '(?i)^(blender|ffmpeg|obs|audacity|gimp|inkscape|krita|handbrake|vlc|' +
    'winrar|7-zip|notepad|sublime|jetbrains|android studio|unity hub|' +
    'epic games launcher|ea app|origin|ubisoft connect|battle\.net|' +
    'nvidia |amd |intel |realtek|killer |logitech|razer|corsair|steelseries|' +
    'microsoft |google |mozilla |adobe |autodesk |docker|virtualbox|vmware)' +
    '|(?i)(driver|redistributable|runtime|framework|sdk|toolkit|launcher|' +
    'bootstrapper|updater|installer|service)$'

$Script:NfMinimumGameExeBytes    = 8MB
$Script:NfMinimumGameFolderBytes = 400MB

function Get-NfTier {
    param([int]$VendorId, [int]$DeviceId)

    if ($VendorId -eq 0x10DE) {
        foreach ($r in $Script:NfTensorlessNvidiaDies) {
            if ($DeviceId -ge $r.Lo -and $DeviceId -le $r.Hi) { return 'Unsupported' }
        }
        foreach ($r in $Script:NfNvidiaArchitectures) {
            if ($DeviceId -ge $r.Lo -and $DeviceId -le $r.Hi) { return $r.Tier }
        }
        return 'Unsupported'
    }

    if ($VendorId -eq 0x1002) {
        foreach ($r in $Script:NfAmdArchitectures) {
            if ($DeviceId -ge $r.Lo -and $DeviceId -le $r.Hi) { return $r.Tier }
        }
    }

    return 'Unsupported'
}

function Get-NfGpu {
    $best = $null

    $adapters = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
                  Where-Object { $_.PNPDeviceID -match 'PCI\\VEN_' })

    foreach ($a in $adapters) {
        $vendorId = 0
        $deviceId = 0
        if ($a.PNPDeviceID -match 'VEN_([0-9A-Fa-f]{4})&DEV_([0-9A-Fa-f]{4})') {
            $vendorId = [Convert]::ToInt32($Matches[1], 16)
            $deviceId = [Convert]::ToInt32($Matches[2], 16)
        }

        $tier = Get-NfTier -VendorId $vendorId -DeviceId $deviceId
        $info = $Script:NfTierInfo[$tier]

        $candidate = [PSCustomObject]@{
            Name     = $a.Name
            Driver   = $a.DriverVersion
            VendorId = $vendorId
            DeviceId = $deviceId
            Tier     = $tier
            TierLabel= $info.Label
            Cost     = $info.Cost
            Budget   = $info.Budget
            Scale    = $info.Scale
            Verdict  = $info.Verdict
            Viable   = ($tier -ne 'Unsupported')
        }

        if (-not $best) { $best = $candidate; continue }
        if ($candidate.Viable -and -not $best.Viable) { $best = $candidate; continue }
        if ($candidate.Viable -and $best.Viable -and $candidate.Cost -lt $best.Cost) {
            $best = $candidate
        }
    }

    return $best
}

function Get-NfExeImports {
    param([Parameter(Mandatory)][string]$Path)

    $imports = New-Object System.Collections.Generic.List[string]
    $stream  = $null

    try {
        $stream = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        $reader = New-Object System.IO.BinaryReader($stream)

        if ($reader.ReadUInt16() -ne 0x5A4D) { return $imports }

        $stream.Position = 0x3C
        $peOffset = $reader.ReadUInt32()
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) { return $imports }

        $reader.ReadUInt16() | Out-Null
        $sectionCount = $reader.ReadUInt16()
        $stream.Position += 12
        $optionalHeaderSize = $reader.ReadUInt16()
        $stream.Position += 2

        $optionalHeaderStart = $stream.Position
        $magic = $reader.ReadUInt16()
        $dataDirOffset = if ($magic -eq 0x20B) { 112 } else { 96 }

        $stream.Position = $optionalHeaderStart + $dataDirOffset + 8
        $importRva = $reader.ReadUInt32()
        if ($importRva -eq 0) { return $imports }

        $sections = @()
        $stream.Position = $optionalHeaderStart + $optionalHeaderSize
        for ($i = 0; $i -lt $sectionCount; $i++) {
            $stream.Position += 8
            $virtualSize    = $reader.ReadUInt32()
            $virtualAddress = $reader.ReadUInt32()
            $rawSize        = $reader.ReadUInt32()
            $rawPointer     = $reader.ReadUInt32()
            $stream.Position += 16
            $sections += @{ Va = $virtualAddress; Vs = $virtualSize
                            Raw = $rawPointer;    Rs = $rawSize }
        }

        function ConvertTo-Offset {
            param([uint32]$Rva, $Sections)
            foreach ($s in $Sections) {
                $span = [Math]::Max($s.Vs, $s.Rs)
                if ($Rva -ge $s.Va -and $Rva -lt ($s.Va + $span)) {
                    return $s.Raw + ($Rva - $s.Va)
                }
            }
            return 0
        }

        $descOffset = ConvertTo-Offset -Rva $importRva -Sections $sections
        if ($descOffset -eq 0) { return $imports }

        for ($i = 0; $i -lt 512; $i++) {
            $stream.Position = $descOffset + ($i * 20)
            if ($stream.Position + 20 -gt $stream.Length) { break }

            $stream.Position += 12
            $nameRva = $reader.ReadUInt32()
            if ($nameRva -eq 0) { break }

            $nameOffset = ConvertTo-Offset -Rva $nameRva -Sections $sections
            if ($nameOffset -eq 0 -or $nameOffset -ge $stream.Length) { continue }

            $stream.Position = $nameOffset
            $chars = New-Object System.Text.StringBuilder
            for ($k = 0; $k -lt 128; $k++) {
                $b = $reader.ReadByte()
                if ($b -eq 0) { break }
                [void]$chars.Append([char]$b)
            }
            if ($chars.Length -gt 0) { $imports.Add($chars.ToString().ToLower()) }
        }
    } catch {
        return $imports
    } finally {
        if ($stream) { $stream.Dispose() }
    }

    return $imports
}

function Get-NfGraphicsApi {
    param([Parameter(Mandatory)][string]$ExePath, [string[]]$FolderFiles)

    $imports = @(Get-NfExeImports -Path $ExePath)

    if ($imports -contains 'd3d12.dll')    { return 'DX12' }
    if ($imports -contains 'vulkan-1.dll') { return 'Vulkan' }
    if ($imports -contains 'd3d11.dll')    { return 'DX11' }
    if ($imports -contains 'd3d9.dll')     { return 'DX9' }

    if ($FolderFiles -contains 'd3d12core.dll') { return 'DX12' }
    if ($FolderFiles -contains 'd3d12.dll')     { return 'DX12' }
    if ($FolderFiles -contains 'vulkan-1.dll')  { return 'Vulkan' }

    return 'unknown'
}

function Get-NfGameEvidence {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Files,
        [Parameter(Mandatory)][string[]]$LowerNames,
        [Parameter(Mandatory)]$Exe,
        [string]$Name = ''
    )

    $reasons = @()

    if ($Path -match $Script:NfNonGamePathPatterns) {
        return [PSCustomObject]@{ LooksLikeGame = $false; Reasons = @('system or application path') }
    }

    if ($Name -and $Name -match $Script:NfNonGameNamePatterns) {
        return [PSCustomObject]@{ LooksLikeGame = $false; Reasons = @('known application, not a game') }
    }

    foreach ($marker in $Script:NfChromiumMarkers) {
        if ($LowerNames -contains $marker) {
            return [PSCustomObject]@{
                LooksLikeGame = $false
                Reasons       = @("Chromium or Electron application ($marker)")
            }
        }
    }

    if ($Exe.Length -ge $Script:NfMinimumGameExeBytes) {
        $reasons += ('executable is {0} MB' -f [int]($Exe.Length / 1MB))
    }

    $totalBytes = ($Files | Measure-Object -Property Length -Sum).Sum
    if ($totalBytes -ge $Script:NfMinimumGameFolderBytes) {
        $reasons += ('install is {0} MB' -f [int]($totalBytes / 1MB))
    }

    foreach ($marker in $Script:NfEngineMarkers) {
        if ($LowerNames -contains $marker) {
            $reasons += "engine runtime $marker"
            break
        }
    }

    $assetCount = 0
    foreach ($f in $Files) {
        if ($Script:NfGameAssetExtensions -contains $f.Extension.ToLower()) {
            $assetCount++
            if ($assetCount -ge 3) { break }
        }
    }
    if ($assetCount -ge 3) { $reasons += 'packed game assets' }

    return [PSCustomObject]@{
        LooksLikeGame = ($reasons.Count -ge 2)
        Reasons       = $reasons
    }
}

function Test-NfGame {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [string]$Source = 'Folder',
        [int]$Depth = 3
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $null }

    $files = @()
    try {
        $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force `
                                 -Depth $Depth -ErrorAction SilentlyContinue)
    } catch { return $null }

    if ($files.Count -eq 0) { return $null }

    $lowerNames = @($files | ForEach-Object { $_.Name.ToLower() })

    $upscalers = @()
    foreach ($k in $Script:NfUpscalerRuntimes.Keys) {
        if ($lowerNames -contains $k) { $upscalers += $Script:NfUpscalerRuntimes[$k] }
    }
    $upscalers = @($upscalers | Select-Object -Unique)

    $antiCheat = @()
    foreach ($ac in $Script:NfAntiCheatFiles) {
        if ($lowerNames -contains $ac) { $antiCheat += $ac }
    }

    $folderLeaf = Split-Path $Path -Leaf
    $candidates = @($files |
                    Where-Object { $_.Extension -eq '.exe' -and
                                   $_.FullName -notmatch $Script:NfIgnoredExePatterns })

    if ($candidates.Count -eq 0) { return $null }

    $normalisedLeaf = ($folderLeaf -replace '[^a-z0-9]', '').ToLower()
    $exe = $candidates |
           Sort-Object @{ Expression = {
                            $stem = ($_.BaseName -replace '[^a-z0-9]', '').ToLower()
                            -not ($normalisedLeaf -like "*$stem*" -or $stem -like "*$normalisedLeaf*")
                          } },
                       @{ Expression = { $_.Length }; Descending = $true } |
           Select-Object -First 1

    $evidence = Get-NfGameEvidence -Path $Path -Files $files -LowerNames $lowerNames -Exe $exe -Name $Name
    if (-not $evidence.LooksLikeGame) { return $null }

    $api = Get-NfGraphicsApi -ExePath $exe.FullName -FolderFiles $lowerNames

    $status  = 'Ready'
    $blocker = ''
    $route   = 'native'

    if ($antiCheat.Count -gt 0) {
        $status  = 'Blocked'
        $blocker = "Anti-cheat present ($($antiCheat[0])). NeuralForge refuses to install here."
        $route   = 'none'
    } elseif ($api -eq 'DX9') {
        $status  = 'Unsupported API'
        $blocker = 'This game renders with DirectX 9. There is no path to a D3D12 device from there.'
        $route   = 'none'
    } elseif ($api -eq 'Vulkan') {
        $status  = 'Unsupported API'
        $blocker = 'This game renders with Vulkan. NeuralForge has no Vulkan bridge yet.'
        $route   = 'none'
    } elseif ($api -eq 'DX11') {
        $route = 'bridge'
        if ($upscalers.Count -eq 0) {
            $status  = 'No motion vectors'
            $blocker = 'DirectX 11 with no upscaler. It would need the D3D12 bridge plus synthesised motion vectors, which is the lowest-quality path there is.'
        } else {
            $status  = 'Ready via bridge'
            $blocker = 'DirectX 11 runs through a private D3D12 device. Expect roughly 10 percent on top of the stage cost.'
        }
    } elseif ($upscalers.Count -eq 0) {
        $status  = 'No motion vectors'
        $blocker = 'No DLSS, FSR or XeSS runtime found. Without engine motion vectors the stage needs optical flow, which is measurably worse.'
    } elseif ($api -eq 'unknown') {
        $blocker = 'Executable is packed, so the graphics API could not be read. An upscaler is present, so DirectX 12 is likely.'
    }

    $manifest  = Join-Path $exe.DirectoryName 'NeuralForge_Backup\manifest.json'
    $installed = Test-Path -LiteralPath $manifest

    return [PSCustomObject]@{
        Name          = $Name
        Source        = $Source
        Path          = $exe.DirectoryName
        Exe           = $exe.Name
        SizeMb        = [int]($exe.Length / 1MB)
        Api           = $api
        Route         = $route
        Upscalers     = ($upscalers -join ', ')
        UpscalerLabel = if ($upscalers.Count) { $upscalers -join ', ' } else { 'none' }
        AntiCheat     = ($antiCheat -join ', ')
        Status        = $status
        Blocker       = $blocker
        Installed     = $installed
    }
}

function Get-NfSteamRoots {
    $roots = New-Object System.Collections.Generic.List[string]

    $steamPath = $null
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        try {
            $v = Get-ItemProperty $key -ErrorAction Stop
            foreach ($prop in @('SteamPath', 'InstallPath')) {
                if ($v.PSObject.Properties.Name -contains $prop -and $v.$prop) {
                    $steamPath = $v.$prop
                    break
                }
            }
            if ($steamPath) { break }
        } catch { }
    }
    if (-not $steamPath) { return $roots }

    $roots.Add((Join-Path $steamPath 'steamapps'))

    $vdf = Join-Path $steamPath 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        foreach ($line in (Get-Content -LiteralPath $vdf)) {
            if ($line -match '"path"\s+"(.+?)"') {
                $roots.Add((Join-Path ($Matches[1] -replace '\\\\', '\') 'steamapps'))
            }
        }
    }

    return $roots
}

function Get-NfSteamGames {
    $games = @()
    $seen  = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    foreach ($root in (Get-NfSteamRoots)) {
        if (-not $root) { continue }

        $resolved = $null
        try { $resolved = (Resolve-Path -LiteralPath $root -ErrorAction Stop).Path } catch { continue }
        if (-not $seen.Add($resolved)) { continue }

        foreach ($acf in @(Get-ChildItem -LiteralPath $resolved -Filter 'appmanifest_*.acf' -ErrorAction SilentlyContinue)) {
            $text = Get-Content -LiteralPath $acf.FullName -Raw
            $name = if ($text -match '"name"\s+"(.+?)"')       { $Matches[1] } else { $null }
            $dir  = if ($text -match '"installdir"\s+"(.+?)"') { $Matches[1] } else { $null }
            if (-not $name -or -not $dir) { continue }

            if ($name -match '(?i)redistributable|steamworks (shared|common)|proton|steam linux runtime') {
                continue
            }

            $g = Test-NfGame -Path (Join-Path $resolved "common\$dir") -Name $name -Source 'Steam'
            if ($g) { $games += $g }
        }
    }

    return $games
}

function Get-NfEpicGames {
    $games    = @()
    $manifest = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
    if (-not (Test-Path -LiteralPath $manifest)) { return $games }

    foreach ($item in @(Get-ChildItem -LiteralPath $manifest -Filter '*.item' -ErrorAction SilentlyContinue)) {
        try {
            $j = Get-Content -LiteralPath $item.FullName -Raw | ConvertFrom-Json
            if (-not $j.InstallLocation -or -not $j.DisplayName) { continue }
            $g = Test-NfGame -Path $j.InstallLocation -Name $j.DisplayName -Source 'Epic'
            if ($g) { $games += $g }
        } catch { }
    }

    return $games
}

function Get-NfGogGames {
    $games = @()

    foreach ($root in @('HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games', 'HKLM:\SOFTWARE\GOG.com\Games')) {
        if (-not (Test-Path $root)) { continue }

        foreach ($key in @(Get-ChildItem $root -ErrorAction SilentlyContinue)) {
            try {
                $v = Get-ItemProperty $key.PSPath -ErrorAction Stop
                if (-not $v.PSObject.Properties.Name.Contains('path'))     { continue }
                if (-not $v.PSObject.Properties.Name.Contains('gameName')) { continue }
                if (-not $v.path -or -not (Test-Path -LiteralPath $v.path)) { continue }

                $g = Test-NfGame -Path $v.path -Name $v.gameName -Source 'GOG'
                if ($g) { $games += $g }
            } catch { }
        }
    }

    return $games
}

function Get-NfUninstallEntryGames {
    $games = @()
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }

        foreach ($key in @(Get-ChildItem $root -ErrorAction SilentlyContinue)) {
            try {
                $v = Get-ItemProperty $key.PSPath -ErrorAction Stop
                $props = $v.PSObject.Properties.Name

                if (-not $props.Contains('InstallLocation')) { continue }
                if (-not $props.Contains('DisplayName'))     { continue }
                if (-not $v.InstallLocation)                 { continue }

                $loc = $v.InstallLocation.Trim('"').TrimEnd('\')
                if (-not $loc -or -not (Test-Path -LiteralPath $loc -PathType Container)) { continue }
                if ($loc -match '(?i)\\windows\\|\\program files\\(common files|windows|internet)') { continue }

                $g = Test-NfGame -Path $loc -Name $v.DisplayName -Source 'Installed'
                if ($g) { $games += $g }
            } catch { }
        }
    }

    return $games
}

function Get-NfFolderGames {
    param([string[]]$Roots)

    $games = @()

    if (-not $Roots) {
        $Roots = @()
        foreach ($d in @([System.IO.DriveInfo]::GetDrives() |
                         Where-Object { $_.IsReady -and $_.DriveType -eq 'Fixed' })) {
            foreach ($name in @('Games', 'Jogos', 'SteamLibrary', 'Program Files (x86)\Games')) {
                $Roots += (Join-Path $d.RootDirectory.FullName $name)
            }
        }
    }

    foreach ($root in $Roots) {
        if (-not $root -or -not (Test-Path -LiteralPath $root -PathType Container)) { continue }

        foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
            $g = Test-NfGame -Path $dir.FullName -Name $dir.Name -Source 'Folder'
            if ($g) { $games += $g }
        }
    }

    return $games
}

function Get-NfGames {
    param([string[]]$ExtraRoots)

    $all = @()
    $all += @(Get-NfSteamGames)
    $all += @(Get-NfEpicGames)
    $all += @(Get-NfGogGames)
    $all += @(Get-NfUninstallEntryGames)
    $all += @(Get-NfFolderGames)

    if ($ExtraRoots) { $all += @(Get-NfFolderGames -Roots $ExtraRoots) }

    $unique = @{}
    foreach ($g in $all) {
        $key = $g.Path.ToLower()
        if (-not $unique.ContainsKey($key)) {
            $unique[$key] = $g
        } elseif ($unique[$key].Source -eq 'Folder' -and $g.Source -ne 'Folder') {
            $unique[$key] = $g
        }
    }

    $statusOrder = @{
        'Ready'             = 0
        'Ready via bridge'  = 1
        'No motion vectors' = 2
        'Unsupported API'   = 3
        'Blocked'           = 4
    }

    return @($unique.Values |
             Sort-Object @{ Expression = { $statusOrder[$_.Status] } }, Name)
}

function Get-NfRuntimeStatus {
    $path = Join-Path $Script:NfRoot 'runtimes\nvngx_dlssnr.dll'

    if (-not (Test-Path -LiteralPath $path)) {
        return [PSCustomObject]@{
            Present = $false
            Valid   = $false
            Message = 'Not supplied. NeuralForge does not ship it. See runtimes/README.md.'
        }
    }

    $file = Get-Item -LiteralPath $path
    $sig  = Get-AuthenticodeSignature -LiteralPath $path

    if ($sig.Status -ne 'Valid') {
        return [PSCustomObject]@{
            Present = $true
            Valid   = $false
            Message = "Signature $($sig.Status). Do not use this file."
        }
    }

    return [PSCustomObject]@{
        Present = $true
        Valid   = $true
        Message = "Valid, $([math]::Round($file.Length / 1MB, 1)) MB, version $($file.VersionInfo.FileVersion)."
    }
}

function Get-NfPayload {
    param([string]$Proxy = 'dxgi')

    return @(
        @{ Src = 'build\bin\NeuralForge.dll';      Dst = "$Proxy.dll" }
        @{ Src = 'configs\neuralforge.ini';        Dst = 'configs\neuralforge.ini' }
        @{ Src = 'configs\anticheat_denylist.txt'; Dst = 'configs\anticheat_denylist.txt' }
    )
}

function Install-NeuralForge {
    param(
        [Parameter(Mandatory)]$Game,
        [string]$Proxy = 'dxgi',
        $Gpu,
        [switch]$Force
    )

    if ($Game.Status -eq 'Blocked' -and -not $Force) {
        throw "Refusing to install: $($Game.Blocker)"
    }

    $backupDir = Join-Path $Game.Path 'NeuralForge_Backup'
    $manifest  = Join-Path $backupDir 'manifest.json'
    $payload   = Get-NfPayload -Proxy $Proxy

    $missing = @()
    foreach ($p in $payload) {
        if (-not (Test-Path -LiteralPath (Join-Path $Script:NfRoot $p.Src))) { $missing += $p.Src }
    }
    if ($missing.Count -gt 0) {
        throw "Build output missing: $($missing -join ', '). Run build.ps1 first, or use a release archive."
    }

    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    $added    = @()
    $replaced = @()

    foreach ($p in $payload) {
        $src = Join-Path $Script:NfRoot $p.Src
        $dst = Join-Path $Game.Path     $p.Dst

        $dstDir = Split-Path $dst -Parent
        if (-not (Test-Path -LiteralPath $dstDir)) {
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        }

        if (Test-Path -LiteralPath $dst) {
            $bak    = Join-Path $backupDir $p.Dst
            $bakDir = Split-Path $bak -Parent
            if (-not (Test-Path -LiteralPath $bakDir)) {
                New-Item -ItemType Directory -Path $bakDir -Force | Out-Null
            }
            Copy-Item -LiteralPath $dst -Destination $bak -Force
            $replaced += $p.Dst
        } else {
            $added += $p.Dst
        }

        Copy-Item -LiteralPath $src -Destination $dst -Force
    }

    $shaderSrc = Join-Path $Script:NfRoot 'build\shaders'
    if (Test-Path -LiteralPath $shaderSrc) {
        $shaderDst = Join-Path $Game.Path 'shaders'
        New-Item -ItemType Directory -Path $shaderDst -Force | Out-Null
        Copy-Item -LiteralPath "$shaderSrc\*" -Destination $shaderDst -Force
        $added += 'shaders'
    }

    if ($Gpu -and $Gpu.Viable) {
        Set-NfConfigValue -Path (Join-Path $Game.Path 'configs\neuralforge.ini') -Values @{
            BudgetMs     = ('{0:N1}' -f $Gpu.Budget)
            WorkingScale = ('{0:N2}' -f $Gpu.Scale)
        }
    }

    @{
        Version   = '0.1.0'
        Installed = (Get-Date).ToString('o')
        Proxy     = $Proxy
        Game      = $Game.Name
        Added     = $added
        Replaced  = $replaced
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifest -Encoding utf8

    return "Installed to $($Game.Path) as $Proxy.dll."
}

function Uninstall-NeuralForge {
    param([Parameter(Mandatory)]$Game)

    $backupDir = Join-Path $Game.Path 'NeuralForge_Backup'
    $manifest  = Join-Path $backupDir 'manifest.json'

    if (-not (Test-Path -LiteralPath $manifest)) {
        throw "No NeuralForge installation found in $($Game.Path)."
    }

    $data = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json

    foreach ($f in $data.Added) {
        $p = Join-Path $Game.Path $f
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
    }

    foreach ($f in $data.Replaced) {
        $src = Join-Path $backupDir $f
        $dst = Join-Path $Game.Path $f
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $dst -Force }
    }

    Remove-Item -LiteralPath $backupDir -Recurse -Force
    return "Removed. $($Game.Path) is back to its previous state."
}

function Set-NfConfigValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Values
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $false }

    $text = Get-Content -LiteralPath $Path -Raw
    foreach ($k in $Values.Keys) {
        $line = '{0,-20} = {1}' -f $k, $Values[$k]
        if ($text -match "(?m)^\s*$k\s*=") {
            $text = $text -replace "(?m)^\s*$k\s*=.*", $line
        } else {
            $text += "`n$line`n"
        }
    }

    Set-Content -LiteralPath $Path -Value $text -Encoding utf8
    return $true
}

function Get-NfConfigValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key,
        $Default = $null
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $Default }

    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if ($line -match "(?i)^\s*$Key\s*=\s*(.+?)\s*(;.*)?$") { return $Matches[1] }
    }

    return $Default
}
