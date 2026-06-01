param(
  [Parameter(Mandatory=$true)][string]$AppId,
  [Parameter(Mandatory=$true)][string]$Url,
  [Parameter(Mandatory=$true)][string]$FixType,
  [Parameter(Mandatory=$true)][string]$InstallPath,
  [Parameter(Mandatory=$true)][string]$GameName,
  [Parameter(Mandatory=$true)][string]$PluginRoot
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$backend = Join-Path $PluginRoot "backend"
$temp = Join-Path $backend "temp_dl"
$statusPath = Join-Path $temp ("fix_status_{0}.json" -f $AppId)
$zipPath = Join-Path $temp ("fix_{0}.zip" -f $AppId)
$extractPath = Join-Path $temp ("fix_extract_{0}" -f $AppId)

function Write-State {
  param([hashtable]$State)
  New-Item -ItemType Directory -Path $temp -Force | Out-Null
  $payload = @{} + $State
  $payload.updatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $tmpPath = "{0}.tmp.{1}.{2}" -f $statusPath, $PID, ([guid]::NewGuid().ToString("N"))
  $payload | ConvertTo-Json -Depth 8 -Compress | Set-Content -LiteralPath $tmpPath -Encoding UTF8
  Move-Item -LiteralPath $tmpPath -Destination $statusPath -Force
}

function Clear-FixScratch {
  Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $extractPath -Recurse -Force -ErrorAction SilentlyContinue
}

try {
  if ([string]::IsNullOrWhiteSpace($InstallPath) -or -not (Test-Path -LiteralPath $InstallPath)) {
    throw "Install path does not exist"
  }

  New-Item -ItemType Directory -Path $temp -Force | Out-Null
  Clear-FixScratch
  Write-State @{ status = "downloading"; bytesRead = 0; totalBytes = 0 }

  Invoke-WebRequest -Uri $Url -OutFile $zipPath -MaximumRedirection 10 -TimeoutSec 180 -Headers @{ "User-Agent" = "discord(dot)gg/luatools" }
  $zipInfo = Get-Item -LiteralPath $zipPath
  if ($zipInfo.Length -le 0) {
    throw "Downloaded archive is empty"
  }

  Write-State @{ status = "extracting"; bytesRead = $zipInfo.Length; totalBytes = $zipInfo.Length }

  Remove-Item -LiteralPath $extractPath -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
  Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force
  Copy-Item -Path (Join-Path $extractPath "*") -Destination $InstallPath -Recurse -Force

  $files = @()
  Get-ChildItem -LiteralPath $extractPath -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($extractPath.Length).TrimStart("\", "/")
    if (-not [string]::IsNullOrWhiteSpace($rel)) {
      $files += $rel
    }
  }

  $logPath = Join-Path $InstallPath ("luatools-fix-log-{0}.log" -f $AppId)
  $previous = ""
  if (Test-Path -LiteralPath $logPath) {
    $previous = Get-Content -LiteralPath $logPath -Raw
  }
  $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $displayName = if ([string]::IsNullOrWhiteSpace($GameName)) { "Unknown Game ($AppId)" } else { $GameName }
  $block = "[FIX]`nDate: $stamp`nGame: $displayName`nFix Type: $FixType`nDownload URL: $Url`nFiles:`n$($files -join "`n")`n[/FIX]`n"
  if ([string]::IsNullOrWhiteSpace($previous)) {
    Set-Content -LiteralPath $logPath -Value $block -Encoding UTF8
  } else {
    Set-Content -LiteralPath $logPath -Value ($previous + "`n---`n`n" + $block) -Encoding UTF8
  }

  Write-State @{
    status = "done"
    success = $true
    bytesRead = $zipInfo.Length
    totalBytes = $zipInfo.Length
  }
  Clear-FixScratch
} catch {
  Write-State @{
    status = "failed"
    success = $false
    error = $_.Exception.Message
  }
  Clear-FixScratch
}
