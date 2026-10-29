#Requires -Version 5.1
[CmdletBinding()]
param([switch]$IncludeHistory)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'setup\common.ps1')
Push-Location $PSScriptRoot
try {
    $files = @(git ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed.' }
    $count = 0
    foreach ($file in $files) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        foreach ($finding in (Get-PrivacyFindings -Content ([IO.File]::ReadAllText((Join-Path $PSScriptRoot $file))))) {
            Write-Warning "$file`:$($finding.Line) [$($finding.Rule)] (value hidden)"
            $count++
        }
    }
    $stagedFiles = @(git ls-files --cached)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot list index files.' }
    foreach ($file in $stagedFiles) {
        $staged = @(git show ":$file")
        if ($LASTEXITCODE -ne 0) { throw "Cannot inspect index file: $file" }
        foreach ($finding in (Get-PrivacyFindings -Content ($staged -join "`n"))) {
            Write-Warning "Index $file`:$($finding.Line) [$($finding.Rule)] (value hidden)"
            $count++
        }
    }
    if ($IncludeHistory) {
        # Inspect publishable refs, not tool-internal checkpoint refs.
        $objects = @(git rev-list --objects --branches --tags --remotes HEAD)
        if ($LASTEXITCODE -ne 0) { throw 'git rev-list failed.' }
        foreach ($entry in $objects) {
            if ($entry -notmatch '^([a-f0-9]{40}) (.+)$') { continue }
            $oid = $Matches[1]
            $name = $Matches[2]
            $type = git cat-file -t $oid
            if ($LASTEXITCODE -ne 0) { throw "Cannot inspect object $oid" }
            if ($type -ne 'blob') { continue }
            $content = git cat-file blob $oid
            if ($LASTEXITCODE -ne 0) { throw "Cannot read object $oid" }
            foreach ($finding in (Get-PrivacyFindings -Content ($content -join "`n"))) {
                Write-Warning "History $oid $name`:$($finding.Line) [$($finding.Rule)] (value hidden)"
                $count++
            }
        }
    }
    if ($count) { throw "$count potential privacy findings. Review locally; never publish the matched values. History is not rewritten automatically." }
    Write-Host 'No pattern matches found. This is a heuristic check, not a guarantee: review names, commands, URLs and git diff manually.'
}
finally {
    Pop-Location
}
