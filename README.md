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
- Existing files are backed up as `.bak-*`; restore these manually if needed.
- Close GlazeWM, YASB, Flow Launcher and TranslucentTB before applying configuration.
- Terminal profiles and settings are merged; additional local profiles are preserved.
- Startup is optional (`-NoAutostart`). Sign out/in or start the apps manually.

WSL, Python and other development tools are not installed. The default Terminal
profile requires **Ubuntu 26.04**; choose another default if unavailable.
The Serial profile requires Python and [pySerial](glazewm/requirements-serial.txt).

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
content before publishing. Keep private files and backups outside the repository.

## Tests

```powershell
.\tests\setup.tests.ps1
```

Tests use isolated fixtures without installing packages or changing live configuration.
