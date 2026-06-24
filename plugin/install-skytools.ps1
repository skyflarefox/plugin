# =====================================
# SkyTools + LuaTools Plugin Installer
# =====================================

$Host.UI.RawUI.WindowTitle = "Skytools Plugin Installer | .gg/luatools"

# ==================== CONFIGURATIONS ====================
$name = "luatools"
$link = "https://github.com/JuniorSantana93/files/raw/refs/heads/main/luatools.zip"
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
        "OK" { "Green" }
        "INFO" { "Cyan" }
        "ERR" { "Red" }
        "WARN" { "Yellow" }
        "LOG" { "Magenta" }
        default { "White" }
    }
    $date = Get-Date -Format "HH:mm:ss"
    $prefix = if ($NoNewline) { "`r[$date] " } else { "[$date] " }
    Write-Host $prefix -ForegroundColor Cyan -NoNewline
    Write-Host "[$Type] $Message" -ForegroundColor $color -NoNewline:$NoNewline
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
$upperName = $name.Substring(0, 1).ToUpper() + $name.Substring(1).ToLower()

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
$SkytoolsItems = @("opensteamtool", "dwmapi.dll", ""xinput1_4.dll")
foreach ($Item in $SkytoolsItems) {
    $ItemPath = Join-Path $steam $Item
    if (Test-Path $ItemPath) {
        Remove-Item $ItemPath -Force -ErrorAction SilentlyContinue
        Log "OK" "Removed: $Item"
    }
}

$tempZip = Join-Path $env:TEMP "skytools.zip"

Log "LOG" "Downloading SkyTools..."
Invoke-WebRequest -Uri "https://github.com/skyflarefox/files/raw/refs/heads/main/skytools.zip" -OutFile $tempZip -TimeoutSec 30 -ErrorAction Stop
Log "OK" "Download completed"
Log "LOG" "Extracting SkyTools to Steam folder..."
Expand-Archive -Path $tempZip -DestinationPath $steam -Force -ErrorAction Stop
Log "OK" "SkyTools installed successfully"
Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
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
    "ext", "millennium", "millennium-migration-temp",
    "plugins", "millennium-updater-temp-files", "millennium.dll",
    "millennium.hhx64.dll", "python311.dll", "version.dll", "wsock32.dll"
)
foreach ($Item in $MillenniumItems) {
    $ItemPath = Join-Path $steam $Item
    if (Test-Path $ItemPath) {
        Remove-Item $ItemPath -Recurse -Force -ErrorAction SilentlyContinue
        Log "OK" "Removed: $Item"
    }
}
# --- Download Millennium (latest stable) ---
Log "LOG" "Downloading Millennium..."
$apiUrl = "https://api.github.com/repos/SteamClientHomebrew/Millennium/releases/latest"
$release = Invoke-RestMethod -Uri $apiUrl -Method Get -ErrorAction Stop
$asset = $release.assets | Where-Object { $_.name -like "*windows-x86_64.zip" } | Select-Object -First 1
if (-not $asset) {
    Log "ERROR" "Could not find the Millennium installation file."
    throw "Asset not found."
}

$tempZip = Join-Path $env:TEMP "millennium.zip"
Log "LOG" "Downloading Millennium v$($release.tag_name)..."
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tempZip -TimeoutSec 60 -ErrorAction Stop
Log "OK" "Download completed"
Log "LOG" "Extracting Millennium to Steam folder..."
Expand-Archive -Path $tempZip -DestinationPath $steam -Force -ErrorAction Stop
Log "OK" "Millennium installed successfully"
Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
Write-Host ""

# ==================== LUATOOLS ====================
for ($i = 5; $i -ge 1; $i--) {
    Log "INFO" "Starting LuaTools Installation in $i second$(if($i -gt 1){'s'})..." $true
    Start-Sleep -Seconds 1
}
Write-Host ""
# --- Cleanup ---
Log "INFO" "Cleaning old LuaTools plugin..."
$LuaToolsPath = Join-Path $steam "plugins\$name"
if (Test-Path $LuaToolsPath) {
    Remove-Item $LuaToolsPath -Recurse -Force -ErrorAction SilentlyContinue
    Log "OK" "Removed: $upperName plugin"
}
$tempZip = Join-Path $env:TEMP "luatools.zip"
Log "LOG" "Downloading LuaTools..."
Invoke-WebRequest -Uri $link -OutFile $tempZip -TimeoutSec 30 -ErrorAction Stop
Log "OK" "Download completed"
$pluginsFolder = Join-Path $steam "plugins"
if (!(Test-Path $pluginsFolder)) {
    New-Item -Path $pluginsFolder -ItemType Directory -Force | Out-Null
    Log "INFO" "Plugins folder created"
}
Log "LOG" "Extracting LuaTools to plugins folder..."
Expand-Archive -Path $tempZip -DestinationPath $pluginsFolder -Force -ErrorAction Stop
Log "OK" "$upperName installed successfully"
Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
Write-Host ""

# ==================== ENABLE PLUGIN ====================
Log "LOG" "Enabling plugin..."
$configPath = Join-Path $steam "millennium/config/config.json"
if (-not (Test-Path $configPath)) {
    $config = @{
        plugins = @{ enabledPlugins = @($name) }
        general = @{ checkForMillenniumUpdates = $false }
    }
    New-Item -Path (Split-Path $configPath) -ItemType Directory -Force | Out-Null
    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
} else {
    $config = (Get-Content $configPath -Raw -Encoding UTF8) | ConvertFrom-Json
    if (-not $config.general) { $config | Add-Member -NotePropertyName general -NotePropertyValue @{} }
    $config.general.checkForMillenniumUpdates = $false
    if (-not $config.plugins) { $config | Add-Member -NotePropertyName plugins -NotePropertyValue @{} }
    if (-not $config.plugins.enabledPlugins) { $config.plugins | Add-Member -NotePropertyName enabledPlugins -NotePropertyValue @() }
    if ($config.plugins.enabledPlugins -notcontains $name) {
        $config.plugins.enabledPlugins += $name
    }
    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
}
Log "OK" "Plugin enabled"
Write-Host ""

# Cleanup
Log "INFO" "Cleaning temporary files..."
Remove-Item -Path $CliFile -Force -ErrorAction SilentlyContinue
Remove-Item -Path $DllFile -Force -ErrorAction SilentlyContinue
Log "OK" "Temporary files removed"
Write-Host ""

# ==================== FINAL ====================
Write-Host ""
Log "OK" "Installation completed successfully!"
Log "WARN" "Steam startup will be longer, don't panic and don't touch anything!"
$exe = Join-Path $steam "steam.exe"
Start-Process $exe -ArgumentList "-clearbeta"
Log "INFO" "Starting Steam..."
Write-Host ""
Log "INFO" "Press any key to close this window..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
exit