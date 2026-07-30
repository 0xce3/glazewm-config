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

# Public repository guardrails: only this explicit allowlist may be staged.
# Do not loosen this list without reviewing the new file for personal, work,
# machine-specific, or credential data.
$forbiddenPatterns = @(
    '(?i)\b(?:api[_-]?key|secret|token|password)\b\s*[:=]\s*[A-Za-z0-9_\-]{12,}',
    '(?i)\b(?:bearer\s+|ghp_|github_pat_|sk-)[A-Za-z0-9._\-]+',
    '(?i)[A-Z]:\\Users\\[^\\]+\\',
    '(?i)\\\\[^\\]+\\[^\\]+',
    '(?i)[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}'
)

# NOTE: windows-terminal\settings.json is intentionally NOT auto-synced here.
# The live WT settings contain private/work-specific profiles (and a Windows
# username in paths). The repo keeps a hand-sanitized template instead, so this
# script never copies the live file back and re-leaks it. If you change the
# Serial profile or color schemes, edit the repo template manually.
$map = @(
    @{ Repo = 'glazewm\config.yaml';            Live = (Join-Path $env:USERPROFILE '.glzr\glazewm\config.yaml') }
    @{ Repo = 'glazewm\requirements-serial.txt'; Live = (Join-Path $env:USERPROFILE '.glzr\glazewm\requirements-serial.txt') }
    @{ Repo = 'glazewm\taskbar.ps1';            Live = (Join-Path $env:USERPROFILE '.glzr\glazewm\taskbar.ps1') }
    @{ Repo = 'glazewm\glaze-layout.ps1';       Live = (Join-Path $env:USERPROFILE '.glzr\glazewm\glaze-layout.ps1') }
    @{ Repo = 'glazewm\glaze-swap.ps1';         Live = (Join-Path $env:USERPROFILE '.glzr\glazewm\glaze-swap.ps1') }
    @{ Repo = 'yasb\config.yaml';               Live = (Join-Path $env:USERPROFILE '.config\yasb\config.yaml') }
    @{ Repo = 'yasb\styles.css';                Live = (Join-Path $env:USERPROFILE '.config\yasb\styles.css') }
    @{ Repo = 'yasb\github-actions.py';          Live = (Join-Path $env:USERPROFILE '.config\yasb\github-actions.py') }
    @{ Repo = 'yasb\github-actions-notify.ps1';  Live = (Join-Path $env:USERPROFILE '.config\yasb\github-actions-notify.ps1') }
    @{ Repo = 'yasb\github-actions-picker.ps1';  Live = (Join-Path $env:USERPROFILE '.config\yasb\github-actions-picker.ps1') }
    @{ Repo = 'yasb\gruvbox-picker.ps1';         Live = (Join-Path $env:USERPROFILE '.config\yasb\gruvbox-picker.ps1') }
    @{ Repo = 'yasb\jlink-control.py';           Live = (Join-Path $env:USERPROFILE '.config\yasb\jlink-control.py') }
    @{ Repo = 'yasb\jlink-target-picker.ps1';    Live = (Join-Path $env:USERPROFILE '.config\yasb\jlink-target-picker.ps1') }
    @{ Repo = 'translucenttb\settings.json';    Live = (Join-Path $env:LOCALAPPDATA 'Packages\28017CharlesMilette.TranslucentTB_v826wp6bftszj\RoamingState\settings.json') }
    @{ Repo = 'flowlauncher\Themes\Gruvbox Soft Dark.xaml'; Live = (Join-Path $env:APPDATA 'FlowLauncher\Themes\Gruvbox Soft Dark.xaml') }
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

$trackedFiles = $map.Repo
foreach ($relativePath in $trackedFiles) {
    $path = Join-Path $repo $relativePath
    if ((Test-Path $path) -and (Select-String -Path $path -Pattern $forbiddenPatterns -Quiet)) {
        throw "Abbruch: potenziell sensible Daten in $relativePath. Datei bereinigen und erneut ausfuehren."
    }
}

if ($Message -match '(?i)co-authored-by:') {
    throw 'Abbruch: Commit-Nachrichten duerfen keine Co-Author-Zeile enthalten.'
}

Push-Location $repo
try {
    git add -- $trackedFiles
    $status = git status --porcelain
    if ([string]::IsNullOrWhiteSpace($status)) {
        Write-Host "`nKeine Aenderungen - Repo ist bereits aktuell." -ForegroundColor Cyan
        return
    }
    git diff --cached --check
    if ($LASTEXITCODE -ne 0) { throw 'Abbruch: Whitespace-Fehler im zu commitenden Diff.' }
    git commit -m $Message | Out-Null
    git push origin main
    Write-Host "`nGepusht: $Message" -ForegroundColor Cyan
}
finally {
    Pop-Location
}
