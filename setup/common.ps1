$ErrorActionPreference = 'Stop'

function Get-ConfigMap {
    @(
        @{ Repo = 'glazewm\config.yaml'; Live = Join-Path $env:USERPROFILE '.glzr\glazewm\config.yaml' }
        @{ Repo = 'glazewm\taskbar.ps1'; Live = Join-Path $env:USERPROFILE '.glzr\glazewm\taskbar.ps1' }
        @{ Repo = 'glazewm\glaze-layout.ps1'; Live = Join-Path $env:USERPROFILE '.glzr\glazewm\glaze-layout.ps1' }
        @{ Repo = 'glazewm\glaze-swap.ps1'; Live = Join-Path $env:USERPROFILE '.glzr\glazewm\glaze-swap.ps1' }
        @{ Repo = 'yasb\config.yaml'; Live = Join-Path $env:USERPROFILE '.config\yasb\config.yaml' }
        @{ Repo = 'yasb\styles.css'; Live = Join-Path $env:USERPROFILE '.config\yasb\styles.css' }
        @{ Repo = 'translucenttb\settings.json'; Live = Join-Path $env:LOCALAPPDATA 'Packages\28017CharlesMilette.TranslucentTB_v826wp6bftszj\RoamingState\settings.json' }
        @{ Repo = 'flowlauncher\Themes\Gruvbox Soft Dark.xaml'; Live = Join-Path $env:APPDATA 'FlowLauncher\Themes\Gruvbox Soft Dark.xaml' }
    )
}

function Get-PrivacyFindings {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Content)

    $rules = [ordered]@{
        Credential = '(?i)\b(?:api[_-]?key|client[_-]?secret|secret|token|password)\b["'']?\s*[:=]\s*["'']?[A-Za-z0-9_+/=.\-]{8,}'
        AccessToken = '(?i)\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16}|sk-[A-Za-z0-9_-]{20,}|Bearer\s+[A-Za-z0-9._-]{16,})'
        PrivateKey = '-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----'
        UserPath = '(?i)(?:[A-Z]:[\\/]+Users[\\/]+(?!Public\b|Default\b)[^\\/\s"''<>]+|/(?:home|Users)/[A-Za-z0-9._-]+)'
        Email = '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'
        NetworkShare = '\\\\[A-Za-z0-9][A-Za-z0-9._-]*\\[A-Za-z0-9$]'
        PrivateAddress = '\b(?:10(?:\.\d{1,3}){3}|192\.168(?:\.\d{1,3}){2}|172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2})\b'
        InternalHost = '(?i)\b[A-Z0-9][A-Z0-9.-]*\.(?:corp|internal|local|intranet)\b'
        UrlCredential = '(?i)https?://[^/\s:@]+:[^/\s@]+@'
    }
    foreach ($rule in $rules.GetEnumerator()) {
        $line = 0
        foreach ($text in ($Content -split '\r?\n')) {
            $line++
            if ($text -match $rule.Value) {
                [pscustomobject]@{ Rule = $rule.Key; Line = $line }
            }
        }
    }
}

function Assert-PublicContent {
    param([string]$Content, [string]$Label)
    $findings = @(Get-PrivacyFindings -Content $Content)
    if ($findings.Count) {
        $locations = $findings | ForEach-Object { "$($_.Rule):$($_.Line)" }
        throw "Privacy check failed: $Label ($($locations -join ', ')). Values are deliberately not printed."
    }
}

function Backup-ConfigFile {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $backup = "$Path.bak-$(Get-Date -Format 'yyyyMMdd-HHmmssfff')-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        Copy-Item -LiteralPath $Path -Destination $backup
        Write-Host "BACKUP: $backup"
    }
}

