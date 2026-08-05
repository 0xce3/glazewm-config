# Restore the GlazeWM / YASB / Windows Terminal setup from this repo.
# Copies each tracked file to its real location, backing up any existing file.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\install.ps1

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path

# Resolve WinGet even when this script is launched from WSL/non-interactive
# PowerShell, where the WindowsApps execution alias may be missing from PATH.
$wingetCommand = Get-Command winget.exe -ErrorAction SilentlyContinue
if ($wingetCommand -and $wingetCommand.Source -notlike '*\Microsoft\WindowsApps\winget.exe') {
    $winget = $wingetCommand.Source
} else {
    $appInstaller = Get-AppxPackage Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1
    $winget = if ($appInstaller) { Join-Path $appInstaller.InstallLocation 'winget.exe' } else { $null }
}
if (-not $winget -or -not (Test-Path $winget)) {
    throw 'WinGet is missing. Install Microsoft App Installer and run this script again.'
}

function Invoke-Winget {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$WingetArguments)

    $stdout = New-TemporaryFile
    $stderr = New-TemporaryFile
    try {
        $process = Start-Process -FilePath $winget -ArgumentList $WingetArguments `
            -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        Get-Content $stdout
        # APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND is expected for a
        # `winget list` probe when the requested package is not installed.
        if ($process.ExitCode -ne 0 -and $process.ExitCode -ne -1978335212) {
            $errorText = Get-Content $stderr -Raw
            throw "WinGet failed with exit code $($process.ExitCode): $errorText"
        }
    }
    finally {
        Remove-Item $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

# Resolve the Windows Terminal settings path (package folder is fixed).
$wtDir = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'

# TranslucentTB (transparent taskbar) MSIX package folder is fixed per publisher.
$ttbAumid = '28017CharlesMilette.TranslucentTB_v826wp6bftszj!TranslucentTB'
$ttbDir = Join-Path $env:LOCALAPPDATA 'Packages\28017CharlesMilette.TranslucentTB_v826wp6bftszj\RoamingState'

# Windows Terminal can only apply a font family after Windows has registered it.
$fontRegistryPaths = @(
    'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
)
$jetBrainsMonoInstalled = $false
foreach ($fontRegistryPath in $fontRegistryPaths) {
    if (-not (Test-Path $fontRegistryPath)) { continue }
    $registeredFonts = (Get-ItemProperty $fontRegistryPath).PSObject.Properties
    if ($registeredFonts | Where-Object {
        $_.Name -match '^JetBrainsMono (?:NFM|Nerd Font Mono)' -or
        $_.Value -match '^JetBrainsMonoNerdFontMono-'
    }) {
        $jetBrainsMonoInstalled = $true
        break
    }
}

if (-not $jetBrainsMonoInstalled) {
    Write-Host 'Installing JetBrainsMono Nerd Font...' -ForegroundColor Cyan
    Invoke-Winget install --id DEVCOM.JetBrainsMonoNerdFont --exact --source winget `
        --accept-package-agreements --accept-source-agreements --silent
} else {
    Write-Host 'OK:     JetBrainsMono Nerd Font is installed.' -ForegroundColor Green
}

