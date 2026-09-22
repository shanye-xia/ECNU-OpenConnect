[CmdletBinding()]
param(
    [ValidateSet('Gui','Connect','Disconnect','Status','WatchRoutes','CliLogin','ForceStop')]
    [string]$Action = 'Gui',
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $PSCommandPath
$AppDir = Split-Path -Parent $ScriptDir
$ConfigPath = Join-Path $ScriptDir 'config.json'
$LoginPath = Join-Path $ScriptDir 'ECNU-OpenConnect.login.xml'
$LegacyUserNamePath = Join-Path $ScriptDir 'ECNU-OpenConnect.username.txt'
$LegacyPasswordPath = Join-Path $ScriptDir 'ECNU-OpenConnect.password.xml'
$LegacyGuiCredentialPath = Join-Path $ScriptDir 'ECNU-OpenConnect.credential.xml'
$PidPath = Join-Path $ScriptDir 'ECNU-OpenConnect.pid.json'
$LogPath = Join-Path $ScriptDir 'ECNU-OpenConnect.log'
$WatcherPidPath = Join-Path $ScriptDir 'ECNU-OpenConnect-routewatch.pid'
$WatcherStopPath = Join-Path $ScriptDir 'ECNU-OpenConnect-routewatch.stop'
$IconPath = Join-Path $ScriptDir 'ECNU-OpenConnect.ico'
$OpenConnectDir = Join-Path $ScriptDir 'openconnect'
$OpenConnectExe = Join-Path $OpenConnectDir 'openconnect.exe'
$VpncScript = Join-Path $OpenConnectDir 'vpnc-script-win.js'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-AppIcon {
    if (Test-Path -LiteralPath $IconPath) { return }
    try {
        if (-not (Test-Path -LiteralPath $ScriptDir)) {
            New-Item -ItemType Directory -Path $ScriptDir -Force | Out-Null
        }
        Add-Type -AssemblyName System.Drawing
        $stream = [System.IO.File]::Open($IconPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        try {
            [System.Drawing.SystemIcons]::Shield.Save($stream)
        }
        finally {
            $stream.Dispose()
        }
    }
    catch {
        # The app can still run with the default window icon.
    }
}

function Set-WindowIcon {
    param($Window)
    try {
        Ensure-AppIcon
        if (Test-Path -LiteralPath $IconPath) {
            $iconUri = [Uri]::new($IconPath, [UriKind]::Absolute)
            $Window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create(
                $iconUri,
                [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,
                [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            )
            $Window.Add_SourceInitialized({
                param($sender, $eventArgs)
                Set-NativeWindowIcon -Window $sender
            })
        }
    }
    catch {
    }
}

function Ensure-NativeShellHelpers {
    if (([System.Management.Automation.PSTypeName]'EcnuTaskbarNative').Type) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class EcnuTaskbarNative
{
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
}
'@
}

function Set-AppUserModelId {
    try {
        Ensure-NativeShellHelpers
        [void][EcnuTaskbarNative]::SetCurrentProcessExplicitAppUserModelID('ECNU.OpenConnect.GUI')
    }
    catch {
    }
}

function Set-NativeWindowIcon {
    param($Window)
    try {
        if (-not (Test-Path -LiteralPath $IconPath)) { return }
        Ensure-NativeShellHelpers
        $helper = [System.Windows.Interop.WindowInteropHelper]::new($Window)
        if ($helper.Handle -eq [IntPtr]::Zero) { return }

        if (-not $script:EcnuOcWindowIcons) {
            $script:EcnuOcWindowIcons = New-Object System.Collections.ArrayList
        }

        $smallIcon = New-Object System.Drawing.Icon($IconPath, 16, 16)
        $largeIcon = New-Object System.Drawing.Icon($IconPath, 32, 32)
        [void]$script:EcnuOcWindowIcons.Add($smallIcon)
        [void]$script:EcnuOcWindowIcons.Add($largeIcon)

        [void][EcnuTaskbarNative]::SendMessage($helper.Handle, 0x0080, [IntPtr]0, $smallIcon.Handle)
        [void][EcnuTaskbarNative]::SendMessage($helper.Handle, 0x0080, [IntPtr]1, $largeIcon.Handle)
    }
    catch {
    }
}

function Ensure-Admin {
    if ((Test-Admin) -or $NoElevate) { return }
    $args = @(
        '-NoProfile',
        '-WindowStyle', 'Hidden',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PSCommandPath),
        $Action
    )
    Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs | Out-Null
    exit 0
}

function New-DefaultConfig {
    [pscustomobject]@{
        Host = 'vpn-ct.ecnu.edu.cn'
        AuthGroup = 'ECNU'
        RememberPassword = $true
        AllowedRoutes = @('172.0.0.0/8')
        CloseToTrayTipShown = $false
        LoginTimeoutSeconds = 50
        UserAgent = 'AnyConnect Linux_64 5.1.02042'
        VersionString = '5.1.02042'
        Os = 'linux-64'
    }
}

function Get-Config {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        $config = New-DefaultConfig
        Save-Config $config
        return $config
    }

    $raw = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $config = New-DefaultConfig
        Save-Config $config
        return $config
    }

    $config = $raw | ConvertFrom-Json
    $default = New-DefaultConfig
    foreach ($name in $default.PSObject.Properties.Name) {
        if (-not ($config.PSObject.Properties.Name -contains $name)) {
            $config | Add-Member -NotePropertyName $name -NotePropertyValue $default.$name
        }
    }
    if ($null -eq $config.AllowedRoutes) { $config.AllowedRoutes = @() }
    return $config
}

function Save-Config($Config) {
    if (-not (Test-Path -LiteralPath $ScriptDir)) {
        New-Item -ItemType Directory -Path $ScriptDir -Force | Out-Null
    }
    [pscustomobject]@{
        Host = $Config.Host
        AuthGroup = $Config.AuthGroup
        RememberPassword = [bool]$Config.RememberPassword
        AllowedRoutes = @($Config.AllowedRoutes)
        CloseToTrayTipShown = [bool]$Config.CloseToTrayTipShown
        LoginTimeoutSeconds = [int]$Config.LoginTimeoutSeconds
        UserAgent = $Config.UserAgent
        VersionString = $Config.VersionString
        Os = $Config.Os
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
}

function Read-TextFileShared {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }

    $stream = $null
    $reader = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
        return $reader.ReadToEnd()
    }
    catch {
        return ''
    }
    finally {
        if ($reader) { $reader.Dispose() }
        elseif ($stream) { $stream.Dispose() }
    }
}

