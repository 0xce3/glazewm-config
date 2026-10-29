#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$SkipPackages,
    [switch]$NoAutostart
)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
. (Join-Path $repo 'setup\common.ps1')

function Confirm-Change {
    param([string]$Target, [string]$Action)
    if (-not $PSCmdlet.ShouldProcess($Target, $Action)) { return $false }
    return ((Read-Host "$Action`n$Target`nAnwenden? [j/N]") -match '^(?i:j|ja|y|yes)$')
}

function Invoke-Winget {
    param([string[]]$Arguments, [switch]$Probe)
    $output = & $script:winget @Arguments 2>&1
    $code = $LASTEXITCODE
    if ($Probe -and $code -eq -1978335212) { return $false }
    if ($code -ne 0) { throw "WinGet failed ($code): $($output -join [Environment]::NewLine)" }
    if ($Probe) { return $true }
    $output | Out-Host
}

$packages = @(
    'glzr-io.glazewm'
    'AmN.yasb'
    'Flow-Launcher.Flow-Launcher'
    'Microsoft.WindowsTerminal'
    'DEVCOM.JetBrainsMonoNerdFont'
    'CharlesMilette.TranslucentTB'
)
$map = @(Get-ConfigMap)
foreach ($item in $map) {
    $source = Join-Path $repo $item.Repo
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing source: $($item.Repo)" }
    Assert-PublicContent -Content ([IO.File]::ReadAllText($source)) -Label $item.Repo
}

Write-Host 'Core setup only. No accounts, work profiles, WSL, Python or licensed tools are imported.'
Write-Host 'Close GlazeWM/YASB/Flow Launcher/TranslucentTB before applying configuration.'
if (-not $SkipPackages) {
    if (-not $WhatIfPreference) {
        $command = Get-Command winget.exe -ErrorAction SilentlyContinue
        $script:winget = if ($command) { $command.Source } else { $null }
        if (-not $script:winget -or -not (Test-Path -LiteralPath $script:winget)) {
            $appInstaller = Get-AppxPackage Microsoft.DesktopAppInstaller |
                Sort-Object Version -Descending | Select-Object -First 1
            if ($appInstaller) { $script:winget = Join-Path $appInstaller.InstallLocation 'winget.exe' }
        }
        if (-not $script:winget -or -not (Test-Path -LiteralPath $script:winget)) {
            throw 'WinGet missing. Install Microsoft App Installer, then retry. No configuration was changed.'
        }
    }
    foreach ($id in $packages) {
        if ($WhatIfPreference) {
            $null = $PSCmdlet.ShouldProcess($id, 'Install package if missing (WinGet)')
            continue
        }
        if (Confirm-Change $id 'Paket pruefen und falls fehlend installieren (Paket-/Quellbedingungen; eventuell UAC)') {
            if (Invoke-Winget -Arguments @('list', '--id', $id, '--exact', '--accept-source-agreements', '--disable-interactivity') -Probe) {
                Write-Host "INSTALLED: $id"
                continue
            }
            Invoke-Winget -Arguments @('install', '--id', $id, '--exact', '--source', 'winget',
                '--accept-package-agreements', '--accept-source-agreements', '--silent', '--disable-interactivity')
            if (-not (Invoke-Winget -Arguments @('list', '--id', $id, '--exact', '--accept-source-agreements', '--disable-interactivity') -Probe)) {
                throw "Package not registered after installation: $id"
            }
        } else { Write-Warning "Skipped package: $id. Dependent features may be unavailable." }
    }
}

# Never kill a running app or overwrite a config it may save over on exit.
$running = @(Get-Process -Name glazewm, yasb, 'Flow.Launcher', TranslucentTB -ErrorAction SilentlyContinue)
if ($running.Count -and -not $WhatIfPreference) {
    throw 'Close GlazeWM, YASB, Flow Launcher and TranslucentTB (including tray icons), then rerun with -SkipPackages. No config was changed.'
}
foreach ($item in $map) {
    if (Confirm-Change $item.Live "Konfiguration uebernehmen: $($item.Repo) (vorhandene Datei sichern)") {
        $content = [IO.File]::ReadAllText((Join-Path $repo $item.Repo))
        $content = ConvertTo-PortableConfig $item.Repo $content
        Write-ConfigText -Path $item.Live -Content $content
    } else { Write-Host "SKIPPED: $($item.Repo)" }
}

