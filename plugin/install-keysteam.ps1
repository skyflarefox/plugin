# =====================================
# SkyTools Installer
# =====================================
$Host.UI.RawUI.WindowTitle = "SkyTools Installer"

# ==================== CONFIGURATIONS ====================
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
    if (Test-Path $ItemPath) {
        Remove-Item $ItemPath -Recurse -Force -ErrorAction SilentlyContinue
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

# ==================== FINAL CLEANUP ====================
Log "INFO" "Cleaning temporary files..."
Get-ChildItem -Path $env:TEMP -Filter "*skytools*.zip" -ErrorAction SilentlyContinue | Remove-Item -Force
Log "OK" "Temporary files removed"
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