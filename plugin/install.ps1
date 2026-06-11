$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$uiCulture = (Get-UICulture).Name
$lang = if ($uiCulture -match "^pt-BR") { "pt-BR" }
        elseif ($uiCulture -match "^pt-PT") { "pt-PT" }
        elseif ($uiCulture -match "^es") { "es" }
        else { "en" }

$strings = @{
    "pt-BR" = @{
        InstallerTitle        = "Luatools Installer - Millennium + Luatools latest"
        InfoSteamSearch       = "Procurando pasta raiz da Steam..."
        ErrSteamNotFound      = "Steam não encontrada. Instale/abra a Steam pelo menos uma vez e tente novamente."
        OkSteamFound          = "Steam encontrada:"
        WarnMillenniumMissing = "Millennium não encontrado. Instalando pela última release do GitHub..."
        InfoMillenniumUpdate  = "Millennium encontrado. Atualizando pela última release do GitHub..."
        InfoFetchingBoth      = "Buscando últimas releases do Millennium e Luatools no GitHub..."
        OkMillenniumRelease   = "Release do Millennium encontrada: {0}"
        OkLuaToolsRelease     = "Release do Luatools encontrada: {0}"
        DownloadingBoth       = "Baixando Millennium e Luatools em paralelo..."
        Extracting            = "Extraindo {0}..."
        CopyingMillennium     = "Copiando/atualizando arquivos do Millennium na raiz da Steam..."
        WarnMillenniumFolder  = "Os arquivos foram extraídos, mas a pasta 'millennium' não foi encontrada. Confira se o asset da release mudou."
        OkMillenniumInstalled = "Millennium instalado/atualizado via GitHub."
        StoppingSteam         = "Fechando Steam..."
        StartingSteam         = "Abrindo Steam novamente..."
        RemovingOldPlugins    = "Removendo plugins antigos/conflitantes..."
        FolderRemoved         = "Pasta removida: {0}"
        InstallingLuaTools    = "Instalando Luatools..."
        OkLuaToolsInstalled   = "Luatools instalado em: {0}"
        EnablingPluginConfig  = "Plugin '{0}' habilitado no config.json."
        RestartingSteam       = "Reiniciando Steam para carregar o plugin..."
        SendingEnableCmd      = "Enviando comando para habilitar o plugin no Millennium..."
        OkEnableCmdSent       = "Comando de habilitação enviado ao Millennium."
        FinalSuccess          = "Luatools instalado/atualizado e habilitado!"
        InstallingSteamTools  = "Abrindo nova janela do PowerShell para instalar/atualizar o SteamTools..."
        OkSteamToolsLaunched  = "SteamTools sendo instalado/atualizado na nova janela."
        PressEnterToExit      = "Pressione Enter para sair"
        ErrGeneric            = "Erro: {0}"
        WarnTempKept          = "Arquivos temporários mantidos em: {0}"
        RunAsAdminErr         = "Execute este instalador como Administrador. A pasta da Steam geralmente fica em Program Files."
        SteamToolsTitle       = "Instalação do SteamTools"
        SteamToolsWarning     = "AVISO: Este comando pode ser bloqueado por alguns antivírus. Certifique-se de que confia na origem (luatools)."
        SteamToolsCommand     = "Comando a ser executado: irm https://luatools.vercel.app/CloudRedirect.ps1 | iex"
        SteamToolsAskExecute  = "Deseja executar o comando agora? (S/N)"
        SteamToolsExecuted    = "Comando executado. Aguarde a conclusão."
        SteamToolsCopyHint    = "Comando não foi executado. Copie o comando acima e execute manualmente em um PowerShell como Administrador quando desejar."
        SteamToolsError       = "Erro ao executar o comando: {0}"
    }
    "pt-PT" = @{
        InstallerTitle        = "Luatools Installer - Millennium + Luatools latest"
        InfoSteamSearch       = "A procurar a pasta raiz da Steam..."
        ErrSteamNotFound      = "Steam não encontrada. Instale/abra a Steam pelo menos uma vez e tente novamente."
        OkSteamFound          = "Steam encontrada:"
        WarnMillenniumMissing = "Millennium não encontrado. A instalar pela última release do GitHub..."
        InfoMillenniumUpdate  = "Millennium encontrado. A atualizar pela última release do GitHub..."
        InfoFetchingBoth      = "A buscar as últimas releases do Millennium e Luatools no GitHub..."
        OkMillenniumRelease   = "Release do Millennium encontrada: {0}"
        OkLuaToolsRelease     = "Release do Luatools encontrada: {0}"
        DownloadingBoth       = "A baixar Millennium e Luatools em paralelo..."
        Extracting            = "A extrair {0}..."
        CopyingMillennium     = "A copiar/atualizar ficheiros do Millennium na raiz da Steam..."
        WarnMillenniumFolder  = "Os ficheiros foram extraídos, mas a pasta 'millennium' não foi encontrada. Verifique se o asset da release mudou."
        OkMillenniumInstalled = "Millennium instalado/atualizado via GitHub."
        StoppingSteam         = "A fechar a Steam..."
        StartingSteam         = "A abrir a Steam novamente..."
        RemovingOldPlugins    = "A remover plugins antigos/em conflito..."
        FolderRemoved         = "Pasta removida: {0}"
        InstallingLuaTools    = "A instalar Luatools..."
        OkLuaToolsInstalled   = "Luatools instalado em: {0}"
        EnablingPluginConfig  = "Plugin '{0}' ativado no config.json."
        RestartingSteam       = "A reiniciar a Steam para carregar o plugin..."
        SendingEnableCmd      = "A enviar comando para ativar o plugin no Millennium..."
        OkEnableCmdSent       = "Comando de ativação enviado ao Millennium."
        FinalSuccess          = "Luatools instalado/atualizado e ativado!"
        InstallingSteamTools  = "A abrir nova janela do PowerShell para instalar/atualizar o SteamTools..."
        OkSteamToolsLaunched  = "SteamTools a ser instalado/atualizado na nova janela."
        PressEnterToExit      = "Prima Enter para sair"
        ErrGeneric            = "Erro: {0}"
        WarnTempKept          = "Ficheiros temporários mantidos em: {0}"
        RunAsAdminErr         = "Execute este instalador como Administrador. A pasta da Steam geralmente fica em Program Files."
        SteamToolsTitle       = "Instalação do SteamTools"
        SteamToolsWarning     = "AVISO: Este comando pode ser bloqueado por alguns antivírus. Certifique-se de que confia na origem (luatools)."
        SteamToolsCommand     = "Comando a executar: irm https://luatools.vercel.app/CloudRedirect.ps1 | iex"
        SteamToolsAskExecute  = "Deseja executar o comando agora? (S/N)"
        SteamToolsExecuted    = "Comando executado. Aguarde a conclusão."
        SteamToolsCopyHint    = "Comando não foi executado. Copie o comando acima e execute manualmente num PowerShell como Administrador quando desejar."
        SteamToolsError       = "Erro ao executar o comando: {0}"
    }
    "es" = @{
        InstallerTitle        = "Luatools Installer - Millennium + Luatools latest"
        InfoSteamSearch       = "Buscando carpeta raíz de Steam..."
        ErrSteamNotFound      = "Steam no encontrada. Instala/abre Steam al menos una vez e inténtalo de nuevo."
        OkSteamFound          = "Steam encontrada:"
        WarnMillenniumMissing = "Millennium no encontrado. Instalando la última release desde GitHub..."
        InfoMillenniumUpdate  = "Millennium encontrado. Actualizando desde la última release de GitHub..."
        InfoFetchingBoth      = "Buscando las últimas releases de Millennium y Luatools en GitHub..."
        OkMillenniumRelease   = "Release de Millennium encontrada: {0}"
        OkLuaToolsRelease     = "Release de Luatools encontrada: {0}"
        DownloadingBoth       = "Descargando Millennium y Luatools en paralelo..."
        Extracting            = "Extrayendo {0}..."
        CopyingMillennium     = "Copiando/actualizando archivos de Millennium en la raíz de Steam..."
        WarnMillenniumFolder  = "Los archivos fueron extraídos, pero la carpeta 'millennium' no se encontró. Comprueba si el asset de la release cambió."
        OkMillenniumInstalled = "Millennium instalado/actualizado vía GitHub."
        StoppingSteam         = "Cerrando Steam..."
        StartingSteam         = "Abriendo Steam nuevamente..."
        RemovingOldPlugins    = "Eliminando plugins antiguos/conflictivos..."
        FolderRemoved         = "Carpeta eliminada: {0}"
        InstallingLuaTools    = "Instalando Luatools..."
        OkLuaToolsInstalled   = "Luatools instalado en: {0}"
        EnablingPluginConfig  = "Plugin '{0}' habilitado en config.json."
        RestartingSteam       = "Reiniciando Steam para cargar el plugin..."
        SendingEnableCmd      = "Enviando comando para habilitar el plugin en Millennium..."
        OkEnableCmdSent       = "Comando de habilitación enviado a Millennium."
        FinalSuccess          = "¡Luatools instalado/actualizado y habilitado!"
        InstallingSteamTools  = "Abriendo nueva ventana de PowerShell para instalar/actualizar SteamTools..."
        OkSteamToolsLaunched  = "SteamTools se está instalando/actualizando en la nueva ventana."
        PressEnterToExit      = "Presiona Enter para salir"
        ErrGeneric            = "Error: {0}"
        WarnTempKept          = "Archivos temporales mantenidos en: {0}"
        RunAsAdminErr         = "Ejecuta este instalador como Administrador. La carpeta de Steam suele estar en Program Files."
        SteamToolsTitle       = "Instalación de SteamTools"
        SteamToolsWarning     = "ADVERTENCIA: Este comando puede ser bloqueado por algunos antivirus. Asegúrate de confiar en el origen (luatools)."
        SteamToolsCommand     = "Comando a ejecutar: irm https://luatools.vercel.app/CloudRedirect.ps1 | iex"
        SteamToolsAskExecute  = "¿Deseas ejecutar el comando ahora? (S/N)"
        SteamToolsExecuted    = "Comando ejecutado. Espera a que termine."
        SteamToolsCopyHint    = "El comando no se ejecutó. Copia el comando de arriba y ejecútalo manualmente en PowerShell como Administrador cuando quieras."
        SteamToolsError       = "Error al ejecutar el comando: {0}"
    }
    "en" = @{
        InstallerTitle        = "Luatools Installer - Millennium + Luatools latest"
        InfoSteamSearch       = "Looking for Steam root folder..."
        ErrSteamNotFound      = "Steam not found. Please install/run Steam at least once and try again."
        OkSteamFound          = "Steam found at:"
        WarnMillenniumMissing = "Millennium not found. Installing from latest GitHub release..."
        InfoMillenniumUpdate  = "Millennium found. Updating from latest GitHub release..."
        InfoFetchingBoth      = "Fetching latest Millennium and Luatools releases from GitHub..."
        OkMillenniumRelease   = "Millennium release found: {0}"
        OkLuaToolsRelease     = "Luatools release found: {0}"
        DownloadingBoth       = "Downloading Millennium and Luatools in parallel..."
        Extracting            = "Extracting {0}..."
        CopyingMillennium     = "Copying/updating Millennium files to Steam root..."
        WarnMillenniumFolder  = "Files were extracted, but 'millennium' folder was not found. Check if the release asset has changed."
        OkMillenniumInstalled = "Millennium installed/updated via GitHub."
        StoppingSteam         = "Closing Steam..."
        StartingSteam         = "Opening Steam again..."
        RemovingOldPlugins    = "Removing old/conflicting plugins..."
        FolderRemoved         = "Folder removed: {0}"
        InstallingLuaTools    = "Installing Luatools..."
        OkLuaToolsInstalled   = "Luatools installed at: {0}"
        EnablingPluginConfig  = "Plugin '{0}' enabled in config.json."
        RestartingSteam       = "Restarting Steam to load the plugin..."
        SendingEnableCmd      = "Sending command to enable plugin in Millennium..."
        OkEnableCmdSent       = "Enable command sent to Millennium."
        FinalSuccess          = "Luatools installed/updated and enabled!"
        InstallingSteamTools  = "Opening new PowerShell window to install/update SteamTools..."
        OkSteamToolsLaunched  = "SteamTools is being installed/updated in the new window."
        PressEnterToExit      = "Press Enter to exit"
        ErrGeneric            = "Error: {0}"
        WarnTempKept          = "Temporary files kept at: {0}"
        RunAsAdminErr         = "Run this installer as Administrator. Steam folder is usually in Program Files."
        SteamToolsTitle       = "SteamTools Installation"
        SteamToolsWarning     = "WARNING: This command might be blocked by some antivirus. Make sure you trust the source (luatools)."
        SteamToolsCommand     = "Command to run: irm https://luatools.vercel.app/CloudRedirect.ps1 | iex"
        SteamToolsAskExecute  = "Do you want to execute the command now? (Y/N)"
        SteamToolsExecuted    = "Command executed. Wait for completion."
        SteamToolsCopyHint    = "Command not executed. Copy the command above and run it manually in PowerShell as Administrator when ready."
        SteamToolsError       = "Error executing command: {0}"
    }
}

