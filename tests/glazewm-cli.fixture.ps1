# Fake GlazeWM CLI used only by the isolated monitor tests.
if ($args[0] -eq 'query') {
    if ($args[1] -eq 'monitors') {
        $monitors = @(1..([int]$env:GLAZE_TEST_MONITORS) | ForEach-Object { @{ id = $_ } })
        @{ success = $true; data = @{ monitors = $monitors } } | ConvertTo-Json -Depth 10 -Compress
    } elseif ($args[1] -eq 'workspaces') {
        @{ success = $true; data = @{ workspaces = @(@{ name = '1' }, @{ name = '9' }) } } | ConvertTo-Json -Depth 10 -Compress
    } else { throw 'Unexpected test query.' }
} else {
    ($args -join ' ') | Add-Content -LiteralPath $env:GLAZE_TEST_LOG
    @{ success = $true; data = @{} } | ConvertTo-Json -Compress
}
$global:LASTEXITCODE = 0
