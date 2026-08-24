$ErrorActionPreference = 'Stop'

$iniPath = Join-Path $env:APPDATA 'GHISLER\wincmd.ini'
$themePath = Join-Path $env:APPDATA 'GHISLER\gruvbox-soft-dark.ini'
if (-not (Test-Path -LiteralPath $themePath)) {
    throw "Total Commander theme file not found: $themePath"
}

$running = @(Get-Process TOTALCMD64, TOTALCMD -ErrorAction SilentlyContinue)
$restartExecutable = $running | Where-Object Path | Select-Object -First 1 -ExpandProperty Path
if ($running) {
    $running | Stop-Process
    $running | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
}

$iniDirectory = Split-Path -Parent $iniPath
if (-not (Test-Path -LiteralPath $iniDirectory)) {
    New-Item -ItemType Directory -Path $iniDirectory -Force | Out-Null
}

$encoding = [System.Text.Encoding]::Default
$lines = [System.Collections.Generic.List[string]]::new()
if (Test-Path -LiteralPath $iniPath) {
    $lines.AddRange([string[]][System.IO.File]::ReadAllLines($iniPath, $encoding))
}

function Set-IniValue {
    param(
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value
    )

    $sectionHeader = "[$Section]"
    $sectionIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index].Trim() -ieq $sectionHeader) {
            $sectionIndex = $index
            break
        }
    }

    if ($sectionIndex -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -ne '') {
            $lines.Add('')
        }
        $lines.Add($sectionHeader)
        $lines.Add("$Key=$Value")
        return
    }

    $sectionEnd = $lines.Count
    for ($index = $sectionIndex + 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index].Trim() -match '^\[.+\]$') {
            $sectionEnd = $index
            break
        }
    }

    for ($index = $sectionIndex + 1; $index -lt $sectionEnd; $index++) {
        if ($lines[$index] -match "^\s*$([regex]::Escape($Key))\s*=") {
            $lines[$index] = "$Key=$Value"
            return
        }
    }
    $lines.Insert($sectionEnd, "$Key=$Value")
}

$backupPath = "$iniPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
if (Test-Path -LiteralPath $iniPath) {
    Copy-Item -LiteralPath $iniPath -Destination $backupPath -Force
    Write-Host "BACKUP: $iniPath -> $backupPath" -ForegroundColor DarkGray
}

Set-IniValue -Section Configuration -Key DarkMode -Value 2
Set-IniValue -Section ColorsDark -Key RedirectSection -Value '%COMMANDER_INI_PATH%\gruvbox-soft-dark.ini'
Set-IniValue -Section ListerDark -Key RedirectSection -Value '%COMMANDER_INI_PATH%\gruvbox-soft-dark.ini'
[System.IO.File]::WriteAllLines($iniPath, $lines, $encoding)
Write-Host 'OK:     Total Commander Gruvbox Soft Dark theme applied.' -ForegroundColor Green

if ($restartExecutable -and (Test-Path -LiteralPath $restartExecutable)) {
    Start-Process -FilePath $restartExecutable -ArgumentList '/O'
}
