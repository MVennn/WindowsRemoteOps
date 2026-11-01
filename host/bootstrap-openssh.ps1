<#
.SYNOPSIS
    Enable OpenSSH Server on this Windows host and authorize one public key.

.DESCRIPTION
    One-time bootstrap for remote administration over SSH. Every action is
    idempotent and printed as it happens. The script does NOT change the
    default shell, UAC, group policy, or any sshd_config option unless
    -DisablePasswordAuth is passed explicitly.

    Steps:
      1. Verify the session is elevated.
      2. Install the OpenSSH.Server optional capability (skip if present).
      3. Set the sshd service to Automatic and start it.
      4. Ensure an inbound firewall rule allows TCP <Port>.
      5. Append the public key to the correct authorized_keys file:
           - administrator accounts -> %ProgramData%\ssh\administrators_authorized_keys
           - standard accounts      -> <profile>\.ssh\authorized_keys
      6. Tighten the ACL on administrators_authorized_keys (required by sshd).
      7. Optional: disable password authentication and restart sshd.

    NOTE: keep this file pure ASCII. Windows PowerShell 5.1 decodes a file
    without a BOM using the ANSI code page, so non-ASCII characters would be
    mangled and can break parsing.

.PARAMETER PublicKeyFile
    Path to the public key file to authorize (for example id_ed25519.pub).

.PARAMETER User
    Account the key belongs to. Defaults to the current user. This decides
    which authorized_keys file is written.

.PARAMETER Port
    TCP port to allow through the firewall. Default 22.

.PARAMETER DisablePasswordAuth
    Set PasswordAuthentication to no in sshd_config and restart sshd.
    Run this ONLY after key authentication has been verified from the client.

.PARAMETER WhatIf
    Print the planned actions without changing anything.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\bootstrap-openssh.ps1 -PublicKeyFile .\id_ed25519.pub

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\bootstrap-openssh.ps1 -PublicKeyFile .\id_ed25519.pub -DisablePasswordAuth
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublicKeyFile,

    [string]$User = "",

    [ValidateRange(1, 65535)]
    [int]$Port = 22,

    [switch]$DisablePasswordAuth
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:Failed = $false