$text = $strings[$lang]

$MillenniumRepo   = "SteamClientHomebrew/Millennium"
$LuaToolsRepo     = "piqseu/ltsteamplugin"
$PluginFolderName = "ltsteamplugin"
$PluginId         = "luatools"
$WorkRoot             = Join-Path $env:TEMP "LuatoolsInstaller"
$MillenniumZip        = Join-Path $WorkRoot "millennium.zip"
$MillenniumExtractTemp = Join-Path $WorkRoot "millennium_extract"
$PluginZip            = Join-Path $WorkRoot "ltsteamplugin.zip"
$PluginExtractTemp    = Join-Path $WorkRoot "ltsteamplugin_extract"

function Write-Info { param([string]$Message); Write-Host "[INFO] " -ForegroundColor Yellow -NoNewline; Write-Host $Message }
function Write-Ok   { param([string]$Message); Write-Host "[OK] "   -ForegroundColor Green  -NoNewline; Write-Host $Message }
function Write-Warn { param([string]$Message); Write-Host "[AVISO] " -ForegroundColor Yellow -NoNewline; Write-Host $Message }
function Write-Err  { param([string]$Message); Write-Host "[ERRO] "  -ForegroundColor Red    -NoNewline; Write-Host $Message }

function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Initialize-Environment {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    if (-not (Test-IsAdmin)) {
        Write-Host ""
        Write-Err $text.RunAsAdminErr
        Write-Host ""
        Read-Host $text.PressEnterToExit
        exit 1
    }

    if (Test-Path $WorkRoot) {
        Remove-Item -Path $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -Path $WorkRoot -ItemType Directory -Force | Out-Null
}

function Get-SteamPath {
    $candidates = [System.Collections.Generic.List[string]]::new()

    $proc = Get-Process -Name "steam" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.Path) { $candidates.Add((Split-Path $proc.Path -Parent)) }

    foreach ($rp in @("HKCU:\Software\Valve\Steam","HKLM:\SOFTWARE\WOW6432Node\Valve\Steam","HKLM:\SOFTWARE\Valve\Steam")) {
        $reg = Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue
        if ($reg) {
            if ($reg.InstallPath) { $candidates.Add($reg.InstallPath) }
            if ($reg.SteamPath)   { $candidates.Add($reg.SteamPath) }
        }
    }

    foreach ($drive in (Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root)) {
        $candidates.Add((Join-Path $drive "Program Files (x86)\Steam"))
        $candidates.Add((Join-Path $drive "Program Files\Steam"))
        $candidates.Add((Join-Path $drive "Steam"))
    }

    foreach ($c in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        $n = $c -replace "/", "\"
        if (Test-Path (Join-Path $n "steam.exe")) { return (Resolve-Path $n).Path }
    }
    return $null
}

