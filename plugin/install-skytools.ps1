# =====================================
# SkyTools + LuaTools Plugin Installer
# =====================================

# Relaunch with administrator rights when started from a regular PowerShell window.
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
$isAdministrator = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdministrator) {
    try {
        $scriptPath = [System.IO.Path]::GetFullPath($PSCommandPath)
        $argumentList = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argumentList -WorkingDirectory $PSScriptRoot -ErrorAction Stop
    } catch {
        Write-Host "Administrator permission is required to install SkyTools." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
    exit
}

Set-Location -LiteralPath $PSScriptRoot
$Host.UI.RawUI.WindowTitle = "Skytools Plugin Installer | https://discord.gg/J9nGjBWxJA"

# ==================== CONFIGURATIONS ====================
$name = "skytools-plugin"
$pluginFolderName = "SkyTools.Plugin"
$skyToolsRepository = "skyflarefox/skytoolsPlugin"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null
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

    $PossiblePaths = $PossiblePaths | Select-Object -Unique | Where-Object { Test-Path $_ }

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
    Log "OK" "Latest SkyTools release found: $($skyToolsRelease.Version) ($($skyToolsRelease.AssetName))"
} catch {
    Log "ERR" $_.Exception.Message
    exit 1
}
# ==================== CLOSE STEAM ====================
Log "INFO" "Closing Steam if running..."
Get-Process -Name "steam" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3
Write-Host ""

# ==================== SKYTOOLS ====================
for ($i = 5; $i -ge 1; $i--) {
    Log "INFO" "Starting SkyTools Installation in $i second$(if($i -gt 1){'s'})..." $true
    Start-Sleep -Seconds 1
}
Write-Host ""

# --- Cleanup ---
Log "INFO" "Cleaning old SkyTools files..."
$SkytoolsItems = @("opensteamtool", "dwmapi.dll", "xinput1_4.dll")
foreach ($Item in $SkytoolsItems) {
    $ItemPath = Join-Path $steam $Item
    if (Test-Path -LiteralPath $ItemPath) {
        Remove-SteamItem -Path $ItemPath
        Log "OK" "Removed: $Item"
    }
}

$tempZip = Join-Path $env:TEMP "skytools.zip"
Log "LOG" "Downloading SkyTools..."
try {
    Invoke-WebRequest -Uri "https://github.com/skyflarefox/files/raw/refs/heads/main/skytools.zip" -OutFile $tempZip -TimeoutSec 30 -ErrorAction Stop
    Log "OK" "Download completed"
    
    Log "LOG" "Extracting SkyTools to Steam folder..."
    Expand-Archive -Path $tempZip -DestinationPath $steam -Force -ErrorAction Stop
    Log "OK" "SkyTools installed successfully"
} catch {
    Log "ERR" "Failed to install SkyTools: $($_.Exception.Message)"
    exit 1
} finally {
    if (Test-Path $tempZip) { Remove-Item $tempZip -Force -ErrorAction SilentlyContinue }
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
    "plugins", "millennium-updater-temp-files", "millennium.dll",
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

    $tempZip = Join-Path $env:TEMP "millennium.zip"
    Log "LOG" "Downloading Millennium $($release.tag_name)..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tempZip -TimeoutSec 60 -ErrorAction Stop
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

$tempZip = Join-Path $env:TEMP "luatools.zip"
Log "LOG" "Downloading Skytools..."
try {
    Log "INFO" "Release: $($skyToolsRelease.Version)"
    Invoke-WebRequest -Uri $skyToolsRelease.DownloadUrl -OutFile $tempZip -TimeoutSec 60 -ErrorAction Stop
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
    if (-not $config.plugins.enabledPlugins) { 
        $config.plugins | Add-Member -NotePropertyName enabledPlugins -NotePropertyValue @() 
    }
    if ($config.plugins.enabledPlugins -notcontains $name) {
        $config.plugins.enabledPlugins += $name
    }

    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
}

Log "OK" "Plugin enabled"
Write-Host ""

# ==================== FINAL CLEANUP ====================
Log "INFO" "Cleaning temporary files..."
Get-ChildItem -Path $env:TEMP -Filter "*skytools*.zip" -ErrorAction SilentlyContinue | Remove-Item -Force
Get-ChildItem -Path $env:TEMP -Filter "*millennium*.zip" -ErrorAction SilentlyContinue | Remove-Item -Force
Get-ChildItem -Path $env:TEMP -Filter "*skytoolsplugin*.zip" -ErrorAction SilentlyContinue | Remove-Item -Force
Log "OK" "Temporary files removed"
Write-Host ""
# ==================== WINDOWS DEFENDER ====================
$Pasta = "C:\Program Files (x86)\Steam"
$Log = ".\Defender_Exclusion.log"

try {
    Add-MpPreference -ExclusionPath $Pasta -ErrorAction Stop

    $Mensagem = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - SUCESSO: A pasta '$Pasta' foi adicionada à exclusao do Windows Defender."
    $Mensagem | Tee-Object -FilePath $Log -Append

} catch {
    $Mensagem = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - FALHA: Nao foi possível adicionar '$Pasta'. Erro: $($_.Exception.Message)"
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
Log "INFO" "Press any key to close this window..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
exit
