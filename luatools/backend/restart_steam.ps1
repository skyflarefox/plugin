param(
  [Parameter(Mandatory=$true)][string]$SteamPath
)

$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

$steamExe = Join-Path $SteamPath "steam.exe"
Start-Sleep -Milliseconds 500

if (Test-Path -LiteralPath $steamExe) {
  Start-Process -FilePath $steamExe -ArgumentList "-shutdown" -WorkingDirectory $SteamPath -WindowStyle Hidden
}

for ($i = 0; $i -lt 20; $i++) {
  Start-Sleep -Milliseconds 500
  if (-not (Get-Process -Name "steam" -ErrorAction SilentlyContinue)) {
    break
  }
}

if (Test-Path -LiteralPath $steamExe) {
  Start-Process -FilePath $steamExe -WorkingDirectory $SteamPath -WindowStyle Normal
}