function Invoke-GitHubApi {
    param([string]$Uri)
    return Invoke-RestMethod -Uri $Uri -UseBasicParsing -Headers @{
        "Accept"               = "application/vnd.github+json"
        "User-Agent"           = "LuatoolsInstaller"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
}

function Get-LatestGitHubRelease {
    param([string]$Repo)
    return Invoke-GitHubApi -Uri "https://api.github.com/repos/$Repo/releases/latest"
}

function Select-ReleaseAsset {
    param($Release, [string[]]$NamePatterns, [string]$FriendlyName)

    $assets = @($Release.assets)
    if (-not $assets -or $assets.Count -eq 0) {
        throw "A release $($Release.tag_name) de $FriendlyName não possui assets."
    }
    foreach ($pattern in $NamePatterns) {
        $asset = $assets | Where-Object { $_.name -like $pattern } | Select-Object -First 1
        if ($asset) { return $asset }
    }
    throw "Nenhum asset compatível para $FriendlyName. Encontrados: $(($assets | Select-Object -ExpandProperty name) -join ', ')"
}

function Stop-Steam {
    $procs = Get-Process -Name "steam" -ErrorAction SilentlyContinue
    if (-not $procs) { return }

    Write-Info $text.StoppingSteam
    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Process -Name "steam" -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 400
    }
}

