param(
  [Parameter(Mandatory=$true)][string]$AppId,
  [Parameter(Mandatory=$true)][string]$Url,
  [Parameter(Mandatory=$true)][string]$ApiName,
  [Parameter(Mandatory=$true)][string]$PluginRoot,
  [Parameter(Mandatory=$true)][string]$SteamPath
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$backend = Join-Path $PluginRoot "backend"
$temp = Join-Path $backend "temp_dl"
$statusPath = Join-Path $temp ("status_{0}.json" -f $AppId)
$zipPath = Join-Path $temp ("{0}.zip" -f $AppId)
$extractPath = Join-Path $temp ("extract_{0}" -f $AppId)
$targetDir = Join-Path $SteamPath "config\stplug-in"
$depotcache = Join-Path $SteamPath "depotcache"
$loadedAppsPath = Join-Path $backend "loadedappids.txt"
$installedAppsPath = Join-Path $backend "installed_lua_apps.txt"
$appidLogPath = Join-Path $backend "appidlogs.txt"

function Get-MorrenusApiKey {
  $settingsPath = Join-Path $backend "data\settings.json"
  try {
    if (-not (Test-Path -LiteralPath $settingsPath)) { return "" }
    $text = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop
    $match = [regex]::Match($text, '"morrenusApiKey"\s*:\s*"([^"]*)"')
    if (-not $match.Success) { return "" }
    return ($match.Groups[1].Value -replace '\s+', '')
  } catch {
    return ""
  }
}

function Write-State {
  param([hashtable]$State)
  New-Item -ItemType Directory -Path $temp -Force | Out-Null
  $payload = @{} + $State
  $payload.updatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $tmpPath = "{0}.tmp.{1}.{2}" -f $statusPath, $PID, ([guid]::NewGuid().ToString("N"))
  $payload | ConvertTo-Json -Depth 8 -Compress | Set-Content -LiteralPath $tmpPath -Encoding UTF8
  Move-Item -LiteralPath $tmpPath -Destination $statusPath -Force
}

function Clear-DownloadScratch {
  param(
    [Parameter(Mandatory=$true)][string]$ZipPath,
    [Parameter(Mandatory=$true)][string]$ExtractPath
  )

  Remove-Item -LiteralPath $ZipPath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $ExtractPath -Recurse -Force -ErrorAction SilentlyContinue
}

function Clear-OldTempFiles {
  try {
    if (-not (Test-Path -LiteralPath $temp)) { return }
    $now = Get-Date

    Get-ChildItem -LiteralPath $temp -Force -ErrorAction SilentlyContinue | ForEach-Object {
      try {
        $age = $now - $_.LastWriteTime
        $name = $_.Name

        if ($_.PSIsContainer) {
          if (($name -match '^extract_\d+$' -or $name -match '^fix_extract_\d+$') -and $age.TotalMinutes -gt 30) {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
          }
          return
        }

        if (($name -match '^\d+\.zip$' -or $name -match '^fix_\d+\.zip$') -and $age.TotalMinutes -gt 30) {
          Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
          return
        }

        if (($name -match '^status_\d+\.json$' -or $name -match '^fix_status_\d+\.json$' -or $name -match '^unfix_status_\d+\.json$') -and $age.TotalDays -gt 7) {
          Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
          return
        }

        if (($name -match '^hidden_command_.*\.txt$' -or $name -match '^worker_daemon_start\.txt$') -and $age.TotalHours -gt 2) {
          Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
          return
        }
      } catch {}
    }
  } catch {}
}

function Invoke-SteamConfigRescanProbe {
  param(
    [Parameter(Mandatory=$true)][string]$InstalledLuaPath
  )

  $now = Get-Date
  foreach ($path in @($InstalledLuaPath, $targetDir, $depotcache, (Join-Path $SteamPath "config"))) {
    try {
      if (Test-Path -LiteralPath $path) {
        (Get-Item -LiteralPath $path -Force).LastWriteTime = $now
      }
    } catch {}
  }

  foreach ($dir in @($targetDir, $depotcache, (Join-Path $SteamPath "config"))) {
    try {
      if (Test-Path -LiteralPath $dir) {
        $probe = Join-Path $dir (".luatools_rescan_probe_{0}.tmp" -f $AppId)
        Set-Content -LiteralPath $probe -Value $now.ToString("o") -Encoding ASCII
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
      }
    } catch {}
  }
}

function Get-DlcCountFromLua {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$BaseAppId
  )

  try {
    $text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($text)) {
      return 0
    }

    $match = [regex]::Match($text, '(?im)^\s*--\s*Total\s+DLCs\s*:\s*(\d+)\s*$')
    if ($match.Success -and [int]$match.Groups[1].Value -gt 0) {
      return [int]$match.Groups[1].Value
    }

    $depotIds = @{}
    foreach ($manifestMatch in [regex]::Matches($text, '(?im)^\s*setManifestid\s*\(\s*["'']?(\d+)["'']?')) {
      $depotIds[$manifestMatch.Groups[1].Value] = $true
    }

    $dlcIds = @{}
    foreach ($appidMatch in [regex]::Matches($text, '(?im)^\s*addappid\s*\(\s*["'']?(\d+)["'']?\s*([^)]*)\)')) {
      $id = $appidMatch.Groups[1].Value
      $argsTail = $appidMatch.Groups[2].Value
      $hasDlcToken = $argsTail -match ',\s*0\s*,\s*["''][A-Fa-f0-9]{16,}["'']'
      if ($id -ne $BaseAppId -and ($hasDlcToken -or -not $depotIds.ContainsKey($id))) {
        $dlcIds[$id] = $true
      }
    }

    return $dlcIds.Count
  } catch {}

  return 0
}

