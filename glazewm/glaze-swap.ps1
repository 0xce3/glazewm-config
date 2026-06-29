# Swap the two main monitors in GlazeWM: every workspace currently on monitor 0
# moves to monitor 1 and vice versa (monitor 2 - the office third screen - is
# left untouched). This is a toggle: run it again to swap back.
#
# It flips the `bind_to_monitor:` values in config.yaml, then reloads GlazeWM
# and nudges existing workspaces to their new monitor. Bound to Alt+Shift+M.

$ErrorActionPreference = 'Stop'
$config = Join-Path $env:USERPROFILE '.glzr\glazewm\config.yaml'
$glaze  = 'C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe'

$lines   = Get-Content -LiteralPath $config
$current = $null
$newMap  = @{}
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "^\s*-\s*name:\s*'([0-9])'") {
        $current = $Matches[1]
        continue
    }
    if ($current -and $lines[$i] -match '^(\s*bind_to_monitor:\s*)(\d+)\s*$') {
        $mon = [int]$Matches[2]
        if ($mon -eq 0) { $mon = 1 } elseif ($mon -eq 1) { $mon = 0 }  # 2 stays
        $lines[$i] = "$($Matches[1])$mon"
        $newMap[$current] = $mon
        $current = $null
    }
}
Set-Content -LiteralPath $config -Value $lines

if (Test-Path $glaze) {
    & $glaze command wm-reload-config | Out-Null
    foreach ($ws in $newMap.Keys) {
        & $glaze command update-workspace-config --workspace $ws --bind-to-monitor $newMap[$ws] | Out-Null
    }
}
