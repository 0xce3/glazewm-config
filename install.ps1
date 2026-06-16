# Restore the GlazeWM / YASB / Windows Terminal setup from this repo.
# Copies each tracked file to its real location, backing up any existing file.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\install.ps1

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path

# Resolve the Windows Terminal settings path (package folder is fixed).
$wtDir = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'

$map = @(
    @{ Src = 'glazewm\config.yaml';            Dst = (Join-Path $env:USERPROFILE '.glzr\glazewm\config.yaml') }
    @{ Src = 'glazewm\serial-menu.ps1';        Dst = (Join-Path $env:USERPROFILE '.glzr\glazewm\serial-menu.ps1') }
    @{ Src = 'glazewm\taskbar.ps1';            Dst = (Join-Path $env:USERPROFILE '.glzr\glazewm\taskbar.ps1') }
    @{ Src = 'glazewm\glaze-layout.ps1';       Dst = (Join-Path $env:USERPROFILE '.glzr\glazewm\glaze-layout.ps1') }
    @{ Src = 'yasb\config.yaml';               Dst = (Join-Path $env:USERPROFILE '.config\yasb\config.yaml') }
    @{ Src = 'yasb\styles.css';                Dst = (Join-Path $env:USERPROFILE '.config\yasb\styles.css') }
    @{ Src = 'shaders\crt.hlsl';               Dst = (Join-Path $env:USERPROFILE '.config\shaders\crt.hlsl') }
    @{ Src = 'windows-terminal\settings.json'; Dst = (Join-Path $wtDir 'settings.json') }
)

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

foreach ($item in $map) {
    $src = Join-Path $repo $item.Src
    $dst = $item.Dst
    if (-not (Test-Path $src)) { Write-Host "SKIP (missing in repo): $($item.Src)" -ForegroundColor Yellow; continue }

    $dstDir = Split-Path -Parent $dst
    if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }

    if (Test-Path $dst) {
        $backup = "$dst.bak-$stamp"
        Copy-Item $dst $backup -Force
        Write-Host "BACKUP: $dst -> $backup" -ForegroundColor DarkGray
    }

    Copy-Item $src $dst -Force
    Write-Host "OK:     $($item.Src) -> $dst" -ForegroundColor Green
}

Write-Host ''
Write-Host 'Done. Start GlazeWM + YASB, then reload GlazeWM with Alt+Shift+R.' -ForegroundColor Cyan
Write-Host 'Make sure dependencies are installed (see README.md).' -ForegroundColor Cyan
