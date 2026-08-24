$ErrorActionPreference = 'Stop'

$command = Get-Command TOTALCMD64.EXE, TOTALCMD.EXE -ErrorAction SilentlyContinue |
    Select-Object -First 1

$registryInstallDirs = @(
    (Get-ItemPropertyValue 'HKCU:\SOFTWARE\Ghisler\Total Commander' -Name InstallDir -ErrorAction SilentlyContinue)
    (Get-ItemPropertyValue 'HKLM:\SOFTWARE\Ghisler\Total Commander' -Name InstallDir -ErrorAction SilentlyContinue)
    (Get-ItemPropertyValue 'HKLM:\SOFTWARE\WOW6432Node\Ghisler\Total Commander' -Name InstallDir -ErrorAction SilentlyContinue)
) | Where-Object { $_ }

$candidates = @(
    $(if ($command) { $command.Source })
    $($registryInstallDirs | ForEach-Object { Join-Path $_ 'TOTALCMD64.EXE' })
    $($registryInstallDirs | ForEach-Object { Join-Path $_ 'TOTALCMD.EXE' })
    (Join-Path $env:ProgramFiles 'totalcmd\TOTALCMD64.EXE')
    $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'totalcmd\TOTALCMD.EXE' })
    'C:\totalcmd\TOTALCMD64.EXE'
    'C:\totalcmd\TOTALCMD.EXE'
) | Where-Object { $_ }

$executable = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $executable) {
    throw 'Total Commander was not found. Run install.ps1 from the glazewm-config repository.'
}

# /O activates an existing instance instead of opening duplicates.
Start-Process -FilePath $executable -ArgumentList '/O'
