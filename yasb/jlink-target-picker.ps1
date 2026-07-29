$ErrorActionPreference = 'Stop'

$controller = Join-Path $PSScriptRoot 'jlink-control.py'
$targetsJson = & py -3 $controller targets
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

$selected = $targets |
    ForEach-Object { [PSCustomObject]@{ Target = [string]$_ } } |
    Out-GridView -Title 'J-Link GDB target - type to filter, then select one' -PassThru

if ($null -eq $selected) { exit 0 }

& py -3 $controller start-gdb --device $selected.Target
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
