# home: dev on 0, communication on 1. office: dev on 1, communication on 0,
# utilities on 2. Missing screens fall back to the last attached monitor.
param([ValidateSet('home', 'office', 'swap')][string]$Layout = 'home')

$ErrorActionPreference = 'Stop'
$config = Join-Path $env:USERPROFILE '.glzr\glazewm\config.yaml'
$command = Get-Command glazewm.exe -ErrorAction SilentlyContinue
$glaze = if ($command) { $command.Source } else { Join-Path $env:ProgramFiles 'glzr.io\GlazeWM\cli\glazewm.exe' }
if (-not (Test-Path -LiteralPath $glaze)) { throw 'GlazeWM CLI not found. Reopen PowerShell after installation.' }

function Invoke-GlazeQuery {
    param([string[]]$Arguments)
    $output = & $glaze @Arguments
    if ($LASTEXITCODE -ne 0) { throw "GlazeWM command failed: $Arguments" }
    $result = ($output -join "`n") | ConvertFrom-Json
    if (-not $result.success) { throw "GlazeWM rejected command: $Arguments" }
    return $result.data
}

$monitors = (Invoke-GlazeQuery @('query', 'monitors')).monitors
$count = @($monitors).Count
if ($count -lt 1) { throw 'GlazeWM reported no monitors. Start the window manager first.' }
$workspaces = (Invoke-GlazeQuery @('query', 'workspaces')).workspaces
$existingNames = @($workspaces | ForEach-Object { $_.name })
$map = if ($Layout -eq 'office') {
    @{ '1'=1; '2'=1; '3'=1; '4'=1; '5'=0; '6'=0; '7'=0; '8'=2; '9'=2 }
} else {
    @{ '1'=0; '2'=0; '3'=0; '4'=0; '5'=1; '6'=1; '7'=1; '8'=1; '9'=1 }
}
$lines = [IO.File]::ReadAllLines($config)
$current = $null
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "^\s*-\s*name:\s*'([0-9])'") { $current = $Matches[1]; continue }
    if ($current -and $lines[$i] -match '^(\s*bind_to_monitor:\s*)(\d+)\s*$') {
        $prefix = $Matches[1]
        $monitor = [int]$Matches[2]
        if ($Layout -eq 'swap') {
            if ($monitor -eq 0) { $monitor = 1 } elseif ($monitor -eq 1) { $monitor = 0 }
        } else { $monitor = $map[$current] }
        $monitor = [Math]::Min($monitor, $count - 1)
        $map[$current] = $monitor
        $lines[$i] = "$prefix$monitor"
        $current = $null
    }
}
Copy-Item -LiteralPath $config -Destination "$config.bak-$([guid]::NewGuid().ToString('N'))"
[IO.File]::WriteAllLines($config, $lines, [Text.UTF8Encoding]::new($false))
$null = Invoke-GlazeQuery @('command', 'wm-reload-config')
foreach ($name in $map.Keys) {
    if ($name -in $existingNames) {
        $null = Invoke-GlazeQuery @('command', 'update-workspace-config', '--workspace', $name, '--bind-to-monitor', [string]$map[$name])
    }
}