function Get-SteamAppName {
  param([Parameter(Mandatory=$true)][string]$AppId)

  try {
    $url = "https://store.steampowered.com/api/appdetails?appids=$AppId&filters=basic"
    $response = Invoke-RestMethod -Uri $url -TimeoutSec 12 -Headers @{ "User-Agent" = "LuaTools" }
    $entry = $response.PSObject.Properties[$AppId]
    if ($entry -and $entry.Value.success -and $entry.Value.data -and $entry.Value.data.name) {
      return [string]$entry.Value.data.name
    }
  } catch {}

  return ""
}

function Repair-Mojibake {
  param([string]$Text)
  if ([string]::IsNullOrEmpty($Text)) { return "" }
  $out = $Text
  for ($i = 0; $i -lt 3; $i++) {
    $looksBroken =
      $out.IndexOf([char]0x00C3) -ge 0 -or
      $out.IndexOf([char]0x00C2) -ge 0 -or
      $out.IndexOf([char]0x00E2) -ge 0
    if (-not $looksBroken) { break }
    try {
      $bytes = [Text.Encoding]::GetEncoding(1252).GetBytes($out)
      $next = [Text.Encoding]::UTF8.GetString($bytes)
      if ($next.IndexOf([char]0xFFFD) -ge 0) { break }
      if ($next -eq $out) { break }
      $out = $next
    } catch {
      break
    }
  }
  return $out
}