# Install Yazi, the terminal file manager used by the GlazeWM Files workspace.
if (-not (Invoke-Winget list --id sxyazi.yazi --exact | Select-String 'Yazi')) {
    Write-Host 'Installing Yazi...' -ForegroundColor Cyan
    Invoke-Winget install --id sxyazi.yazi --exact --source winget `
        --accept-package-agreements --accept-source-agreements --silent
} else {
    Write-Host 'OK:     Yazi is installed.' -ForegroundColor Green
}

# On Windows, Yazi uses Git's file.exe for reliable MIME detection. Keep an
# existing user override; otherwise configure the standard Git-for-Windows path.
$gitFile = Join-Path $env:ProgramFiles 'Git\usr\bin\file.exe'
if ((Test-Path $gitFile) -and [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('YAZI_FILE_ONE', 'User'))) {
    [Environment]::SetEnvironmentVariable('YAZI_FILE_ONE', $gitFile, 'User')
    $env:YAZI_FILE_ONE = $gitFile
    Write-Host "OK:     YAZI_FILE_ONE -> $gitFile" -ForegroundColor Green
}

$map = @(
    @{ Src = 'glazewm\config.yaml';            Dst = (Join-Path $env:USERPROFILE '.glzr\glazewm\config.yaml') }
    @{ Src = 'glazewm\requirements-serial.txt'; Dst = (Join-Path $env:USERPROFILE '.glzr\glazewm\requirements-serial.txt') }
    @{ Src = 'glazewm\taskbar.ps1';            Dst = (Join-Path $env:USERPROFILE '.glzr\glazewm\taskbar.ps1') }
    @{ Src = 'glazewm\glaze-layout.ps1';       Dst = (Join-Path $env:USERPROFILE '.glzr\glazewm\glaze-layout.ps1') }
    @{ Src = 'glazewm\glaze-swap.ps1';         Dst = (Join-Path $env:USERPROFILE '.glzr\glazewm\glaze-swap.ps1') }
    @{ Src = 'glazewm\yazi.ps1';               Dst = (Join-Path $env:USERPROFILE '.glzr\glazewm\yazi.ps1') }
    @{ Src = 'yasb\config.yaml';               Dst = (Join-Path $env:USERPROFILE '.config\yasb\config.yaml') }
    @{ Src = 'yasb\styles.css';                Dst = (Join-Path $env:USERPROFILE '.config\yasb\styles.css') }
    @{ Src = 'yasb\gruvbox-picker.ps1';         Dst = (Join-Path $env:USERPROFILE '.config\yasb\gruvbox-picker.ps1') }
    @{ Src = 'yasb\jlink-control.py';           Dst = (Join-Path $env:USERPROFILE '.config\yasb\jlink-control.py') }
    @{ Src = 'yasb\jlink-target-picker.ps1';    Dst = (Join-Path $env:USERPROFILE '.config\yasb\jlink-target-picker.ps1') }
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

# Remove files superseded by the Python terminal tools.
Remove-Item (Join-Path $env:USERPROFILE '.glzr\glazewm\serial-menu.ps1') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:USERPROFILE '.glzr\glazewm\requirements-jlink.txt') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:USERPROFILE '.glzr\glazewm\serial-monitor.py') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:USERPROFILE '.glzr\glazewm\jlink-manager.py') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:USERPROFILE '.glzr\glazewm\requirements-tui.txt') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:USERPROFILE '.config\yasb\jlink-menu.ps1') -Force -ErrorAction SilentlyContinue

# Install pySerial's ready-made miniterm.
$serialRequirements = Join-Path $env:USERPROFILE '.glzr\glazewm\requirements-serial.txt'
if (Get-Command py -ErrorAction SilentlyContinue) {
    py -3 -c "import serial" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Installing the serial monitor dependency...' -ForegroundColor Cyan
        py -3 -m pip install -r $serialRequirements
        if ($LASTEXITCODE -ne 0) { throw 'Could not install the serial monitor Python dependency.' }
    }
} else {
    Write-Host 'SKIP: Python launcher not found; install Python 3.9+ to use the Serial profile.' -ForegroundColor Yellow
}

# Install TranslucentTB (transparent taskbar) if missing, and register it to
# start at login via a Startup-folder shortcut (kept out of the GlazeWM config).
if (-not (Invoke-Winget list --id CharlesMilette.TranslucentTB | Select-String 'TranslucentTB')) {
    Write-Host 'Installing TranslucentTB...' -ForegroundColor Cyan
    Invoke-Winget install --id CharlesMilette.TranslucentTB --source winget `
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
if (-not (Invoke-Winget list --id Flow-Launcher.Flow-Launcher | Select-String 'Flow')) {
    Write-Host 'Installing Flow Launcher...' -ForegroundColor Cyan
    Invoke-Winget install --id Flow-Launcher.Flow-Launcher --source winget `
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
