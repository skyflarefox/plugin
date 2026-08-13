[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('Plugin', 'PluginDlls', 'Completo')]
    [string]$Modo,

    [string]$SteamPath,

    [ValidateSet('auto', 'en', 'pt-BR', 'es', 'ru')]
    [string]$Idioma = 'auto'
)

$ErrorActionPreference = 'Stop'
try {
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
} catch {
}

$translations = @{
    'en' = @{
        title = 'SkyTools and Millennium Uninstaller'
        menu1 = '1 - Uninstall only SkyTools Plugin for Millennium.'
        menu2 = '2 - Uninstall SkyTools Plugin + SkyTools DLLs from Millennium.'
        menu3 = '3 - Uninstall Millennium, SkyTools and DLLs, including all plugins and themes.'
        choose = 'Choose 1, 2 or 3'
        invalid = 'Invalid option.'
        steamNotFound = 'Steam folder was not found. Use -SteamPath "C:\path\Steam".'
        unsafePath = 'Path refused for safety: {0}'
        skipped = 'SKIPPED: {0} does not exist.'
        removed = 'REMOVED: {0}'
        closingSteam = 'Closing Steam...'
        steamFound = 'Steam found at: {0}'
        confirmPlugin = 'Close Steam and remove only the old SkyTools Plugin'
        confirmPluginDlls = 'Close Steam and remove SkyTools Plugin and SkyTools DLLs'
        confirmComplete = 'Close Steam and completely remove Millennium, SkyTools, all plugins and themes'
        pluginWarning = 'Only SkyTools Plugin will be removed. Millennium, its other plugins, themes and DLLs will be preserved.'
        pluginDllsWarning = 'SkyTools Plugin and SkyTools DLLs will be removed. Millennium, its other plugins and themes will be preserved.'
        completeWarning = 'Millennium, SkyTools, integration DLLs, all Millennium plugins and themes will be removed.'
        luaPreserved = 'The config\stplug-in folder and its Lua files will be preserved.'
        pluginDone = 'SkyTools Plugin was removed. Millennium and the DLLs were preserved.'
        pluginDllsDone = 'SkyTools Plugin and SkyTools DLLs were removed. Millennium, other plugins and themes were preserved.'
        completeDone = 'Complete removal finished.'
        steamNotReopened = 'Steam was not reopened automatically.'
    }
    'pt-BR' = @{
        title = 'Desinstalador do SkyTools e Millennium'
        menu1 = '1 - Desinstalar somente o Plugin do SkyTools para Millennium.'
        menu2 = '2 - Desinstalar o Plugin do SkyTools + DLLs do SkyTools do Millennium.'
        menu3 = '3 - Desinstalar o Millennium, SkyTools, DLLs incluindo todos os Plugins e Temas.'
        choose = 'Escolha 1, 2 ou 3'
        invalid = 'Opção inválida.'
        steamNotFound = 'A pasta da Steam não foi encontrada. Use -SteamPath "C:\caminho\Steam".'
        unsafePath = 'Caminho recusado por segurança: {0}'
        skipped = 'IGNORADO: {0} não existe.'
        removed = 'REMOVIDO: {0}'
        closingSteam = 'Fechando a Steam...'
        steamFound = 'Steam encontrada em: {0}'
        confirmPlugin = 'Fechar a Steam e remover somente o Plugin antigo do SkyTools'
        confirmPluginDlls = 'Fechar a Steam e remover o Plugin e as DLLs do SkyTools'
        confirmComplete = 'Fechar a Steam e remover completamente Millennium, SkyTools, todos os plugins e temas'
        pluginWarning = 'Somente o Plugin do SkyTools será removido. O Millennium, outros plugins, temas e DLLs serão preservados.'
        pluginDllsWarning = 'O Plugin e as DLLs do SkyTools serão removidos. O Millennium, outros plugins e temas serão preservados.'
        completeWarning = 'Millennium, SkyTools, DLLs de integração, todos os plugins e temas do Millennium serão removidos.'
        luaPreserved = 'A pasta config\stplug-in e seus arquivos Lua serão preservados.'
        pluginDone = 'O Plugin do SkyTools foi removido. O Millennium e as DLLs foram preservados.'
        pluginDllsDone = 'O Plugin e as DLLs do SkyTools foram removidos. Millennium, outros plugins e temas foram preservados.'
        completeDone = 'Remoção completa concluída.'
        steamNotReopened = 'A Steam não foi reaberta automaticamente.'
    }
    'es' = @{
        title = 'Desinstalador de SkyTools y Millennium'
        menu1 = '1 - Desinstalar solamente el Plugin de SkyTools para Millennium.'
        menu2 = '2 - Desinstalar el Plugin de SkyTools + las DLL de SkyTools de Millennium.'
        menu3 = '3 - Desinstalar Millennium, SkyTools y las DLL, incluidos todos los plugins y temas.'
        choose = 'Elige 1, 2 o 3'
        invalid = 'Opción no válida.'
        steamNotFound = 'No se encontró la carpeta de Steam. Usa -SteamPath "C:\ruta\Steam".'
        unsafePath = 'Ruta rechazada por seguridad: {0}'
        skipped = 'OMITIDO: {0} no existe.'
        removed = 'ELIMINADO: {0}'
        closingSteam = 'Cerrando Steam...'
        steamFound = 'Steam encontrado en: {0}'
        confirmPlugin = 'Cerrar Steam y eliminar solamente el Plugin antiguo de SkyTools'
        confirmPluginDlls = 'Cerrar Steam y eliminar el Plugin y las DLL de SkyTools'
        confirmComplete = 'Cerrar Steam y eliminar completamente Millennium, SkyTools, todos los plugins y temas'
        pluginWarning = 'Solo se eliminará el Plugin de SkyTools. Millennium, los demás plugins, temas y DLL se conservarán.'
        pluginDllsWarning = 'Se eliminarán el Plugin y las DLL de SkyTools. Millennium, los demás plugins y temas se conservarán.'
        completeWarning = 'Se eliminarán Millennium, SkyTools, las DLL de integración y todos los plugins y temas de Millennium.'
        luaPreserved = 'La carpeta config\stplug-in y sus archivos Lua se conservarán.'
        pluginDone = 'El Plugin de SkyTools fue eliminado. Millennium y las DLL se conservaron.'
        pluginDllsDone = 'El Plugin y las DLL de SkyTools fueron eliminados. Millennium, los demás plugins y temas se conservaron.'
        completeDone = 'Desinstalación completa finalizada.'
        steamNotReopened = 'Steam no se abrió nuevamente de forma automática.'
    }
    'ru' = @{
        title = 'Удаление SkyTools и Millennium'
        menu1 = '1 - Удалить только плагин SkyTools для Millennium.'
        menu2 = '2 - Удалить плагин SkyTools и библиотеки DLL SkyTools из Millennium.'
        menu3 = '3 - Удалить Millennium, SkyTools, библиотеки DLL, а также все плагины и темы.'
        choose = 'Выберите 1, 2 или 3'
        invalid = 'Недопустимый вариант.'
        steamNotFound = 'Папка Steam не найдена. Используйте -SteamPath "C:\путь\Steam".'
        unsafePath = 'Путь отклонен из соображений безопасности: {0}'
        skipped = 'ПРОПУЩЕНО: {0} не существует.'
        removed = 'УДАЛЕНО: {0}'
        closingSteam = 'Закрытие Steam...'
        steamFound = 'Steam найден здесь: {0}'
        confirmPlugin = 'Закрыть Steam и удалить только старый плагин SkyTools'
        confirmPluginDlls = 'Закрыть Steam и удалить плагин и библиотеки DLL SkyTools'
        confirmComplete = 'Закрыть Steam и полностью удалить Millennium, SkyTools, все плагины и темы'
        pluginWarning = 'Будет удален только плагин SkyTools. Millennium, другие плагины, темы и библиотеки DLL будут сохранены.'
        pluginDllsWarning = 'Будут удалены плагин и библиотеки DLL SkyTools. Millennium, другие плагины и темы будут сохранены.'
        completeWarning = 'Будут удалены Millennium, SkyTools, интеграционные библиотеки DLL, а также все плагины и темы Millennium.'
        luaPreserved = 'Папка config\stplug-in и находящиеся в ней файлы Lua будут сохранены.'
        pluginDone = 'Плагин SkyTools удален. Millennium и библиотеки DLL сохранены.'
        pluginDllsDone = 'Плагин и библиотеки DLL SkyTools удалены. Millennium, другие плагины и темы сохранены.'
        completeDone = 'Полное удаление завершено.'
        steamNotReopened = 'Steam не был запущен повторно автоматически.'
    }
}