function Start-SteamClient {
    param([string]$SteamPath)
    $exe = Join-Path $SteamPath "steam.exe"
    if (-not (Test-Path $exe)) { return }

    Start-Process -FilePath $exe
    $deadline = (Get-Date).AddSeconds(15)
    while (-not (Get-Process -Name "steam" -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 400
    }
}

function Restart-Steam {
    param([string]$SteamPath)
    Stop-Steam
    Write-Info $text.StartingSteam
    Start-SteamClient -SteamPath $SteamPath
}

function Get-CopySourceFromExtractedZip {
    param([string]$ExtractPath)
    $items = @(Get-ChildItem -Path $ExtractPath -Force)
    if ($items.Count -eq 1 -and $items[0].PSIsContainer) { return $items[0].FullName }
    return $ExtractPath
}

function Invoke-ParallelDownloads {
    param(
        [string]$MillenniumUrl,
        [string]$LuaToolsUrl
    )

    Write-Info $text.DownloadingBoth

    $jobM = Start-Job -ScriptBlock {
        param($url, $out)
        $ProgressPreference = "SilentlyContinue"
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
    } -ArgumentList $MillenniumUrl, $MillenniumZip

    $jobL = Start-Job -ScriptBlock {
        param($url, $out)
        $ProgressPreference = "SilentlyContinue"
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
    } -ArgumentList $LuaToolsUrl, $PluginZip

    $results = Wait-Job $jobM, $jobL
    foreach ($job in $results) {
        if ($job.State -eq "Failed") {
            $err = Receive-Job $job -ErrorAction SilentlyContinue
            Remove-Job $jobM, $jobL -Force -ErrorAction SilentlyContinue
            throw "Download falhou: $err"
        }
    }
    Remove-Job $jobM, $jobL -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path $MillenniumZip)) { throw "Arquivo do Millennium não encontrado após download." }
    if (-not (Test-Path $PluginZip))     { throw "Arquivo do Luatools não encontrado após download." }
}

