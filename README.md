# Windows Workflow

A keyboard-driven Windows setup with a consistent Gruvbox Soft Dark theme.

**Includes:** GlazeWM, YASB, Flow Launcher, Windows Terminal,
JetBrainsMono Nerd Font and TranslucentTB.

## Install

Requires Windows 11, PowerShell 5.1 and [WinGet](https://apps.microsoft.com/detail/9nblggh4nns1).
Run from your normal user account. Review the [bootstrap](bootstrap.ps1)
and [installer](install.ps1) before executing downloaded code.

```powershell
$p = Join-Path $env:TEMP ("glazewm-bootstrap-" + [guid]::NewGuid() + ".ps1"); Invoke-WebRequest "https://raw.githubusercontent.com/0xce3/glazewm-config/main/bootstrap.ps1" -UseBasicParsing -OutFile $p; try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p; if ($LASTEXITCODE -ne 0) { throw "Setup failed: $LASTEXITCODE" } } finally { Remove-Item -LiteralPath $p -Force }
```

From a local checkout:

```powershell
.\install.ps1 -WhatIf       # Preview
.\install.ps1               # Install interactively
.\install.ps1 -SkipPackages # Configure existing installations
```

- Every package, configuration change and startup entry requires confirmation.
- Approved configuration changes overwrite the existing files.
- Close GlazeWM, YASB, Flow Launcher and TranslucentTB before applying configuration.
- Terminal profiles and settings are merged; additional local profiles are preserved.
- Startup is optional (`-NoAutostart`). Sign out/in or start the apps manually.

Startup shortcut backups are stored in `%LOCALAPPDATA%\glazewm-config\backups\startup`,
not in the Startup folder. If an older installation causes “Open with” prompts
at sign-in, run `.\repair-startup.ps1`. It moves only installer-generated backup
files out of Startup, with confirmation; active shortcuts remain unchanged.

WSL, Python and other development tools are not installed. The default Terminal
profile requires **Ubuntu 26.04**; choose another default if unavailable.
The Serial profile requires Python and [pySerial](glazewm/requirements-serial.txt).

## Native Taskbar + Adaptive Islands

YASB now provides only Home and GlazeWM workspaces in a Gruvbox Adaptive Island
on the left. Windows supplies the centered application icons and the native
system tray, Quick Settings, notifications and clock on the right. TranslucentTB
keeps the taskbar background clear; the island retains the Gruvbox surface and
orange workspace selection. The former YASB status widgets are inactive.

An additional right-hand Adaptive Island appears on every display. Its visible
surface mirrors the current left island's width and corner radius; the background
matches the left island: Gruvbox Dark `#282828` at 90% opacity. It stays empty on
displays without a native taskbar.
The helper in [taskbar.ps1](glazewm/taskbar.ps1) makes right-hand islands
click-through and places them behind any overlapping native taskbar, while keeping
left-hand workspace bars in front. GlazeWM starts the helper on startup/reload and
signals it to stop on shutdown. Right-hand islands never reserve extra work area.
Their bar dimensions inherit the left bar's settings; the visible surface width
is set by `.tray-backdrop-widget` in [YASB stylesheet](yasb/styles.css).

Prerequisites:

- Use a YASB version supporting `style: adaptive` and its stylesheet properties
	(see [Adaptive bar style](https://github.com/amnweb/yasb/wiki/Styling#adaptive-bar-style)).
- Position the Windows taskbar at the **top**, with centered application icons,
	using the option available on your Windows build or your existing taskbar tool.
	This repository does not move the native taskbar or install shell modifications.
- Turn off Windows Widgets on the taskbar if its left-side button occupies the
	workspace area. The default layout uses the native taskbar on the primary
	display only; YASB reserves its own row on secondary displays.

To apply to an existing setup, close the managed apps, run
`.\install.ps1 -SkipPackages`, and approve the configuration copies. Start
TranslucentTB and GlazeWM again; GlazeWM starts YASB and disables taskbar auto-hide.
Reloading GlazeWM alone does not run its startup commands.

Windows alone reserves the primary display's work area: `primary-bar` has
`windows_app_bar: false` to avoid an extra reserved row. `secondary-bar` uses
`windows_app_bar: true` on the other displays, where no native taskbar reserves
space. If you enable native taskbars there, set this flag to `false` as well.
The always-on-top islands occupy the left `40%` of each screen at a height of
`32` logical pixels, matching the native Small taskbar, and hide for fullscreen applications. GlazeWM's top outer
gap is `2px`, so tiled windows start just below the reserved row.
These are starting dimensions for the wide-screen layout, not automatic collision
detection. Adjust `dimensions.width` and `dimensions.height` in
[YASB configuration](yasb/config.yaml) for your display scaling and taskbar size.
Leave enough width for all workspace labels and enough clearance before the
native application icons; compact the workspace display names in
[GlazeWM configuration](glazewm/config.yaml) on smaller displays if needed.
Adaptive Islands shapes YASB's surface around its widgets; it neither embeds nor
repositions Windows controls, and transparent space inside its window should not
be relied on to pass clicks through to the taskbar.

## Shortcuts

| Shortcut | Action |
|---|---|
| `Alt+H/J/K/L` | Focus window |
| `Alt+Shift+H/J/K/L` | Move window |
| `Alt+1..9` / `Alt+Shift+1..9` | Switch workspace / move window to workspace |
| `Alt+Enter` | Terminal |
| `Win` | Flow Launcher |
| `Alt+Shift+Y` | File Explorer |
| `Alt+Shift+S` | Serial terminal |
| `Alt+Shift+R` | Reload GlazeWM |
| `Alt+Shift+Z/O` | Two-/three-monitor layout |
| `Alt+Shift+M` | Swap monitors 0 and 1 |

All workspaces initially use monitor 0. Layout shortcuts fall back to available monitors.
See [GlazeWM configuration](glazewm/config.yaml) for all bindings.

## Export configuration

```powershell
.\sync.ps1                       # Export allowlisted configuration
.\sync.ps1 -TerminalOnly         # Export sanitized Terminal settings only
.\check-public.ps1 -IncludeHistory
git diff
git diff --cached
```

Exports require confirmation and never commit or push automatically.
Terminal exports include approved profiles, appearance and keyboard actions;
machine-specific WSL IDs and start directories are normalized.
Unknown commands, environment variables and private application state are excluded.

Privacy checks are heuristic. Review every diff for credentials and company-specific
content before publishing. Keep private files outside the repository.

## Tests

```powershell
.\tests\setup.tests.ps1
```

Tests use isolated fixtures without installing packages or changing live configuration.
