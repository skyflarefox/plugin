<#
.SYNOPSIS
    Steam Manifest Downloader - Downloads depot manifests for SteamTools

.DESCRIPTION
    Downloads depot manifests via Morrenus API when SteamTools servers are unavailable.
    Includes rate-limiting controls (HTTP 429 handling and request throttling).

.PARAMETER AppId
    The Steam App ID to download manifests for.
    Can also be set via $env:APP_ID.

.PARAMETER DelaySeconds
    Delay in seconds between manifest downloads to prevent rate limits (Default: 2).
#>

param(
    [string]$AppId,
    [int]$DelaySeconds = 2
)

# Set console encoding to UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "Steam Manifest Downloader (Rate-Limit Protected)"

# Fixed Morrenus API Key
$activeApiKey = "smm_3fc9926ade87d1b58c54c8325c674419a3a5ff78865a4649000a218fedb6439f3190c0d122e050a3c60a3d003537b870"

function Write-Header {
    Clear-Host
    Write-Host ""
    $esc = [char]27
    $sourceLink = "$esc]8;;https://hubcapmanifest.com/$esc\Morrenus API$esc]8;;$esc\"
    
    Write-Host "  +================================================================+" -ForegroundColor Cyan
    Write-Host "  |         STEAM MANIFEST DOWNLOADER (For Steamtools)             |" -ForegroundColor Cyan
    Write-Host "  |    Downloads Out-Of-Date Manifest Files From $sourceLink          |" -ForegroundColor Cyan
    Write-Host "  +================================================================+" -ForegroundColor Cyan
    Write-Host ""
}

function Write-ProgressBar {
    param(
        [int]$Current,
        [int]$Total,
        [string]$Label,
        [int]$Width = 40,
        [ConsoleColor]$Color = "Green"
    )

    $percent = if ($Total -gt 0) { [math]::Round(($Current / $Total) * 100) } else { 0 }
    $filled = [math]::Floor(($Current / [math]::Max($Total, 1)) * $Width)
    $empty = $Width - $filled

    $barFilled = "#" * $filled
    $barEmpty = "-" * $empty

    Write-Host ("`r  {0} [{1}" -f $Label, $barFilled) -NoNewline
    Write-Host $barEmpty -NoNewline -ForegroundColor DarkGray
    Write-Host ("] {0}% ({1}/{2})    " -f $percent, $Current, $Total) -NoNewline
}

function Write-Status {
    param(
        [string]$Message,
        [ConsoleColor]$Color = "White"
    )
    Write-Host "  [*] $Message" -ForegroundColor $Color
}

function Write-Success {
    param([string]$Message)
    Write-Host "  [+] $Message" -ForegroundColor Green
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "  [-] $Message" -ForegroundColor Red
}

function Write-WarningMsg {
    param([string]$Message)
    Write-Host "  [!] $Message" -ForegroundColor Yellow
}

function Exit-WithPrompt {
    Write-Host ""
    Write-Host "  Press any key to exit..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

function Get-SteamPath {
    $registryPaths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam",
        "HKCU:\SOFTWARE\Valve\Steam"
    )

    foreach ($path in $registryPaths) {
        try {
            $steamPath = (Get-ItemProperty -Path $path -ErrorAction SilentlyContinue).InstallPath
            if ($steamPath -and (Test-Path $steamPath)) {
                return $steamPath
            }
        } catch {}
    }

    return $null
}

function Get-DepotIdsFromLua {
    param([string]$LuaPath)

    $depots = @()
    $content = Get-Content -Path $LuaPath -ErrorAction Stop

    foreach ($line in $content) {
        if ($line -match 'addappid\s*\(\s*(\d+)\s*,\s*\d+\s*,\s*"[a-fA-F0-9]+"') {
            $depotId = $matches[1]
            $depots += $depotId
        }
    }

    return $depots | Select-Object -Unique
}

function Get-AppInfo {
    param([string]$AppId)

    $url = "https://api.steamcmd.net/v1/info/$AppId"

    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 30
        return $response
    } catch {
        return $null
    }
}

function Get-ManifestIdForDepot {
    param(
        [object]$AppInfo,
        [string]$AppId,
        [string]$DepotId
    )

    try {
        $depots = $AppInfo.data.$AppId.depots
        if ($depots.$DepotId -and $depots.$DepotId.manifests -and $depots.$DepotId.manifests.public) {
            return $depots.$DepotId.manifests.public.gid
        }
    } catch {}

    return $null
}