function Get-TextTail {
    param([string]$Text, [int]$LineCount = 80)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $lines = $Text -split "`r?`n"
    if ($lines.Count -le $LineCount) { return ($lines -join [Environment]::NewLine).TrimEnd() }
    return (($lines | Select-Object -Last $LineCount) -join [Environment]::NewLine).TrimEnd()
}

function Update-VpncScriptRoutes {
    param([string[]]$Routes)
    if (-not (Test-Path -LiteralPath $VpncScript)) { return }
    $cleanRoutes = @($Routes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
    if ($cleanRoutes.Count -eq 0) { $cleanRoutes = @('172.0.0.0/8') }
    $routeText = ($cleanRoutes -join ',')
    $escaped = [Regex]::Escape($routeText)
    $scriptText = [System.IO.File]::ReadAllText($VpncScript, [System.Text.Encoding]::UTF8)
    $replacement = 'var ecnuDefaultSplitRoutes = "' + $routeText.Replace('\','\\').Replace('"','\"') + '";'
    if ($scriptText -match 'var ecnuDefaultSplitRoutes = "[^"]*";') {
        $scriptText = [Regex]::Replace($scriptText, 'var ecnuDefaultSplitRoutes = "[^"]*";', $replacement, 1)
    }
    else {
        $scriptText = $scriptText -replace '(// ECNU_SPLIT_ROUTES is set by the GUI[^\r\n]*\r?\n)', ('$1' + $replacement + [Environment]::NewLine)
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($VpncScript, $scriptText, $utf8NoBom)
}

function Write-AppLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try {
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # OpenConnect can briefly hold the log file; status should not fail because of logging.
    }
}

function Get-SavedCredential {
    if (Test-Path -LiteralPath $LoginPath) {
        try {
            $cred = Import-Clixml -LiteralPath $LoginPath
            if ($cred -is [System.Management.Automation.PSCredential]) {
                return $cred
            }
        }
        catch {
            Remove-SavedCredential
        }
    }

    $legacyUserName = Get-LegacySavedUserName
    if ($legacyUserName -and (Test-Path -LiteralPath $LegacyPasswordPath)) {
        try {
            $securePassword = Import-Clixml -LiteralPath $LegacyPasswordPath
            if ($securePassword -is [System.Security.SecureString]) {
                $cred = [System.Management.Automation.PSCredential]::new($legacyUserName, $securePassword)
                Save-Credential $cred
                Remove-LegacySplitCredential
                return $cred
            }
        }
        catch {
            Remove-LegacySplitCredential
        }
    }

    foreach ($path in @($LegacyGuiCredentialPath)) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            $cred = Import-Clixml -LiteralPath $path
            if ($cred -is [System.Management.Automation.PSCredential]) {
                Save-Credential $cred
                return $cred
            }
        }
        catch {
            Remove-Item -LiteralPath $LegacyGuiCredentialPath -Force -ErrorAction SilentlyContinue
        }
    }
    return $null
}

function Get-LegacySavedUserName {
    if (-not (Test-Path -LiteralPath $LegacyUserNamePath)) { return '' }
    try {
        return (Get-Content -LiteralPath $LegacyUserNamePath -Raw -Encoding UTF8).Trim()
    }
    catch {
        return ''
    }
}

function Get-SavedUserName {
    $cred = Get-SavedCredential
    if ($cred -and -not [string]::IsNullOrWhiteSpace($cred.UserName)) {
        return [string]$cred.UserName
    }
    return Get-LegacySavedUserName
}

function Remove-LegacySplitCredential {
    Remove-Item -LiteralPath $LegacyUserNamePath,$LegacyPasswordPath -Force -ErrorAction SilentlyContinue
}

function Save-Credential {
    param([Parameter(Mandatory)][System.Management.Automation.PSCredential]$Credential)
    $Credential | Export-Clixml -LiteralPath $LoginPath
    Remove-LegacySplitCredential
    Remove-Item -LiteralPath $LegacyGuiCredentialPath -Force -ErrorAction SilentlyContinue
}

function Remove-SavedCredential {
    Remove-Item -LiteralPath $LoginPath,$LegacyGuiCredentialPath -Force -ErrorAction SilentlyContinue
    Remove-LegacySplitCredential
}

function ConvertFrom-SecureStringToPlain {
    param([System.Security.SecureString]$SecureString)
    if (-not $SecureString -or $SecureString.Length -eq 0) { return '' }

    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        if ($ptr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }
    }
}

function ConvertTo-SecureStringFromPlain {
    param([string]$Text)
    $secure = New-Object System.Security.SecureString
    if ($Text) {
        foreach ($ch in $Text.ToCharArray()) { $secure.AppendChar($ch) }
    }
    $secure.MakeReadOnly()
    return $secure
}

function Get-SavedLauncherProcess {
    $config = Get-Config
    if (Test-Path -LiteralPath $PidPath) {
        try {
            $saved = Get-Content -LiteralPath $PidPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $process = Get-CimInstance Win32_Process -Filter "ProcessId = $($saved.Pid)" -ErrorAction SilentlyContinue
            if ($process -and ($process.CommandLine -like "*$($config.Host)*" -or $process.CommandLine -like "*$OpenConnectExe*")) {
                return $process
            }
        }
        catch {
        }
        Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue
    }

    $fallback = @(Get-OpenConnectProcesses | Select-Object -First 1)
    if ($fallback.Count -gt 0) { return $fallback[0] }
    return $null
}

function Get-OpenConnectProcesses {
    $openConnectPattern = "*$OpenConnectExe*"
    $normalizedOpenConnect = $OpenConnectExe.ToLowerInvariant()

    @(Get-CimInstance Win32_Process -Filter "Name = 'openconnect.exe' OR Name = 'cmd.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            if (-not $_.CommandLine) { return $false }

            if ($_.Name -ieq 'openconnect.exe') {
                if ($_.ExecutablePath -and $_.ExecutablePath.ToLowerInvariant() -eq $normalizedOpenConnect) { return $true }
                return ($_.CommandLine -like $openConnectPattern)
            }

            return ($_.Name -ieq 'cmd.exe' -and $_.CommandLine -like $openConnectPattern)
        } |
        Sort-Object ProcessId -Unique)
}

