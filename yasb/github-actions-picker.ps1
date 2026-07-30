param(
    [switch]$Configure
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'gruvbox-picker.ps1')

$pythonLauncher = Join-Path $env:SystemRoot 'py.exe'
$controller = Join-Path $PSScriptRoot 'github-actions.py'
$workflows = @()
if (-not $Configure) {
    $savedJson = & $pythonLauncher -3 $controller selected-workflows
    $saved = $savedJson | ConvertFrom-Json
    $workflows = @($saved.workflows)
}

if ($workflows.Count -eq 0) {
    $resultJson = & $pythonLauncher -3 $controller available-repositories
    $result = $resultJson | ConvertFrom-Json

    if ($LASTEXITCODE -ne 0 -or $result.error) {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show(
            [string]$result.error,
            'GitHub Actions',
            'OK',
            'Warning'
        ) | Out-Null
        exit 1
    }

    $repositories = @(Show-GruvboxPicker `
        -Items @($result.repositories) `
        -Title 'GitHub Actions - Repository' `
        -Prompt 'Search repositories')

    if ($repositories.Count -eq 0) { exit 0 }

    $workflowJson = & $pythonLauncher -3 $controller available-workflows @repositories
    $workflowResult = $workflowJson | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $workflowResult.error) {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show(
            [string]$workflowResult.error,
            'GitHub Actions',
            'OK',
            'Warning'
        ) | Out-Null
        exit 1
    }

    $workflowLabels = @($workflowResult.workflows | ForEach-Object { [string]$_.label })
    $selectedWorkflowLabels = @(Show-GruvboxPicker `
        -Items $workflowLabels `
        -Title 'GitHub Actions - Workflow' `
        -Prompt 'Search workflows')

    if ($selectedWorkflowLabels.Count -eq 0) { exit 0 }
    $workflows = @(
        $workflowResult.workflows |
            Where-Object { $_.label -eq $selectedWorkflowLabels[0] } |
            Select-Object -First 1 -ExpandProperty value
    )
    & $pythonLauncher -3 $controller select-workflows @workflows
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

$runJson = & $pythonLauncher -3 $controller available-runs @workflows
$runResult = $runJson | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $runResult.error) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        [string]$runResult.error,
        'GitHub Actions',
        'OK',
        'Warning'
    ) | Out-Null
    exit 1
}

$runLabels = @($runResult.runs | ForEach-Object { [string]$_.label })
$selectedRunLabels = @(Show-GruvboxPicker `
    -Items $runLabels `
    -Title 'GitHub Actions - Runs' `
    -Prompt 'Search workflow runs')

if ($selectedRunLabels.Count -eq 0) { exit 0 }
$runs = @(
    $runResult.runs |
        Where-Object { $_.label -eq $selectedRunLabels[0] } |
        Select-Object -First 1 -ExpandProperty value
)

& $pythonLauncher -3 $controller select-runs @runs
if ($LASTEXITCODE -ne 0) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        'The repository selection could not be saved.',
        'GitHub Actions',
        'OK',
        'Error'
    ) | Out-Null
    exit 1
}
