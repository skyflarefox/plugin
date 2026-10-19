# =====================================
# SkyTools Plugin + SkyTools DLL Installer
# =====================================

# Relaunch with administrator rights when started from a regular PowerShell window.
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
$isAdministrator = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdministrator) {
    $temporaryElevationScript = $false
    try {
        $workingDirectory = (Get-Location).Path
        if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
            # `irm <url> | iex` has no script path. Persist the in-memory script
            # temporarily so Windows can relaunch it through UAC.
            $scriptPath = Join-Path $env:TEMP ("install-skytools-elevated-{0}.ps1" -f [Guid]::NewGuid().ToString("N"))
            $temporaryElevationScript = $true
            $scriptContent = [string]$MyInvocation.MyCommand.Definition
            if ([string]::IsNullOrWhiteSpace($scriptContent)) {
                throw "The installer content could not be prepared for administrator mode."
            }
            [System.IO.File]::WriteAllText(
                $scriptPath,
                $scriptContent,
                (New-Object System.Text.UTF8Encoding($true)))
        } else {
            $scriptPath = [System.IO.Path]::GetFullPath($PSCommandPath)
            if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
                $workingDirectory = $PSScriptRoot
            }
        }
        $argumentList = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argumentList -WorkingDirectory $workingDirectory -ErrorAction Stop
    } catch {
        if ($temporaryElevationScript -and $scriptPath -and (Test-Path -LiteralPath $scriptPath)) {
            Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
        }
        Write-Host "Administrator permission is required to install SkyTools." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
    exit
}

if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    Set-Location -LiteralPath $PSScriptRoot
}
$Host.UI.RawUI.WindowTitle = "Skytools Plugin Installer | https://discord.gg/J9nGjBWxJA"

# ==================== CONFIGURATIONS ====================
$name = "skytools-plugin"
$pluginFolderName = "SkyTools.Plugin"
$skyToolsRepository = "skyflarefox/skytoolsPlugin"
$skyToolsDllRepository = "MalucoPlayGamer/GreenTools"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$ProgressPreference = 'SilentlyContinue'

# ==================== LOGGING ====================
function Log {
    param (
        [string]$Type,
        [string]$Message,
        [boolean]$NoNewline = $false
    )
    $Type = $Type.ToUpper()
    $color = switch ($Type) {
        "OK"    { "Green" }
        "INFO"  { "Cyan" }
        "ERR"   { "Red" }
        "WARN"  { "Yellow" }
        "LOG"   { "Magenta" }
        default { "White" }
    }
    $date = Get-Date -Format "HH:mm:ss"
    $prefix = if ($NoNewline) { "`r[$date] " } else { "[$date] " }
    Write-Host $prefix -ForegroundColor Cyan -NoNewline
    Write-Host "[$Type] $Message" -ForegroundColor $color -NoNewline:$NoNewline
}

function Get-LatestSkyToolsRelease {
    $apiUrl = "https://api.github.com/repos/$skyToolsRepository/releases/latest"
    $headers = @{
        "Accept"               = "application/vnd.github+json"
        "User-Agent"           = "SkyTools-Plugin-Installer"
        "X-GitHub-Api-Version" = "2022-11-28"
    }

    try {
        $release = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec 30 -ErrorAction Stop
        $assets = @($release.assets | Where-Object {
            $_.name -match '(?i)\.zip$' -and $_.browser_download_url
        })
        $asset = $assets | Where-Object { $_.name -match '(?i)^skytools(?:[._-].*)?\.zip$' } | Select-Object -First 1
        if (-not $asset) { $asset = $assets | Select-Object -First 1 }
        if (-not $asset) { throw "The latest release does not contain a ZIP asset." }

        return [PSCustomObject]@{
            Version     = [string]$release.tag_name
            AssetName   = [string]$asset.name
            DownloadUrl = [string]$asset.browser_download_url
        }
    } catch {
        throw "Could not find the latest SkyTools release on GitHub: $($_.Exception.Message)"
    }
}