function Initialize-LogFile {
    param([string[]]$Lines)
    try {
        $stream = [System.IO.File]::Open($LogPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
        try {
            $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::UTF8)
            try {
                foreach ($line in $Lines) { $writer.WriteLine($line) }
            }
            finally {
                $writer.Dispose()
            }
        }
        finally {
            if ($stream) { $stream.Dispose() }
        }
    }
    catch {
        # If an old OpenConnect process still owns the log, do not fail login here.
        Write-AppLog "Could not reset log file before login: $($_.Exception.Message)" 'WARN'
    }
}

function Test-OpenConnectReady {
    if (-not (Test-Path -LiteralPath $OpenConnectExe)) {
        throw "没有找到内置 openconnect.exe：$OpenConnectExe"
    }
    if (-not (Test-Path -LiteralPath $VpncScript)) {
        throw "没有找到 vpnc-script-win.js：$VpncScript"
    }
}

function Quote-CmdArg([string]$Value) {
    return '"' + ($Value -replace '"','\"') + '"'
}

function Start-Connection {
    param(
        [Parameter(Mandatory)][string]$UserName,
        [System.Security.SecureString]$Password,
        [bool]$RememberPassword
    )

    Ensure-Admin
    Test-OpenConnectReady
    $config = Get-Config
    if (Get-SavedLauncherProcess) { throw '当前已登录，请先退出登录。' }
    $savedLogin = Get-SavedCredential
    if ([string]::IsNullOrWhiteSpace($UserName) -and $savedLogin) {
        $UserName = $savedLogin.UserName
    }
    if ([string]::IsNullOrWhiteSpace($UserName)) { throw '请输入账号。' }

    $credential = $null
    $saveCredentialAfterSuccess = $false
    $removeCredentialAfterSuccess = -not $RememberPassword
    if ($Password -and $Password.Length -gt 0) {
        $credential = [System.Management.Automation.PSCredential]::new($UserName.Trim(), $Password)
        $saveCredentialAfterSuccess = [bool]$RememberPassword
    }
    else {
        $credential = Get-SavedCredential
        if (-not $credential) { throw '请输入密码，或先保存一次凭据。' }
        if ($credential.UserName -ne $UserName.Trim()) {
            throw '已保存凭据的账号和当前账号不同，请输入密码后重新登录。'
        }
    }

    $config.RememberPassword = [bool]$RememberPassword
    Save-Config $config
    Update-VpncScriptRoutes -Routes @($config.AllowedRoutes)

    Initialize-LogFile @(
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Starting ECNU OpenConnect",
        "OpenConnect: $OpenConnectExe",
        "VPN host: $($config.Host)",
        "User: $($credential.UserName)",
        "Routes via VPN: $(($config.AllowedRoutes | ForEach-Object { $_ }) -join ', ')",
        ''
    )

    $arguments = @(
        '-v',
        '--protocol=anyconnect',
        "--user=$($credential.UserName)",
        "--authgroup=$($config.AuthGroup)",
        "--os=$($config.Os)",
        '--disable-ipv6',
        '--no-proxy',
        '--passwd-on-stdin',
        "--script=$VpncScript",
        "--useragent=$($config.UserAgent)",
        "--version-string=$($config.VersionString)",
        $config.Host
    )

    $quotedArguments = ($arguments | ForEach-Object { Quote-CmdArg $_ }) -join ' '
    $innerCommand = (Quote-CmdArg $OpenConnectExe) + ' ' + $quotedArguments + ' >> ' + (Quote-CmdArg $LogPath) + ' 2>&1'

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $env:ComSpec
    $startInfo.Arguments = '/d /s /c "' + $innerCommand + '"'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardInput = $true
    $startInfo.WorkingDirectory = $OpenConnectDir
    $splitRoutes = (@($config.AllowedRoutes) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ','
    if ([string]::IsNullOrWhiteSpace($splitRoutes)) { $splitRoutes = '172.0.0.0/8' }
    $startInfo.EnvironmentVariables['ECNU_SPLIT_ROUTES'] = $splitRoutes

    $launcher = New-Object System.Diagnostics.Process
    $launcher.StartInfo = $startInfo
    if (-not $launcher.Start()) { throw '无法启动 OpenConnect。' }

    @{
        Pid = $launcher.Id
        StartedAt = (Get-Date).ToString('o')
        Host = $config.Host
        OpenConnect = $OpenConnectExe
    } | ConvertTo-Json | Set-Content -LiteralPath $PidPath -Encoding UTF8

    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($credential.Password)
    try {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
        $launcher.StandardInput.WriteLine($plain)
        $launcher.StandardInput.Close()
    }
    finally {
        if ($ptr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
        $plain = $null
    }

    $connected = $false
    $deadline = (Get-Date).AddSeconds([int]$config.LoginTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        $launcher.Refresh()
        if ($launcher.HasExited) { break }
        $logText = Read-TextFileShared -Path $LogPath
        if ($logText -match 'X-CSTP-Address:|Configured as |Connected as ') {
            $connected = $true
            break
        }
    }

    $launcher.Refresh()
    if ($launcher.HasExited) {
        Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue
        $tail = Get-TextTail -Text (Read-TextFileShared -Path $LogPath) -LineCount 12
        if ($tail -match 'Failed to complete authentication|Login failed|Password:\s*fgets') {
            Remove-SavedCredential
            throw "认证失败，已清除保存的密码。请重新输入正确密码后再登录。最近日志：`r`n$tail"
        }
        throw "OpenConnect 启动后退出。最近日志：`r`n$tail"
    }

    Write-AppLog "Split routes passed to vpnc-script-win.js: $splitRoutes"

    if ($connected) {
        Write-AppLog 'Connected.'
    }
    else {
        Write-AppLog 'OpenConnect is still running, but no configured-address marker was detected before timeout.' 'WARN'
    }

    if ($saveCredentialAfterSuccess) {
        Save-Credential $credential
    }
    elseif ($removeCredentialAfterSuccess) {
        Remove-SavedCredential
    }
}

function Stop-RouteWatcher {
    Remove-Item -LiteralPath $WatcherStopPath -Force -ErrorAction SilentlyContinue
    New-Item -ItemType File -Path $WatcherStopPath -Force | Out-Null
    if (Test-Path -LiteralPath $WatcherPidPath) {
        $pidText = (Get-Content -LiteralPath $WatcherPidPath -Raw -ErrorAction SilentlyContinue).Trim()
        if ($pidText -match '^\d+$') {
            $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$pidText" -ErrorAction SilentlyContinue
            if ($proc -and $proc.CommandLine -like '*ECNU-OpenConnect-GUI.ps1*' -and $proc.CommandLine -like '*WatchRoutes*') {
                Stop-Process -Id ([int]$pidText) -Force -ErrorAction SilentlyContinue
            }
        }
        Remove-Item -LiteralPath $WatcherPidPath -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $WatcherStopPath -Force -ErrorAction SilentlyContinue
}

function Start-RouteWatcher {
    Stop-RouteWatcher
    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden',
        '-File', ('"{0}"' -f $PSCommandPath),
        'WatchRoutes',
        '-NoElevate'
    )
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -WindowStyle Hidden -PassThru
    Set-Content -LiteralPath $WatcherPidPath -Value $p.Id -Encoding ASCII
    Write-AppLog "Route watcher started, PID $($p.Id)."
}

function Stop-Connection {
    Ensure-Admin
    Stop-RouteWatcher
    $matches = @(Get-OpenConnectProcesses)
    foreach ($match in $matches) {
        try {
            & taskkill.exe /PID $match.ProcessId /T /F | Out-Null
            Write-AppLog "OpenConnect stopped. PID $($match.ProcessId)."
        }
        catch {
            Write-AppLog "Could not stop PID $($match.ProcessId): $($_.Exception.Message)" 'WARN'
        }
    }
    Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue
}

function Get-VpnAssignedAddress {
    if (-not (Test-Path -LiteralPath $LogPath)) { return $null }
    $text = Read-TextFileShared -Path $LogPath
    $matches = [regex]::Matches($text, '(?:X-CSTP-Address:\s*|Configured as\s+)(\d{1,3}(?:\.\d{1,3}){3})')
    if ($matches.Count -gt 0) { return $matches[$matches.Count - 1].Groups[1].Value }
    return $null
}

function Get-VpnInterfaceIndex {
    $assigned = Get-VpnAssignedAddress
    if ($assigned) {
        $ip = Get-NetIPAddress -AddressFamily IPv4 -IPAddress $assigned -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($ip) { return [int]$ip.InterfaceIndex }
    }

    $candidates = @(Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue | Where-Object {
        $_.Status -eq 'Up' -and ($_.InterfaceDescription -match 'OpenConnect|Wintun|WireGuard|TAP|TUN' -or $_.Name -match 'OpenConnect|Wintun|TAP|TUN')
    } | Sort-Object ifIndex)
    foreach ($adapter in $candidates) {
        $routes = @(Get-NetRoute -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction SilentlyContinue)
        if ($routes.Count -gt 0) { return [int]$adapter.ifIndex }
    }
    return $null
}

function Convert-PrefixToRouteParts {
    param([Parameter(Mandatory)][string]$DestinationPrefix)
    $parts = $DestinationPrefix -split '/'
    if ($parts.Count -ne 2) { throw "CIDR 格式不正确：$DestinationPrefix" }
    $bits = [int]$parts[1]
    if ($bits -lt 0 -or $bits -gt 32) { throw "CIDR 掩码长度不正确：$DestinationPrefix" }
    $maskOctets = @()
    for ($i = 0; $i -lt 4; $i++) {
        $remaining = $bits - ($i * 8)
        if ($remaining -ge 8) {
            $maskOctets += 255
        }
        elseif ($remaining -gt 0) {
            $maskOctets += [int](256 - [math]::Pow(2, 8 - $remaining))
        }
        else {
            $maskOctets += 0
        }
    }
    [pscustomobject]@{
        Network = $parts[0]
        Mask = ($maskOctets -join '.')
    }
}

function Test-Cidr {
    param([string]$Value)
    if ($Value -notmatch '^(\d{1,3}\.){3}\d{1,3}/([0-9]|[12][0-9]|3[0-2])$') { return $false }
    $ip = ($Value -split '/')[0]
    foreach ($octet in ($ip -split '\.')) {
        if ([int]$octet -lt 0 -or [int]$octet -gt 255) { return $false }
    }
    return $true
}

function Invoke-RouteExe {
    param([Parameter(Mandatory)][string[]]$RouteArgs, [switch]$IgnoreFailure)
    $routeExe = Join-Path $env:SystemRoot 'System32\route.exe'
    $output = & $routeExe @RouteArgs 2>&1
    $exitCode = $LASTEXITCODE
    if ($output) { Write-AppLog ('route.exe {0}: {1}' -f ($RouteArgs -join ' '), (($output | Out-String).Trim())) }
    if ($exitCode -ne 0 -and -not $IgnoreFailure) {
        throw ('route.exe failed ({0}): route.exe {1}' -f $exitCode, ($RouteArgs -join ' '))
    }
}

function Get-VpnRouteContext {
    $ifIndex = Get-VpnInterfaceIndex
    if (-not $ifIndex) { throw '没有找到 OpenConnect VPN 网卡。' }
    $routes = @(Get-NetRoute -InterfaceIndex $ifIndex -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction SilentlyContinue)
    $gateway = ($routes | Where-Object { $_.NextHop -and $_.NextHop -ne '0.0.0.0' } |
        Group-Object NextHop | Sort-Object Count -Descending | Select-Object -First 1).Name
    if (-not $gateway) { $gateway = '0.0.0.0' }
    [pscustomobject]@{
        InterfaceIndex = [int]$ifIndex
        Gateway = [string]$gateway
        Routes = $routes
    }
}

function Add-RouteViaVpn {
    param([string]$DestinationPrefix, [object]$Context)
    $parts = Convert-PrefixToRouteParts -DestinationPrefix $DestinationPrefix
    Invoke-RouteExe -RouteArgs @('ADD', $parts.Network, 'MASK', $parts.Mask, $Context.Gateway, 'METRIC', '5', 'IF', [string]$Context.InterfaceIndex) -IgnoreFailure
}

function Remove-RouteFromVpn {
    param([string]$DestinationPrefix, [string]$NextHop, [int]$InterfaceIndex)
    $parts = Convert-PrefixToRouteParts -DestinationPrefix $DestinationPrefix
    $hop = if ($NextHop) { $NextHop } else { '0.0.0.0' }
    Invoke-RouteExe -RouteArgs @('DELETE', $parts.Network, 'MASK', $parts.Mask, $hop, 'IF', [string]$InterfaceIndex) -IgnoreFailure
}

function Apply-Routes {
    Ensure-Admin
    $config = Get-Config
    $context = Get-VpnRouteContext
    $defaultPrefixes = @('0.0.0.0/0','0.0.0.0/1','128.0.0.0/1')
    foreach ($route in $context.Routes) {
        if ($defaultPrefixes -contains $route.DestinationPrefix) {
            Remove-RouteFromVpn -DestinationPrefix $route.DestinationPrefix -NextHop $route.NextHop -InterfaceIndex $context.InterfaceIndex
            Write-AppLog "Removed VPN default route $($route.DestinationPrefix)."
        }
    }

    foreach ($prefix in @($config.AllowedRoutes)) {
        if ([string]::IsNullOrWhiteSpace($prefix)) { continue }
        if (-not (Test-Cidr $prefix)) { throw "路由不是有效 CIDR：$prefix" }
        $exists = @(Get-NetRoute -InterfaceIndex $context.InterfaceIndex -AddressFamily IPv4 -DestinationPrefix $prefix -PolicyStore ActiveStore -ErrorAction SilentlyContinue)
        if ($exists.Count -eq 0) {
            Add-RouteViaVpn -DestinationPrefix $prefix -Context $context
            Write-AppLog "Added VPN route $prefix via ifIndex $($context.InterfaceIndex)."
        }
    }
}

function Watch-Routes {
    Ensure-Admin
    Write-AppLog 'Route watcher loop started.'
    $misses = 0
    while ($true) {
        if (Test-Path -LiteralPath $WatcherStopPath) { break }
        if (-not (Get-SavedLauncherProcess)) { break }
        try {
            Apply-Routes
            $misses = 0
        }
        catch {
            $misses++
            Write-AppLog "Route watcher check failed: $($_.Exception.Message)" 'WARN'
            if ($misses -ge 5) { break }
        }
        Start-Sleep -Seconds 3
    }
    Remove-Item -LiteralPath $WatcherPidPath,$WatcherStopPath -Force -ErrorAction SilentlyContinue
    Write-AppLog 'Route watcher loop stopped.'
}

function Start-CliLogin {
    Ensure-Admin
    $cred = Get-SavedCredential
    if ($cred) {
        Write-Host "使用已保存账号 / Using saved account: $($cred.UserName)"
        Start-Connection -UserName $cred.UserName -Password $cred.Password -RememberPassword $true
        Write-Host '登录流程已启动。 / Login started.'
        return
    }

    $defaultUser = Get-SavedUserName
    if ($defaultUser) {
        $prompt = "账号 / Account [$defaultUser]"
        $inputUser = Read-Host $prompt
        $userName = if ([string]::IsNullOrWhiteSpace($inputUser)) { $defaultUser } else { $inputUser.Trim() }
    }
    else {
        $userName = (Read-Host '账号 / Account').Trim()
    }

    if ([string]::IsNullOrWhiteSpace($userName)) {
        throw '没有输入账号。'
    }

    $securePassword = Read-Host '密码 / Password' -AsSecureString
    if (-not $securePassword -or $securePassword.Length -eq 0) {
        throw '没有输入密码。'
    }

    Start-Connection -UserName $userName -Password $securePassword -RememberPassword $true
    Write-Host '登录流程已启动。 / Login started.'
}

function Stop-OpenConnectForce {
    Ensure-Admin
    Stop-RouteWatcher

    $matches = @(Get-CimInstance Win32_Process -Filter "Name = 'openconnect.exe'" -ErrorAction SilentlyContinue)
    $launchers = @(Get-CimInstance Win32_Process -Filter "Name = 'cmd.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*$OpenConnectExe*" })
    $targets = @(($matches + $launchers) | Sort-Object ProcessId -Unique)

    if ($targets.Count -eq 0) {
        Write-Host '没有找到 openconnect.exe 进程。 / No openconnect.exe process was found.'
    }

    foreach ($target in $targets) {
        try {
            & taskkill.exe /PID $target.ProcessId /T /F | Out-Null
            Write-Host "已强制停止 PID $($target.ProcessId) / Force-stopped PID $($target.ProcessId)"
            Write-AppLog "Force-stopped OpenConnect PID $($target.ProcessId)."
        }
        catch {
            Write-Host "停止 PID $($target.ProcessId) 失败：$($_.Exception.Message)"
            Write-AppLog "Could not force-stop PID $($target.ProcessId): $($_.Exception.Message)" 'WARN'
        }
    }

    Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue
}

function Get-StatusText {
    $launcher = Get-SavedLauncherProcess
    if (-not $launcher) { return '未连接' }
    $addr = Get-VpnAssignedAddress
    if ($addr) { return "已连接  $addr" }
    return '连接中 / 已启动'
}

function Get-LogTail {
    if (-not (Test-Path -LiteralPath $LogPath)) { return '' }
    return Get-TextTail -Text (Read-TextFileShared -Path $LogPath) -LineCount 80
}

function Open-LogFile {
    if (-not (Test-Path -LiteralPath $LogPath)) {
        New-Item -ItemType File -Path $LogPath -Force | Out-Null
    }
    Start-Process -FilePath 'notepad.exe' -ArgumentList ('"{0}"' -f $LogPath) | Out-Null
}

function Open-LogFolder {
    if (-not (Test-Path -LiteralPath $ScriptDir)) {
        New-Item -ItemType Directory -Path $ScriptDir -Force | Out-Null
    }
    Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $ScriptDir) | Out-Null
}

