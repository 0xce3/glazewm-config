param([switch]$Run)

$ErrorActionPreference = 'Stop'

$yaziCommand = Get-Command yazi.exe -ErrorAction SilentlyContinue
$yaziPath = if ($yaziCommand) { $yaziCommand.Source } else { $null }

if (-not $yaziPath) {
    $packageRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    $yaziPath = Get-ChildItem $packageRoot -Filter yazi.exe -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object FullName -Like '*\sxyazi.yazi_*' |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

if (-not $yaziPath) {
    throw 'Yazi was not found. Run install.ps1 from the glazewm-config repository.'
}

if ($Run) {
    # WinGet package directories are not always visible to terminal processes
    # that were already running when a package was installed.
    $fzf = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages') `
        -Filter fzf.exe -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object FullName -Like '*\junegunn.fzf_*' |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName

    if ($fzf) {
        $env:PATH = (Split-Path $fzf -Parent) + [IO.Path]::PathSeparator + $env:PATH
    }

    # 7-Zip's WinGet/standard installer does not always add itself to PATH,
    # while Yazi expects to find either 7zz.exe or 7z.exe for archive previews.
    $sevenZip = @(
        (Join-Path $env:ProgramFiles '7-Zip\7z.exe')
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe' })
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

    if ($sevenZip) {
        $env:PATH = (Split-Path $sevenZip -Parent) + [IO.Path]::PathSeparator + $env:PATH
    }

    & $yaziPath
    exit $LASTEXITCODE
}

# Start the inner runner in the new terminal so its PATH changes apply even
# when Windows Terminal is reusing an already-running server process.
& wt.exe new-tab --title YAZI powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Run
