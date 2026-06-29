# Serial terminal launcher with an interactive, curses-like TUI.
# Arrow keys to navigate, Enter to select. Uses plink (PuTTY) for a native
# Windows serial connection. ASCII-only for Windows PowerShell 5.1.

$ErrorActionPreference = 'Stop'

# Gruvbox-ish accent colors using console color names.
$AccentColor    = 'Yellow'
$HighlightFg    = 'Black'
$HighlightBg    = 'Yellow'
$DimColor       = 'DarkGray'
$TitleColor     = 'Green'

function Draw-Box {
    param([string]$Title, [string[]]$Lines)

    $width = 44
    $bar = ('=' * $width)
    Write-Host ''
    Write-Host ("  +{0}+" -f $bar) -ForegroundColor $AccentColor
    $pad = [Math]::Max(0, [int](($width - $Title.Length) / 2))
    $centered = (' ' * $pad) + $Title
    $centered = $centered.PadRight($width)
    Write-Host ("  |{0}|" -f $centered) -ForegroundColor $AccentColor
    Write-Host ("  +{0}+" -f $bar) -ForegroundColor $AccentColor
}

function Show-Menu {
    param(
        [string]   $Title,
        [string[]] $Items,
        [int]      $Default = 0,
        [string]   $Hint = 'Pfeiltasten = navigieren   Enter = waehlen   q = zurueck'
    )

    $index = $Default
    [System.Console]::CursorVisible = $false

    while ($true) {
        Clear-Host
        Draw-Box -Title $Title
        Write-Host ''

        for ($i = 0; $i -lt $Items.Count; $i++) {
            if ($i -eq $index) {
                Write-Host '   ' -NoNewline
                Write-Host (' > ' + $Items[$i] + ' ') -ForegroundColor $HighlightFg -BackgroundColor $HighlightBg
            } else {
                Write-Host ('     ' + $Items[$i]) -ForegroundColor Gray
            }
        }

        Write-Host ''
        Write-Host ("  $Hint") -ForegroundColor $DimColor

        $key = [System.Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'   { $index = ($index - 1 + $Items.Count) % $Items.Count }
            'DownArrow' { $index = ($index + 1) % $Items.Count }
            'Enter'     { [System.Console]::CursorVisible = $true; return $index }
            'Q'         { [System.Console]::CursorVisible = $true; return -1 }
            'Escape'    { [System.Console]::CursorVisible = $true; return -1 }
        }
    }
}