function Try-DownloadUrl {
    param(
        [string]$Url,
        [string]$OutputFile,
        [int]$MaxRetries = 5,
        [string]$Label = "Morrenus"
    )

    $lastError = $null

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            if (Test-Path $OutputFile) {
                Remove-Item $OutputFile -Force -ErrorAction SilentlyContinue
            }

            Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 120 -OutFile $OutputFile -ErrorAction Stop

            if (Test-Path $OutputFile) {
                $fileSize = (Get-Item $OutputFile).Length
                if ($fileSize -gt 0) {
                    return @{ Success = $true; Is404 = $false; Size = $fileSize; Attempts = $attempt }
                }
            }

            $lastError = "Empty file received"
        } catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            if ($statusCode -eq 404) {
                if (Test-Path $OutputFile) { Remove-Item $OutputFile -Force -ErrorAction SilentlyContinue }
                return @{ Success = $false; Is404 = $true; Error = "Not found (404)"; Attempts = $attempt }
            }

            # Trata especificamente Rate Limit (Erro 429)
            if ($statusCode -eq 429) {
                $retryAfterSec = 5 * $attempt # Backoff exponencial (5s, 10s, 15s...)
                
                # Tenta ler cabeçalho Retry-After se fornecido pela API
                try {
                    $headerVal = $_.Exception.Response.Headers["Retry-After"]
                    if ($headerVal -and [int]::TryParse($headerVal, [ref]$retryAfterSec)) {
                        # Usa valor retornado pela API
                    }
                } catch {}

                Write-WarningMsg "Rate limit ativado (429)! Aguardando ${retryAfterSec}s para tentar novamente (Tentativa $attempt/$MaxRetries)..."
                Start-Sleep -Seconds $retryAfterSec
                continue
            }

            $lastError = $_.Exception.Message
        }

        if ($attempt -lt $MaxRetries) {
            $waitSec = 3 * $attempt
            Write-Host "      Tentativa $attempt falhou ($Label): $lastError" -ForegroundColor DarkYellow
            Write-Host "      Aguardando ${waitSec}s antes de tentar novamente..." -ForegroundColor DarkGray
            Start-Sleep -Seconds $waitSec
        }
    }

    return @{ Success = $false; Is404 = $false; Error = $lastError; Attempts = $MaxRetries }
}

function Download-Manifest {
    param(
        [string]$DepotId,
        [string]$ManifestId,
        [string]$OutputPath,
        [string]$ApiKey
    )

    $outputFile = Join-Path $OutputPath "${DepotId}_${ManifestId}.manifest"
    $morrenusUrl = "https://hubcapmanifest.com/api/v1/generate/manifest?depot_id=${DepotId}&manifest_id=${ManifestId}&api_key=${ApiKey}"

    $result = Try-DownloadUrl -Url $morrenusUrl -OutputFile $outputFile -MaxRetries 5 -Label "Morrenus"

    if ($result.Success) {
        return @{ Success = $true; FilePath = $outputFile; Size = $result.Size; Attempts = $result.Attempts }
    }

    return @{ Success = $false; Error = $result.Error; Attempts = $result.Attempts }
}

function Format-FileSize {
    param([long]$Bytes)

    if ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    } elseif ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    } else {
        return "$Bytes B"
    }
}

# ===========================================================================
# MAIN SCRIPT
# ===========================================================================

Write-Header
Write-Host "  [MODE] Morrenus API (Rate-Limit Protected - Delay: ${DelaySeconds}s)" -ForegroundColor Cyan
Write-Host ""
Write-Status "Validando chave de API Morrenus..."

try {
    $statsResponse = Invoke-RestMethod -Uri "https://hubcapmanifest.com/api/v1/user/stats?api_key=$activeApiKey" -Method Get -TimeoutSec 15 -ErrorAction Stop
    if (-not $statsResponse.can_make_requests) {
        Write-ErrorMsg "Limite diário atingido ($($statsResponse.daily_usage)/$($statsResponse.daily_limit)). Tente novamente amanhã."
        Exit-WithPrompt
    }
    Write-Success "API Key válida! Usuário: $($statsResponse.username) | Limite Diário: $($statsResponse.daily_usage)/$($statsResponse.daily_limit)"
} catch {
    $statusCode = $null
    if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
    if ($statusCode -eq 401 -or $statusCode -eq 403 -or $statusCode -eq 404) {
        Write-ErrorMsg "Chave de API não encontrada ou expirada."
    } else {
        try {
            $errBody = $_.ErrorDetails.Message | ConvertFrom-Json
            Write-ErrorMsg $errBody.detail
        } catch {
            Write-ErrorMsg "Falha ao validar chave de API: $($_.Exception.Message)"
        }
    }
    Exit-WithPrompt
}

