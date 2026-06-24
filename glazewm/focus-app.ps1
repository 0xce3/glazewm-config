# Bring a specific app's window to the foreground from anywhere (any GlazeWM
# workspace). Meant for Microsoft Teams: when a meeting is running it opens a
# separate window that is easy to lose. This activates the Teams window,
# preferring a meeting/call window if one exists.
#
# Usage: focus-app.ps1 [processName]   (default: ms-teams)
#
# Bound to Alt+M in config.yaml. After the window is activated, GlazeWM follows
# the foreground change and switches to whatever workspace it lives on.

param(
    [string]$ProcessName = 'ms-teams'
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

# Collect PIDs for the target process (handle "ms-teams" / "Teams").
$pids = @{}
foreach ($p in Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -ieq $ProcessName -or $_.ProcessName -ieq 'Teams' }) {
    $pids[[uint32]$p.Id] = $true
}
if ($pids.Count -eq 0) { return }

# Enumerate visible top-level windows of those PIDs and score meeting windows.
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
    # Score: meeting/call windows first.
    $score = 1
    if ($title -imatch 'meeting|besprechung|call|anruf|\| Microsoft Teams') { $score = 10 }
    [void]$candidates.Add([pscustomobject]@{ Handle = $hWnd; Title = $title; Score = $score })
    return $true
}
[void][Win]::EnumWindows($cb, [IntPtr]::Zero)
if ($candidates.Count -eq 0) { return }

$target = $candidates | Sort-Object -Property Score -Descending | Select-Object -First 1
$hwnd = $target.Handle

# Reliable foreground switch (attach to the current foreground thread first).
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
