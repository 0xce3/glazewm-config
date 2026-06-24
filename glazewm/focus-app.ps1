# Bring a specific app (default: Microsoft Teams) to the foreground from any
# workspace AND show it fullscreen on the monitor you are currently using, so a
# running meeting overlays your main screen instead of sitting in a tiny tile.
#
# Usage: focus-app.ps1 [processName] [-NoFullscreen]
#
# Bound to Alt+M in config.yaml.

param(
    [string]$ProcessName = 'ms-teams',
    [switch]$NoFullscreen
)

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class Win {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr p);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
}
"@

# Find the best window of the target app and bring it to the foreground.
# Returns $true if a window was activated.
function Invoke-Activate {
    param([string]$Name)

    $pids = @{}
    foreach ($p in Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessName -ieq $Name -or $_.ProcessName -ieq 'Teams' }) {
        $pids[[uint32]$p.Id] = $true
    }
    if ($pids.Count -eq 0) { return $false }

    $candidates = New-Object System.Collections.ArrayList
    $cb = [Win+EnumWindowsProc] {
        param($hWnd, $lParam)
        if (-not [Win]::IsWindowVisible($hWnd)) { return $true }
        $winPid = [uint32]0
        [void][Win]::GetWindowThreadProcessId($hWnd, [ref]$winPid)
        if (-not $pids.ContainsKey($winPid)) { return $true }
        $len = [Win]::GetWindowTextLength($hWnd)
        if ($len -le 0) { return $true }
        $sb = New-Object System.Text.StringBuilder ($len + 1)
        [void][Win]::GetWindowText($hWnd, $sb, $sb.Capacity)
        $title = $sb.ToString()
        if ([string]::IsNullOrWhiteSpace($title)) { return $true }
        $score = 1
        if ($title -imatch 'meeting|besprechung|call|anruf|\| Microsoft Teams') { $score = 10 }
        [void]$candidates.Add([pscustomobject]@{ Handle = $hWnd; Score = $score })
        return $true
    }
    [void][Win]::EnumWindows($cb, [IntPtr]::Zero)
    if ($candidates.Count -eq 0) { return $false }

    $hwnd = ($candidates | Sort-Object Score -Descending | Select-Object -First 1).Handle

    $SW_RESTORE = 9
    $fg = [Win]::GetForegroundWindow()
    $fgPid = [uint32]0
    $fgThread = [Win]::GetWindowThreadProcessId($fg, [ref]$fgPid)
    $myThread = [Win]::GetCurrentThreadId()
    [void][Win]::AttachThreadInput($myThread, $fgThread, $true)
    [void][Win]::ShowWindow($hwnd, $SW_RESTORE)
    [void][Win]::BringWindowToTop($hwnd)
    [void][Win]::SetForegroundWindow($hwnd)
    [void][Win]::AttachThreadInput($myThread, $fgThread, $false)
    return $true
}

# Resolve the GlazeWM CLI (used to move + fullscreen the window).
$glazewm = Join-Path ${env:ProgramFiles} 'glzr.io\GlazeWM\cli\glazewm.exe'
if (-not (Test-Path $glazewm)) {
    $c = Get-Command glazewm -ErrorAction SilentlyContinue
    $glazewm = if ($c) { $c.Source } else { $null }
}

function Get-Focused {
    if (-not $glazewm) { return $null }
    try { return (& $glazewm query focused | ConvertFrom-Json).data.focused } catch { return $null }
}

# Remember which workspace you're on now = your current (main) monitor.
$origWs = $null
if ($glazewm) {
    try {
        $origWs = ((& $glazewm query workspaces | ConvertFrom-Json).data.workspaces |
            Where-Object { $_.hasFocus } | Select-Object -First 1).name
    } catch {}
}

# 1) Raise Teams.
if (-not (Invoke-Activate -Name $ProcessName)) { return }

if ($NoFullscreen -or -not $glazewm) { return }

# 2) Move it onto your current workspace and make it fullscreen.
Start-Sleep -Milliseconds 250
$f = Get-Focused
if (-not $f -or ("$($f.processName)" -inotmatch '^(ms-teams|Teams)$')) { return }

if ($origWs) {
    & $glazewm command move --workspace $origWs | Out-Null
    Start-Sleep -Milliseconds 120
    # Re-focus Teams on the destination workspace (move doesn't follow focus).
    [void](Invoke-Activate -Name $ProcessName)
    Start-Sleep -Milliseconds 120
}

# Fullscreen on top -> overlays the whole monitor. Idempotent (set, not toggle).
$f = Get-Focused
if ($f -and ("$($f.processName)" -imatch '^(ms-teams|Teams)$')) {
    & $glazewm command set-fullscreen --shown-on-top true | Out-Null
}
