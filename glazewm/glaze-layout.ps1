# Switch GlazeWM workspace->monitor layout between "home" and "office".
#
#   home   (2 monitors): main/dev = monitor 0 (left), laptop/comms = monitor 1
#   office (3 monitors): laptop/comms = monitor 0, main/dev = monitor 1,
#                        third screen (right) = monitor 2
#
# It rewrites only the `bind_to_monitor:` values in config.yaml, then reloads
# GlazeWM. Bound via Alt+Shift+O (office) / Alt+Shift+Z (home).
#
# Usage:
#   powershell -File glaze-layout.ps1 home
#   powershell -File glaze-layout.ps1 office

param([ValidateSet('home', 'office')][string]$Layout = 'home')

$ErrorActionPreference = 'Stop'
$config = Join-Path $env:USERPROFILE '.glzr\glazewm\config.yaml'
$glaze  = 'C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe'

# workspace name -> monitor index, per layout
if ($Layout -eq 'office') {
    $map = @{ '1'=1; '2'=1; '3'=1; '4'=1; '5'=0; '6'=0; '7'=0; '8'=2; '9'=2 }
} else {
    $map = @{ '1'=0; '2'=0; '3'=0; '4'=0; '5'=1; '6'=1; '7'=1; '8'=1; '9'=1 }
}

$lines   = Get-Content -LiteralPath $config
$current = $null
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "^\s*-\s*name:\s*'([0-9])'") {
        $current = $Matches[1]
        continue
    }
    if ($current -and $lines[$i] -match '^(\s*bind_to_monitor:\s*)\d+\s*$') {
        if ($map.ContainsKey($current)) {
            $lines[$i] = "$($Matches[1])$($map[$current])"
        }
        $current = $null
    }
}
Set-Content -LiteralPath $config -Value $lines

if (Test-Path $glaze) {
    # Reload so the in-memory config + on-demand workspaces (8/9) pick up the
    # new bindings.
    & $glaze command wm-reload-config | Out-Null

    # wm-reload-config does NOT relocate already-existing workspaces, so nudge
    # each one to its target monitor. Non-existent workspaces (e.g. 8/9 without
    # keep_alive) just return success:false and are harmlessly skipped.
    foreach ($ws in $map.Keys) {
        & $glaze command update-workspace-config --workspace $ws --bind-to-monitor $map[$ws] | Out-Null
    }
}
