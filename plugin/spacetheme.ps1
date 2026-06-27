$steamPath = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue).SteamPath
if (-not $steamPath -or -not (Test-Path $steamPath)) {
    Write-Host "Steam not found." -ForegroundColor Red
    exit 1
}

$skinDir = "$steamPath\millennium\themes\Steam"
if (-not (Test-Path $skinDir)) {
    Write-Host "Spacetheme was not found. Exiting." -ForegroundColor Red
    pause
    exit 1
}

Write-Host "Closing all Steam processes..." -ForegroundColor Yellow

Get-Process -Name "steam" -ErrorAction SilentlyContinue | ForEach-Object { $_.CloseMainWindow() | Out-Null }
Start-Sleep -Seconds 1

Get-Process -Name "steam", "steamwebhelper", "steamerrorreporter" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

Stop-Service "Steam Client Service" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

Get-Process -Name "steam", "steamwebhelper", "steamservice", "steamerrorreporter" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# ============================================================================
# ROTINA CORRIGIDA: INJEÇÃO LIMPA SEM CARACTERES DE SINTAXE INVÁLIDOS
# ============================================================================
Write-Host "Checking icon patches for webkit.js..." -ForegroundColor Yellow

$webkitPath = "$skinDir\src\js\webkit.js"

# Bloco modificado: comentários em JS válidos (//) e sem usar a palavra banida para evitar autossabotagem
$iconsContent = @'
(function() {
    "use strict";
    
    if (!document.querySelector('link[href*="font-awesome"]')) {
        const link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = 'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css';
        link.crossOrigin = 'anonymous';
        document.head.appendChild(link);
    }

    if (!document.getElementById('lt-theme-webkit-fix')) {
        const style = document.createElement('style');
        style.id = 'lt-theme-webkit-fix';
        style.textContent = `
            html body [class*="overlay"] i,
            html body [class*="-button"] i,
            html body [class*="-btn"] i,
            html body [class*="overlay"] i,
            html body i.fa-discord,
            html body i.fab,
            html body i.fa-brands {
                font-style: normal !important;
                display: inline-block !important;
                text-transform: none !important;
                speak: never !important;
                -webkit-font-smoothing: antialiased !important;
                -moz-osx-font-smoothing: grayscale !important;
                visibility: visible !important;
                opacity: 1 !important;
                color: inherit !important;
            }

            html body [class*="overlay"] i,
            html body [class*="-button"] i,
            html body [class*="-btn"] i {
                font-family: 'Font Awesome 6 Free' !important;
                font-weight: 900 !important;
            }

            html body i.fa-discord,
            html body i.fab,
            html body i.fa-brands,
            html body [class*="overlay"] i[class*="discord"],
            html body [class*="-btn"] i[class*="discord"] {
                font-family: 'Font Awesome 6 Brands' !important;
                font-weight: 400 !important;
            }
        `;
        document.head.appendChild(style);
    }
})();
'@

if (Test-Path $webkitPath) {
    try {
        $webkitContent = Get-Content $webkitPath -Raw -ErrorAction Stop

        # Carrega as linhas de forma limpa para remontagem
        $lines = Get-Content $webkitPath
        $lastImportIndex = -1
        $alreadyHasFix = $false

        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "^\s*import\s+") {
                $lastImportIndex = $i
            }
            if ($lines[$i] -match "lt-theme-webkit-fix") {
                $alreadyHasFix = $true
            }
        }

        if ($alreadyHasFix) {
            Write-Host "Icon patch is already verified. Skipping injection." -ForegroundColor Cyan
        } else {
            # Remonta o arquivo inserindo o bloco na posição correta pós-imports
            if ($lastImportIndex -ne -1) {
                $newLines = @()
                for ($i = 0; $i -le $lastImportIndex; $i++) { $newLines += $lines[$i] }
                $newLines += "`r`n" + $iconsContent + "`r`n"
                for ($i = $lastImportIndex + 1; $i -lt $lines.Count; $i++) { $newLines += $lines[$i] }
                $finalContent = $newLines -join "`r`n"
            } else {
                $finalContent = $iconsContent + "`r`n`r`n" + $webkitContent
            }

            Set-Content $webkitPath -Value $finalContent -NoNewline -Encoding UTF8 -ErrorAction Stop
            Write-Host "Successfully injected clean Icons patch right after imports!" -ForegroundColor Green
        }
    } catch {
        Write-Host "Failed to apply icon patch to webkit.js: $_" -ForegroundColor Red
    }
} else {
    Write-Host "webkit.js target not found in theme assets. Skipping icon patch." -ForegroundColor DarkGray
}
# ============================================================================

Write-Host ""
Write-Host "Scanning skin folder for luatools occurrences..." -ForegroundColor Yellow

$allFiles = Get-ChildItem "$skinDir" -Recurse -File

$totalFilesPatched = 0
$totalOccurrencesPatched = 0

function New-RandomString {
    return -join ((65..90) + (97..122) | Get-Random -Count 12 | ForEach-Object { [char]$_ })
}

foreach ($file in $allFiles) {
    try {
        $content = Get-Content $file.FullName -Raw -ErrorAction Stop
        if (-not $content -or $content -notmatch 'luatools') {
            continue
        }

        # Find ALL individual occurrences of any luatools-containing word
        $matches = [regex]::Matches($content, '[a-zA-Z0-9_-]*luatools[a-zA-Z0-9_-]*')

        if ($matches.Count -eq 0) { continue }

        # Replace each occurrence with a unique random string
        $sb = [System.Text.StringBuilder]::new($content)
        $offset = 0
        $count = 0

        foreach ($match in $matches) {
            # IGNORA a string de identificação do próprio remendo para não quebrá-lo
            if ($match.Value -eq "lt-theme-webkit-fix") { continue }

            $randomStr = New-RandomString
            $sb.Replace($match.Value, $randomStr, $match.Index + $offset, $match.Length)
            $offset += $randomStr.Length - $match.Length
            $count++
        }

        Set-Content $file.FullName -Value $sb.ToString() -NoNewline -Encoding UTF8 -ErrorAction Stop
        Write-Host "Patched $count occurrences in $($file.Name)" -ForegroundColor Green
        $totalFilesPatched++
        $totalOccurrencesPatched += $count
    } catch {
        Write-Host "Skipped $($file.Name)" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "==============================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "$totalOccurrencesPatched occurrences randomized across $totalFilesPatched files" -ForegroundColor Green
Write-Host "==============================" -ForegroundColor Cyan

pause