function Write-ConfigText {
    param([string]$Path, [string]$Content)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Backup-ConfigFile -Path $Path
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

function ConvertTo-PortableConfig {
    param([string]$RelativePath, [string]$Content)
    if ($RelativePath -eq 'glazewm\config.yaml') {
        return [regex]::Replace($Content, '(?m)^([ \t]*bind_to_monitor:[ \t]*)\d+[ \t]*(\r?)$', '${1}0${2}')
    }
    return $Content
}

function Set-JsonProperty {
    param([object]$Object, [string]$Name, [AllowNull()][object]$Value)
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { $property.Value = $Value }
    else { $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value }
}

function Merge-TerminalSettings {
    param([object]$Settings, [object]$Template)
    $Template = ConvertFrom-Jsonc ($Template | ConvertTo-Json -Depth 100)
    foreach ($property in $Template.PSObject.Properties) {
        if ($property.Name -notin @('$schema', '$help', 'profiles', 'schemes', 'keybindings', 'actions', 'defaultProfile')) {
            Set-JsonProperty $Settings $property.Name $property.Value
        }
    }
    if (-not $Settings.profiles) { Set-JsonProperty $Settings profiles ([pscustomobject]@{}) }
    if (-not $Settings.profiles.defaults) { Set-JsonProperty $Settings.profiles defaults ([pscustomobject]@{}) }
    foreach ($property in $Template.profiles.defaults.PSObject.Properties) {
        if ($property.Name -eq 'font') {
            if (-not $Settings.profiles.defaults.font) { Set-JsonProperty $Settings.profiles.defaults font ([pscustomobject]@{}) }
            foreach ($fontProperty in $property.Value.PSObject.Properties) {
                Set-JsonProperty $Settings.profiles.defaults.font $fontProperty.Name $fontProperty.Value
            }
        } else { Set-JsonProperty $Settings.profiles.defaults $property.Name $property.Value }
    }
    if ($Template.profiles.list) {
        $profiles = @($Settings.profiles.list | Where-Object { $_ })
        foreach ($profile in $Template.profiles.list) {
            $existing = @($profiles | Where-Object { $_.guid -eq $profile.guid }) | Select-Object -First 1
            if ($existing) {
                foreach ($property in $profile.PSObject.Properties) {
                    if ($property.Name -eq 'font' -and $existing.font) {
                        foreach ($entry in $property.Value.PSObject.Properties) {
                            Set-JsonProperty $existing.font $entry.Name $entry.Value
                        }
                    } else { Set-JsonProperty $existing $property.Name $property.Value }
                }
            } else { $profiles += $profile }
        }
        Set-JsonProperty $Settings.profiles list $profiles
    }
    if ($Template.defaultProfile -and $Template.defaultProfile -in @($Template.profiles.list | ForEach-Object { $_.guid })) {
        Set-JsonProperty $Settings defaultProfile $Template.defaultProfile
    }
    if ($null -ne $Template.actions) {
        $ids = @($Template.actions | Where-Object id | ForEach-Object { $_.id })
        $actionKeys = @($Template.actions | Where-Object keys | ForEach-Object { $_.keys })
        $commands = @($Template.actions | ForEach-Object { $_ | ConvertTo-Json -Depth 100 -Compress })
        $actions = @($Settings.actions | Where-Object {
            $_ -and $_.id -notin $ids -and $_.keys -notin $actionKeys -and
            ($_ | ConvertTo-Json -Depth 100 -Compress) -notin $commands
        }) + @($Template.actions)
        Set-JsonProperty $Settings actions $actions
    }
    $names = @($Template.schemes | ForEach-Object { $_.name })
    $schemes = @($Settings.schemes | Where-Object { $_ -and $_.name -notin $names }) + @($Template.schemes)
    Set-JsonProperty $Settings schemes $schemes

    # Keep local-only profiles, actions and unrelated keybindings.
    $keys = @($Template.keybindings | ForEach-Object { $_.keys })
    $bindings = @($Settings.keybindings | Where-Object { $_ -and $_.keys -notin $keys }) + @($Template.keybindings)
    Set-JsonProperty $Settings keybindings $bindings
    return $Settings
}

function Get-TerminalPaths {
    @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json')
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
}

function ConvertTo-PublicTerminalSettings {
    param([object]$Settings)
    $result = [pscustomobject]@{ '$schema' = 'https://aka.ms/terminal-profiles-schema' }
    $rootNames = @(
        'copyFormatting', 'copyOnSelect', 'showTabsInTitlebar', 'showTerminalTitleInTitlebar',
        'useAcrylicInTabRow', 'alwaysShowTabs', 'tabWidthMode', 'theme',
        'initialCols', 'initialRows', 'launchMode', 'confirmCloseAllTabs',
        'experimental.rendering.forceFullRepaint', 'warning.largePaste',
        'windowingBehavior', 'focusFollowMouse', 'trimBlockSelection', 'trimPaste',
        'wordDelimiters', 'snapToGridOnResize', 'scrollToInput'
    )
    foreach ($property in $Settings.PSObject.Properties) {
        if ($property.Name -in $rootNames) { Set-JsonProperty $result $property.Name $property.Value }
        elseif ($property.Name -notin @('$schema', '$help', 'profiles', 'defaultProfile', 'schemes', 'actions', 'keybindings', 'disabledProfileSources', 'newTabMenu', 'themes', 'searchWebDefaultQueryUrl')) {
            Write-Warning "Terminal setting omitted by public allowlist: $($property.Name)"
        }
    }
        if ($null -ne $Settings.disabledProfileSources) {
            $sources = @($Settings.disabledProfileSources | Where-Object {
                $_ -match '^(?:Windows\.Terminal\.(?:Azure|Wsl|PowershellCore|VisualStudio)|Microsoft\.WSL|Git|CanonicalGroupLimited\.Ubuntu[\d.]*LTS_79rhkp1fndgsc)$'
            })
            if ($sources.Count -ne @($Settings.disabledProfileSources).Count) { Write-Warning 'Non-allowlisted disabled Terminal profile sources omitted.' }
            Set-JsonProperty $result disabledProfileSources $sources
        }
        if ($Settings.searchWebDefaultQueryUrl -eq 'https://www.google.com/search?q=%22%s%22') {
            Set-JsonProperty $result searchWebDefaultQueryUrl $Settings.searchWebDefaultQueryUrl
        } elseif ($Settings.searchWebDefaultQueryUrl) { Write-Warning 'Custom Terminal search URL omitted.' }
        if ($null -ne $Settings.newTabMenu) {
            Set-JsonProperty $result newTabMenu @([pscustomobject]@{ type = 'remainingProfiles' })
            Write-Warning 'Terminal new-tab menu normalized to remainingProfiles; custom entries are not exported.'
        }
        if ($Settings.themes) { Write-Warning 'Custom Terminal themes omitted; color schemes are exported separately.' }
    $visualNames = @(
        'background', 'foreground', 'colorScheme', 'font', 'opacity', 'padding',
        'scrollbarState', 'useAcrylic', 'cursorShape', 'cursorHeight', 'cursorColor',
        'selectionBackground', 'antialiasingMode', 'bellStyle', 'closeOnExit',
        'historySize', 'snapOnInput', 'suppressApplicationTitle', 'adjustIndistinguishableColors',
        'intenseTextStyle', 'retroTerminalEffect'
    )
    function Select-TerminalAppearance {
        param([object]$InputObject)
        $selected = [pscustomobject]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            if ($property.Name -notin $visualNames) { continue }
            if ($property.Name -eq 'font') {
                $font = [pscustomobject]@{}
                foreach ($entry in $property.Value.PSObject.Properties) {
                    if ($entry.Name -in @('face', 'size', 'weight', 'features', 'axes', 'builtinGlyphs', 'cellWidth', 'cellHeight')) {
                        Set-JsonProperty $font $entry.Name $entry.Value
                    }
                }
                Set-JsonProperty $selected font $font
            } else { Set-JsonProperty $selected $property.Name $property.Value }
        }
        return $selected
    }
    $defaults = Select-TerminalAppearance $Settings.profiles.defaults
    $profiles = @()
    $index = 0
    foreach ($profile in $Settings.profiles.list) {
        $index++
        $command = $profile.commandline
        $wslMatch = [regex]::Match([string]$command, '^(?i)"?(?:(?:[A-Z]:\\Windows|%SystemRoot%)\\System32\\)?wsl\.exe"?\s*(.*)$')
        $publicCommand = $null
        $name = $null
        if ($command -match '^(?i)(?:powershell(?:\.exe)?|%SystemRoot%\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe)$') {
            $name = 'Windows PowerShell'
            $publicCommand = '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe'
        } elseif ($command -match '^(?i)(?:cmd(?:\.exe)?|%SystemRoot%\\System32\\cmd\.exe)$') {
            $name = 'Command Prompt'
            $publicCommand = '%SystemRoot%\System32\cmd.exe'
        } elseif (-not $command -and $profile.source -eq 'Windows.Terminal.PowershellCore') {
            $name = 'PowerShell'
        } elseif (-not $command -and
            ($profile.source -match '^CanonicalGroupLimited\.Ubuntu(?:\d+\.\d+)?LTS_79rhkp1fndgsc$' -or
                $profile.source -in @('Microsoft.WSL', 'Windows.Terminal.Wsl')) -and
            $profile.name -match '^Ubuntu(?:[- ]\d+\.\d+(?:\.\d+)?(?: LTS)?)?$') {
            $name = $profile.name
        } elseif ($wslMatch.Success -and
            $profile.name -match '^Ubuntu(?:[- ]\d+\.\d+(?:\.\d+)?(?: LTS)?)?$') {
            $arguments = $wslMatch.Groups[1].Value
            if ($arguments -match '^(?i)--distribution-id\s+(\{?[a-f0-9-]{36}\}?)$') {
                $distributionId = [guid]::Empty
                if ([guid]::TryParse($Matches[1], [ref]$distributionId)) {
                    $registration = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss\{$distributionId}"
                    if (Test-Path -LiteralPath $registration) {
                        $distribution = (Get-ItemProperty -LiteralPath $registration -Name DistributionName).DistributionName
                        if ($distribution -match '^Ubuntu(?:-\d+\.\d+)?$') {
                            $arguments = "--distribution $distribution"
                            Write-Warning "Terminal profile #${index}: machine-specific WSL ID replaced by portable Ubuntu distro name."
                        }
                    }
                }
            }
            # Only a distro selector and home directory are allowed, never shell commands.
            if ($arguments -match '^(?i)(?:(?:--cd\s+"?~"?|(?:-d|--distribution)\s+"?Ubuntu(?:-\d+\.\d+)?"?)\s*)*$') {
                $name = $profile.name
                $publicCommand = '%SystemRoot%\System32\wsl.exe'
                if ($arguments) { $publicCommand += " $arguments" }
            }
        } elseif ($profile.name -eq 'Serial' -and $command -eq (Get-PublicSerialCommand)) {
            $name = 'Serial'
            $publicCommand = $command
        }
        $guid = [guid]::Empty
        if (-not $name -or -not [guid]::TryParse([string]$profile.guid, [ref]$guid)) {
            Write-Warning "Terminal profile #$index omitted: unknown command/source or invalid GUID. Review locally; no private value printed."
            continue
        }
        $public = Select-TerminalAppearance $profile
        Set-JsonProperty $public name $name
        Set-JsonProperty $public guid "{$guid}"
        if ($null -ne $profile.hidden) { Set-JsonProperty $public hidden ([bool]$profile.hidden) }
        if ($publicCommand) { Set-JsonProperty $public commandline $publicCommand }
        elseif ($profile.source) { Set-JsonProperty $public source $profile.source }
        if ($profile.icon -match '^[^\p{L}\p{N}\\/:.]{1,8}$') { Set-JsonProperty $public icon $profile.icon }
        if ($profile.tabTitle -eq $name) { Set-JsonProperty $public tabTitle $name }
        Set-JsonProperty $public startingDirectory '%USERPROFILE%'
        $profiles += $public
    }
    Set-JsonProperty $result profiles ([pscustomobject]@{ defaults = $defaults; list = $profiles })
    if ($Settings.defaultProfile -and $Settings.defaultProfile -in @($profiles | ForEach-Object { $_.guid })) {
        Set-JsonProperty $result defaultProfile $Settings.defaultProfile
    } elseif ($Settings.defaultProfile) {
        Write-Warning 'Terminal default profile omitted because its profile is not public; target default is preserved.'
    }
    $schemeNames = @('name', 'background', 'foreground', 'cursorColor', 'selectionBackground',
        'black', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white',
        'brightBlack', 'brightRed', 'brightGreen', 'brightYellow', 'brightBlue', 'brightPurple', 'brightCyan', 'brightWhite')
    $schemes = @(
        foreach ($scheme in $Settings.schemes) {
            $public = [pscustomobject]@{}
            foreach ($property in $scheme.PSObject.Properties) {
                if ($property.Name -in $schemeNames) { Set-JsonProperty $public $property.Name $property.Value }
            }
            $public
        }
    )
    Set-JsonProperty $result schemes $schemes
    $safeActions = @('copy', 'paste', 'find', 'scrollUp', 'scrollDown', 'scrollUpPage', 'scrollDownPage',
        'scrollToTop', 'scrollToBottom', 'duplicateTab', 'closePane', 'closeTab', 'newTab',
        'openSettings', 'unbound', 'toggleFullscreen', 'toggleFocusMode', 'toggleAlwaysOnTop')
    $exportedActionIds = @()
    foreach ($collection in @('actions', 'keybindings')) {
        $items = @(
            foreach ($item in $Settings.$collection) {
                $public = [pscustomobject]@{}
                if ($collection -eq 'keybindings' -and $item.PSObject.Properties['id'] -and $null -eq $item.id) {
                    Set-JsonProperty $public id $null
                } elseif ($collection -eq 'keybindings' -and ($item.id -match '^Terminal\.[A-Za-z0-9.]+$' -or $item.id -in $exportedActionIds)) {
                    Set-JsonProperty $public id $item.id
                } elseif ($item.command -is [string] -and $item.command -in $safeActions) {
                    Set-JsonProperty $public command $item.command
                    if ($item.id -match '^User\.[A-Za-z0-9.]+$') { Set-JsonProperty $public id $item.id }
                } elseif ($item.command.action -eq 'copy' -and
                    @($item.command.PSObject.Properties.Name | Where-Object { $_ -notin @('action', 'singleLine') }).Count -eq 0) {
                    Set-JsonProperty $public command $item.command
                    if ($item.id -match '^User\.[A-Za-z0-9.]+$') { Set-JsonProperty $public id $item.id }
                } elseif (($item.command.action -eq 'sendInput' -and
                    $item.command.input -match '^(?:\x1b\[[0-9;]*[A-Za-z~]|[\x01-\x1f])$' -and
                    @($item.command.PSObject.Properties.Name | Where-Object { $_ -notin @('action', 'input') }).Count -eq 0) -or
                    ($item.command.action -in @('moveFocus', 'swapPane', 'resizePane') -and
                    $item.command.direction -in @('left', 'right', 'up', 'down', 'previous', 'next', 'nextInOrder', 'previousInOrder') -and
                    @($item.command.PSObject.Properties.Name | Where-Object { $_ -notin @('action', 'direction') }).Count -eq 0)) {
                    Set-JsonProperty $public command $item.command
                    if ($item.id -match '^User\.[A-Za-z0-9.]+$') { Set-JsonProperty $public id $item.id }
                } else {
                    Write-Warning "Terminal $collection entry omitted: non-allowlisted action (no value printed)."
                    continue
                }
                if ($null -ne $item.keys) { Set-JsonProperty $public keys $item.keys }
                $public
            }
        )
        Set-JsonProperty $result $collection $items
        if ($collection -eq 'actions') { $exportedActionIds = @($items | Where-Object id | ForEach-Object { $_.id }) }
    }
    $json = $result | ConvertTo-Json -Depth 100
    Assert-PublicContent $json 'public Terminal settings'
    return $result
}

