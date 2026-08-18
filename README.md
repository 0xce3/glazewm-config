# glazewm-config

My complete Windows tiling-WM setup — a keyboard-driven "embedded hacker" workflow
built around **GlazeWM**, **YASB**, and **Windows Terminal** (WSL + neovim).

Everything here lets me restore the whole environment on a fresh machine in one step.

## What's tracked

| Path | What it is | Restores to |
|------|------------|-------------|
| `glazewm/config.yaml` | GlazeWM window manager config (workspaces, keybinds, gaps, rules) | `~/.glzr/glazewm/config.yaml` |
| `glazewm/taskbar.ps1` | Hide/show/toggle the Windows taskbar | `~/.glzr/glazewm/taskbar.ps1` |
| `glazewm/yazi.ps1` | Locate and launch Yazi in Windows Terminal | `~/.glzr/glazewm/yazi.ps1` |
| `yazi/yazi.toml` | Open text, code, and image files with their Windows-associated app | `%APPDATA%/yazi/config/yazi.toml` |
| `yazi/keymap.toml` | Quick jumps to Downloads, Documents, and WSL distributions | `%APPDATA%/yazi/config/keymap.toml` |
| `yasb/config.yaml` | YASB status bar layout | `~/.config/yasb/config.yaml` |
| `yasb/styles.css` | YASB Gruvbox Soft Dark theme | `~/.config/yasb/styles.css` |
| `yasb/gruvbox-picker.ps1` | Shared Gruvbox searchable selection dialog | `~/.config/yasb/gruvbox-picker.ps1` |
| `yasb/jlink-control.py` | Headless J-Link server controller for YASB | `~/.config/yasb/jlink-control.py` |
| `windows-terminal/settings.json` | Sanitized Windows Terminal reference template (never deployed automatically) | Manual reference only |
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
- [Yazi](https://github.com/sxyazi/yazi) — terminal file manager for workspace 9 (`install.ps1` installs it, fzf, 7-Zip archive support, and Git's `file.exe` MIME detection)
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
`install.ps1` intentionally leaves all Windows Terminal profiles, defaults, and
machine-local settings untouched.

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

The right side of YASB contains a single `J` icon when SEGGER J-Link is
installed. It is green while a Remote Server client is connected and gray
otherwise. Left click toggles the Remote Server; right click restarts it.

Status is refreshed every second by reading the Windows TCP table without
connecting to the server itself. The executable is discovered from `PATH`,
standard SEGGER installation folders, or `JLINK_BIN`. `JLINK_LOG_DIR` can
override the default log directory.

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
| `Alt+Shift+Y` | Yazi file manager (workspace 9) |
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
- **Monitor 1 (comms):** `5:teams` · `6:slack` · `7:mail` · `8:misc` · `9:files` (Explorer/Yazi)
