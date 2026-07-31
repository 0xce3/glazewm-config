# glazewm-config

My complete Windows tiling-WM setup — a keyboard-driven "embedded hacker" workflow
built around **GlazeWM**, **YASB**, and **Windows Terminal** (WSL + neovim).

Everything here lets me restore the whole environment on a fresh machine in one step.

## What's tracked

| Path | What it is | Restores to |
|------|------------|-------------|
| `glazewm/config.yaml` | GlazeWM window manager config (workspaces, keybinds, gaps, rules) | `~/.glzr/glazewm/config.yaml` |
| `glazewm/taskbar.ps1` | Hide/show/toggle the Windows taskbar | `~/.glzr/glazewm/taskbar.ps1` |
| `yasb/config.yaml` | YASB status bar layout | `~/.config/yasb/config.yaml` |
| `yasb/styles.css` | YASB Gruvbox Soft Dark theme | `~/.config/yasb/styles.css` |
| `yasb/gruvbox-picker.ps1` | Shared Gruvbox searchable selection dialog | `~/.config/yasb/gruvbox-picker.ps1` |
| `yasb/jlink-control.py` | Headless J-Link server controller for YASB | `~/.config/yasb/jlink-control.py` |
| `yasb/jlink-target-picker.ps1` | Searchable GDB target picker for YASB | `~/.config/yasb/jlink-target-picker.ps1` |
| `windows-terminal/settings.json` | Windows Terminal profiles + Gruvbox schemes | `…/WindowsTerminal_*/LocalState/settings.json` |
| `translucenttb/settings.json` | TranslucentTB config (fully transparent taskbar) | `…/TranslucentTB_*/RoamingState/settings.json` |
| `flowlauncher/Themes/Gruvbox Soft Dark.xaml` | Flow Launcher Gruvbox theme (floating app launcher) | `%APPDATA%/FlowLauncher/Themes/` |

## Theme

Gruvbox Soft Dark throughout. Focused window border = Gruvbox orange (`#fe8019`),
opaque application windows, and a floating YASB bar that matches the window gaps.

## Dependencies

- [GlazeWM](https://github.com/glzr-io/glazewm)
- [YASB](https://github.com/amnweb/yasb) — `winget install AmN.yasb`
- [Windows Terminal](https://github.com/microsoft/terminal)
- [TranslucentTB](https://github.com/TranslucentTB/TranslucentTB) — `winget install CharlesMilette.TranslucentTB` (transparent taskbar; `install.ps1` handles it)
- [Flow Launcher](https://github.com/Flow-Launcher/Flow.Launcher) — `winget install Flow-Launcher.Flow-Launcher` (floating launcher on the Windows key; `install.ps1` applies the Gruvbox theme)
- [SEGGER J-Link Software](https://www.segger.com/downloads/jlink/) (optional, for the J-Link manager)
- [Python 3.9+](https://www.python.org/downloads/) and pySerial (for miniterm)
- WSL (Ubuntu) + [my neovim config](https://github.com/0xce3/nvim-config)
- JetBrainsMono Nerd Font

## Restore on a new machine

```powershell
git clone https://github.com/0xce3/glazewm-config
cd glazewm-config
# Review install.ps1, then run it (copies files to their locations):
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Then start GlazeWM and YASB. Reload GlazeWM config with `Alt+Shift+R`.

## Serial monitor

Open the Windows Terminal `Serial` profile or run:

```powershell
powershell.exe -NoLogo -NoProfile -Command "$baud = Read-Host 'Baud rate [115200]'; if ([string]::IsNullOrWhiteSpace($baud)) { $baud = 115200 }; py -m serial.tools.miniterm - $baud --encoding utf-8 --filter direct --eol CRLF --dtr 1 --rts 1 --exit-char 17"
```

Enter a baud rate or press Enter to accept 115200. Miniterm's built-in prompt
then lists the available COM ports. It uses 8N1, UTF-8 and CRLF. The `direct`
filter passes firmware ANSI sequences through to Windows Terminal instead of
displaying them as text.
Press `Ctrl+T`, then `B` to change the baud rate, `Ctrl+T` for the other
built-in menu commands, or `Ctrl+Q` to quit.

## J-Link manager

The right side of YASB contains a compact J-Link status and control group:

- The status shows `Off`, `Remote`, `GDB`, or `R+G`.
- Click the `J` before the status to open a native YASB popup with separate
  start, stop, and restart actions for the Remote and GDB servers. Starting GDB
  opens the searchable target picker. A final action stops all local J-Link
  servers.

Status is refreshed every second. `Active` indicates that a real Remote client
is connected; the check reads the Windows TCP table and does not connect to the
server itself. Server processes survive YASB reloads,
and the selected GDB target is remembered in the user's application-data
directory. Executables are discovered from `PATH`, standard SEGGER installation
folders, or `JLINK_BIN`; no machine-specific paths are stored in the repo.

The equivalent environment variables are `JLINK_BIN`, `JLINK_DEVICE`,
`JLINK_INTERFACE`, `JLINK_SPEED`, `JLINK_GDB_PORT`, `JLINK_REMOTE_PORT`, and
`JLINK_LOG_DIR`.

## Keep the repo up to date

After changing any live config, pull the changes back into the repo and push:

```powershell
powershell -ExecutionPolicy Bypass -File .\sync.ps1
powershell -ExecutionPolicy Bypass -File .\sync.ps1 "describe the change"
```

`sync.ps1` copies the live files into the repo, commits, and pushes — one command.

## Key bindings (quick reference)

| Key | Action |
|-----|--------|
| `Alt+H/J/K/L` | Focus left/down/up/right (Vim) |
| `Alt+Shift+H/J/K/L` | Move window |
| `Alt+1..9` | Focus workspace |
| `Alt+Shift+1..9` | Move window to workspace |
| `Alt+Tab` | Jump to last-used workspace |
| `Alt+Enter` | Windows Terminal |
| `Alt+Shift+Enter` | Chrome |
| `Alt+Shift+S` | Serial console |
| `Alt+Shift+X` | Snip overlay |
| `Alt+Shift+C` | Snipping Tool app |
| `Alt+Shift+M` | Swap the two main monitors (everything on 0 ↔ 1) |
| `Alt+Shift+T` | Toggle Windows taskbar |
| `Win` | Flow Launcher (floating app/search launcher) |
| `Alt+R` | Resize mode |
| `Alt+F` | Fullscreen |
| `Alt+Shift+R` | Reload GlazeWM config |

## Terminal scrolling & search (Windows Terminal)

Global Windows Terminal keybindings — useful for the serial console scrollback
(plain `PageUp` / `Ctrl+F` are intentionally left for Neovim/bash):

| Key | Action |
|-----|--------|
| `Shift+PageUp` / `Shift+PageDown` | Scroll output one page |
| `Ctrl+Shift+Up` / `Ctrl+Shift+Down` | Scroll output one line |
| `Ctrl+Shift+Home` / `Ctrl+Shift+End` | Scroll to top / bottom |
| `Ctrl+Shift+F` | Search in the output |

## Workspace layout

- **Monitor 0 (dev):** `1:term` · `2:code` · `3:web` · `4:serial`
- **Monitor 1 (comms):** `5:teams` · `6:slack` · `7:mail` · `8` · `9`