while ($true) {
    # --- Discover available COM ports ---
    $ports = @([System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object {
        [int]($_ -replace '\D', '')
    })

    if ($ports.Count -eq 0) {
        Clear-Host
        Draw-Box -Title 'SERIAL CONSOLE'
        Write-Host ''
        Write-Host '  Keine COM-Ports gefunden.' -ForegroundColor Red
        Write-Host '  Geraet anschliessen und [Enter] druecken (q = beenden)...' -ForegroundColor Red
        $k = [System.Console]::ReadKey($true)
        if ($k.Key -eq 'Q') { return }
        continue
    }

    # Friendly names where available.
    $friendly = @{}
    try {
        Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '\((COM\d+)\)' } |
            ForEach-Object {
                if ($_.Name -match '\((COM\d+)\)') { $friendly[$Matches[1]] = $_.Name }
            }
    } catch { }

    $portLabels = $ports | ForEach-Object {
        if ($friendly.ContainsKey($_)) { $friendly[$_] } else { $_ }
    }

    $pIdx = Show-Menu -Title 'SERIAL CONSOLE  --  PORT' -Items $portLabels -Default 0 `
        -Hint 'Pfeiltasten = navigieren   Enter = waehlen   q = beenden'
    if ($pIdx -lt 0) { return }
    $port = $ports[$pIdx]

    # --- Baudrate (115200 preselected) ---
    $common = @(9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600, 'Eigene Eingabe...')
    $defaultBaud = [Array]::IndexOf($common, 115200)

    $bIdx = Show-Menu -Title ("BAUDRATE  --  $port") -Items ($common | ForEach-Object { "$_" }) -Default $defaultBaud `
        -Hint 'Pfeiltasten = navigieren   Enter = waehlen   q = zurueck'
    if ($bIdx -lt 0) { continue }

    if ($common[$bIdx] -eq 'Eigene Eingabe...') {
        [System.Console]::CursorVisible = $true
        Write-Host ''
        $baud = Read-Host '  Baudrate eingeben'
        if ([string]::IsNullOrWhiteSpace($baud)) { $baud = 115200 }
    } else {
        $baud = $common[$bIdx]
    }

    # --- Connect ---
    Clear-Host
    Draw-Box -Title 'SERIAL CONSOLE'
    Write-Host ''
    Write-Host ("  Verbinde mit {0} @ {1} 8N1 ..." -f $port, $baud) -ForegroundColor $TitleColor
    Write-Host '  PgUp / Strg+Up = Scroll-Modus (j/k  PgUp/PgDn  gg/G  q=live)' -ForegroundColor $DimColor
    Write-Host '  Strg+C = beenden' -ForegroundColor $DimColor
    Write-Host ''

    # Open the serial port directly via .NET instead of plink. plink only pipes
    # raw bytes (no terminal emulation / charset translation), so 8-bit chars
    # like the degree sign (0xB0) that firmware sends as Latin-1 come out
    # garbled in the UTF-8 terminal. Here we decode the incoming bytes as
    # Latin-1 and let the console re-encode them as UTF-8, so they render right.
    # Change $SerialCharset to 'IBM437' (CP437) or 'Windows-1252' if needed.
    $SerialCharset = 'ISO-8859-1'

    [Console]::OutputEncoding   = [System.Text.Encoding]::UTF8
    [Console]::TreatControlCAsInput = $true

    $sp = New-Object System.IO.Ports.SerialPort($port, [int]$baud, `
        [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
    $sp.Handshake      = [System.IO.Ports.Handshake]::None
    $sp.Encoding       = [System.Text.Encoding]::GetEncoding($SerialCharset)
    $sp.ReadTimeout    = 50
    $sp.ReadBufferSize = 65536
    $sp.DtrEnable      = $true
    $sp.RtsEnable      = $true

    # Scrollback buffer (one entry per output line) so we can navigate history
    # with the keyboard. Live output is printed raw (ANSI preserved); a separate
    # "scroll mode" freezes the view and renders from this buffer.
    $esc      = [char]27
    $buffer   = New-Object 'System.Collections.Generic.List[string]'
    $maxLines = 50000
    $partial  = ''
    $scroll   = $false
    $top      = 0
    $pendingG = $false
    $needDraw = $false
    $pendingLive = ''   # output that arrives while in scroll mode (flushed on exit)
    $query    = ''                 # active search term in scroll mode
    $hits     = $null              # buffer line indices matching $query
    $matchIdx = 0                  # which match is currently selected

    function Get-ViewHeight { [Math]::Max(1, [Console]::WindowHeight - 1) }
    function Get-Bottom([int]$count) { [Math]::Max(0, $count - (Get-ViewHeight)) }

    # All buffer line indices that contain $q (case-insensitive).
    function Find-Matches($buf, [string]$q) {
        $res = New-Object System.Collections.Generic.List[int]
        if (-not [string]::IsNullOrEmpty($q)) {
            for ($i = 0; $i -lt $buf.Count; $i++) {
                if ($buf[$i].IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { [void]$res.Add($i) }
            }
        }
        return $res
    }

    # Scroll position that puts buffer line $line near the top of the view.
    function Get-TopForLine([int]$line, [int]$count) {
        [Math]::Min((Get-Bottom $count), [Math]::Max(0, $line - 2))
    }

    # Render the scroll-mode frame. $hlLine is highlighted (current search hit),
    # $status is the bottom bar text.
    function Draw-Scroll($buf, [int]$topIdx, [char]$esc, [string]$status, [int]$hlLine) {
        $h = Get-ViewHeight
        $w = [Math]::Max(1, [Console]::WindowWidth - 1)
        $count = $buf.Count
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append("$esc[H$esc[2J")
        for ($i = 0; $i -lt $h; $i++) {
            $idx = $topIdx + $i
            if ($idx -ge 0 -and $idx -lt $count) {
                $line = $buf[$idx]
                if ($line.Length -gt $w) { $line = $line.Substring(0, $w) }
                if ($idx -eq $hlLine) { [void]$sb.Append("$esc[7m$line$esc[0m") }
                else { [void]$sb.Append($line) }
            }
            [void]$sb.Append("$esc[0m`r`n")
        }
        [void]$sb.Append("$esc[7m $status $esc[0m")
        [Console]::Write($sb.ToString())
    }

    # Scroll mode runs on the alternate screen buffer (like less/vim): it has no
    # scrollback, so navigating never duplicates output into the live terminal.
    $altEnter = "$esc[?1049h$esc[?25l"   # enter alt screen + hide cursor
    $altLeave = "$esc[?25h$esc[?1049l"   # show cursor + leave alt screen (restores live)

    try {
        $sp.Open()
        while ($sp.IsOpen) {
            # Drain the device. Always buffer complete lines; print only in live.
            $chunk = $sp.ReadExisting()
            if ($chunk.Length -gt 0) {
                if (-not $scroll) { [Console]::Write($chunk) } else { $pendingLive += $chunk }
                $partial += $chunk

                # A clear-screen (e.g. the `clear` command -> ESC[2J / ESC[3J, or
                # a form feed) wipes the live screen, so wipe our scrollback too.
                if (($chunk -match "$esc\[[23]J") -or ($chunk.IndexOf([char]12) -ge 0)) {
                    $buffer.Clear(); $partial = ''
                    $hits = $null; $query = ''; $top = 0
                    if ($scroll) { $needDraw = $true }
                } else {
                    while (($nl = $partial.IndexOf("`n")) -ge 0) {
                        [void]$buffer.Add($partial.Substring(0, $nl).TrimEnd("`r"))
                        $partial = $partial.Substring($nl + 1)
                    }
                    if ($buffer.Count -gt $maxLines) { $buffer.RemoveRange(0, $buffer.Count - $maxLines) }
                }
            }

            while ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                $ctrl = ($k.Modifiers -band [ConsoleModifiers]::Control) -ne 0

                if ($ctrl -and $k.Key -eq [ConsoleKey]::C) { $sp.Close(); break }

                if (-not $scroll) {
                    # Live mode: PgUp / Ctrl+Up enter scroll mode; other printable
                    # keys go to the device (special keys have KeyChar = NUL).
                    if ($k.Key -eq [ConsoleKey]::PageUp -or ($ctrl -and $k.Key -eq [ConsoleKey]::UpArrow)) {
                        $scroll = $true
                        $pendingLive = ''
                        $query = ''; $hits = $null; $matchIdx = 0
                        [Console]::Write($altEnter)
                        $top = [Math]::Max(0, (Get-Bottom $buffer.Count) - (Get-ViewHeight))
                        $needDraw = $true
                    } elseif ($k.KeyChar -ne [char]0) {
                        $sp.Write([string]$k.KeyChar)
                    }
                } else {
                    # Scroll mode: vim-style navigation over the buffer.
                    $bottom = Get-Bottom $buffer.Count
                    $page = Get-ViewHeight
                    $half = [Math]::Max(1, [int]($page / 2))
                    $isG = ($k.KeyChar -eq 'g')
                    if (-not $isG) { $pendingG = $false }

                    switch ($k.Key) {
                        ([ConsoleKey]::Escape)   { $scroll = $false }
                        ([ConsoleKey]::PageUp)   { $top = [Math]::Max(0, $top - $page); $needDraw = $true }
                        ([ConsoleKey]::PageDown) { $top = [Math]::Min($bottom, $top + $page); $needDraw = $true }
                        ([ConsoleKey]::UpArrow)  { $top = [Math]::Max(0, $top - 1); $needDraw = $true }
                        ([ConsoleKey]::DownArrow){ $top = [Math]::Min($bottom, $top + 1); $needDraw = $true }
                        ([ConsoleKey]::Home)     { $top = 0; $needDraw = $true }
                        ([ConsoleKey]::End)      { $top = $bottom; $needDraw = $true }
                        default {
                            if ($ctrl -and $k.Key -eq [ConsoleKey]::U) { $top = [Math]::Max(0, $top - $half); $needDraw = $true }
                            elseif ($ctrl -and $k.Key -eq [ConsoleKey]::D) { $top = [Math]::Min($bottom, $top + $half); $needDraw = $true }
                            elseif ($ctrl -and $k.Key -eq [ConsoleKey]::B) { $top = [Math]::Max(0, $top - $page); $needDraw = $true }
                            elseif ($ctrl -and $k.Key -eq [ConsoleKey]::F) { $top = [Math]::Min($bottom, $top + $page); $needDraw = $true }
                            else {
                                switch ($k.KeyChar) {
                                    'k' { $top = [Math]::Max(0, $top - 1); $needDraw = $true }
                                    'j' { $top = [Math]::Min($bottom, $top + 1); $needDraw = $true }
                                    'G' { $top = $bottom; $needDraw = $true }
                                    'g' { if ($pendingG) { $top = 0; $pendingG = $false; $needDraw = $true } else { $pendingG = $true } }
                                    'q' { $scroll = $false }
                                    'i' { $scroll = $false }
                                    'n' {
                                        if ($hits -and $hits.Count -gt 0) {
                                            $matchIdx = ($matchIdx + 1) % $hits.Count
                                            $top = Get-TopForLine $hits[$matchIdx] $buffer.Count
                                            $needDraw = $true
                                        }
                                    }
                                    'N' {
                                        if ($hits -and $hits.Count -gt 0) {
                                            $matchIdx = ($matchIdx - 1 + $hits.Count) % $hits.Count
                                            $top = Get-TopForLine $hits[$matchIdx] $buffer.Count
                                            $needDraw = $true
                                        }
                                    }
                                    '/' {
                                        # Read a search term at the bottom bar (Enter=go, Esc=cancel).
                                        $q = ''
                                        $cur = if ($hits -and $hits.Count -gt 0) { $hits[$matchIdx] } else { -1 }
                                        while ($true) {
                                            Draw-Scroll $buffer $top $esc ("/$q   [Enter=suchen  Esc=abbrechen]") $cur
                                            $ik = [Console]::ReadKey($true)
                                            if ($ik.Key -eq [ConsoleKey]::Enter) { break }
                                            elseif ($ik.Key -eq [ConsoleKey]::Escape) { $q = $null; break }
                                            elseif ($ik.Key -eq [ConsoleKey]::Backspace) { if ($q.Length -gt 0) { $q = $q.Substring(0, $q.Length - 1) } }
                                            elseif ($ik.KeyChar -ne [char]0 -and -not [char]::IsControl($ik.KeyChar)) { $q += $ik.KeyChar }
                                        }
                                        if ($q) {
                                            $query = $q
                                            $hits = Find-Matches $buffer $query
                                            if ($hits.Count -gt 0) {
                                                $matchIdx = 0
                                                $top = Get-TopForLine $hits[0] $buffer.Count
                                            }
                                        }
                                        $needDraw = $true
                                    }
                                }
                            }
                        }
                    }

                    # Left scroll mode: drop back to the live screen (restored as
                    # it was) and flush whatever arrived while we were scrolling.
                    if (-not $scroll) {
                        [Console]::Write($altLeave)
                        if ($pendingLive) { [Console]::Write($pendingLive); $pendingLive = '' }
                    }
                }
            }

            if ($scroll -and $needDraw) {
                $count = $buffer.Count
                $hl = -1
                if ($query -and $hits -and $hits.Count -gt 0) {
                    $status = ("/{0}   Treffer {1}/{2}   n/N=naechster/vorh.  /=neu  q=live" -f $query, ($matchIdx + 1), $hits.Count)
                    $hl = $hits[$matchIdx]
                } elseif ($query) {
                    $status = "/$query   kein Treffer   /=neu  q=live"
                } else {
                    $last = [Math]::Min($top + (Get-ViewHeight), $count)
                    $status = ("-- SCROLL --  {0}-{1}/{2}   j/k PgUp/PgDn Ctrl+U/D gg/G  /=Suche  q=live" -f ($top + 1), $last, $count)
                }
                Draw-Scroll $buffer $top $esc $status $hl
                $needDraw = $false
            }

            Start-Sleep -Milliseconds 5
        }
    } catch {
        Write-Host ''
        Write-Host ('  Fehler: {0}' -f $_.Exception.Message) -ForegroundColor $AccentColor
    } finally {
        if ($scroll) { [Console]::Write($altLeave) }   # never leave the alt screen on
        if ($sp -and $sp.IsOpen) { $sp.Close() }
        $sp.Dispose()
        [Console]::TreatControlCAsInput = $false
    }

    Write-Host ''
    Write-Host ('  Verbindung zu {0} beendet.' -f $port) -ForegroundColor $AccentColor
    Write-Host '  [Enter] = zurueck zum Menue, Strg+D = Fenster schliessen' -ForegroundColor $DimColor
    [System.Console]::ReadKey($true) | Out-Null
}
