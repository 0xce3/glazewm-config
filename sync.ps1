# Sync the live configs into this repo, then commit & push.
# Copies each tracked file FROM its real location INTO the repo, so the repo
# always reflects your current setup. One command keeps the backup up to date.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\sync.ps1
#   powershell -ExecutionPolicy Bypass -File .\sync.ps1 "custom commit message"

param([string]$Message = "Update configs")

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path

# NOTE: windows-terminal\settings.json is intentionally NOT auto-synced here.
# The live WT settings contain private/work-specific profiles (and a Windows
# username in paths). The repo keeps a hand-sanitized template instead, so this
# script never copies the live file back and re-leaks it. If you change the
# Serial profile or color schemes, edit the repo template manually.
$map = @(
    @{ Repo = 'glazewm\config.yaml';            Live = (Join-Path $env:USERPROFILE '.glzr\glazewm\config.yaml') }
    @{ Repo = 'glazewm\serial-menu.ps1';        Live = (Join-Path $env:USERPROFILE '.glzr\glazewm\serial-menu.ps1') }
    @{ Repo = 'glazewm\taskbar.ps1';            Live = (Join-Path $env:USERPROFILE '.glzr\glazewm\taskbar.ps1') }
    @{ Repo = 'glazewm\glaze-layout.ps1';       Live = (Join-Path $env:USERPROFILE '.glzr\glazewm\glaze-layout.ps1') }
    @{ Repo = 'yasb\config.yaml';               Live = (Join-Path $env:USERPROFILE '.config\yasb\config.yaml') }
    @{ Repo = 'yasb\styles.css';                Live = (Join-Path $env:USERPROFILE '.config\yasb\styles.css') }
)

foreach ($item in $map) {
    $live = $item.Live
    $dst  = Join-Path $repo $item.Repo
    if (-not (Test-Path $live)) { Write-Host "SKIP (live missing): $($item.Repo)" -ForegroundColor Yellow; continue }
    $dstDir = Split-Path -Parent $dst
    if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    Copy-Item $live $dst -Force
    Write-Host "PULLED: $($item.Repo)" -ForegroundColor Green
}

Push-Location $repo
try {
    git add -A
    $status = git status --porcelain
    if ([string]::IsNullOrWhiteSpace($status)) {
        Write-Host "`nKeine Aenderungen - Repo ist bereits aktuell." -ForegroundColor Cyan
        return
    }
    git commit -m $Message | Out-Null
    git push origin main
    Write-Host "`nGepusht: $Message" -ForegroundColor Cyan
}
finally {
    Pop-Location
}