function Show-CloseToTrayTip {
    param($Owner)

    $tipXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ECNU OpenConnect" Width="460" SizeToContent="Height" ResizeMode="NoResize"
        WindowStartupLocation="CenterOwner" Background="#F3F3F3" FontFamily="Segoe UI" FontSize="14">
    <Border Margin="18" Background="#FFFFFF" BorderBrush="#E1E1E1" BorderThickness="1" CornerRadius="8" Padding="18">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <TextBlock Grid.Row="0" Text="已隐藏到托盘" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,10"/>
            <StackPanel Grid.Row="1">
                <TextBlock Text="关闭窗口后，VPN 工具会继续在通知区域运行。" TextWrapping="Wrap" Foreground="#404040" LineHeight="22"/>
                <TextBlock Text="你可以右键托盘图标执行登录、退出登录、打开日志或彻底退出。" TextWrapping="Wrap" Foreground="#404040" LineHeight="22" Margin="0,6,0,14"/>
                <CheckBox x:Name="DontShowAgain" Content="下次不再提示"/>
            </StackPanel>
            <Button Grid.Row="2" x:Name="OkButton" Content="知道了" Width="96" Height="34" HorizontalAlignment="Right" Background="#0067C0" Foreground="#FFFFFF" Margin="0,16,0,0"/>
        </Grid>
    </Border>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$tipXaml)
    $dialog = [Windows.Markup.XamlReader]::Load($reader)
    Set-WindowIcon -Window $dialog
    $dialog.Owner = $Owner
    $ok = $dialog.FindName('OkButton')
    $check = $dialog.FindName('DontShowAgain')
    $ok.Add_Click({ $dialog.DialogResult = $true })
    [void]$dialog.ShowDialog()
    return [bool]$check.IsChecked
}