$flowPath = Join-Path $env:APPDATA 'FlowLauncher\Settings\Settings.json'
if (Confirm-Change $flowPath 'Flow: Gruvbox, Dark, LWin-Hotkey und Sound aus zusammenfuehren') {
    $flow = Read-JsonConfig $flowPath
    Set-JsonProperty $flow Theme 'Gruvbox Soft Dark'
    Set-JsonProperty $flow ColorScheme 'Dark'
    Set-JsonProperty $flow Hotkey 'LWin'
    Set-JsonProperty $flow UseSound $false
    Write-ConfigText $flowPath ($flow | ConvertTo-Json -Depth 100)
}

$terminalPaths = @(Get-TerminalPaths)
$existingTerminals = @($terminalPaths | Where-Object { Test-Path -LiteralPath $_ })
if (-not $existingTerminals.Count) { $existingTerminals = @($terminalPaths[0]) }
foreach ($terminalPath in $existingTerminals) {
    if (Confirm-Change $terminalPath 'Terminal: bereinigte Profile/Einstellungen zusammenfuehren; exportiertes Standardprofil uebernehmen; lokale Zusatzprofile behalten') {
        $settings = Read-JsonConfig $terminalPath
        $template = Get-Content -LiteralPath (Join-Path $repo 'windows-terminal\settings.json') -Raw | ConvertFrom-Json
        Assert-PublicContent ($template | ConvertTo-Json -Depth 100) 'Terminal template'
        if (@($template.profiles.list | Where-Object { $_.commandline -match '(?i)wsl\.exe|serial\.tools' -or $_.source -match '(?i)Ubuntu|WSL' }).Count) {
            Write-Warning 'Restored Ubuntu/Serial profiles need separately installed WSL distros or Python/pySerial. The core installer does not install these dependencies. Change the default profile if unavailable.'
        }
        $merged = Merge-TerminalSettings $settings $template
        Write-ConfigText $terminalPath ($merged | ConvertTo-Json -Depth 100)
    }
}

if (-not $NoAutostart) {
    $startup = [Environment]::GetFolderPath('Startup')
    $links = @(
        @{ Name = 'GlazeWM'; File = 'glazewm.exe'; Candidates = @(
            (Join-Path $env:ProgramFiles 'glzr.io\GlazeWM\glazewm.exe')
        ) }
        @{ Name = 'Flow Launcher'; File = 'Flow.Launcher.exe'; Candidates = @(
            (Join-Path $env:LOCALAPPDATA 'FlowLauncher\Flow.Launcher.exe')
        ) }
        @{ Name = 'TranslucentTB'; File = 'explorer.exe'; Candidates = @(); Arguments = 'shell:AppsFolder\28017CharlesMilette.TranslucentTB_v826wp6bftszj!TranslucentTB' }
    )
    foreach ($link in $links) {
        $path = Join-Path $startup "$($link.Name).lnk"
        if (-not (Confirm-Change $path 'Autostart bei Anmeldung einrichten (YASB startet durch GlazeWM)')) { continue }
        $target = $link.Candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $target) {
            $command = Get-Command $link.File -ErrorAction SilentlyContinue
            if ($command) { $target = $command.Source }
        }
        if (-not $target) { throw "Cannot find $($link.File). Start the installed app once, reopen PowerShell and retry." }
        if (-not (Test-Path -LiteralPath $startup)) { New-Item -ItemType Directory -Path $startup -Force | Out-Null }
        Backup-ConfigFile $path
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($path)
        $shortcut.TargetPath = $target
        $shortcut.WorkingDirectory = Split-Path -Parent $target
        $shortcut.Arguments = if ($link.Arguments) { $link.Arguments } else { '' }
        if ($link.Name -eq 'GlazeWM' -and $target -like '*\cli\glazewm.exe') { $shortcut.Arguments = 'start' }
        $shortcut.Save()
        if (-not (Test-Path -LiteralPath $path)) { throw "Startup shortcut was not created: $path" }
    }
}
if ($WhatIfPreference) {
    Write-Host 'Preview only: no packages, files, processes or startup entries changed.'
} else {
    Write-Host 'Selected changes applied. No apps were started. Sign out/in to use approved startup entries.'
    Write-Host 'Monitor default: all workspaces on monitor 0. Alt+Shift+Z/O selects a 2/3-screen layout with single-screen fallback.'
}