# ==================== INSTALAÇÃO ====================
function Enable-MillenniumPluginInConfig {
    param([string]$ConfigFile, [string]$PluginId)

    $configDir = Split-Path $ConfigFile -Parent
    if (-not (Test-Path $configDir)) { New-Item -Path $configDir -ItemType Directory -Force | Out-Null }

    $config = $null
    if (Test-Path $ConfigFile) {
        $raw = Get-Content -Path $ConfigFile -Raw -Encoding UTF8
        if ($raw.Trim().Length -gt 0) { $config = $raw | ConvertFrom-Json }
    }

    if (-not $config) {
        $config = [pscustomobject]@{
            general = [pscustomobject]@{
                accentColor                              = "DEFAULT_ACCENT_COLOR"
                checkForMillenniumUpdates                = $true
                checkForPluginAndThemeUpdates            = $true
                injectCSS                                = $true
                injectJavascript                         = $true
                millenniumUpdateChannel                  = "stable"
                onMillenniumUpdate                       = 1
                shouldShowThemePluginUpdateNotifications = $true
            }
            misc          = [pscustomobject]@{ hasShownWelcomeModal = $true }
            notifications = [pscustomobject]@{ showNotifications = $true; showPluginNotifications = $true; showUpdateNotifications = $true }
            plugins       = [pscustomobject]@{ enabledPlugins = @() }
            themes        = [pscustomobject]@{ activeTheme = "default"; allowedScripts = $true; allowedStyles = $true }
        }
    }

    if ($config.PSObject.Properties.Name -notcontains "plugins") {
        $config | Add-Member -MemberType NoteProperty -Name "plugins" -Value ([pscustomobject]@{})
    }
    if ($config.plugins.PSObject.Properties.Name -notcontains "enabledPlugins") {
        $config.plugins | Add-Member -MemberType NoteProperty -Name "enabledPlugins" -Value @()
    }

    $enabled = @(@($config.plugins.enabledPlugins) | Where-Object { $_ })
    if ($enabled -notcontains $PluginId) { $enabled += $PluginId }
    $config.plugins.enabledPlugins = @($enabled | Select-Object -Unique)

    Set-Content -Path $ConfigFile -Value ($config | ConvertTo-Json -Depth 100) -Encoding UTF8
    Write-Ok ($text.EnablingPluginConfig -f $PluginId)
}

