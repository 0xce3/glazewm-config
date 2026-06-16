# Toggle the Windows taskbar between auto-hide and always-visible.
#
# auto-hide (default): the taskbar slides away but reappears on hover at the
# screen edge AND when the Windows key / Start is pressed. This is the native
# Windows "Automatically hide the taskbar" behaviour, set via the appbar API
# so it applies instantly (no Explorer restart).
#
# Usage:
#   powershell -File taskbar.ps1 autohide   # enable auto-hide
#   powershell -File taskbar.ps1 show       # always visible
#   powershell -File taskbar.ps1 toggle     # flip current state

param([ValidateSet('autohide', 'show', 'toggle')][string]$Action = 'autohide')

$sig = @'
using System;
using System.Runtime.InteropServices;
public static class TB {
    [StructLayout(LayoutKind.Sequential)]
    public struct APPBARDATA {
        public uint cbSize;
        public IntPtr hWnd;
        public uint uCallbackMessage;
        public uint uEdge;
        public int left, top, right, bottom;
        public IntPtr lParam;
    }
    [DllImport("shell32.dll")] public static extern IntPtr SHAppBarMessage(uint msg, ref APPBARDATA data);
    [DllImport("user32.dll")]  public static extern IntPtr FindWindow(string c, string w);
    [DllImport("user32.dll")]  public static extern bool ShowWindow(IntPtr h, int n);

    public const uint ABM_GETSTATE = 0x00000004;
    public const uint ABM_SETSTATE = 0x0000000A;
    public const int  ABS_AUTOHIDE = 0x01;
    public const int  ABS_ALWAYSONTOP = 0x02;
    public const int  SW_SHOW = 5;

    public static int GetState() {
        var d = new APPBARDATA(); d.cbSize = (uint)Marshal.SizeOf(d);
        return (int)SHAppBarMessage(ABM_GETSTATE, ref d);
    }
    public static void SetState(int state) {
        // Make sure the bar window isn't left hidden from a previous full-hide.
        IntPtr tray = FindWindow("Shell_TrayWnd", null);
        if (tray != IntPtr.Zero) ShowWindow(tray, SW_SHOW);
        var d = new APPBARDATA();
        d.cbSize = (uint)Marshal.SizeOf(d);
        d.hWnd = tray;
        d.lParam = (IntPtr)state;
        SHAppBarMessage(ABM_SETSTATE, ref d);
    }
}
'@
if (-not ('TB' -as [type])) { Add-Type -TypeDefinition $sig }

if ($Action -eq 'toggle') {
    $isAuto = ([TB]::GetState() -band [TB]::ABS_AUTOHIDE) -ne 0
    $Action = if ($isAuto) { 'show' } else { 'autohide' }
}

if ($Action -eq 'autohide') {
    [TB]::SetState([TB]::ABS_AUTOHIDE)
} else {
    [TB]::SetState([TB]::ABS_ALWAYSONTOP)
}
