#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'setup\common.ps1')
$script:assertions = 0
function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:assertions++
}
function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    Assert $threw $Message
}

$temp = Join-Path ([IO.Path]::GetTempPath()) "glazewm-tests-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $parseErrors = @()
    Get-ChildItem -LiteralPath $repo -Recurse -Filter *.ps1 | ForEach-Object {
        $tokens = $null
        $errors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
        $parseErrors += $errors
    }
    Assert ($parseErrors.Count -eq 0) "All PowerShell files parse: $parseErrors"

    $jsonc = @'
{
  // comment
  "url": "https://example.com/a//b",
  "text": "quote: \" /* not a comment */",
  "path": "C:\\Tools\\",
  "list": [1, 2, /* comment */],
  "nested": {"keep": true,},
}
'@
    $parsed = ConvertFrom-Jsonc $jsonc
    Assert ($parsed.url -eq 'https://example.com/a//b') 'JSONC preserves URLs'
    Assert ($parsed.text -eq 'quote: " /* not a comment */') 'JSONC preserves escaped quotes and comment markers'
    Assert ($parsed.path -eq 'C:\Tools\') 'JSONC preserves backslashes'
    Assert ($parsed.list.Count -eq 2 -and $parsed.nested.keep) 'JSONC accepts trailing commas'
    Assert-Throws { ConvertFrom-Jsonc '{"broken": /*' } 'Invalid comment fails'
    Assert-Throws { ConvertFrom-Jsonc '{bad}' } 'Invalid JSON fails'
    Assert-Throws { ConvertFrom-Jsonc '[]' } 'Non-object JSON fails'

    $fullTemplate = Get-Content -LiteralPath (Join-Path $repo 'windows-terminal\settings.json') -Raw | ConvertFrom-Json
    $template = [pscustomobject]@{
        profiles = [pscustomobject]@{ defaults = [pscustomobject]@{
            colorScheme = $fullTemplate.profiles.defaults.colorScheme
            font = [pscustomobject]@{ face = $fullTemplate.profiles.defaults.font.face }
        } }
        schemes = $fullTemplate.schemes
        keybindings = $fullTemplate.keybindings
    }
    $settings = ConvertFrom-Jsonc @'
{
  "defaultProfile": "machine-profile",
  "profiles": {
    "defaults": {"font": {"size": 14}, "opacity": 95},
    "list": [{"guid": "machine-profile", "name": "Local shell"}]
  },
  "actions": [{"command": "paste", "keys": "alt+v"}],
  "keybindings": [{"id": "old-search", "keys": "ctrl+shift+f"}, {"id": "custom", "keys": "alt+x"}],
  "schemes": [{"name": "Custom"}, {"name": "Gruvbox Soft Dark", "background": "#000000"}],
  "unrelated": true
}
'@
    $merged = Merge-TerminalSettings $settings $template
    Assert ($merged.defaultProfile -eq 'machine-profile' -and $merged.profiles.list[0].name -eq 'Local shell') 'Profiles and default profile remain local'
    Assert ($merged.profiles.defaults.font.size -eq 14 -and $merged.profiles.defaults.opacity -eq 95) 'Unrelated defaults survive'
    Assert ($merged.profiles.defaults.font.face -eq $template.profiles.defaults.font.face) 'Font applied'
    Assert ($merged.actions[0].keys -eq 'alt+v' -and $merged.unrelated) 'Custom actions and properties survive'
    Assert (@($merged.keybindings | Where-Object keys -eq 'alt+x').Count -eq 1) 'Custom keybinding survives'
    Assert (@($merged.keybindings | Where-Object keys -eq 'ctrl+shift+f').Count -eq 1) 'Owned binding is replaced, not duplicated'
    Assert (@($merged.schemes | Where-Object name -eq 'Custom').Count -eq 1) 'Custom color scheme survives'
    $once = $merged | ConvertTo-Json -Depth 100
    $twice = (Merge-TerminalSettings $merged $template) | ConvertTo-Json -Depth 100
    Assert ($once -eq $twice) 'Terminal merge is idempotent'
    $fresh = Merge-TerminalSettings ([pscustomobject]@{}) $template
    Assert ($fresh.profiles.defaults.colorScheme -eq 'Gruvbox Soft Dark') 'Fresh Terminal settings supported'
    Assert (-not $fresh.defaultProfile -and -not $fresh.profiles.list) 'No machine-specific profiles invented'

    $terminalFixture = ConvertFrom-Jsonc @'
{
  "copyOnSelect": true,
  "startupActions": "not-public",
  "profiles": {
    "defaults": {"font": {"face": "Example Mono", "size": 12}, "opacity": 90, "environment": {"PRIVATE": "never-export"}},
    "list": [
      {"name": "Private original name", "guid": "{11111111-1111-1111-1111-111111111111}", "commandline": "powershell.exe", "startingDirectory": "private-folder", "environment": {"PRIVATE": "never-export"}},
      {"name": "Ubuntu 26.04", "guid": "{22222222-2222-2222-2222-222222222222}", "commandline": "C:\\Windows\\System32\\wsl.exe --distribution Ubuntu-26.04"},
      {"name": "Custom", "guid": "{33333333-3333-3333-3333-333333333333}", "commandline": "ssh private-host"},
      {"name": "Ubuntu", "guid": "{44444444-4444-4444-4444-444444444444}", "commandline": "wsl.exe --distribution Ubuntu --exec sh"},
      {"name": "Serial", "guid": "{55555555-5555-5555-5555-555555555555}", "commandline": "powershell.exe -Command unsafe"},
      {"name": "Ubuntu", "guid": "{66666666-6666-6666-6666-666666666666}", "source": "Microsoft.WSL"}
    ]
  },
  "defaultProfile": "{22222222-2222-2222-2222-222222222222}",
  "schemes": [{"name": "Example", "background": "#123456", "privateExtra": "never-export"}],
  "actions": [
    {"id": "User.Pane", "command": {"action": "moveFocus", "direction": "left"}},
    {"id": "User.Arrow", "command": {"action": "sendInput", "input": "\u001b[1;5D"}},
    {"id": "User.Unsafe", "command": {"action": "sendInput", "input": "shell-command"}}
  ],
  "keybindings": [
    {"id": "User.Pane", "keys": "ctrl+left"},
    {"id": "User.Arrow", "keys": "alt+left"},
    {"id": "User.Unsafe", "keys": "alt+x"},
    {"id": "Terminal.CopyToClipboard", "keys": "ctrl+c"},
    {"id": null, "keys": "ctrl+shift+t"}
  ]
}
'@
    $publicTerminal = ConvertTo-PublicTerminalSettings $terminalFixture
    $publicJson = $publicTerminal | ConvertTo-Json -Depth 100
    Assert ($publicTerminal.profiles.list.Count -eq 3) 'Only allowlisted Terminal profiles exported'
    Assert ($publicTerminal.profiles.list[0].name -eq 'Windows PowerShell') 'Profile names canonicalized, not copied from private names'
    Assert ($publicTerminal.profiles.list[0].startingDirectory -eq '%USERPROFILE%') 'Starting directories made portable'
    Assert ($publicTerminal.profiles.list[1].commandline -eq '%SystemRoot%\System32\wsl.exe --distribution Ubuntu-26.04') 'WSL executable path made portable'
    Assert ($publicJson -notmatch 'never-export|private-host|shell-command|not-public|private-folder|Private original name') 'Private fields and unsafe commands absent from public export'
    Assert ($publicTerminal.profiles.defaults.font.size -eq 12 -and $publicTerminal.profiles.defaults.opacity -eq 90) 'Appearance settings exported'
    Assert ($publicTerminal.actions.Count -eq 2 -and $publicTerminal.keybindings.Count -eq 4) 'Control sequences and pane bindings exported without dangling action references'
    Assert ($publicTerminal.defaultProfile -eq $terminalFixture.defaultProfile) 'Public default profile exported'
    $localTerminal = ConvertFrom-Jsonc '{"defaultProfile":"local","profiles":{"defaults":{"font":{"size":9}},"list":[{"guid":"local","name":"Local"}]}}'
    $restoredTerminal = Merge-TerminalSettings $localTerminal $publicTerminal
    Assert ($restoredTerminal.profiles.list.Count -eq 4) 'Restored public profiles coexist with local profiles'
    Assert ($restoredTerminal.defaultProfile -eq $publicTerminal.defaultProfile) 'Exported default restored'
    Assert ($restoredTerminal.profiles.defaults.font.size -eq 12 -and $restoredTerminal.copyOnSelect) 'Exported defaults/global settings restored'
    $restoredOnce = $restoredTerminal | ConvertTo-Json -Depth 100
    Assert (((Merge-TerminalSettings (ConvertFrom-Jsonc $restoredOnce) $publicTerminal) | ConvertTo-Json -Depth 100) -eq $restoredOnce) 'Profile/action/global merge idempotent after disk roundtrip'
    $matchedProfile = $restoredTerminal.profiles.list | Where-Object guid -eq '{11111111-1111-1111-1111-111111111111}'
    Set-JsonProperty $matchedProfile font ([pscustomobject]@{ size = 8; weight = 'bold' })
    Set-JsonProperty $publicTerminal.profiles.list[0] font ([pscustomobject]@{ size = 13 })
    $restoredTerminal = Merge-TerminalSettings $restoredTerminal $publicTerminal
    Assert ($matchedProfile.font.size -eq 13 -and $matchedProfile.font.weight -eq 'bold') 'Profile font merge preserves unrelated local font settings'
    $serialFixture = [pscustomobject]@{ profiles = [pscustomobject]@{ list = @(
        [pscustomobject]@{ guid = '{55555555-5555-5555-5555-555555555555}'; name = 'Serial'; commandline = Get-PublicSerialCommand }
    ) } }
    Assert ((ConvertTo-PublicTerminalSettings $serialFixture).profiles.list.Count -eq 1) 'Exact known Serial command exported'
    $idFixture = ConvertFrom-Jsonc '{"profiles":{"list":[{"guid":"{11111111-1111-1111-1111-111111111111}","name":"Ubuntu 26.04","commandline":"wsl.exe --distribution-id {22222222-2222-2222-2222-222222222222}"}]}}'
    try {
        function Test-Path {
            param([string]$LiteralPath)
            if ($LiteralPath -notlike 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss\*') { throw 'Unexpected registry lookup in fixture' }
            return $true
        }
        function Get-ItemProperty {
            param([string]$LiteralPath, [string]$Name)
            return [pscustomobject]@{ DistributionName = 'Ubuntu-26.04' }
        }
        $idPublic = ConvertTo-PublicTerminalSettings $idFixture
        Assert ($idPublic.profiles.list[0].commandline -eq '%SystemRoot%\System32\wsl.exe --distribution Ubuntu-26.04') 'Machine WSL registration IDs resolved to portable distro names'
    }
    finally {
        Remove-Item Function:\Test-Path
        Remove-Item Function:\Get-ItemProperty
    }
    $unsafeVisual = ConvertFrom-Jsonc '{"profiles":{"defaults":{"font":{"face":"Example"}}},"schemes":[{"name":"Example"}]}'
    Set-JsonProperty $unsafeVisual.profiles.defaults 'background' ('C:\' + 'Users\sample\image.png')
    Assert-Throws { ConvertTo-PublicTerminalSettings $unsafeVisual } 'Residual sensitive value aborts sanitized export'

    $samples = @(
        ('pass' + 'word = "' + ('x' * 20) + '"')
        ('gh' + 'p_' + ('x' * 36))
        ('C:\' + 'Users\sample\project')
        ('C:\\' + 'Users\\sample\\project')
        ('someone' + '@example.com')
        ('\\' + 'fileserver\share')
        ('192.' + '168.5.20')
        ('build.' + 'internal')
        ('-----BEGIN ' + 'PRIVATE KEY-----')
        ('https://user:' + 'value' + '@' + 'example.com')
    )
    foreach ($sample in $samples) {
        Assert (@(Get-PrivacyFindings $sample).Count -gt 0) 'Sensitive fixture detected (value hidden)'
    }
    Assert (@(Get-PrivacyFindings 'http://127.0.0.1:6123 %USERPROFILE% C:\Program Files\Example').Count -eq 0) 'Portable paths and loopback accepted'
    Assert-Throws { Assert-PublicContent $samples[0] 'fixture' } 'Privacy guard aborts'

    $path = Join-Path $temp 'config.json'
    Write-ConfigText $path '{"original":true}'
    Write-ConfigText $path '{"new":true}'
    $backup = @(Get-ChildItem -LiteralPath $temp -Filter 'config.json.bak-*')
    Assert ($backup.Count -eq 1) 'Existing file is backed up'
    Assert (([IO.File]::ReadAllText($backup[0].FullName)) -eq '{"original":true}') 'Backup preserves exact original content'
    Assert (([IO.File]::ReadAllText($path)) -eq '{"new":true}') 'New content is persistent'
    $empty = Read-JsonConfig (Join-Path $temp 'missing.json')
    Set-JsonProperty $empty Theme 'Gruvbox Soft Dark'
    Set-JsonProperty $empty UseSound $false
    Assert ($empty.Theme -eq 'Gruvbox Soft Dark' -and $empty.UseSound -eq $false) 'Missing Flow properties supported'

    $map = @(Get-ConfigMap)
    Assert (@($map.Repo | Select-Object -Unique).Count -eq $map.Count) 'One shared, unique deployment/export allowlist'
    Assert (@($map | Where-Object Repo -match '(?i)Settings\\Settings|windows-terminal|private|local\\').Count -eq 0) 'Private application settings excluded from export'
    foreach ($item in $map) {
        Assert (Test-Path -LiteralPath (Join-Path $repo $item.Repo)) "Mapped source exists: $($item.Repo)"
    }
    $glaze = [IO.File]::ReadAllText((Join-Path $repo 'glazewm\config.yaml'))
    $bindings = [regex]::Matches($glaze, '(?m)^\s+bind_to_monitor:\s*(\d+)')
    Assert ($bindings.Count -eq 9) 'All nine workspaces have a portable binding'
    Assert (@($bindings | Where-Object { $_.Groups[1].Value -ne '0' }).Count -eq 0) 'Fresh setup only uses monitor 0'
    Assert ((ConvertTo-PortableConfig 'glazewm\config.yaml' '    bind_to_monitor: 2') -eq '    bind_to_monitor: 0') 'Machine monitor bindings never enter portable deployment'
    Assert ((ConvertTo-PortableConfig 'glazewm\config.yaml' "    bind_to_monitor: 2`r`n    bind_to_monitor: 1`r`n") -eq "    bind_to_monitor: 0`r`n    bind_to_monitor: 0`r`n") 'Portable normalization preserves CRLF'

    $originalProfile = $env:USERPROFILE
    $originalTestMonitors = $env:GLAZE_TEST_MONITORS
    $originalTestLog = $env:GLAZE_TEST_LOG
    try {
        $env:USERPROFILE = Join-Path $temp 'profile'
        $env:GLAZE_TEST_LOG = Join-Path $temp 'cli.log'
        $configPath = Join-Path $env:USERPROFILE '.glzr\glazewm\config.yaml'
        New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force | Out-Null
        function Get-Command {
            param([string]$Name)
            if ($Name -ne 'glazewm.exe') { throw "Unexpected test command lookup: $Name" }
            [pscustomobject]@{ Source = Join-Path $PSScriptRoot 'glazewm-cli.fixture.ps1' }
        }
        foreach ($screenCount in 1..3) {
            $env:GLAZE_TEST_MONITORS = [string]$screenCount
            foreach ($layout in @('home', 'office')) {
                [IO.File]::WriteAllText($configPath, $glaze)
                & (Join-Path $repo 'glazewm\glaze-layout.ps1') $layout
                $actual = [regex]::Matches([IO.File]::ReadAllText($configPath), '(?m)^\s+bind_to_monitor:\s*(\d+)')
                $expected = if ($layout -eq 'home') { @(0,0,0,0,1,1,1,1,1) } else { @(1,1,1,1,0,0,0,2,2) }
                for ($i = 0; $i -lt 9; $i++) {
                    Assert ([int]$actual[$i].Groups[1].Value -eq [Math]::Min($expected[$i], $screenCount - 1)) "$screenCount screens, $layout workspace $($i+1)"
                }
            }
        }
        & (Join-Path $repo 'glazewm\glaze-layout.ps1') swap
        $actual = [regex]::Matches([IO.File]::ReadAllText($configPath), '(?m)^\s+bind_to_monitor:\s*(\d+)')
        Assert ((($actual | ForEach-Object { $_.Groups[1].Value }) -join ',') -eq '0,0,0,0,1,1,1,2,2') 'Swap leaves third monitor unchanged'
        $commands = Get-Content -LiteralPath $env:GLAZE_TEST_LOG
        Assert (@($commands | Where-Object { $_ -match '--workspace [2-8] ' }).Count -eq 0) 'Only existing workspaces are moved'
        Assert (@($commands | Where-Object { $_ -match 'wm-reload-config' }).Count -eq 7) 'Every layout change reloads GlazeWM'
    }
    finally {
        Remove-Item Function:\Get-Command
        $env:USERPROFILE = $originalProfile
        $env:GLAZE_TEST_MONITORS = $originalTestMonitors
        $env:GLAZE_TEST_LOG = $originalTestLog
    }

    $originalAppData = $env:APPDATA
    $originalLocalAppData = $env:LOCALAPPDATA
    try {
        $env:USERPROFILE = Join-Path $temp 'install-profile'
        $env:APPDATA = Join-Path $env:USERPROFILE 'Roaming'
        $env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'Local'
        function Get-Process { return @() }
        function Read-Host { return 'j' }
        $flowPath = Join-Path $env:APPDATA 'FlowLauncher\Settings\Settings.json'
        Write-ConfigText $flowPath '{"PluginState":{"keep":true},"Theme":"Old"}'
        $terminalPath = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
        Write-ConfigText $terminalPath $jsonc
        & (Join-Path $repo 'install.ps1') -SkipPackages -NoAutostart | Out-Null
        foreach ($item in (Get-ConfigMap)) {
            Assert (([IO.File]::ReadAllText($item.Live)) -eq ([IO.File]::ReadAllText((Join-Path $repo $item.Repo)))) "Installer deploys exact source: $($item.Repo)"
        }
        $flowAfter = Read-JsonConfig $flowPath
        Assert ($flowAfter.PluginState.keep -and $flowAfter.Hotkey -eq 'LWin' -and -not $flowAfter.UseSound) 'Installer merges Flow without losing local plugin state'
        $terminalAfter = Read-JsonConfig $terminalPath
        Assert ($terminalAfter.url -eq $parsed.url -and $terminalAfter.profiles.defaults.colorScheme -eq 'Gruvbox Soft Dark') 'Installer merges real JSONC file'
        & (Join-Path $repo 'install.ps1') -SkipPackages -NoAutostart | Out-Null
        Assert (@(Get-ChildItem -LiteralPath (Split-Path -Parent $flowPath) -Filter 'Settings.json.bak-*').Count -eq 2) 'Repeated installation backs up each Flow version'
        Assert ((Read-JsonConfig $terminalPath | ConvertTo-Json -Depth 100) -eq ($terminalAfter | ConvertTo-Json -Depth 100)) 'Full repeated deployment is idempotent'
        function Read-Host { return '' }
        Write-ConfigText $flowPath '{"Theme":"Declined"}'
        & (Join-Path $repo 'install.ps1') -SkipPackages -NoAutostart | Out-Null
        Assert ((Read-JsonConfig $flowPath).Theme -eq 'Declined') 'Enter declines changes'

        $syncRepo = Join-Path $temp 'sync-repo'
        New-Item -ItemType Directory -Path (Join-Path $syncRepo 'setup') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repo 'setup\common.ps1') -Destination (Join-Path $syncRepo 'setup\common.ps1')
        Copy-Item -LiteralPath (Join-Path $repo 'sync.ps1') -Destination (Join-Path $syncRepo 'sync.ps1')
        $sentinel = Join-Path $syncRepo 'glazewm\config.yaml'
        Write-ConfigText $sentinel 'unchanged'
        $lastItem = @(Get-ConfigMap)[-1]
        [IO.File]::WriteAllText($lastItem.Live, $samples[0])
        Assert-Throws { & (Join-Path $syncRepo 'sync.ps1') } 'Unsafe last file aborts the entire export'
        Assert (([IO.File]::ReadAllText($sentinel)) -eq 'unchanged') 'No early file copied before privacy validation completes'
        [IO.File]::WriteAllText($lastItem.Live, [IO.File]::ReadAllText((Join-Path $repo $lastItem.Repo)))
        $liveGlaze = Join-Path $env:USERPROFILE '.glzr\glazewm\config.yaml'
        [IO.File]::WriteAllText($liveGlaze, ($glaze -replace 'bind_to_monitor: 0', 'bind_to_monitor: 2'))
        function Read-Host { return 'j' }
        & (Join-Path $syncRepo 'sync.ps1') | Out-Null
        Assert (([IO.File]::ReadAllText($sentinel)) -eq $glaze) 'Clean export normalizes machine monitor assignments'
        Assert (-not (Test-Path -LiteralPath (Join-Path $syncRepo 'flowlauncher\Settings'))) 'Export never copies Flow account/plugin settings'
        [IO.File]::WriteAllText($sentinel, 'terminal-only-sentinel')
        & (Join-Path $syncRepo 'sync.ps1') -TerminalOnly | Out-Null
        Assert (([IO.File]::ReadAllText($sentinel)) -eq 'terminal-only-sentinel') 'TerminalOnly export does not touch other repository configs'
        Assert (Test-Path -LiteralPath (Join-Path $syncRepo 'windows-terminal\settings.json')) 'TerminalOnly export persists the sanitized settings'

        $sha = 'a' * 40
        $fixtureRoot = Join-Path $temp "archive\glazewm-config-$sha"
        New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $fixtureRoot 'install.ps1'), "throw 'Fixture must not actually execute'")
        $fixtureZip = Join-Path $temp 'fixture.zip'
        Compress-Archive -LiteralPath $fixtureRoot -DestinationPath $fixtureZip
        $mockState = @{ DownloadUri = ''; DownloadDirectory = ''; InstallerArguments = @() }
        function Invoke-RestMethod {
            param([string]$Uri, [hashtable]$Headers)
            Assert ($Uri -eq 'https://api.github.com/repos/0xce3/glazewm-config/commits/main') 'Bootstrap resolves the expected public repository'
            return [pscustomobject]@{ sha = $sha }
        }
        function Invoke-WebRequest {
            param([string]$Uri, [hashtable]$Headers, [switch]$UseBasicParsing, [string]$OutFile)
            $mockState.DownloadUri = $Uri
            $mockState.DownloadDirectory = Split-Path -Parent $OutFile
            Copy-Item -LiteralPath $fixtureZip -Destination $OutFile
        }
        function powershell.exe {
            $mockState.InstallerArguments = @($args)
            $global:LASTEXITCODE = 0
        }
        & (Join-Path $repo 'bootstrap.ps1') | Out-Null
        Assert ($mockState.DownloadUri -eq "https://codeload.github.com/0xce3/glazewm-config/zip/$sha") 'Bootstrap downloads the resolved commit, not a moving branch'
        $retained = @(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'glazewm-config\source') -Directory)
        Assert ($retained.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $retained[0].FullName 'install.ps1'))) 'Bootstrap retains exact installer sources'
        Assert ($mockState.InstallerArguments[-1] -eq (Join-Path $retained[0].FullName 'install.ps1')) 'Bootstrap invokes the retained installer'
        Assert (-not (Test-Path -LiteralPath $mockState.DownloadDirectory)) 'Bootstrap cleans its own temporary download directory'
        function powershell.exe { $global:LASTEXITCODE = 17 }
        Assert-Throws { & (Join-Path $repo 'bootstrap.ps1') -Revision $sha } 'Bootstrap propagates installer failure'
        Assert (-not (Test-Path -LiteralPath $mockState.DownloadDirectory)) 'Bootstrap also cleans after failure'
    }
    finally {
        Remove-Item Function:\Get-Process
        Remove-Item Function:\Read-Host
        foreach ($mock in @('Invoke-RestMethod', 'Invoke-WebRequest', 'powershell.exe')) {
            if (Test-Path -LiteralPath "Function:\$mock") { Remove-Item -LiteralPath "Function:\$mock" }
        }
        $env:USERPROFILE = $originalProfile
        $env:APPDATA = $originalAppData
        $env:LOCALAPPDATA = $originalLocalAppData
    }

    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'install.ps1') -WhatIf 2>&1
    Assert ($LASTEXITCODE -eq 0) "Installer preview succeeds: $output"
    Assert (($output -join "`n") -match 'Preview only') 'Preview reaches completion without prompts'
    & (Join-Path $repo 'check-public.ps1')
    Write-Host "PASS: $script:assertions assertions"
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force
}
