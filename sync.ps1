#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param([switch]$TerminalOnly)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'setup\common.ps1')

# Validate the entire export before changing any repository file.
$pending = @(
    $map = if ($TerminalOnly) { @() } else { @(Get-ConfigMap) }
    foreach ($item in $map) {
        if (-not (Test-Path -LiteralPath $item.Live)) {
            Write-Warning "Missing live config, not exported: $($item.Repo)"
            continue
        }
        $content = [IO.File]::ReadAllText($item.Live)
        Assert-PublicContent -Content $content -Label $item.Repo
        $content = ConvertTo-PortableConfig $item.Repo $content
        [pscustomobject]@{ Repo = $item.Repo; Content = $content }
    }
    $terminalPaths = @(Get-TerminalPaths | Where-Object { Test-Path -LiteralPath $_ })
    if ($terminalPaths.Count -gt 1) { throw 'Multiple Stable Terminal settings files found. Select/consolidate the intended installation locally before exporting.' }
    if ($terminalPaths.Count -eq 1) {
        $terminal = ConvertTo-PublicTerminalSettings (Read-JsonConfig $terminalPaths[0])
        [pscustomobject]@{ Repo = 'windows-terminal\settings.json'; Content = ($terminal | ConvertTo-Json -Depth 100) }
    } else { Write-Warning 'No Windows Terminal settings found; public template unchanged.' }
)
foreach ($item in $pending) {
    $destination = Join-Path $PSScriptRoot $item.Repo
    if ($PSCmdlet.ShouldProcess($item.Repo, 'Export public config') -and
        (Read-Host "Export $($item.Repo)? Review for work-specific content afterwards [j/N]") -match '^(?i:j|ja|y|yes)$') {
        Write-ConfigText $destination $item.Content
    }
}
Write-Host 'No staging, commit or push performed. Review git diff and run check-public.ps1 before publishing.'
Write-Host 'Terminal exports are allowlisted/sanitized. Review the diff for company-specific names before publishing.'
Write-Host 'Flow settings, accounts, plugins, histories and local overlays are NEVER exported.'
