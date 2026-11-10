#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'setup\common.ps1')
Move-LegacyStartupBackups
Write-Host 'Startup backup check complete. Active shortcuts and unrelated files were left untouched.'
