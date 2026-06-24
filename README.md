# glazewm-config

My complete Windows tiling-WM setup — a keyboard-driven "embedded hacker" workflow
built around **GlazeWM**, **YASB**, and **Windows Terminal** (WSL + neovim).

Everything here lets me restore the whole environment on a fresh machine in one step.

## What's tracked

| Path | What it is | Restores to |
|------|------------|-------------|
| `glazewm/config.yaml` | GlazeWM window manager config (workspaces, keybinds, gaps, rules) | `~/.glzr/glazewm/config.yaml` |
| `glazewm/serial-menu.ps1` | Curses-style serial console launcher (plink, port/baud picker) | `~/.glzr/glazewm/serial-menu.ps1` |
| `glazewm/taskbar.ps1` | Hide/show/toggle the Windows taskbar | `~/.glzr/glazewm/taskbar.ps1` |
| `glazewm/focus-app.ps1` | Raise Teams (meeting) + fullscreen overlay on the current monitor | `~/.glzr/glazewm/focus-app.ps1` |
| `yasb/config.yaml` | YASB status bar layout | `~/.config/yasb/config.yaml` |
| `yasb/styles.css` | YASB Gruvbox Soft Dark theme | `~/.config/yasb/styles.css` |
| `windows-terminal/settings.json` | Windows Terminal profiles + Gruvbox schemes | `…/WindowsTerminal_*/LocalState/settings.json` |
| `translucenttb/settings.json` | TranslucentTB config (fully transparent taskbar) | `…/TranslucentTB_*/RoamingState/settings.json` |
| `flowlauncher/Themes/Gruvbox Soft Dark.xaml` | Flow Launcher Gruvbox theme (floating app launcher) | `%APPDATA%/FlowLauncher/Themes/` |

## Theme

Gruvbox Soft Dark throughout. Focused window border = Gruvbox orange (`#fe8019`),
85% window transparency, floating YASB bar that matches the window gaps.

## Dependencies

- [GlazeWM](https://github.com/glzr-io/glazewm)
- [YASB](https://github.com/amnweb/yasb) — `winget install AmN.yasb`
- [Windows Terminal](https://github.com/microsoft/terminal)
- [TranslucentTB](https://github.com/TranslucentTB/TranslucentTB) — `winget install CharlesMilette.TranslucentTB` (transparent taskbar; `install.ps1` handles it)
- [Flow Launcher](https://github.com/Flow-Launcher/Flow.Launcher) — `winget install Flow-Launcher.Flow-Launcher` (floating launcher on the Windows key; `install.ps1` applies the Gruvbox theme)
- [PuTTY](https://www.putty.org/) (for `plink`, used by the serial console) — `winget install PuTTY.PuTTY`
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
| `Alt+M` | Teams (meeting) fullscreen overlay on your current monitor |
| `Alt+Shift+X` | Snip overlay |
| `Alt+Shift+C` | Snipping Tool app |
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
