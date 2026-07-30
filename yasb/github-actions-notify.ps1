param(
    [Parameter(Mandatory)]
    [string]$Message,
    [ValidateSet('success', 'error', 'warning')]
    [string]$Kind = 'success'
)

$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$notification = New-Object System.Windows.Forms.NotifyIcon
$notification.Icon = switch ($Kind) {
    'error' { [System.Drawing.SystemIcons]::Error }
    'warning' { [System.Drawing.SystemIcons]::Warning }
    default { [System.Drawing.SystemIcons]::Information }
}
$notification.BalloonTipIcon = switch ($Kind) {
    'error' { 'Error' }
    'warning' { 'Warning' }
    default { 'Info' }
}
$notification.BalloonTipTitle = 'GitHub Actions'
$notification.BalloonTipText = $Message
$notification.Visible = $true
$notification.ShowBalloonTip(5000)
Start-Sleep -Seconds 6
$notification.Dispose()