function Write-Step {
    param([string]$Message)
    Write-Host "[*] $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Message)
    Write-Host "[=] $Message" -ForegroundColor DarkGray
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Fail {
    param([string]$Message)
    Write-Host "[x] $Message" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------- 1. elevation
Write-Step "Checking elevation"
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail "This script must run in an elevated (Administrator) PowerShell session."
}
Write-Ok "Running elevated"

# ---------------------------------------------------------------- 2. public key
Write-Step "Reading public key"
if (-not (Test-Path -LiteralPath $PublicKeyFile)) {
    Fail "Public key file not found: $PublicKeyFile"
}
$keyLine = (Get-Content -LiteralPath $PublicKeyFile -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($keyLine)) {
    Fail "Public key file is empty: $PublicKeyFile"
}
$keyLine = ($keyLine -split "`r?`n")[0].Trim()
if ($keyLine -notmatch '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-|sk-ssh-|sk-ecdsa-)') {
    Fail "File does not look like an OpenSSH public key: $PublicKeyFile"
}
$keyParts = $keyLine -split '\s+'
if ($keyParts.Count -lt 2 -or [string]::IsNullOrWhiteSpace($keyParts[1])) {
    Fail "Public key line has no key body: $PublicKeyFile"
}
$keyBody = $keyParts[1]
Write-Ok ("Key type: " + $keyParts[0] + ", fingerprint input length: " + $keyBody.Length)

# ---------------------------------------------------------------- 3. account
Write-Step "Resolving target account"
if ([string]::IsNullOrWhiteSpace($User)) {
    $User = $env:USERNAME
}
$isAdminAccount = $false
try {
    $adminGroupName = (Get-LocalGroup -SID "S-1-5-32-544").Name
    $members = Get-LocalGroupMember -Group $adminGroupName -ErrorAction Stop
    foreach ($m in $members) {
        $shortName = ($m.Name -split '\\')[-1]
        if ($shortName -ieq $User) { $isAdminAccount = $true; break }
    }
}
catch {
    Write-Warn "Could not enumerate the Administrators group: $($_.Exception.Message)"
    if ($User -ieq $env:USERNAME) {
        # The process token already answers the question: this script refuses
        # to run unelevated, and an elevated token comes from an admin account.
        $isAdminAccount = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        Write-Warn "Falling back to the process token check; admin = $isAdminAccount"
    }
    else {
        # Guessing wrong here means the key lands in the file sshd never reads
        # for this account (PITFALLS P2). Stop instead of writing it.
        Fail "Cannot determine whether '$User' is an administrator, so the correct authorized_keys file is unknown. Check with 'net localgroup administrators' and re-run."
    }
}
if ($isAdminAccount) {
    Write-Ok "Account '$User' is in the local Administrators group"
}
else {
    Write-Ok "Account '$User' is a standard user"
}

# ---------------------------------------------------------------- 4. capability
Write-Step "Checking the OpenSSH.Server capability"
$capability = Get-WindowsCapability -Online -Name "OpenSSH.Server*" | Select-Object -First 1
if ($null -eq $capability) {
    Fail "This Windows image does not offer the OpenSSH.Server capability. Use the Win32-OpenSSH MSI instead (see docs/RECON-WINDOWS-SSH.md, option D)."
}
if ($capability.State -eq "Installed") {
    Write-Skip "Already installed: $($capability.Name)"
}
else {
    if ($PSCmdlet.ShouldProcess($capability.Name, "Install Windows capability")) {
        Add-WindowsCapability -Online -Name $capability.Name | Out-Null
        Write-Ok "Installed $($capability.Name)"
    }
}

# ---------------------------------------------------------------- 5. service
Write-Step "Configuring the sshd service"
if ($PSCmdlet.ShouldProcess("sshd", "Set startup type to Automatic and start")) {
    Set-Service -Name sshd -StartupType Automatic
    $svc = Get-Service -Name sshd
    if ($svc.Status -ne "Running") {
        Start-Service -Name sshd
    }
    $svc = Get-Service -Name sshd
    Write-Ok ("sshd is " + $svc.Status + " / " + $svc.StartType)
}

# ---------------------------------------------------------------- 6. firewall
Write-Step "Ensuring the inbound firewall rule for TCP $Port"
$ruleName = "OpenSSH-Server-In-TCP"
$rule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
if ($null -eq $rule) {
    if ($PSCmdlet.ShouldProcess($ruleName, "Create inbound allow rule for TCP $Port")) {
        New-NetFirewallRule -Name $ruleName -DisplayName "OpenSSH Server (sshd)" `
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort $Port -Profile Any | Out-Null
        Write-Ok "Created firewall rule $ruleName (TCP $Port, profile Any)"
    }
}
else {
    # The capability ships this rule scoped to the Private profile. On a host
    # whose network is classified as Public the rule matches nothing, yet it
    # still reads Enabled=True - so never trust the existing rule, force it.
    # Do NOT try New-NetFirewallRule as a fallback: the name already exists and
    # the error would be swallowed by -ErrorAction SilentlyContinue.
    if ($PSCmdlet.ShouldProcess($ruleName, "Force Enabled=True, Profile=Any, Action=Allow, LocalPort=$Port")) {
        Set-NetFirewallRule -Name $ruleName -Enabled True -Profile Any -Action Allow
        # The port lives on the associated port filter, not on the rule itself:
        # Set-NetFirewallRule cannot change it, so a stale port (e.g. 22 from
        # the capability) would stay in place while the script reports -Port
        # as applied. Rewrite the filter explicitly, idempotently.
        $null = Get-NetFirewallRule -Name $ruleName | Set-NetFirewallPortFilter -Protocol TCP -LocalPort $Port
        Write-Ok "Updated firewall rule $ruleName (TCP $Port, profile Any)"
    }
}

$netProfiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue
foreach ($p in $netProfiles) {
    if ($p.NetworkCategory -eq "Public") {
        Write-Warn ("Network '" + $p.Name + "' is on the Public profile; the rule may not apply. Consider setting it to Private.")
    }
}

# ---------------------------------------------------------------- 7. authorized_keys
Write-Step "Writing the public key"
if ($isAdminAccount) {
    $authFile = Join-Path $env:ProgramData "ssh\administrators_authorized_keys"
}
else {
    if ($User -ine $env:USERNAME) {
        # The account may have been renamed, in which case the profile folder
        # does not match the account name. Resolve the real profile path from
        # the registry instead of assuming C:\Users\<name>.
        $sid = $null
        try {
            $sid = (Get-LocalUser -Name $User -ErrorAction Stop).SID
        }
        catch {
            Fail "Cannot resolve a local account named '$User': $($_.Exception.Message)"
        }
        $profileKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"
        $profilePath = (Get-ItemProperty -Path $profileKey -ErrorAction SilentlyContinue).ProfileImagePath
        if ([string]::IsNullOrWhiteSpace($profilePath)) {
            Fail "Cannot resolve the profile path for '$User' (SID $sid). Pass the key for the current user instead."
        }
        $authFile = Join-Path $profilePath ".ssh\authorized_keys"
        Write-Ok "Resolved profile path: $profilePath"
    }
    else {
        $authFile = Join-Path $env:USERPROFILE ".ssh\authorized_keys"
    }
}
$authDir = Split-Path -Parent $authFile
if (-not (Test-Path -LiteralPath $authDir)) {
    if ($PSCmdlet.ShouldProcess($authDir, "Create directory")) {
        New-Item -ItemType Directory -Path $authDir -Force | Out-Null
    }
}

$already = $false
$needsNewline = $false
if (Test-Path -LiteralPath $authFile) {
    $raw = Get-Content -LiteralPath $authFile -Raw -ErrorAction SilentlyContinue
    if (-not [string]::IsNullOrEmpty($raw)) {
        # Add-Content never prepends a newline: if the file does not end with
        # one, the new key would be glued to the last line and destroy that
        # entry too. Remember to emit a line break first.
        $needsNewline = -not $raw.EndsWith("`n")
        foreach ($line in ($raw -split "`r?`n")) {
            $parts = ($line.Trim() -split '\s+')
            if ($parts.Count -ge 2 -and $parts[1] -eq $keyBody) { $already = $true; break }
        }
    }
}
if ($already) {
    Write-Skip "Key already present in $authFile"
}
else {
    if ($PSCmdlet.ShouldProcess($authFile, "Append public key")) {
        $value = if ($needsNewline) { "`r`n" + $keyLine } else { $keyLine }
        Add-Content -LiteralPath $authFile -Value $value -Encoding ASCII
        Write-Ok "Appended key to $authFile"
    }
}

if ($isAdminAccount) {
    Write-Step "Tightening ACL on administrators_authorized_keys"
    if ($PSCmdlet.ShouldProcess($authFile, "Reset inheritance; grant Administrators and SYSTEM")) {
        # Use well-known SIDs instead of group names: "Administrators" / "SYSTEM"
        # are localized on non-English Windows and would not resolve.
        #   S-1-5-32-544 = BUILTIN\Administrators, S-1-5-18 = NT AUTHORITY\SYSTEM
        $null = icacls $authFile /inheritance:r /grant "*S-1-5-32-544:F" /grant "*S-1-5-18:F"
        if ($LASTEXITCODE -ne 0) {
            # A too-permissive ACL makes sshd silently ignore this file
            # (PITFALLS P1) - that must not look like success.
            Fail "icacls could not tighten the ACL on $authFile (exit code $LASTEXITCODE). sshd would silently ignore this file - see docs/PITFALLS.md P1."
        }
        Write-Ok "ACL restricted to Administrators and SYSTEM"
    }
}

# ---------------------------------------------------------------- 8. optional hardening
if ($DisablePasswordAuth) {
    Write-Step "Disabling password and keyboard-interactive authentication"
    $configPath = Join-Path $env:ProgramData "ssh\sshd_config"
    if (-not (Test-Path -LiteralPath $configPath)) {
        Fail "sshd_config not found: $configPath"
    }
    if ($PSCmdlet.ShouldProcess($configPath, "Disable password auth and restart sshd")) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backup = "$configPath.bak-$stamp"
        Copy-Item -LiteralPath $configPath -Destination $backup
        Write-Ok "Backed up sshd_config to $backup"

        # PasswordAuthentication alone is not enough on Windows: keyboard-
        # interactive stays enabled and sshd still accepts a typed password
        # through it. Both have to go.
        $text = Get-Content -LiteralPath $configPath -Raw
        foreach ($directive in @("PasswordAuthentication", "KbdInteractiveAuthentication")) {
            # Matches both "Directive yes" and the commented default "#Directive yes".
            $pattern = "(?m)^\s*#?\s*$directive\s+(yes|no)\s*$"
            if ([regex]::IsMatch($text, $pattern)) {
                $text = [regex]::Replace($text, $pattern, "$directive no")
            }
            else {
                # Appending at the very end would put the directive inside a
                # "Match" block when the config ends with one (the Windows
                # default does). Inside Match it only affects those connections
                # and password auth stays on in the main scope (PITFALLS P11).
                # Insert above the first top-level Match line instead.
                $matchLine = [regex]::Match($text, "(?mi)^\s*match\b")
                $line = "$directive no`r`n"
                if ($matchLine.Success) {
                    $text = $text.Substring(0, $matchLine.Index) + $line + $text.Substring($matchLine.Index)
                }
                else {
                    $text = $text.TrimEnd() + "`r`n" + $line
                }
            }
            Write-Ok "$directive -> no"
        }
        Set-Content -LiteralPath $configPath -Value $text -Encoding ASCII -NoNewline

        # Validate before restarting: a config sshd cannot parse would leave the
        # service down. On failure, put the backup back and stop - the machine
        # then keeps its previous (working) authentication configuration.
        $sshdExe = Join-Path $env:WinDir "System32\OpenSSH\sshd.exe"
        if (Test-Path -LiteralPath $sshdExe) {
            & $sshdExe -t
            if ($LASTEXITCODE -ne 0) {
                Copy-Item -LiteralPath $backup -Destination $configPath -Force
                Fail "sshd rejected the new sshd_config (exit code $LASTEXITCODE); restored the backup. Nothing else was changed."
            }
        }

        # -Force is required: a plain Restart-Service fails with
        # ServiceHasDependentServices and silently leaves the old config loaded.
        Restart-Service -Name sshd -Force
        if ((Get-Service -Name sshd).Status -ne "Running") {
            Fail "sshd did not come back to Running after the restart. Restore the backup: Copy-Item '$backup' '$configPath' -Force"
        }
        Write-Ok "sshd restarted; only publickey authentication is accepted now"
        Write-Warn "Verify from the operator machine that password auth is really gone (docs/PITFALLS.md P11) - do not trust the config file alone."
    }
}

# ---------------------------------------------------------------- 9. summary
Write-Host ""
Write-Step "Summary"
Write-Host ("    capability : " + $capability.Name)
$svcSummary = Get-Service -Name sshd -ErrorAction SilentlyContinue
Write-Host ("    service    : " + $(if ($null -ne $svcSummary) { $svcSummary.Status } else { "not installed" }))
Write-Host ("    account    : " + $User + " (admin: " + $isAdminAccount + ")")
Write-Host ("    key file   : " + $authFile)
Write-Host ("    port       : " + $Port)
Write-Host ""
Write-Host "Next: from the operator machine, run tools/verify-host.py" -ForegroundColor Cyan
Write-Host "Do NOT disable password authentication before key login is verified." -ForegroundColor Yellow

if ($script:Failed) { exit 1 }
exit 0
