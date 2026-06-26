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

    function Get-ViewHeight { [Math]::Max(1, [Console]::WindowHeight - 1) }
    function Get-Bottom([int]$count) { [Math]::Max(0, $count - (Get-ViewHeight)) }

    # Render the scroll-mode frame from the buffer starting at line $topIdx.
    function Draw-Scroll($buf, [int]$topIdx, [char]$esc) {
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
                [void]$sb.Append($line)
            }
            [void]$sb.Append("$esc[0m`r`n")
        }
        $last = [Math]::Min($topIdx + $h, $count)
        [void]$sb.Append(("$esc[7m -- SCROLL --  {0}-{1}/{2}   j/k  PgUp/PgDn  Ctrl+U/D  gg/G  q=live $esc[0m" -f ($topIdx + 1), $last, $count))
        [Console]::Write($sb.ToString())
    }

    # Leave scroll mode: redraw the tail of the buffer and resume live output.
    function Restore-Live($buf, [char]$esc, [string]$partial) {
        $h = Get-ViewHeight
        $start = [Math]::Max(0, $buf.Count - $h)
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append("$esc[H$esc[2J")
        for ($i = $start; $i -lt $buf.Count; $i++) { [void]$sb.Append($buf[$i]); [void]$sb.Append("`r`n") }
        if ($partial) { [void]$sb.Append($partial) }
        [Console]::Write($sb.ToString())
    }

    try {
        $sp.Open()
        while ($sp.IsOpen) {
            # Drain the device. Always buffer complete lines; print only in live.
            $chunk = $sp.ReadExisting()
            if ($chunk.Length -gt 0) {
                if (-not $scroll) { [Console]::Write($chunk) }
                $partial += $chunk
                while (($nl = $partial.IndexOf("`n")) -ge 0) {
                    [void]$buffer.Add($partial.Substring(0, $nl).TrimEnd("`r"))
                    $partial = $partial.Substring($nl + 1)
                }
                if ($buffer.Count -gt $maxLines) { $buffer.RemoveRange(0, $buffer.Count - $maxLines) }
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
                                }
                            }
                        }
                    }

                    if (-not $scroll) { Restore-Live $buffer $esc $partial }
                }
            }

            if ($scroll -and $needDraw) { Draw-Scroll $buffer $top $esc; $needDraw = $false }

            Start-Sleep -Milliseconds 5
        }
    } catch {
        Write-Host ''
        Write-Host ('  Fehler: {0}' -f $_.Exception.Message) -ForegroundColor $AccentColor
    } finally {
        if ($sp -and $sp.IsOpen) { $sp.Close() }
        $sp.Dispose()
        [Console]::TreatControlCAsInput = $false
    }

    Write-Host ''
    Write-Host ('  Verbindung zu {0} beendet.' -f $port) -ForegroundColor $AccentColor
    Write-Host '  [Enter] = zurueck zum Menue, Strg+D = Fenster schliessen' -ForegroundColor $DimColor
    [System.Console]::ReadKey($true) | Out-Null
}
