# Portable Windows workflow

GlazeWM + YASB + Flow Launcher, Windows Terminal, JetBrainsMono Nerd Font
und TranslucentTB im Gruvbox Soft Dark Look. Oeffentliche Konfiguration,
keine Kopie eines Firmenrechners.

## Installation mit einem One-Liner

Voraussetzung: Windows 11, Windows PowerShell 5.1, Internet und funktionierendes
WinGet ([App Installer](https://apps.microsoft.com/detail/9nblggh4nns1)).
Im normalen Benutzerkonto ausfuehren, **nicht** als anderer Administrator.
Einzelne Paketinstaller koennen eine UAC-Bestaetigung benoetigen.

**Der One-Liner funktioniert mit dieser neuen Version erst, nachdem die
Aenderungen geprueft und nach `main` veroeffentlicht wurden.**

```powershell
$p = Join-Path $env:TEMP ("glazewm-bootstrap-" + [guid]::NewGuid() + ".ps1"); Invoke-WebRequest "https://raw.githubusercontent.com/0xce3/glazewm-config/main/bootstrap.ps1" -UseBasicParsing -OutFile $p; try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p; if ($LASTEXITCODE -ne 0) { throw "Setup failed: $LASTEXITCODE" } } finally { Remove-Item -LiteralPath $p -Force }
```

Das ist heruntergeladener Code: [Bootstrap](bootstrap.ps1) und
[Installer](install.ps1) vorab lesen. HTTPS und eine aufgeloeste Commit-ID sind
kein Ersatz fuer diese Pruefung. Der Bootstrap zeigt die konkrete Commit-ID,
fragt vor dem Download nach und behaelt die Quellen unter
`%LOCALAPPDATA%\glazewm-config\source\<commit>-<id>`.
Git ist zur Installation nicht erforderlich. Fuer einen bewusst ausgewaehlten
Stand den Bootstrap von der geprueften 40-stelligen Commit-ID herunterladen
und mit `-Revision <commit>` starten statt `main` zu verwenden.

Alternativ aus einem lokalen Checkout:

```powershell
# Vorschau: keine Installationen, Rueckfragen oder Schreibzugriffe
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -WhatIf
# Interaktive Installation
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
# Nur Konfiguration; Pakete sind schon vorhanden
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -SkipPackages
```

## Was passiert?

- Jedes Paket, jede Konfigurationsdatei und jeder Autostarteintrag wird
  **einzeln bestaetigt**. Enter bedeutet Nein; es gibt kein pauschales `-Force`.
- Installiert werden ausschliesslich `glzr-io.glazewm`, `AmN.yasb`,
  `Flow-Launcher.Flow-Launcher`, `Microsoft.WindowsTerminal`,
  `DEVCOM.JetBrainsMonoNerdFont` und `CharlesMilette.TranslucentTB`.
  Vorhandene Pakete werden nicht absichtlich aktualisiert; bei Fehlern wird
  abgebrochen, nicht still weitergemacht. WinGet prueft die Paketdownloads.
- Bestehende Dateien erhalten vor dem Schreiben eine eindeutige
  `.bak-<timestamp>-<id>`-Kopie direkt neben dem Original. Diese Backups koennen
  private Inhalte enthalten: nicht hochladen!
- GlazeWM/YASB/Flow/TranslucentTB muessen vor der Konfigurationsphase beendet
  sein. Das Skript beendet keine Prozesse. Startet ein Paketinstaller seine
  App automatisch, diese ueber das Tray beenden und mit `-SkipPackages` erneut
  ausfuehren. Ein Abbruch rollt bereits bestaetigte Schritte nicht zurueck.
- GlazeWM, YASB und TranslucentTB erhalten die oeffentlichen Dateien.
  Windows Terminal erhaelt die bereinigten Profile, Darstellung,
  Tastaturaktionen und globalen Einstellungen aus dem Export. Profile werden
  anhand ihrer GUID zusammengefuehrt; lokale Zusatzprofile bleiben erhalten.
  Das exportierte Standardprofil wird uebernommen, sofern es zu den
  exportierten Profilen gehoert. Bestaetigung und Backup erfolgen davor.
- Flow bekommt Theme, Dark Mode, `LWin` als Hotkey und ausgeschalteten Sound.
  Konten, Plugins und andere Einstellungen bleiben lokal. Fehlende
  Einstellungsdateien werden angelegt. JSONC-Kommentare werden beim
  Zusammenfuehren entfernt; das Original bleibt im Backup.
- Bestaetigte Startup-Verknuepfungen starten GlazeWM, Flow Launcher und
  TranslucentTB bei Anmeldung. GlazeWM startet YASB. Bestehende native
  Autostarteinstellungen werden nicht entfernt; bei doppelten Eintraegen
  selbst entscheiden, welcher bestehen bleibt. `-NoAutostart` ueberspringt
  die Verknuepfungen. Apps werden nicht sofort gestartet.

Nach der Installation ab-/anmelden oder die Apps manuell starten.
Bei abgelehnten Schritten ist die Einrichtung entsprechend unvollstaendig.
Bei Wiederholung entstehen keine doppelten verwalteten Verknuepfungen oder
Terminal-Farbschemata. Paketversionen sind nicht festgeschrieben; es wird kein
bitidentisches Windows-Abbild versprochen. Portable/Scoop-Installationen,
Terminal Preview und abweichende App-Datenpfade werden nicht automatisch erkannt.

## Dateien und Monitore

Die gemeinsame [Allowlist](setup/common.ps1) definiert Installation und Export:

| Quelle | Ziel |
|---|---|
| `glazewm/config.yaml`, Taskbar-/Layout-Helfer | `%USERPROFILE%\.glzr\glazewm` |
| `yasb/config.yaml`, `styles.css` | `%USERPROFILE%\.config\yasb` |
| Flow-Theme | `%APPDATA%\FlowLauncher\Themes` |
| TranslucentTB-Config | `%LOCALAPPDATA%\Packages\28017CharlesMilette.TranslucentTB_v826wp6bftszj\RoamingState` |
| Bereinigte Terminal-Profile und Einstellungen | Zusammenfuehrung in Stable-Store-/unpackaged-Einstellungen |

Installation und Export setzen Monitorbindungen auf **0**; lokale
Bildschirmindizes werden so nicht auf den neuen Rechner uebertragen.
Der portable Ausgangszustand nutzt fuer alle neun Workspaces **Monitor 0**,
also auch einen einzelnen Bildschirm. `Alt+Shift+Z` waehlt zwei Bildschirme
(Dev 0, Kommunikation/Utilities 1), `Alt+Shift+O` drei
(Dev 1, Kommunikation 0, Utilities 2). Nicht vorhandene Indizes fallen auf
den letzten angeschlossenen Bildschirm zurueck. `Alt+Shift+M` tauscht 0/1;
der dritte Bildschirm bleibt unveraendert. Die Anordnung ist eine lokale
Entscheidung, keine Eigenschaft des urspruenglichen Laptops.

## Nicht enthalten

Keine Firmen-/Kundenprojekte, internen Server, Benutzerpfade, VPNs,
Zertifikate, Zugangsdaten, Lizenzdateien, Konten oder Anmeldesitzungen.
Generische Teams-/Slack-/Outlook-Fensterregeln sind enthalten, die Apps selbst
werden nicht installiert.

Auch Chrome, VS Code, WSL/Ubuntu, Neovim und Python werden **nicht** installiert.
`Alt+Shift+Y` oeffnet Windows Explorer auf Workspace 9.
Die optionalen [pySerial-Anforderungen](glazewm/requirements-serial.txt)
bleiben als Referenz erhalten, werden aber nicht automatisch eingerichtet.
Das exportierte `Serial`-Profil benoetigt separat installiertes Python und
pySerial; `Alt+Shift+S` startet es. Die Ubuntu-Profile benoetigen die jeweils
passende WSL-Distribution. Auf diesem Stand ist Ubuntu 26.04 das
Terminal-Standardprofil: ohne diese Distribution nach dem Restore zunaechst
Windows PowerShell als Standardprofil auswaehlen oder Ubuntu separat einrichten.

Private Ergaenzungen ausserhalb des Repos aufbewahren. `local/`, `private/`,
`.env*`, `*.local.*`, gaengige private Schluessel, Backups und Logs sind
zusaetzlich ignoriert. Diese Ordner werden **nicht automatisch geladen**.
Die Ignore-Regeln schuetzen keine schon versionierten Dateien.

## Sicherer Export statt automatischem Push

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sync.ps1 -WhatIf
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sync.ps1
# Nur die bereinigten Terminal-Profile/Einstellungen aktualisieren:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sync.ps1 -TerminalOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\check-public.ps1
# Zusaetzlich erreichbare Branches, Tags, Remotes und HEAD untersuchen:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\check-public.ps1 -IncludeHistory
git diff
git diff --cached
```

Sync liest ausschliesslich die Allowlist und prueft **alle** gefundenen
Live-Dateien vor dem ersten Schreiben. Bei einem Musterfund wird der gesamte
Export abgebrochen. Jede Kopie braucht eine Bestaetigung. Es gibt **kein**
automatisches Staging, Commit oder Push. Flow-Einstellungen, Plugin-Daten,
Historien und private Ergaenzungen werden niemals exportiert.

### Bereinigtes Windows-Terminal-Backup

[windows-terminal/settings.json](windows-terminal/settings.json) enthaelt
bereits die bereinigten sechs Profile des aktuellen Setups, darunter Serial
und Ubuntu, Fontgroessen, Farben, Transparenz, Terminal-Optionen und
tmux-/Pane-Tastaturbelegungen. Es wird **kein vollstaendiges privates Backup**
erstellt. Der Terminal-Export wird auch beim normalen Sync angeboten.

Eine separate Allowlist erlaubt Standard-Shells, bekannte Ubuntu-Quellen,
WSL-Aufrufe ohne Shell-Kommandos und exakt den bekannten Serial-Aufruf.
WSL-Registrierungs-IDs werden ueber die lokale WSL-Registrierung in den
portablen Ubuntu-Distributionsnamen uebersetzt. Benutzerabhaengige
Startverzeichnisse werden durch `%USERPROFILE%` ersetzt. Profilnamen fuer
Windows-Shells werden vereinheitlicht. Umgebungsvariablen, Hintergrundbilder,
Dateipfad-Icons, eigene Start-/SSH-Kommandos und unbekannte Profile werden
nicht exportiert. Sichere Tastaturaktionen, Pane-Navigation und reine
Steuersequenzen duerfen mit; `sendInput` mit ausfuehrbarem Text nicht.
Ausgelassene Profile/Aktionen werden ohne private Werte gemeldet.
Die Standard-Neuer-Tab-Auswahl wird auf `remainingProfiles` normalisiert;
benutzerdefinierte Menueeintraege, Themes und Such-URLs sind nicht allgemein
freigegeben. Farbschemata werden gesondert uebernommen.

Auch das bereinigte Ergebnis wird vor dem Schreiben auf Datenschutzmuster
geprueft. Frei waehlbare Namen (z.B. Font, Farbschema, Aktions-ID) muessen
weiterhin im Diff auf Firmenbezug kontrolliert werden. Bei zwei gefundenen
Stable-Terminal-Konfigurationen bricht der Export ab statt eine zu raten.
Beim Restore werden nur exportierte Felder ueberschrieben; lokale
Zusatzprofile/-aktionen und nicht exportierte Einstellungen bleiben erhalten.

Die lokale Datenschutzpruefung untersucht Arbeitsbaum inkl. nicht ignorierter
neuer Dateien **und den Git-Index**. Sie meldet nur Datei, Zeile und
Musterkategorie, keine gefundenen Werte. Sie erkennt u.a. typische Tokens,
private Schluessel, Benutzerpfade, E-Mails, UNC-Freigaben, private IPv4-Adressen
und interne Hostnamen. Sie laedt **keine Inhalte zu einem Dienst hoch**.
Eine kleine CI-Pruefung fuehrt die gleichen Tests bei Push/PR aus; sie kann
die erstmalige Veroeffentlichung eines Secrets nicht verhindern.

**Musterpruefung ist keine Garantie.** Firmen-/Kundennamen, beliebige
Zugangsdaten oder interne Kommandos koennen unauffaellig aussehen. Vor jedem
Commit Diff und Index manuell pruefen. Vor einer ersten Veroeffentlichung auch
die Historie pruefen. Bei Treffern nicht einfach Warnungen abschalten:
Dateien lokal bereinigen, betroffene Secrets ggf. rotieren und eine etwaige
Historienbereinigung bewusst planen. Das Skript schreibt die Historie nicht um.
Commit-Nachrichten/-Metadaten, geloeschte/unerreichbare Git-Objekte, LFS-Inhalte
und Submodule werden nicht durch diese Inhaltspruefung abgedeckt.

## Wiederherstellung / Tests

Zum Rueckgaengigmachen Apps beenden und die passende `.bak-*`-Kopie ueber die
betroffene Datei zurueckkopieren. Neu angelegte Einstellungen oder
Startup-Verknuepfungen bei Bedarf einzeln entfernen. Installierte Apps bleiben
bestehen und koennen normal ueber Windows deinstalliert werden.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\setup.tests.ps1
```

Tests nutzen temporaere Verzeichnisse, eine simulierte GlazeWM-CLI und
lokal simulierte Bootstrap-Downloads. Auch Installationswiederholung,
Einzelbestaetigungen, Backups und der Export-Abbruch werden geprueft.
Sie installieren keine Pakete und veraendern keine Live-Einstellungen.
Eine echte Neuinstallation ist anschliessend auf einer separaten Windows-VM
zu testen, nicht auf dem Arbeitslaptop.

## Tastatur

| Tasten | Aktion |
|---|---|
| `Alt+H/J/K/L` | Fokus links/unten/oben/rechts |
| `Alt+Shift+H/J/K/L` | Fenster verschieben |
| `Alt+1..9` / `Alt+Shift+1..9` | Workspace fokussieren / Fenster verschieben |
| `Alt+Tab` | Letzter Workspace |
| `Alt+Enter` | Windows Terminal mit wiederhergestelltem Standardprofil |
| `Alt+Shift+Enter` | Chrome, falls lokal installiert |
| `Alt+Shift+Y` | Windows Explorer (Workspace 9) |
| `Alt+Shift+X/C` | Screenshot / Snipping Tool |
| `Alt+R` / `Alt+F` | Resize-Modus / Vollbild |
| `Alt+Shift+R` / `Alt+Shift+T` | GlazeWM neu laden / Taskbar umschalten |
| `Win` | Flow Launcher |
| `Shift+PageUp/PageDown` | Terminal seitenweise scrollen |
| `Ctrl+Shift+Pfeile` | Terminal-Panes vergroessern/verkleinern |
| `Ctrl+Up/Down` | Terminal-Pane-Fokus |
| `Ctrl+Left/Right` / `Ctrl+1..9` | tmux-Fenster wechseln (Steuersequenzen) |
| `Ctrl+Shift+Home/End` | Terminal Anfang/Ende |
| `Ctrl+Shift+F` | Terminal-Suche |

Workspaces: 1 Terminal, 2 Serial (optional), 3 Web, 4 Code,
5 Teams, 6 Slack, 7 Mail, 8 Misc, 9 Files.
