$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'gruvbox-picker.ps1')

$controller = Join-Path $PSScriptRoot 'jlink-control.py'
$pythonLauncher = Join-Path $env:SystemRoot 'py.exe'
$targetsJson = & $pythonLauncher -3 $controller targets
if ($LASTEXITCODE -ne 0) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        'Could not load the SEGGER J-Link target database.',
        'J-Link Manager',
        'OK',
        'Error'
    ) | Out-Null
    exit 1
}

$targets = $targetsJson | ConvertFrom-Json
if (-not $targets) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        'No supported J-Link targets were found.',
        'J-Link Manager',
        'OK',
        'Warning'
    ) | Out-Null
    exit 1
}

$selection = @(Show-GruvboxPicker `
    -Items @($targets) `
    -Title 'J-Link GDB - Target' `
    -Prompt 'Search J-Link targets')

if ($selection.Count -eq 0) { exit 0 }

& $pythonLauncher -3 $controller start-gdb --device $selection[0]
if ($LASTEXITCODE -ne 0) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        'The J-Link GDB server could not be started. Check ~/.jlink-logs.',
        'J-Link Manager',
        'OK',
        'Error'
    ) | Out-Null
    exit 1
}
