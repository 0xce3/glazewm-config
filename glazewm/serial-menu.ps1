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
    Write-Host '  (beenden: Strg+C)' -ForegroundColor $DimColor
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

    try {
        $sp.Open()
        while ($sp.IsOpen) {
            # Drain whatever the device has sent and print it (Latin-1 -> UTF-8).
            $chunk = $sp.ReadExisting()
            if ($chunk.Length -gt 0) { [Console]::Write($chunk) }

            # Forward keystrokes to the device; Ctrl+C ends the session.
            while ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                if (($k.Modifiers -band [ConsoleModifiers]::Control) -and $k.Key -eq [ConsoleKey]::C) {
                    $sp.Close()
                    break
                }
                if ($k.KeyChar) { $sp.Write([string]$k.KeyChar) }
            }

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