if ($Idioma -eq 'auto') {
    $culture = [Globalization.CultureInfo]::CurrentUICulture.Name
    $Idioma = switch -Regex ($culture) {
        '^pt(?:-|$)' { 'pt-BR'; break }
        '^es(?:-|$)' { 'es'; break }
        '^ru(?:-|$)' { 'ru'; break }
        default { 'en' }
    }
}
$script:Text = $translations[$Idioma]
if (-not $script:Text) {
    $script:Text = $translations['en']
}

function T {
    param([string]$Key)

    $value = $script:Text[$Key]
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $translations['en'][$Key]
    }
    return $value
}

function Get-SteamPath {
    param([string]$ConfiguredPath)

    $candidates = @($ConfiguredPath)
    foreach ($entry in @(
        @{ Path = 'HKCU:\Software\Valve\Steam'; Name = 'SteamPath' },
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam'; Name = 'InstallPath' },
        @{ Path = 'HKLM:\SOFTWARE\Valve\Steam'; Name = 'InstallPath' }
    )) {
        try {
            $value = (Get-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -ErrorAction Stop).($entry.Name)
            if ($value) {
                $candidates += $value
            }
        } catch {
        }
    }

    if (${env:ProgramFiles(x86)}) {
        $candidates += Join-Path ${env:ProgramFiles(x86)} 'Steam'
    }
    if ($env:ProgramFiles) {
        $candidates += Join-Path $env:ProgramFiles 'Steam'
    }

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        try {
            $resolved = [IO.Path]::GetFullPath($candidate)
            if (Test-Path -LiteralPath (Join-Path $resolved 'steam.exe') -PathType Leaf) {
                return $resolved.TrimEnd([IO.Path]::DirectorySeparatorChar)
            }
        } catch {
        }
    }

    throw (T 'steamNotFound')
}

