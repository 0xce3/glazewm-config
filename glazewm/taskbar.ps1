# Toggle the Windows taskbar between auto-hide and always-visible.
#
# auto-hide: the taskbar slides away but reappears on hover at the
# screen edge AND when the Windows key / Start is pressed. This is the native
# Windows "Automatically hide the taskbar" behaviour, set via the appbar API
# so it applies instantly (no Explorer restart).
#
# Usage:
#   powershell -File taskbar.ps1 autohide   # enable auto-hide
#   powershell -File taskbar.ps1 show       # always visible
#   powershell -File taskbar.ps1 toggle     # flip current state

param([ValidateSet('autohide', 'show', 'toggle', 'frontmost', 'stop-frontmost')][string]$Action = 'show')

$sig = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
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
public static class YasbFrontmost {
    private delegate bool WindowCallback(IntPtr window, IntPtr parameter);
    private delegate void EventCallback(IntPtr hook, uint eventType, IntPtr window, int objectId, int childId, uint threadId, uint time);
    [StructLayout(LayoutKind.Sequential)]
    private struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    private struct MonitorInfo { public int Size; public Rect Monitor, Work; public uint Flags; }
    [DllImport("user32.dll")] private static extern bool EnumWindows(WindowCallback callback, IntPtr parameter);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr window, StringBuilder text, int count);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr window, StringBuilder text, int count);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] private static extern int GetWindowLong(IntPtr window, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongW")] private static extern int SetWindowLong(IntPtr window, int index, int value);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr window, IntPtr after, int left, int top, int width, int height, uint flags);
    [DllImport("user32.dll")] private static extern IntPtr SetWinEventHook(uint first, uint last, IntPtr module, EventCallback callback, uint processId, uint threadId, uint flags);
    [DllImport("user32.dll")] private static extern bool UnhookWinEvent(IntPtr hook);
    private static readonly string Name = "Local\\GlazeWM.YasbFrontmost." + Process.GetCurrentProcess().SessionId;
    private static bool repairing;

    private static bool IsTaskbar(IntPtr window) {
        var className = new StringBuilder(128);
        GetClassName(window, className, className.Capacity);
        return className.ToString() == "Shell_TrayWnd" || className.ToString() == "Shell_SecondaryTrayWnd";
    }

    private static bool IsBar(IntPtr window) {
        var title = new StringBuilder(128);
        GetWindowText(window, title, title.Capacity);
        if (title.ToString() != "YasbBar") return false;
        uint processId;
        GetWindowThreadProcessId(window, out processId);
        try {
            using (var process = Process.GetProcessById((int)processId)) {
                return process.ProcessName.Equals("yasb", StringComparison.OrdinalIgnoreCase);
            }
        } catch (ArgumentException) { return false; }
        catch (InvalidOperationException) { return false; }
        catch (System.ComponentModel.Win32Exception) { return false; }
    }

    public static bool IsTrayBackdrop(int barLeft, int barRight, int trayLeft, int trayRight) {
        return barLeft + (barRight - barLeft) / 2 > trayLeft + (trayRight - trayLeft) / 2;
    }

    public static void Repair() {
        if (repairing) return;
        repairing = true;
        try {
            var windows = new List<IntPtr>();
            EnumWindows(delegate(IntPtr window, IntPtr parameter) {
                if (IsWindowVisible(window)) windows.Add(window);
                return true;
            }, IntPtr.Zero);
            foreach (IntPtr bar in windows) {
                if (!IsBar(bar)) continue;
                Rect barRect;
                var monitor = new MonitorInfo();
                monitor.Size = Marshal.SizeOf(monitor);
                if (!GetWindowRect(bar, out barRect) || !GetMonitorInfo(MonitorFromWindow(bar, 2), ref monitor)) continue;
                if (!IsTrayBackdrop(barRect.Left, barRect.Right, monitor.Monitor.Left, monitor.Monitor.Right)) continue;
                int style = GetWindowLong(bar, -20);
                int backdropStyle = style | 0x08000020;
                if (style != backdropStyle) {
                    SetWindowLong(bar, -20, backdropStyle);
                    SetWindowPos(bar, IntPtr.Zero, 0, 0, 0, 0, 0x0237);
                }
            }
            for (int trayIndex = 0; trayIndex < windows.Count; trayIndex++) {
                if (!IsTaskbar(windows[trayIndex])) continue;
                Rect trayRect;
                if (!GetWindowRect(windows[trayIndex], out trayRect)) continue;
                for (int barIndex = 0; barIndex < windows.Count; barIndex++) {
                    IntPtr bar = windows[barIndex];
                    if (!IsBar(bar)) continue;
                    Rect barRect;
                    if (!GetWindowRect(bar, out barRect)) continue;
                    if (barRect.Left >= trayRect.Right || barRect.Right <= trayRect.Left ||
                        barRect.Top >= trayRect.Bottom || barRect.Bottom <= trayRect.Top) continue;
                    if (IsTrayBackdrop(barRect.Left, barRect.Right, trayRect.Left, trayRect.Right)) {
                        if (barIndex != trayIndex + 1)
                            SetWindowPos(bar, windows[trayIndex], 0, 0, 0, 0, 0x0233);
                        continue;
                    }
                    if (barIndex < trayIndex) continue;
                    IntPtr after = trayIndex == 0 ? new IntPtr(-1) : windows[trayIndex - 1];
                    SetWindowPos(bar, after, 0, 0, 0, 0, 0x0213);
                }
            }
        } finally { repairing = false; }
    }

    public static void Stop() {
        try {
            using (var signal = EventWaitHandle.OpenExisting(Name + ".Stop")) { signal.Set(); }
        } catch (WaitHandleCannotBeOpenedException) { }
    }

    public static void Run() {
        using (var mutex = new Mutex(false, Name)) {
            bool acquired;
            try { acquired = mutex.WaitOne(0); } catch (AbandonedMutexException) { acquired = true; }
            if (!acquired) return;
            try {
                using (var signal = new EventWaitHandle(false, EventResetMode.ManualReset, Name + ".Stop"))
                using (var timer = new System.Windows.Forms.Timer())
                using (var context = new System.Windows.Forms.ApplicationContext()) {
                    EventCallback callback = delegate(IntPtr hook, uint eventType, IntPtr window, int objectId, int childId, uint threadId, uint time) {
                        if (window != IntPtr.Zero && objectId == 0 && (IsTaskbar(window) || IsBar(window))) Repair();
                    };
                    IntPtr foreground = SetWinEventHook(3, 3, IntPtr.Zero, callback, 0, 0, 0);
                    IntPtr reorder = SetWinEventHook(0x8002, 0x8004, IntPtr.Zero, callback, 0, 0, 0);
                    try {
                        timer.Interval = 500;
                        timer.Tick += delegate {
                            if (signal.WaitOne(0)) context.ExitThread();
                            else Repair();
                        };
                        Repair();
                        timer.Start();
                        System.Windows.Forms.Application.Run(context);
                    } finally {
                        timer.Stop();
                        if (foreground != IntPtr.Zero) UnhookWinEvent(foreground);
                        if (reorder != IntPtr.Zero) UnhookWinEvent(reorder);
                        GC.KeepAlive(callback);
                    }
                }
            } finally { mutex.ReleaseMutex(); }
        }
    }
}
'@
if (-not ('YasbFrontmost' -as [type])) {
    Add-Type -TypeDefinition $sig -ReferencedAssemblies System, System.Windows.Forms
}

if ($Action -eq 'frontmost') {
    [YasbFrontmost]::Run()
    return
}
if ($Action -eq 'stop-frontmost') {
    [YasbFrontmost]::Stop()
    return
}

if ($Action -eq 'toggle') {
    $isAuto = ([TB]::GetState() -band [TB]::ABS_AUTOHIDE) -ne 0
    $Action = if ($isAuto) { 'show' } else { 'autohide' }
}

if ($Action -eq 'autohide') {
    [TB]::SetState([TB]::ABS_AUTOHIDE)
} else {
    [TB]::SetState([TB]::ABS_ALWAYSONTOP)
}