function Remove-SteamItem {
    param([Parameter(Mandatory = $true)][string]$Path)

    $steamRoot = [System.IO.Path]::GetFullPath($steam).TrimEnd('\')
    $target = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    if ($target -eq $steamRoot -or -not $target.StartsWith($steamRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a path outside the Steam folder: $target"
    }
    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
    }
}

function Get-LatestSkyToolsDllRelease {
    $headers = @{ 'User-Agent' = 'SkyTools-Plugin-Installer'; 'Accept' = 'application/vnd.github+json' }
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$skyToolsDllRepository/releases/latest" -Headers $headers -TimeoutSec 30 -ErrorAction Stop
    $asset = $release.assets | Where-Object { $_.name -like '*-Release.zip' -and $_.browser_download_url } | Select-Object -First 1
    if (!$asset) { throw 'The latest SkyTools DLL release does not contain a Release.zip package.' }
    return [PSCustomObject]@{
        Version = [string]$release.tag_name
        DownloadUrl = [string]$asset.browser_download_url
        Digest = [string]$asset.digest
    }
}

function Set-SkyToolsTomlDefault([string]$Text, [string]$Section, [string]$Key, [string]$Value) {
    $pattern = '(?ms)^[ \t]*\[' + [regex]::Escape($Section) + '\][ \t]*(?:#[^\r\n]*)?(?:\r?\n|\z)(?<body>.*?)(?=^[ \t]*\[|\z)'
    $block = [regex]::Match($Text,$pattern)
    if (!$block.Success) { return $Text.TrimEnd() + "`r`n`r`n[$Section]`r`n$Key = $Value`r`n" }
    if ($block.Groups['body'].Value -match ('(?m)^\s*' + [regex]::Escape($Key) + '\s*=')) { return $Text }
    $prefix = if ($block.Value.EndsWith("`n")) { '' } else { "`r`n" }
    return $Text.Insert($block.Index + $block.Length,"$prefix$Key = $Value`r`n")
}

function Install-SkyToolsDllRelease {
    param([Parameter(Mandatory = $true)]$Release)
    $work = Join-Path $env:TEMP ('skytools-install-' + [Guid]::NewGuid().ToString('N'))
    $required = @('GreenTools.dll','wsock32.dll','winmm.dll')
    $legacy = @('dwmapi.dll','xinput1_4.dll','OpenSteamTool.dll','version.dll')
    $obsoleteBackups = @('wsock32.dll.dolintools-greentools.orig','winmm.dll.dolintools-greentools.orig','version.dll.dolintools-greentools.orig')
    $tracked = @($required + $legacy + @('greentools.toml','greentools\greentools.toml','opensteamtool.toml','.dolintools-skytools'))
    $backup = Join-Path $work 'backup'
    $previousFiles = @{}; $modified = $false; $rollbackFailed = $false
    $steamRoot = [IO.Path]::GetFullPath($steam).TrimEnd('\')
    function Assert-SkyToolsTarget([string]$Path) {
        $target = [IO.Path]::GetFullPath($Path)
        if (!$target.StartsWith($steamRoot + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid Steam target.' }
        $current = $target
        while ($current) {
            if ((Test-Path -LiteralPath $current) -and (Get-Item -LiteralPath $current -Force).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) { throw "Refusing a linked Steam target: $current" }
            if ($current -eq $steamRoot) { break }
            $current = Split-Path $current -Parent
        }
    }
    try {
        foreach ($relative in @($tracked + $obsoleteBackups)) { Assert-SkyToolsTarget (Join-Path $steamRoot $relative) }
        $expectedUrl = 'https://github.com/MalucoPlayGamer/GreenTools/releases/download/'
        if (!$Release.DownloadUrl.StartsWith($expectedUrl,[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid GreenTools download URL.' }
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $zip = Join-Path $work 'release.zip'
        Log 'LOG' "Downloading GreenTools $($Release.Version)..."
        Invoke-WebRequest -Uri $Release.DownloadUrl -OutFile $zip -TimeoutSec 90 -UseBasicParsing -ErrorAction Stop
        if ((Get-Item -LiteralPath $zip).Length -gt 128MB) { throw 'The DLL package exceeds the size limit.' }
        if ($Release.Digest -match '^sha256:([a-fA-F0-9]{64})$') {
            if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $Matches[1]) { throw 'The SkyTools DLL package checksum does not match GitHub.' }
        }
        $staged = @{}; $hashes = @{}
        $archive = [IO.Compression.ZipFile]::OpenRead($zip)
        try {
            foreach ($fileName in $required) {
                $files = @($archive.Entries | Where-Object { $_.Name -ieq $fileName })
                if ($files.Count -ne 1 -or $files[0].Length -lt 64 -or $files[0].Length -gt 64MB) { throw "Missing or invalid release file: $fileName" }
                $destination = Join-Path $work $fileName
                $sourceStream = $files[0].Open(); $output = [IO.File]::Create($destination)
                try { $sourceStream.CopyTo($output) } finally { $sourceStream.Dispose(); $output.Dispose() }
                $stream = [IO.File]::OpenRead($destination)
                try { if ($stream.ReadByte() -ne 77 -or $stream.ReadByte() -ne 90) { throw "Invalid DLL: $fileName" } } finally { $stream.Dispose() }
                $staged[$fileName] = $destination
                $hashes[$fileName] = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
            }
        } finally { $archive.Dispose() }
        $configPath = Join-Path $steamRoot 'greentools.toml'
        if (Test-Path -LiteralPath (Join-Path $steamRoot 'greentools\greentools.toml')) { $configPath = Join-Path $steamRoot 'greentools\greentools.toml' }
        $oldConfig = Join-Path $steamRoot 'opensteamtool.toml'
        $config = if (Test-Path -LiteralPath $configPath) { Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 }
            elseif (Test-Path -LiteralPath $oldConfig) { Get-Content -LiteralPath $oldConfig -Raw -Encoding UTF8 } else { '' }
        $defaults = @(
            @('log','level','"info"'), @('manifest','url','"manifestdex"'),
            @('manifest','timeout_resolve_ms','5000'), @('manifest','timeout_connect_ms','5000'),
            @('manifest','timeout_send_ms','10000'), @('manifest','timeout_recv_ms','10000'),
            @('lua','paths','["config/stplug-in", "config/lua"]'), @('stats','enable_api','true'),
            @('cloud','enabled','true'), @('inject','path','"OnlineFix.dll"'), @('inject','when_cmdline','"-onlinefix"'),
            @('update','enabled','true'), @('cef','enable_debugging','true'), @('cef','devtools_port','27183'))
        foreach ($item in $defaults) { $config = Set-SkyToolsTomlDefault $config $item[0] $item[1] $item[2] }
        [IO.Directory]::CreateDirectory($backup) | Out-Null
        foreach ($relative in $tracked) {
            $path = Join-Path $steamRoot $relative
            $previousFiles[$relative] = Test-Path -LiteralPath $path -PathType Leaf
            if ($previousFiles[$relative]) {
                $previous = Join-Path $backup $relative
                [IO.Directory]::CreateDirectory((Split-Path $previous -Parent)) | Out-Null
                Copy-Item -LiteralPath $path -Destination $previous -Force -ErrorAction Stop
            }
        }
        $modified = $true
        foreach ($fileName in $required) {
            $destination = Join-Path $steamRoot $fileName
            if (Test-Path -LiteralPath $destination) { [IO.File]::SetAttributes($destination,[IO.FileAttributes]::Normal) }
            Copy-Item -LiteralPath $staged[$fileName] -Destination $destination -Force -ErrorAction Stop
            if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $hashes[$fileName]) { throw "Hash verification failed after installing $fileName." }
        }
        [IO.Directory]::CreateDirectory((Split-Path $configPath -Parent)) | Out-Null
        [IO.File]::WriteAllText($configPath,$config,[Text.UTF8Encoding]::new($false))
        foreach ($fileName in $legacy) { Remove-SteamItem (Join-Path $steamRoot $fileName) }
        Remove-SteamItem $oldConfig
        [IO.File]::WriteAllText((Join-Path $steamRoot '.dolintools-skytools'),('GreenTools ' + $Release.Version),[Text.Encoding]::ASCII)
        foreach ($fileName in $obsoleteBackups) { Remove-SteamItem (Join-Path $steamRoot $fileName) }
        Log 'OK' "GreenTools $($Release.Version) installed successfully"
        return @{ repository='MalucoPlayGamer/GreenTools'; version=$Release.Version; hashes=$hashes }
    } catch {
        if ($modified) {
            foreach ($relative in $tracked) {
                $destination = Join-Path $steamRoot $relative
                try {
                    Remove-SteamItem $destination
                    if ($previousFiles[$relative]) {
                        [IO.Directory]::CreateDirectory((Split-Path $destination -Parent)) | Out-Null
                        Copy-Item -LiteralPath (Join-Path $backup $relative) -Destination $destination -Force -ErrorAction Stop
                    }
                } catch { $rollbackFailed = $true; Log 'ERR' "Rollback failed for $relative. Backup retained at: $backup" }
            }
        }
        throw
    } finally {
        $resolved = [IO.Path]::GetFullPath($work)
        $tempPrefix = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
        if (!$rollbackFailed -and $resolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# ==================== STEAM DETECTION ====================
Log "INFO" "Searching for Steam installation..."

function Find-SteamPath {
    $PossiblePaths = @()
    
    try {
        $reg = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -ErrorAction SilentlyContinue
        if ($reg.InstallPath) { $PossiblePaths += $reg.InstallPath }
    } catch {}

    try {
        $reg = Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue
        if ($reg.SteamPath) { $PossiblePaths += $reg.SteamPath -replace '\\\\', '\' }
    } catch {}

    $DefaultPath = "C:\Program Files (x86)\Steam"
    if (Test-Path $DefaultPath) { $PossiblePaths += $DefaultPath }

    $PossiblePaths = @($PossiblePaths | Select-Object -Unique | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'steam.exe') -PathType Leaf })

    if ($PossiblePaths.Count -eq 0) {
        Log "ERR" "Steam installation not found. Please install Steam first."
        exit 1
    }

    $SteamPath = $PossiblePaths[0]
    Log "OK" "Steam found at: $SteamPath"
    return $SteamPath
}

$steam = Find-SteamPath
$upperName = "SkyTools"
try {
    $skyToolsRelease = Get-LatestSkyToolsRelease
    $skyToolsDllRelease = Get-LatestSkyToolsDllRelease
    Log "OK" "Latest SkyTools release found: $($skyToolsRelease.Version) ($($skyToolsRelease.AssetName))"
    Log "OK" "Latest SkyTools DLL release found: $($skyToolsDllRelease.Version)"
} catch {
    Log "ERR" $_.Exception.Message
    exit 1
}
# ==================== CLOSE STEAM ====================
Log "INFO" "Closing Steam if running..."
Get-Process -Name "steam", "steamwebhelper" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3
Write-Host ""

# ==================== SKYTOOLS ====================
for ($i = 5; $i -ge 1; $i--) {
    Log "INFO" "Starting SkyTools Installation in $i second$(if($i -gt 1){'s'})..." $true
    Start-Sleep -Seconds 1
}
Write-Host ""

# ==================== MILLENNIUM ====================
for ($i = 5; $i -ge 1; $i--) {
    Log "INFO" "Starting Millennium Installation in $i second$(if($i -gt 1){'s'})..." $true
    Start-Sleep -Seconds 1
}
Write-Host ""

# --- Cleanup ---
Log "INFO" "Cleaning old Millennium files..."
$MillenniumItems = @(
    "ext", "millennium-migration-temp",
    "millennium-updater-temp-files", "millennium.dll",
    "millennium.hhx64.dll", "python311.dll", "version.dll", "wsock32.dll"
)
foreach ($Item in $MillenniumItems) {
    $ItemPath = Join-Path $steam $Item
    if (Test-Path -LiteralPath $ItemPath) {
        Remove-SteamItem -Path $ItemPath
        Log "OK" "Removed: $Item"
    }
}

$millenniumRoot = Join-Path $steam "millennium"
if (Test-Path -LiteralPath $millenniumRoot) {
    Get-ChildItem -LiteralPath $millenniumRoot -Force | Where-Object {
        $_.Name -notin @("plugins", "themes", "config")
    } | ForEach-Object {
        Remove-SteamItem -Path $_.FullName
        Log "OK" "Removed Millennium item: $($_.Name)"
    }
}

$skyToolsPreservedData = Join-Path $env:TEMP ('skytools-user-data-' + [Guid]::NewGuid().ToString('N'))
$skyToolsWasInstalled = Test-Path -LiteralPath (Join-Path $millenniumRoot "plugins\$pluginFolderName\plugin.json")
$existingData = Join-Path $millenniumRoot "plugins\$pluginFolderName\data"
if (Test-Path -LiteralPath $existingData) {
    New-Item -ItemType Directory -Path $skyToolsPreservedData -Force | Out-Null
    Get-ChildItem -LiteralPath $existingData -Force | Where-Object {
        $_.Name -notmatch '^(skytools-hidden-console|temp$|jobs$|drop-uploads$|launchers$)' -and $_.Extension -ne '.ps1'
    } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $skyToolsPreservedData -Recurse -Force -ErrorAction Stop }
    Log 'INFO' "Preserving SkyTools settings and backups: $skyToolsPreservedData"
}
$millenniumPluginPath = Join-Path $millenniumRoot "plugins\$pluginFolderName"
if (Test-Path -LiteralPath $millenniumPluginPath) {
    Remove-SteamItem -Path $millenniumPluginPath
    Log "OK" "Removed old SkyTools plugin: $millenniumPluginPath"
}

# --- Download Millennium (latest stable) ---
Log "LOG" "Downloading Millennium..."
try {
    $apiUrl = "https://api.github.com/repos/SteamClientHomebrew/Millennium/releases/latest"
    $millenniumHeaders = @{
        "Accept"               = "application/vnd.github+json"
        "User-Agent"           = "SkyTools-Plugin-Installer"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
    $release = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $millenniumHeaders -TimeoutSec 30 -ErrorAction Stop
    $asset = $release.assets | Where-Object { $_.name -like "*windows-x86_64.zip" } | Select-Object -First 1

    if (-not $asset) {
        Log "ERR" "Could not find Millennium installation file."
        throw "Asset not found."
    }

    $tempZip = Join-Path $env:TEMP ("millennium-{0}.zip" -f [Guid]::NewGuid().ToString("N"))
    Log "LOG" "Downloading Millennium $($release.tag_name)..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tempZip -TimeoutSec 60 -UseBasicParsing -ErrorAction Stop
    Log "OK" "Download completed"

    Log "LOG" "Extracting Millennium to Steam folder..."
    Expand-Archive -Path $tempZip -DestinationPath $steam -Force -ErrorAction Stop
    Log "OK" "Millennium installed successfully"
} catch {
    Log "ERR" "Failed to install Millennium: $($_.Exception.Message)"
    exit 1
} finally {
    if (Test-Path $tempZip) { Remove-Item $tempZip -Force -ErrorAction SilentlyContinue }
}
Write-Host ""

# ==================== Skytools ====================
for ($i = 5; $i -ge 1; $i--) {
    Log "INFO" "Starting Skytools Installation in $i second$(if($i -gt 1){'s'})..." $true
    Start-Sleep -Seconds 1
}
Write-Host ""

# --- Cleanup ---
Log "INFO" "Cleaning old SkyTools plugin..."
$LuaToolsPath = Join-Path $steam "millennium\plugins\$pluginFolderName"
if (Test-Path -LiteralPath $LuaToolsPath) {
    Remove-SteamItem -Path $LuaToolsPath
    Log "OK" "Removed: $upperName plugin"
}

$tempZip = Join-Path $env:TEMP ("skytoolsplugin-{0}.zip" -f [Guid]::NewGuid().ToString("N"))
Log "LOG" "Downloading Skytools..."
try {
    Log "INFO" "Release: $($skyToolsRelease.Version)"
    Invoke-WebRequest -Uri $skyToolsRelease.DownloadUrl -OutFile $tempZip -TimeoutSec 60 -UseBasicParsing -ErrorAction Stop
    Log "OK" "Download completed: $($skyToolsRelease.AssetName)"

    $pluginsFolder = Join-Path $steam "millennium\plugins"
    if (!(Test-Path -LiteralPath $pluginsFolder)) {
        New-Item -Path $pluginsFolder -ItemType Directory -Force | Out-Null
        Log "INFO" "Plugins folder created"
    }

    Log "LOG" "Extracting Skytools to plugins folder..."
    Expand-Archive -Path $tempZip -DestinationPath $pluginsFolder -Force -ErrorAction Stop
    Log "OK" "$upperName installed successfully"
} catch {
    Log "ERR" "Failed to install Skytools: $($_.Exception.Message)"
    exit 1
} finally {
    if (Test-Path $tempZip) { Remove-Item $tempZip -Force -ErrorAction SilentlyContinue }
}
Write-Host ""

$installedPlugin = Join-Path $steam "millennium\plugins\$pluginFolderName"
$installedData = Join-Path $installedPlugin 'data'
try {
    if (!(Test-Path -LiteralPath (Join-Path $installedPlugin 'plugin.json'))) { throw 'The package does not contain SkyTools.Plugin/plugin.json.' }
    [IO.Directory]::CreateDirectory($installedData) | Out-Null
    if (Test-Path -LiteralPath $skyToolsPreservedData) {
        Get-ChildItem -LiteralPath $skyToolsPreservedData -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $installedData -Recurse -Force -ErrorAction Stop }
    }
    if ($skyToolsWasInstalled) {
        $manifestPath = Join-Path $installedPlugin 'plugin.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $manifest.PSObject.Properties['firstRunNotice']) { $manifest | Add-Member -NotePropertyName firstRunNotice -NotePropertyValue $false }
        else { $manifest.firstRunNotice = $false }
        [IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
    }
    $installedDlls = Install-SkyToolsDllRelease -Release $skyToolsDllRelease
    [IO.File]::WriteAllText((Join-Path $installedData 'skytools-dll-integrity.json'),($installedDlls | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $installedData 'skytools-greentools-1.7-migrated.txt'),$skyToolsDllRelease.Version,[Text.Encoding]::ASCII)
} catch {
    Log 'ERR' "Failed to finish the SkyTools installation: $($_.Exception.Message)"
    exit 1
}

# ==================== ENABLE PLUGIN ====================
Log "LOG" "Enabling plugin..."
$configPath = Join-Path $steam "millennium/config/config.json"

if (-not (Test-Path $configPath)) {
    $config = @{
        plugins = @{ 
            enabledPlugins = @($name) 
        }
    }
    New-Item -Path (Split-Path $configPath) -ItemType Directory -Force | Out-Null
    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
} 
else {
    $config = (Get-Content $configPath -Raw -Encoding UTF8) | ConvertFrom-Json

    if (-not $config.plugins) { 
        $config | Add-Member -NotePropertyName plugins -NotePropertyValue @{} 
    }
    if ($null -eq $config.plugins.PSObject.Properties["enabledPlugins"]) { 
        $config.plugins | Add-Member -NotePropertyName enabledPlugins -NotePropertyValue @() 
    }
    if ($config.plugins.enabledPlugins -notcontains $name) {
        $config.plugins.enabledPlugins = @($config.plugins.enabledPlugins) + @($name)
    }

    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
}

Log "OK" "Plugin enabled"
Write-Host ""

# ==================== FINAL CLEANUP ====================
Log "INFO" "Cleaning temporary files..."
if (Test-Path -LiteralPath $skyToolsPreservedData) {
    $resolvedData = [IO.Path]::GetFullPath($skyToolsPreservedData)
    $tempPrefix = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
    if ($resolvedData.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolvedData -Recurse -Force }
}
Log "OK" "Temporary files removed"
Write-Host ""
# ==================== WINDOWS DEFENDER ====================
$Pasta = $steam
$Log = ".\Defender_Exclusion.log"

try {
    Add-MpPreference -ExclusionPath $Pasta -ErrorAction Stop

    $Mensagem = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - SUCESSO: A pasta '$Pasta' foi adicionada $([char]0x00E0) exclusao do Windows Defender."
    $Mensagem | Tee-Object -FilePath $Log -Append

} catch {
    $Mensagem = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - FALHA: Nao foi poss$([char]0x00ED)vel adicionar '$Pasta'. Erro: $($_.Exception.Message)"
    $Mensagem | Tee-Object -FilePath $Log -Append
}

Write-Host ""
# ==================== FINAL ====================
Log "OK" "Installation completed successfully!"
Log "WARN" "Steam startup will be longer, don't panic and don't touch anything!"
$exe = Join-Path $steam "steam.exe"
Start-Process $exe -ArgumentList "-clearbeta"
Log "INFO" "Starting Steam..."
Write-Host ""
if ($PSCommandPath -and [System.IO.Path]::GetFileName($PSCommandPath) -like "install-skytools-elevated-*.ps1") {
    Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
}
Log "INFO" "Press any key to close this window..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
exit