try {
  if ([string]::IsNullOrWhiteSpace($SteamPath) -or -not (Test-Path -LiteralPath $SteamPath)) {
    throw "Steam path not found: $SteamPath"
  }

  New-Item -ItemType Directory -Path $temp -Force | Out-Null
  New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
  New-Item -ItemType Directory -Path $depotcache -Force | Out-Null
  Clear-DownloadScratch -ZipPath $zipPath -ExtractPath $extractPath
  Clear-OldTempFiles

  Write-State @{ status = "downloading"; currentApi = $ApiName; bytesRead = 0; totalBytes = 0 }

  $effectiveUrl = $Url
  if ($ApiName -match "morrenus") {
    $morrenusKey = Get-MorrenusApiKey
    if ([string]::IsNullOrWhiteSpace($morrenusKey)) {
      throw "Morrenus API key is missing"
    }
    $effectiveUrl = "https://hubcapmanifest.com/api/v1/manifest/$AppId`?api_key=$([uri]::EscapeDataString($morrenusKey))"
  }

  Invoke-WebRequest -Uri $effectiveUrl -OutFile $zipPath -MaximumRedirection 10 -TimeoutSec 180 -Headers @{ "User-Agent" = "discord(dot)gg/luatools" }
  $zipInfo = Get-Item -LiteralPath $zipPath
  if ($zipInfo.Length -le 0) {
    throw "Downloaded archive is empty"
  }
  Write-State @{ status = "processing"; currentApi = $ApiName; bytesRead = $zipInfo.Length; totalBytes = $zipInfo.Length }

  Remove-Item -LiteralPath $extractPath -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
  Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

  $manifestCount = 0
  Get-ChildItem -LiteralPath $extractPath -Recurse -File -Filter "*.manifest" | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $depotcache $_.Name) -Force
    $manifestCount += 1
  }

  $luaFile = Get-ChildItem -LiteralPath $extractPath -Recurse -File -Filter "$AppId.lua" | Select-Object -First 1
  if (-not $luaFile) {
    $luaFile = Get-ChildItem -LiteralPath $extractPath -Recurse -File -Filter "*.lua" | Select-Object -First 1
  }
  if (-not $luaFile) {
    throw "No lua file found in downloaded archive"
  }

  $dlcCount = Get-DlcCountFromLua -Path $luaFile.FullName -BaseAppId $AppId
  $installedLuaPath = Join-Path $targetDir ("{0}.lua" -f $AppId)
  Copy-Item -LiteralPath $luaFile.FullName -Destination $installedLuaPath -Force
  Invoke-SteamConfigRescanProbe -InstalledLuaPath $installedLuaPath

  $existingName = ""
  $lines = @()
  if (Test-Path -LiteralPath $loadedAppsPath) {
    foreach ($line in Get-Content -LiteralPath $loadedAppsPath -ErrorAction SilentlyContinue) {
      $trimmed = ([string]$line).Trim()
      if (-not $trimmed) { continue }
      if ($trimmed -match '^(\d+):(.*)$') {
        if ($matches[1] -eq $AppId) {
          $candidateName = $matches[2].Trim()
          if ($candidateName -and $candidateName -notmatch '^UNKNOWN\s*\(') {
            $existingName = $candidateName
          }
          continue
        }
        $lines += $trimmed
      }
    }
  }

  $name = Repair-Mojibake (Get-SteamAppName -AppId $AppId)
  if ([string]::IsNullOrWhiteSpace($name)) { $name = $existingName }
  if ([string]::IsNullOrWhiteSpace($name)) { $name = "UNKNOWN ($AppId)" }
  $name = Repair-Mojibake $name
  $lines += "$AppId`:$name"
  $lines | Set-Content -LiteralPath $loadedAppsPath -Encoding UTF8

  $installedLines = @()
  if (Test-Path -LiteralPath $installedAppsPath) {
    foreach ($line in Get-Content -LiteralPath $installedAppsPath -ErrorAction SilentlyContinue) {
      $trimmed = ([string]$line).Trim()
      if ($trimmed -and $trimmed -match '^(\d+):' -and $matches[1] -ne $AppId) {
        $installedLines += $trimmed
      }
    }
  }
  $installedLines += "$AppId`:$name"
  $installedLines | Set-Content -LiteralPath $installedAppsPath -Encoding UTF8

  $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  Add-Content -LiteralPath $appidLogPath -Value "[ADDED - $ApiName] $AppId - $name - $stamp"

  Write-State @{
    status = "done"
    success = $true
    currentApi = $ApiName
    api = $ApiName
    bytesRead = $zipInfo.Length
    totalBytes = $zipInfo.Length
    manifests = $manifestCount
    dlcs = $dlcCount
  }
  Clear-DownloadScratch -ZipPath $zipPath -ExtractPath $extractPath
} catch {
  Write-State @{
    status = "failed"
    success = $false
    currentApi = $ApiName
    error = $_.Exception.Message
  }
  Clear-DownloadScratch -ZipPath $zipPath -ExtractPath $extractPath
}
