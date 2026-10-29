#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidatePattern('^(main|[a-fA-F0-9]{40})$')][string]$Revision = 'main'
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$headers = @{ 'User-Agent' = 'glazewm-config-bootstrap' }
if ($Revision -eq 'main') {
    $commit = Invoke-RestMethod 'https://api.github.com/repos/0xce3/glazewm-config/commits/main' -Headers $headers
    $Revision = $commit.sha
}
if ($Revision -notmatch '^[a-fA-F0-9]{40}$') { throw 'GitHub did not return a valid commit SHA.' }
Write-Host "Source: https://github.com/0xce3/glazewm-config/tree/$Revision"
if ((Read-Host 'Download this public revision and run its interactive installer? [j/N]') -notmatch '^(?i:j|ja|y|yes)$') {
    return
}
$id = [guid]::NewGuid().ToString('N')
$temporary = Join-Path ([IO.Path]::GetTempPath()) "glazewm-setup-$id"
$sourceRoot = Join-Path $env:LOCALAPPDATA 'glazewm-config\source'
$destination = Join-Path $sourceRoot "$Revision-$id"
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    $archive = Join-Path $temporary 'source.zip'
    Invoke-WebRequest "https://codeload.github.com/0xce3/glazewm-config/zip/$Revision" -Headers $headers -UseBasicParsing -OutFile $archive
    Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $temporary 'expanded')
    $source = Join-Path $temporary "expanded\glazewm-config-$Revision"
    if (-not (Test-Path -LiteralPath (Join-Path $source 'install.ps1'))) { throw 'Archive has no installer.' }
    New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
    Move-Item -LiteralPath $source -Destination $destination
    Write-Host "Retained installer source: $destination"
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $destination 'install.ps1')
    if ($LASTEXITCODE -ne 0) { throw "Installer failed ($LASTEXITCODE). Fix the reported problem and rerun install.ps1 from the retained source." }
}
finally {
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
