# Restore the GlazeWM / YASB / Windows Terminal setup from this repo.
# Copies each tracked file to its real location, backing up any existing file.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\install.ps1

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path

# Resolve the Windows Terminal settings path (package folder is fixed).
$wtDir = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'

# TranslucentTB (transparent taskbar) MSIX package folder is fixed per publisher.
$ttbAumid = '28017CharlesMilette.TranslucentTB_v826wp6bftszj!TranslucentTB'
$ttbDir = Join-Path $env:LOCALAPPDATA 'Packages\28017CharlesMilette.TranslucentTB_v826wp6bftszj\RoamingState'

$map = @(
    @{ Src = 'glazewm\config.yaml';            Dst = (Join-Path $env:USERPROFILE '.glzr\glazewm\config.yaml') }
    @{ Src = 'glazewm\serial-menu.ps1';        Dst = (Join-Path $env:USERPROFILE '.glzr\glazewm\serial-menu.ps1') }
    @{ Src = 'glazewm\taskbar.ps1';            Dst = (Join-Path $env:USERPROFILE '.glzr\glazewm\taskbar.ps1') }
    @{ Src = 'glazewm\glaze-layout.ps1';       Dst = (Join-Path $env:USERPROFILE '.glzr\glazewm\glaze-layout.ps1') }
    @{ Src = 'glazewm\glaze-swap.ps1';         Dst = (Join-Path $env:USERPROFILE '.glzr\glazewm\glaze-swap.ps1') }
    @{ Src = 'yasb\config.yaml';               Dst = (Join-Path $env:USERPROFILE '.config\yasb\config.yaml') }
    @{ Src = 'yasb\styles.css';                Dst = (Join-Path $env:USERPROFILE '.config\yasb\styles.css') }
    @{ Src = 'windows-terminal\settings.json'; Dst = (Join-Path $wtDir 'settings.json') }
    @{ Src = 'translucenttb\settings.json';    Dst = (Join-Path $ttbDir 'settings.json') }
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

# Install TranslucentTB (transparent taskbar) if missing, and register it to
# start at login via a Startup-folder shortcut (kept out of the GlazeWM config).
if (-not (winget list --id CharlesMilette.TranslucentTB 2>$null | Select-String 'TranslucentTB')) {
    Write-Host 'Installing TranslucentTB...' -ForegroundColor Cyan
    winget install --id CharlesMilette.TranslucentTB --source winget `
        --accept-package-agreements --accept-source-agreements --silent | Out-Null
}

$startupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'TranslucentTB.lnk'
if (-not (Test-Path $startupLnk)) {
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($startupLnk)
    $sc.TargetPath = 'explorer.exe'
    $sc.Arguments = 'shell:AppsFolder\' + $ttbAumid
    $sc.Save()
    Write-Host "OK:     TranslucentTB autostart -> $startupLnk" -ForegroundColor Green
}

# Install Flow Launcher (floating app launcher on the Windows key) if missing,
# deploy the Gruvbox theme, and point its settings at it. Flow Launcher manages
# its own start-at-login, so no extra shortcut is needed.
if (-not (winget list --id Flow-Launcher.Flow-Launcher 2>$null | Select-String 'Flow')) {
    Write-Host 'Installing Flow Launcher...' -ForegroundColor Cyan
    winget install --id Flow-Launcher.Flow-Launcher --source winget `
        --accept-package-agreements --accept-source-agreements --silent | Out-Null
}

$flowThemeDir = Join-Path $env:APPDATA 'FlowLauncher\Themes'
$flowTheme = Join-Path $repo 'flowlauncher\Themes\Gruvbox Soft Dark.xaml'
if (Test-Path $flowTheme) {
    if (-not (Test-Path $flowThemeDir)) { New-Item -ItemType Directory -Path $flowThemeDir -Force | Out-Null }
    Copy-Item $flowTheme (Join-Path $flowThemeDir 'Gruvbox Soft Dark.xaml') -Force
    Write-Host "OK:     Flow Launcher theme -> $flowThemeDir" -ForegroundColor Green
}

# Patch the three settings we care about (theme, dark scheme, Windows-key hotkey)
# without overwriting Flow Launcher's machine-local state. Flow must be closed.
$flowSettings = Join-Path $env:APPDATA 'FlowLauncher\Settings\Settings.json'
if (Test-Path $flowSettings) {
    Stop-Process -Name 'Flow.Launcher' -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
    $json = Get-Content $flowSettings -Raw | ConvertFrom-Json
    $json.Theme = 'Gruvbox Soft Dark'
    $json.ColorScheme = 'Dark'
    $json.Hotkey = 'LWin'
    $json.UseSound = $false
    $json | ConvertTo-Json -Depth 32 | Set-Content $flowSettings -Encoding UTF8
    Write-Host "OK:     Flow Launcher settings (theme/dark/LWin hotkey/no sound)" -ForegroundColor Green
}

Write-Host ''
Write-Host 'Done. Start GlazeWM + YASB, then reload GlazeWM with Alt+Shift+R.' -ForegroundColor Cyan
Write-Host 'TranslucentTB starts at next login (or launch it now for a transparent taskbar).' -ForegroundColor Cyan
Write-Host 'Make sure dependencies are installed (see README.md).' -ForegroundColor Cyan