function Start-Gui {
    Ensure-Admin
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Ensure-AppIcon
    Set-AppUserModelId

    $createdMutex = $false
    $script:EcnuOcSingleInstanceMutex = New-Object System.Threading.Mutex($true, 'Local\ECNUOpenConnectGuiSingleInstance', [ref]$createdMutex)
    if (-not $createdMutex) {
        [System.Windows.Forms.MessageBox]::Show('ECNU OpenConnect 已经在运行，请在托盘图标中操作。', 'ECNU OpenConnect', 'OK', 'Information') | Out-Null
        $script:EcnuOcSingleInstanceMutex.Dispose()
        return
    }

    $config = Get-Config
    $savedCred = Get-SavedCredential
    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ECNU OpenConnect" Width="900" Height="620" MinWidth="820" MinHeight="560"
        WindowStartupLocation="CenterScreen" Background="#F3F3F3" FontFamily="Segoe UI" FontSize="14">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Height" Value="38"/>
            <Setter Property="Padding" Value="16,0"/>
            <Setter Property="Margin" Value="0,0,10,0"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="#D0D0D0"/>
            <Setter Property="Background" Value="#FFFFFF"/>
            <Setter Property="Foreground" Value="#1F1F1F"/>
        </Style>
        <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="#0067C0"/>
            <Setter Property="BorderBrush" Value="#0067C0"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
        </Style>
        <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="#C42B1C"/>
            <Setter Property="BorderBrush" Value="#C42B1C"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Height" Value="34"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="BorderBrush" Value="#D0D0D0"/>
            <Setter Property="Background" Value="#FFFFFF"/>
        </Style>
        <Style TargetType="PasswordBox">
            <Setter Property="Height" Value="34"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="BorderBrush" Value="#D0D0D0"/>
            <Setter Property="Background" Value="#FFFFFF"/>
        </Style>
        <Style TargetType="ListBox">
            <Setter Property="BorderBrush" Value="#D0D0D0"/>
            <Setter Property="Background" Value="#FFFFFF"/>
        </Style>
    </Window.Resources>
    <Grid Margin="22">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <DockPanel Grid.Row="0" LastChildFill="True" Margin="0,0,0,18">
            <Border DockPanel.Dock="Right" Background="#E8F1FB" BorderBrush="#B7D7F4" BorderThickness="1" CornerRadius="16" Padding="14,6">
                <TextBlock x:Name="StatusText" Foreground="#005A9E" FontWeight="SemiBold"/>
            </Border>
            <StackPanel>
                <TextBlock Text="ECNU OpenConnect" FontSize="26" FontWeight="SemiBold" Foreground="#202020"/>
                <TextBlock x:Name="HostText" Margin="0,4,0,0" Foreground="#606060"/>
            </StackPanel>
        </DockPanel>

        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="330"/>
                <ColumnDefinition Width="18"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <Border Grid.Column="0" Background="#FFFFFF" BorderBrush="#E1E1E1" BorderThickness="1" CornerRadius="8" Padding="18">
                <StackPanel>
                    <TextBlock Text="账号" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,14"/>
                    <TextBlock Text="用户名" Foreground="#606060" Margin="0,0,0,6"/>
                    <TextBox x:Name="UserText" Margin="0,0,0,14"/>
                    <TextBlock Text="密码" Foreground="#606060" Margin="0,0,0,6"/>
                    <PasswordBox x:Name="PassText" Margin="0,0,0,12"/>
                    <CheckBox x:Name="RememberCheck" Content="保存密码到本机" Margin="0,0,0,22"/>

                    <Button x:Name="ActionButton" Content="登录" Style="{StaticResource PrimaryButton}" Margin="0,0,0,10"/>
                </StackPanel>
            </Border>

            <Grid Grid.Column="2">
                <Grid.RowDefinitions>
                    <RowDefinition Height="230"/>
                    <RowDefinition Height="18"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <Border Grid.Row="0" Background="#FFFFFF" BorderBrush="#E1E1E1" BorderThickness="1" CornerRadius="8" Padding="18">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <TextBlock Grid.Row="0" Text="走 VPN 的路由" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,12"/>
                        <ListBox Grid.Row="1" x:Name="RouteList" Margin="0,0,0,12"/>
                        <DockPanel Grid.Row="2" LastChildFill="True">
                            <Button DockPanel.Dock="Right" x:Name="RemoveRouteButton" Content="删除选中" Width="96" Margin="10,0,0,0"/>
                            <Button DockPanel.Dock="Right" x:Name="AddRouteButton" Content="添加" Width="76" Margin="10,0,0,0"/>
                            <TextBox x:Name="RouteText" Text="202.120.0.0/16"/>
                        </DockPanel>
                    </Grid>
                </Border>

                <Border Grid.Row="2" Background="#FFFFFF" BorderBrush="#E1E1E1" BorderThickness="1" CornerRadius="8" Padding="18">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        <TextBlock Grid.Row="0" Text="日志" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,12"/>
                        <DockPanel Grid.Row="1" LastChildFill="True" Margin="0,0,0,12">
                            <Button DockPanel.Dock="Right" x:Name="OpenLogFolderButton" Content="打开目录" Width="92" Margin="10,0,0,0"/>
                            <Button DockPanel.Dock="Right" x:Name="OpenLogButton" Content="打开日志" Width="92" Margin="10,0,0,0"/>
                            <TextBox x:Name="LogPathText" IsReadOnly="True" Height="34"/>
                        </DockPanel>
                        <TextBox Grid.Row="2" x:Name="LogText" FontFamily="Consolas" FontSize="12" TextWrapping="NoWrap"
                                 AcceptsReturn="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                                 IsReadOnly="True" Height="Auto"/>
                    </Grid>
                </Border>
            </Grid>
        </Grid>

        <TextBlock Grid.Row="2" Margin="2,14,0,0" Foreground="#707070"
                   Text="路由策略写入 internal\openconnect\vpnc-script-win.js；默认不添加全局 VPN 路由。"/>
    </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)
    Set-WindowIcon -Window $window
    $primaryButtonStyle = $window.Resources['PrimaryButton']
    $dangerButtonStyle = $window.Resources['DangerButton']

    $status = $window.FindName('StatusText')
    $hostText = $window.FindName('HostText')
    $userText = $window.FindName('UserText')
    $passText = $window.FindName('PassText')
    $rememberCheck = $window.FindName('RememberCheck')
    $routeList = $window.FindName('RouteList')
    $routeText = $window.FindName('RouteText')
    $logPathText = $window.FindName('LogPathText')
    $logText = $window.FindName('LogText')
    $actionButton = $window.FindName('ActionButton')
    $addRouteButton = $window.FindName('AddRouteButton')
    $removeRouteButton = $window.FindName('RemoveRouteButton')
    $openLogButton = $window.FindName('OpenLogButton')
    $openLogFolderButton = $window.FindName('OpenLogFolderButton')

    $hostText.Text = "服务器：$($config.Host)    认证组：$($config.AuthGroup)    默认不走代理"
    $logPathText.Text = $LogPath
    if ($savedCred) {
        $userText.Text = [string]$savedCred.UserName
        try {
            $passText.Password = ConvertFrom-SecureStringToPlain $savedCred.Password
        }
        catch {
            $passText.Clear()
        }
    }
    else {
        $userText.Text = Get-SavedUserName
    }
    $rememberCheck.IsChecked = [bool]$config.RememberPassword
    foreach ($route in @($config.AllowedRoutes)) { [void]$routeList.Items.Add([string]$route) }

    $script:EcnuOcReallyExit = $false
    $script:EcnuOcWasMinimizedToTray = $false
    $script:EcnuOcStoppedOnExit = $false

    $trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $trayStatusItem = $trayMenu.Items.Add('未连接')
    $trayStatusItem.Enabled = $false
    [void]$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $trayShowItem = $trayMenu.Items.Add('显示窗口')
    $trayActionItem = $trayMenu.Items.Add('登录')
    [void]$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $trayOpenLogItem = $trayMenu.Items.Add('打开日志')
    $trayOpenLogFolderItem = $trayMenu.Items.Add('打开日志目录')
    [void]$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $trayExitItem = $trayMenu.Items.Add('退出程序')

    $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
    if (Test-Path -LiteralPath $IconPath) {
        $notifyIcon.Icon = New-Object System.Drawing.Icon($IconPath)
    }
    else {
        $notifyIcon.Icon = [System.Drawing.SystemIcons]::Shield
    }
    $notifyIcon.Text = 'ECNU OpenConnect'
    $notifyIcon.ContextMenuStrip = $trayMenu
    $notifyIcon.Visible = $true

    function Show-Toast {
        param([string]$Title, [string]$Text)
        try {
            $notifyIcon.BalloonTipTitle = $Title
            $notifyIcon.BalloonTipText = $Text
            $notifyIcon.ShowBalloonTip(2500)
        }
        catch {
        }
    }

    function Show-UserMessage {
        param(
            [string]$Text,
            [string]$Title = 'ECNU OpenConnect',
            [string]$Icon = 'Information'
        )

        if ($window.IsVisible) {
            [System.Windows.MessageBox]::Show($window, $Text, $Title, 'OK', $Icon) | Out-Null
        }
        else {
            Show-Toast -Title $Title -Text $Text
        }
    }

    function Save-RoutesFromList {
        $cfg = Get-Config
        $items = @()
        foreach ($item in $routeList.Items) { $items += [string]$item }
        $cfg.AllowedRoutes = @($items)
        $cfg.RememberPassword = [bool]$rememberCheck.IsChecked
        Save-Config $cfg
        Update-VpncScriptRoutes -Routes $items
    }

    function Show-MainWindow {
        if (-not $window.IsVisible) { $window.Show() }
        if ($window.WindowState -eq [System.Windows.WindowState]::Minimized) {
            $window.WindowState = [System.Windows.WindowState]::Normal
        }
        $window.Activate() | Out-Null
        $script:EcnuOcWasMinimizedToTray = $false
    }

    function Refresh-Ui {
        $running = [bool](Get-SavedLauncherProcess)
        $status.Text = Get-StatusText
        $trayStatusItem.Text = $status.Text
        $notifyIcon.Text = if ($status.Text.Length -gt 63) { $status.Text.Substring(0, 63) } else { "ECNU OpenConnect - $($status.Text)" }
        if ($running) {
            $actionButton.Content = '退出登录'
            $actionButton.Style = $dangerButtonStyle
            $trayActionItem.Text = '退出登录'
            $userText.IsEnabled = $false
            $passText.IsEnabled = $false
            $rememberCheck.IsEnabled = $false
        }
        else {
            $actionButton.Content = '登录'
            $actionButton.Style = $primaryButtonStyle
            $trayActionItem.Text = '登录'
            $userText.IsEnabled = $true
            $passText.IsEnabled = $true
            $rememberCheck.IsEnabled = $true
            $saved = Get-SavedCredential
            if ($saved -and [string]::IsNullOrWhiteSpace($userText.Text)) {
                $userText.Text = $saved.UserName
            }
            if ($saved -and [string]::IsNullOrWhiteSpace($passText.Password)) {
                try {
                    $passText.Password = ConvertFrom-SecureStringToPlain $saved.Password
                }
                catch {
                    $passText.Clear()
                }
            }
        }
        $logText.Text = Get-LogTail
        $logText.CaretIndex = $logText.Text.Length
        $logText.ScrollToEnd()
    }

    function Invoke-PrimaryAction {
        try {
            $actionButton.IsEnabled = $false
            $trayActionItem.Enabled = $false
            if (Get-SavedLauncherProcess) {
                $status.Text = '正在退出登录...'
                $window.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background)
                Stop-Connection
                Refresh-Ui
                Show-UserMessage -Text '已退出登录。'
            }
            else {
                $status.Text = '正在登录...'
                $window.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background)
                Save-RoutesFromList
                if (Get-SavedLauncherProcess) {
                    throw '当前已登录，请先退出登录。'
                }
                $secure = ConvertTo-SecureStringFromPlain $passText.Password
                Start-Connection -UserName $userText.Text.Trim() -Password $secure -RememberPassword:([bool]$rememberCheck.IsChecked)
                $passText.Clear()
                Refresh-Ui
                Show-UserMessage -Text '登录流程已启动，路由策略已应用。'
            }
        }
        catch {
            Refresh-Ui
            if (Get-SavedLauncherProcess) {
                Show-UserMessage -Text '当前已登录，请先退出登录。'
            }
            else {
                if ($_.Exception.Message -match '认证失败|authentication|Login failed|Password:\s*fgets') {
                    Remove-SavedCredential
                    $passText.Clear()
                    $passText.IsEnabled = $true
                    $rememberCheck.IsEnabled = $true
                }
                Show-UserMessage -Text $_.Exception.Message -Title '登录失败' -Icon 'Error'
            }
        }
        finally {
            $actionButton.IsEnabled = $true
            $trayActionItem.Enabled = $true
        }
    }

    $actionButton.Add_Click({ Invoke-PrimaryAction })

    $addRouteButton.Add_Click({
        $value = $routeText.Text.Trim()
        if (-not (Test-Cidr $value)) {
            [System.Windows.MessageBox]::Show($window, '请输入有效 CIDR，例如 202.120.0.0/16。', '路由格式错误', 'OK', 'Warning') | Out-Null
            return
        }
        if (-not $routeList.Items.Contains($value)) {
            [void]$routeList.Items.Add($value)
            Save-RoutesFromList
        }
    })

    $removeRouteButton.Add_Click({
        if ($routeList.SelectedIndex -ge 0) {
            $routeList.Items.RemoveAt($routeList.SelectedIndex)
            Save-RoutesFromList
        }
    })

    $openLogButton.Add_Click({ Open-LogFile })
    $openLogFolderButton.Add_Click({ Open-LogFolder })

    $trayShowItem.Add_Click({ $window.Dispatcher.Invoke([Action]{ Show-MainWindow }) })
    $trayActionItem.Add_Click({ $window.Dispatcher.Invoke([Action]{ Invoke-PrimaryAction }) })
    $trayOpenLogItem.Add_Click({ Open-LogFile })
    $trayOpenLogFolderItem.Add_Click({ Open-LogFolder })
    $trayExitItem.Add_Click({
        $window.Dispatcher.Invoke([Action]{
            $script:EcnuOcReallyExit = $true
            try {
                Stop-Connection
                $script:EcnuOcStoppedOnExit = $true
            }
            catch {
                Write-AppLog "Stop on application exit failed: $($_.Exception.Message)" 'WARN'
            }
            $window.Close()
        })
    })
    $notifyIcon.Add_DoubleClick({ $window.Dispatcher.Invoke([Action]{ Show-MainWindow }) })

    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(2500)
    $timer.Add_Tick({ Refresh-Ui })
    $timer.Start()

    $window.Add_Closing({
        param($sender, $eventArgs)
        if (-not $script:EcnuOcReallyExit) {
            $eventArgs.Cancel = $true
            $cfg = Get-Config
            if (-not [bool]$cfg.CloseToTrayTipShown) {
                $dontShow = Show-CloseToTrayTip -Owner $window
                if ($dontShow) {
                    $cfg.CloseToTrayTipShown = $true
                    Save-Config $cfg
                }
            }
            $window.Hide()
            $script:EcnuOcWasMinimizedToTray = $true
            $notifyIcon.BalloonTipTitle = 'ECNU OpenConnect'
            $notifyIcon.BalloonTipText = '已隐藏到托盘。右键托盘图标可操作 VPN。'
            $notifyIcon.ShowBalloonTip(2500)
        }
    })

    $window.Add_Closed({
        if ($script:EcnuOcReallyExit -and -not $script:EcnuOcStoppedOnExit) {
            try { Stop-Connection } catch {}
        }
        $timer.Stop()
        $notifyIcon.Visible = $false
        $notifyIcon.Dispose()
        $trayMenu.Dispose()
        if ($script:EcnuOcSingleInstanceMutex) {
            try {
                $script:EcnuOcSingleInstanceMutex.ReleaseMutex()
                $script:EcnuOcSingleInstanceMutex.Dispose()
            }
            catch {
            }
        }
        [Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()
    })

    Refresh-Ui
    $window.Show()
    [Windows.Threading.Dispatcher]::Run()
}

switch ($Action) {
    'Gui' { Start-Gui }
    'Connect' { throw 'Connect action is driven by the GUI so credentials are not passed through the command line.' }
    'Disconnect' { Stop-Connection }
    'Status' { Get-StatusText | Write-Output }
    'WatchRoutes' { Watch-Routes }
    'CliLogin' { Start-CliLogin }
    'ForceStop' { Stop-OpenConnectForce }
}