function Get-PublicSerialCommand {
    return 'powershell.exe -NoLogo -NoProfile -Command "$baud = Read-Host ''Baud rate [115200]''; if ([string]::IsNullOrWhiteSpace($baud)) { $baud = 115200 }; py -m serial.tools.miniterm - $baud --encoding utf-8 --filter direct --eol CRLF --dtr 1 --rts 1 --exit-char 17"'
}

function Read-JsonConfig {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]@{} }
    return (ConvertFrom-Jsonc ([IO.File]::ReadAllText($Path)))
}

function ConvertFrom-Jsonc {
    param([string]$Content)
    # Strip comments only outside strings, preserving escapes and line numbers.
    $buffer = $Content.ToCharArray()
    $quoted = $false
    for ($i = 0; $i -lt $buffer.Length; $i++) {
        $c = $buffer[$i]
        if ($quoted) {
            if ($c -eq '\') { $i++ }
            elseif ($c -eq '"') { $quoted = $false }
            continue
        }
        if ($c -eq '"') { $quoted = $true; continue }
        if ($c -ne '/' -or $i + 1 -ge $buffer.Length) { continue }
        if ($buffer[$i + 1] -eq '/') {
            while ($i -lt $buffer.Length -and $buffer[$i] -notin @("`r", "`n")) {
                $buffer[$i] = ' '
                $i++
            }
        } elseif ($buffer[$i + 1] -eq '*') {
            $buffer[$i] = $buffer[$i + 1] = ' '
            $i += 2
            while ($i + 1 -lt $buffer.Length -and -not ($buffer[$i] -eq '*' -and $buffer[$i + 1] -eq '/')) {
                if ($buffer[$i] -notin @("`r", "`n")) { $buffer[$i] = ' ' }
                $i++
            }
            if ($i + 1 -ge $buffer.Length) { throw 'Unterminated JSONC block comment.' }
            $buffer[$i] = $buffer[$i + 1] = ' '
            $i++
        }
    }
    $quoted = $false
    for ($i = 0; $i -lt $buffer.Length; $i++) {
        if ($quoted) {
            if ($buffer[$i] -eq '\') { $i++ }
            elseif ($buffer[$i] -eq '"') { $quoted = $false }
            continue
        }
        if ($buffer[$i] -eq '"') { $quoted = $true; continue }
        if ($buffer[$i] -eq ',') {
            $next = $i + 1
            while ($next -lt $buffer.Length -and [char]::IsWhiteSpace($buffer[$next])) { $next++ }
            if ($next -lt $buffer.Length -and $buffer[$next] -in @('}', ']')) { $buffer[$i] = ' ' }
        }
    }
    $clean = (-join $buffer).Trim()
    if (-not $clean.StartsWith('{')) { throw 'Expected a JSON object in configuration.' }
    $result = $clean | ConvertFrom-Json
    return $result
}