Write-Host ""

while ($true) {

    if (-not $AppId) {
        $AppId = $env:APP_ID
    }
    if (-not $AppId) {
        $AppId = Read-Host "  Digite o AppID da Steam (Não use Depot ID ou DLC ID)"
    }

    if ([string]::IsNullOrWhiteSpace($AppId) -or $AppId -notmatch '^\d+$') {
        Write-ErrorMsg "Um App ID válido é obrigatório!"
        Exit-WithPrompt
    }

    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor DarkGray
    Write-Host ""

    Write-Status "Localizando instalação da Steam..."
    $steamPath = Get-SteamPath

    if (-not $steamPath) {
        Write-ErrorMsg "Não foi possível localizar a instalação da Steam!"
        exit 1
    }

    Write-Success "Steam encontrada em: $steamPath"

    $luaPath = Join-Path $steamPath "config\stplug-in\$AppId.lua"
    Write-Status "Procurando arquivo Lua: $luaPath"

    if (-not (Test-Path $luaPath)) {
        Write-Host ""
        Write-ErrorMsg "Arquivo Lua ausente para o AppID $AppId"
        Write-Host "  Caminho esperado: $luaPath" -ForegroundColor DarkGray
        exit 1
    }

    Write-Success "Arquivo Lua encontrado!"
    Write-Host ""

    Write-Status "Analisando arquivo Lua para extrair Depot IDs..."
    $depotIds = Get-DepotIdsFromLua -LuaPath $luaPath

    if ($depotIds.Count -eq 0) {
        Write-ErrorMsg "Nenhum Depot ID encontrado no arquivo Lua!"
        exit 1
    }

    Write-Success "Encontrado(s) $($depotIds.Count) depot ID(s)"
    Write-Host ""

    Write-Host "  +---------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  | Depot IDs encontrados:                                        |" -ForegroundColor DarkGray
    $depotList = ($depotIds -join ", ")
    if ($depotList.Length -gt 55) {
        $depotList = $depotList.Substring(0, 52) + "..."
    }
    $paddedDepotList = $depotList.PadRight(60)
    Write-Host "  | $paddedDepotList|" -ForegroundColor White
    Write-Host "  +---------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""

    Write-Status "Buscando informações no SteamCMD API..."
    $appInfo = Get-AppInfo -AppId $AppId

    if (-not $appInfo -or $appInfo.status -ne "success") {
        Write-ErrorMsg "Falha ao obter informações do App ID no SteamCMD API!"
        exit 1
    }

    Write-Success "Informações do App obtidas com sucesso"
    Write-Host ""

    Write-Status "Mapeando Depot IDs com Manifest IDs..."
    $downloadQueue = @()

    foreach ($depotId in $depotIds) {
        $manifestId = Get-ManifestIdForDepot -AppInfo $appInfo -AppId $AppId -DepotId $depotId

        if ($manifestId) {
            $downloadQueue += @{
                DepotId = $depotId
                ManifestId = $manifestId
            }
        }
    }

    if ($downloadQueue.Count -eq 0) {
        Write-WarningMsg "Nenhum manifesto correspondente encontrado para os depots!"
        exit 1
    }

    Write-Success "Encontrado(s) $($downloadQueue.Count) depot(s) com manifestos disponíveis"
    Write-Host ""

    $depotCachePath = Join-Path $steamPath "depotcache"
    if (-not (Test-Path $depotCachePath)) {
        New-Item -ItemType Directory -Path $depotCachePath -Force | Out-Null
    }

    Write-Status "Diretório de saída: $depotCachePath"
    Write-Host ""

    Write-Host "  ================================================================" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  BAIXANDO MANIFESTOS (MORRENUS API)" -ForegroundColor Cyan
    Write-Host ""

    $successCount = 0
    $skippedCount = 0
    $failedDepots = @()
    $totalSize = 0
    $startTime = Get-Date

    for ($i = 0; $i -lt $downloadQueue.Count; $i++) {
        $item = $downloadQueue[$i]
        $depotId = $item.DepotId
        $manifestId = $item.ManifestId

        Write-Host ""
        Write-ProgressBar -Current ($i) -Total $downloadQueue.Count -Label "Progresso Geral" -Color Cyan
        Write-Host ""
        Write-Host ""

        $existingFile = Join-Path $depotCachePath "${depotId}_${manifestId}.manifest"
        if (Test-Path $existingFile) {
            $existingSize = (Get-Item $existingFile).Length
            if ($existingSize -gt 0) {
                $skippedCount++
                $sizeStr = Format-FileSize -Bytes $existingSize
                Write-Host "  [=] Depot $depotId - Já atualizado ($sizeStr), pulando..." -ForegroundColor DarkCyan
                continue
            }
        }

        Write-Host "  +---------------------------------------------------------------+" -ForegroundColor DarkGray
        $depotLine = "Baixando: Depot $depotId"
        $manifestLine = "Manifest ID: $manifestId"
        Write-Host ("  | {0,-62}|" -f $depotLine) -ForegroundColor Yellow
        Write-Host ("  | {0,-62}|" -f $manifestLine) -ForegroundColor White
        Write-Host "  +---------------------------------------------------------------+" -ForegroundColor DarkGray

        $result = Download-Manifest -DepotId $depotId -ManifestId $manifestId -OutputPath $depotCachePath -ApiKey $activeApiKey

        if ($result.Success) {
            $successCount++
            $totalSize += $result.Size
            $sizeStr = Format-FileSize -Bytes $result.Size
            $retryInfo = if ($result.Attempts -gt 1) { " [Tentativa $($result.Attempts)]" } else { "" }
            Write-Success "Depot $depotId - Baixado ($sizeStr)$retryInfo"
        } else {
            $failedDepots += @{
                DepotId = $depotId
                ManifestId = $manifestId
                Error = $result.Error
            }
            Write-ErrorMsg "Depot $depotId - Falhou após $($result.Attempts) tentativas: $($result.Error)"
        }

        # Pausa anti-rate-limit entre requisições sucessivas
        if ($i -lt ($downloadQueue.Count - 1) -and $DelaySeconds -gt 0) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    Write-Host ""
    Write-ProgressBar -Current $downloadQueue.Count -Total $downloadQueue.Count -Label "Progresso Geral" -Color Cyan
    Write-Host ""

    $endTime = Get-Date
    $elapsed = $endTime - $startTime

    Write-Host ""
    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  DOWNLOAD CONCLUÍDO" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  +---------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  |                         RESUMO                                |" -ForegroundColor DarkGray
    Write-Host "  +---------------------------------------------------------------+" -ForegroundColor DarkGray

    $successText = "Baixados:      $successCount"
    Write-Host ("  |  {0,-60}|" -f $successText) -ForegroundColor Green

    $skippedText = "Ignorados:     $skippedCount (já atualizados)"
    Write-Host ("  |  {0,-60}|" -f $skippedText) -ForegroundColor DarkCyan

    $failedText = "Falhas:        $($failedDepots.Count)"
    $failedColor = if ($failedDepots.Count -gt 0) { "Red" } else { "Green" }
    Write-Host ("  |  {0,-60}|" -f $failedText) -ForegroundColor $failedColor

    $totalText = "Total:         $($downloadQueue.Count) depots"
    Write-Host ("  |  {0,-60}|" -f $totalText) -ForegroundColor White

    $sizeText = "Tamanho:       $(Format-FileSize -Bytes $totalSize)"
    Write-Host ("  |  {0,-60}|" -f $sizeText) -ForegroundColor White

    $timeText = "Tempo Total:   $($elapsed.ToString('mm\:ss'))"
    Write-Host ("  |  {0,-60}|" -f $timeText) -ForegroundColor White

    $outputText = "Destino:       $depotCachePath"
    if ($outputText.Length -gt 60) {
        $outputText = $outputText.Substring(0, 57) + "..."
    }
    Write-Host ("  |  {0,-60}|" -f $outputText) -ForegroundColor White

    Write-Host "  +---------------------------------------------------------------+" -ForegroundColor DarkGray

    if ($failedDepots.Count -gt 0) {
        Write-Host ""
        Write-Host "  DOWNLOADS COM FALHA:" -ForegroundColor Red
        Write-Host ""
        foreach ($failed in $failedDepots) {
            Write-Host "    Depot $($failed.DepotId) (Manifest: $($failed.ManifestId))" -ForegroundColor Red
            Write-Host "    Erro: $($failed.Error)" -ForegroundColor DarkRed
            Write-Host ""
        }
    }

    Write-Host ""
    Write-Host "  O que deseja fazer agora?" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    1. Processar outro AppID" -ForegroundColor White
    Write-Host "    2. Sair" -ForegroundColor White
    Write-Host ""
    do {
        $nextChoice = Read-Host "  Digite sua escolha (1-2)"
    } while ($nextChoice -notin @("1","2"))

    if ($nextChoice -eq "2") { break }

    $AppId = $null
    Write-Header
    Write-Host ""

}

exit 0