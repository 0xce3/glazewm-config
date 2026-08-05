$ErrorActionPreference = 'Stop'

$yaziCommand = Get-Command yazi.exe -ErrorAction SilentlyContinue
$yaziPath = if ($yaziCommand) { $yaziCommand.Source } else { $null }

if (-not $yaziPath) {
    $packageRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    $yaziPath = Get-ChildItem $packageRoot -Filter yazi.exe -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object FullName -Like '*\sxyazi.yazi_*' |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

if (-not $yaziPath) {
    throw 'Yazi was not found. Run install.ps1 from the glazewm-config repository.'
}

& wt.exe new-tab --title YAZI $yaziPath