function Assert-InsideSteam {
    param(
        [string]$Root,
        [string]$Candidate
    )

    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $candidatePath = [IO.Path]::GetFullPath($Candidate)
    if (-not $candidatePath.StartsWith(
        $rootPath + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
        throw ((T 'unsafePath') -f $candidatePath)
    }

    return $candidatePath
}

function Remove-SteamItem {
    param(
        [string]$Root,
        [string]$RelativePath
    )

    $target = Assert-InsideSteam -Root $Root -Candidate (Join-Path $Root $RelativePath)
    if (-not (Test-Path -LiteralPath $target)) {
        Write-Host ((T 'skipped') -f $RelativePath) -ForegroundColor DarkGray
        return
    }

    Remove-Item -LiteralPath $target -Recurse -Force
    Write-Host ((T 'removed') -f $RelativePath) -ForegroundColor Green
}

function Stop-SteamClient {
    param([string]$Root)

    if (-not (Get-Process -Name steam -ErrorAction SilentlyContinue)) {
        return
    }

    Write-Host (T 'closingSteam') -ForegroundColor Yellow
    Start-Process -FilePath (Join-Path $Root 'steam.exe') -ArgumentList '-shutdown' -WindowStyle Hidden
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while ((Get-Process -Name steam -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }

    Get-Process -Name steam, steamwebhelper -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

$pluginItems = @(
    'millennium\plugins\SkyTools.Plugin',
    'millennium\plugins\skytools-plugin',
    'plugins\SkyTools.Plugin',
    'plugins\skytools-plugin'
)

$skyToolsItems = @(
    '.dolintools-skytools',
    'dwmapi.dll',
    'xinput1_4.dll',
    'OpenSteamTool.dll',
    'opensteamtool.toml',
    'opensteamtool'
)

$millenniumItems = @(
    'ext',
    'millennium',
    'millennium-migration-temp',
    'plugins',
    'millennium-updater-temp-files',
    'millennium.dll',
    'millennium.hhx64.dll',
    'python311.dll',
    'user32.dll',
    'version.dll',
    'wsock32.dll',
    'steamui\skins'
)

if (-not $Modo) {
    Write-Host ''
    Write-Host (T 'title') -ForegroundColor Cyan
    Write-Host ('=' * (T 'title').Length) -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host (T 'menu1')
    Write-Host (T 'menu2')
    Write-Host (T 'menu3')
    Write-Host ''
    $choice = Read-Host (T 'choose')
    $Modo = switch ($choice) {
        '1' { 'Plugin' }
        '2' { 'PluginDlls' }
        '3' { 'Completo' }
        default { throw (T 'invalid') }
    }
}

$steam = Get-SteamPath -ConfiguredPath $SteamPath
Write-Host ((T 'steamFound') -f $steam) -ForegroundColor Cyan
Write-Host ''

$items = @()
$confirmation = ''
$completion = ''
switch ($Modo) {
    'Plugin' {
        Write-Host (T 'pluginWarning') -ForegroundColor Yellow
        $items = $pluginItems
        $confirmation = T 'confirmPlugin'
        $completion = T 'pluginDone'
    }
    'PluginDlls' {
        Write-Host (T 'pluginDllsWarning') -ForegroundColor Yellow
        Write-Host (T 'luaPreserved') -ForegroundColor Yellow
        $items = @($pluginItems) + @($skyToolsItems)
        $confirmation = T 'confirmPluginDlls'
        $completion = T 'pluginDllsDone'
    }
    'Completo' {
        Write-Host (T 'completeWarning') -ForegroundColor Yellow
        Write-Host (T 'luaPreserved') -ForegroundColor Yellow
        $items = @($pluginItems) + @($skyToolsItems) + @($millenniumItems)
        $confirmation = T 'confirmComplete'
        $completion = T 'completeDone'
    }
}

if (-not $PSCmdlet.ShouldProcess($steam, $confirmation)) {
    return
}

Stop-SteamClient -Root $steam
foreach ($item in $items | Select-Object -Unique) {
    Remove-SteamItem -Root $steam -RelativePath $item
}

Write-Host ''
Write-Host $completion -ForegroundColor Green
Write-Host (T 'steamNotReopened') -ForegroundColor Cyan