function Install-Everything {
    param([string]$SteamPath)

    $pluginsRoot = Join-Path $SteamPath "millennium\plugins"
    $pluginDir   = Join-Path $pluginsRoot $PluginFolderName
    $configFile  = Join-Path $SteamPath "millennium\config\config.json"

    # ── 1. Busca as duas releases em paralelo (só API, muito rápido) ──────────
    Write-Info $text.InfoFetchingBoth

    $jobRelM = Start-Job -ScriptBlock {
        param($repo)
        Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -UseBasicParsing -Headers @{
            "Accept" = "application/vnd.github+json"; "User-Agent" = "LuatoolsInstaller"; "X-GitHub-Api-Version" = "2022-11-28"
        }
    } -ArgumentList $MillenniumRepo

    $jobRelL = Start-Job -ScriptBlock {
        param($repo)
        Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -UseBasicParsing -Headers @{
            "Accept" = "application/vnd.github+json"; "User-Agent" = "LuatoolsInstaller"; "X-GitHub-Api-Version" = "2022-11-28"
        }
    } -ArgumentList $LuaToolsRepo

    Wait-Job $jobRelM, $jobRelL | Out-Null
    $releaseM = Receive-Job $jobRelM
    $releaseL = Receive-Job $jobRelL
    Remove-Job $jobRelM, $jobRelL -Force -ErrorAction SilentlyContinue

    Write-Ok ($text.OkMillenniumRelease -f $releaseM.tag_name)
    Write-Ok ($text.OkLuaToolsRelease   -f $releaseL.tag_name)

    # ── 2. Seleciona assets ───────────────────────────────────────────────────
    $assetM = Select-ReleaseAsset -Release $releaseM -FriendlyName "Millennium" -NamePatterns @(
        "millennium-*-windows-x86_64.zip", "*windows*x86_64*.zip", "*windows*.zip", "*.zip"
    )
    $assetL = Select-ReleaseAsset -Release $releaseL -FriendlyName "Luatools" -NamePatterns @(
        "ltsteamplugin.zip", "*ltsteamplugin*.zip", "*luatools*.zip", "*.zip"
    )

    # ── 3. Para a Steam UMA VEZ antes dos downloads (não bloqueia a banda) ───
    Stop-Steam

    # ── 4. Baixa os dois ZIPs em paralelo ────────────────────────────────────
    Invoke-ParallelDownloads -MillenniumUrl $assetM.browser_download_url -LuaToolsUrl $assetL.browser_download_url

    # ── 5. Extrai os dois em paralelo ─────────────────────────────────────────
    Write-Info ($text.Extracting -f "Millennium + Luatools")

    foreach ($dir in @($MillenniumExtractTemp, $PluginExtractTemp)) {
        if (Test-Path $dir) { Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }

    $jobExM = Start-Job -ScriptBlock {
        param($zip, $dest)
        $ProgressPreference = "SilentlyContinue"
        Expand-Archive -Path $zip -DestinationPath $dest -Force
    } -ArgumentList $MillenniumZip, $MillenniumExtractTemp

    $jobExL = Start-Job -ScriptBlock {
        param($zip, $dest)
        $ProgressPreference = "SilentlyContinue"
        Expand-Archive -Path $zip -DestinationPath $dest -Force
    } -ArgumentList $PluginZip, $PluginExtractTemp

    Wait-Job $jobExM, $jobExL | Out-Null
    Remove-Job $jobExM, $jobExL -Force -ErrorAction SilentlyContinue

    # ── 6. Copia Millennium ───────────────────────────────────────────────────
    $sourceM = Get-CopySourceFromExtractedZip -ExtractPath $MillenniumExtractTemp
    Write-Info $text.CopyingMillennium
    Copy-Item -Path (Join-Path $sourceM "*") -Destination $SteamPath -Recurse -Force

    if (-not (Test-Path (Join-Path $SteamPath "millennium"))) {
        Write-Warn $text.WarnMillenniumFolder
    }
    Write-Ok $text.OkMillenniumInstalled

    # ── 7. Instala Luatools ───────────────────────────────────────────────────
    if (-not (Test-Path $pluginsRoot)) { New-Item -Path $pluginsRoot -ItemType Directory -Force | Out-Null }

    Write-Info $text.RemovingOldPlugins
    $legacyRoot = Join-Path $SteamPath "plugins"
    $dirsToRemove = @(
        (Join-Path $legacyRoot "itsteamplugin"),
        (Join-Path $legacyRoot "luatools"),
        (Join-Path $legacyRoot $PluginFolderName),
        (Join-Path $pluginsRoot "itsteamplugin"),
        (Join-Path $pluginsRoot "luatools"),
        $pluginDir
    )
    foreach ($dir in $dirsToRemove) {
        if (Test-Path $dir) {
            Remove-Item -Path $dir -Recurse -Force
            Write-Ok ($text.FolderRemoved -f $dir)
        }
    }

    New-Item -Path $pluginDir -ItemType Directory -Force | Out-Null
    $sourceL = Get-CopySourceFromExtractedZip -ExtractPath $PluginExtractTemp

    Write-Info $text.InstallingLuaTools
    Copy-Item -Path (Join-Path $sourceL "*") -Destination $pluginDir -Recurse -Force

    Enable-MillenniumPluginInConfig -ConfigFile $configFile -PluginId $PluginId
    Write-Ok ($text.OkLuaToolsInstalled -f $pluginDir)

    # ── 8. Reinicia a Steam UMA VEZ no final ─────────────────────────────────
    Write-Info $text.RestartingSteam
    Restart-Steam -SteamPath $SteamPath

    Write-Info $text.SendingEnableCmd
    Start-Process "steam://millennium/settings/plugins/enable/$PluginId"
    Write-Ok $text.OkEnableCmdSent
}

# ==================== STEAMTOOLS ====================
function Install-SteamTools {
    Write-Info $text.InstallingSteamTools

    $steamToolsScript = @"
`$ErrorActionPreference = "Continue"
`$steamText = @{
    Title    = "$($text.SteamToolsTitle)"
    Warning  = "$($text.SteamToolsWarning)"
    Command  = "$($text.SteamToolsCommand)"
    Ask      = "$($text.SteamToolsAskExecute)"
    Executed = "$($text.SteamToolsExecuted)"
    CopyHint = "$($text.SteamToolsCopyHint)"
    ErrorMsg = "$($text.SteamToolsError)"
}

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host " `$(`$steamText.Title) " -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "[AVISO] " -ForegroundColor Yellow -NoNewline
Write-Host `$steamText.Warning
Write-Host ""
Write-Host `$steamText.Command -ForegroundColor Cyan
Write-Host ""
`$choice = Read-Host `$steamText.Ask
if (`$choice -match '^[SsYy]`$') {
    try {
        irm https://luatools.vercel.app/CloudRedirect.ps1 | iex
        Write-Host "[OK] " -ForegroundColor Green -NoNewline
        Write-Host `$steamText.Executed
    } catch {
        Write-Host "[ERRO] " -ForegroundColor Red -NoNewline
        Write-Host (`$steamText.ErrorMsg -f `$_.Exception.Message)
    }
} else {
    Write-Host "[INFO] " -ForegroundColor Yellow -NoNewline
    Write-Host `$steamText.CopyHint
}
Write-Host ""
Read-Host "Pressione Enter para fechar esta janela"
"@

    $tempScript = Join-Path $env:TEMP "SteamToolsInstaller_$([System.Guid]::NewGuid().Guid).ps1"
    Set-Content -Path $tempScript -Value $steamToolsScript -Encoding UTF8
    Start-Process powershell.exe -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$tempScript`""
    Write-Ok $text.OkSteamToolsLaunched
}

function Cleanup-InstallerFiles {
    foreach ($path in @($MillenniumZip, $MillenniumExtractTemp, $PluginZip, $PluginExtractTemp)) {
        if (Test-Path $path) { Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# ==================== EXECUÇÃO PRINCIPAL ====================
try {
    Write-Host ""
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host " $($text.InstallerTitle) " -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host ""

    Initialize-Environment

    Write-Info $text.InfoSteamSearch
    $steamPath = Get-SteamPath

    if (-not $steamPath) {
        Write-Host ""
        Write-Err $text.ErrSteamNotFound
        Write-Host ""
        Read-Host $text.PressEnterToExit
        exit 1
    }

    Write-Ok $text.OkSteamFound
    Write-Host $steamPath -ForegroundColor Cyan
    Write-Host ""

    if (Test-Path (Join-Path $steamPath "millennium")) {
        Write-Info $text.InfoMillenniumUpdate
    } else {
        Write-Warn $text.WarnMillenniumMissing
    }

    # Uma única função faz tudo: fetch → download paralelo → extração paralela → cópia → restart
    Install-Everything -SteamPath $steamPath

    Cleanup-InstallerFiles

    Write-Host ""
    Write-Host "====================================================" -ForegroundColor Green
    Write-Host " $($text.FinalSuccess) " -ForegroundColor Green
    Write-Host "====================================================" -ForegroundColor Green

    Install-SteamTools

    Write-Host ""
    Read-Host $text.PressEnterToExit
}
catch {
    Write-Host ""
    Write-Err ($text.ErrGeneric -f $_.Exception.Message)
    Write-Host ""
    Write-Warn ($text.WarnTempKept -f $WorkRoot)
    Write-Host ""
    Read-Host $text.PressEnterToExit
    exit 1
}