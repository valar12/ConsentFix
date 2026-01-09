<#
.SYNOPSIS
Creates (if needed) a security group, ensures service principals exist for a set of appIds,
locks them down (AppRoleAssignmentRequired = $true), and assigns the group to each app.

.NOTES
https://msendpointmgr.com/2026/01/08/consentfix-quickfix/
Requires Microsoft Graph PowerShell SDK.
Scopes used:
- Application.ReadWrite.All
- AppRoleAssignment.ReadWrite.All
- Group.ReadWrite.All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$GroupDisplayName,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Apps = @(
        "04b07795-8ddb-461a-bbee-02f9e1bf7b46",  # Microsoft Azure CLI
        "1950a258-227b-4e31-a9cf-717495945fc2",  # Microsoft Azure PowerShell
        "04f0c124-f2bc-4f59-8241-bf6df9866bbd",  # Visual Studio
        "aebc6443-996d-45c2-90f0-388ff96faa56",  # Visual Studio Code
        "12128f48-ec9e-42f0-b203-ea49fb6af367"   # MS Teams Powershell Cmdlets
    )
)

# -------------------------
# Helpers (recommended)
# -------------------------
function Escape-ODataString {
    param([Parameter(Mandatory)][string]$Value)
    # OData: escape single quotes by doubling them
    return $Value -replace "'", "''"
}

function Get-OrCreateServicePrincipalByAppId {
    param(
        [Parameter(Mandatory)][string]$AppId,
        [int]$MaxAttempts = 8,
        [int]$DelaySeconds = 2
    )

    $sp = Get-MgServicePrincipal -Filter "appId eq '$AppId'" -ErrorAction SilentlyContinue
    if ($sp) { return ($sp | Select-Object -First 1) }

    Write-Host "Creating service principal for $AppId..." -ForegroundColor Cyan
    New-MgServicePrincipal -AppId $AppId -ErrorAction Stop | Out-Null

    # Retry due to eventual consistency after SP creation
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        Start-Sleep -Seconds $DelaySeconds
        $sp = Get-MgServicePrincipal -Filter "appId eq '$AppId'" -ErrorAction SilentlyContinue
        if ($sp) { return ($sp | Select-Object -First 1) }
    }

    return $null
}

# -------------------------
# Import module + connect
# -------------------------
try {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
        throw "Microsoft.Graph PowerShell SDK is not installed."
    }

    Import-Module Microsoft.Graph -ErrorAction Stop
    Import-Module Microsoft.Graph.Applications -ErrorAction SilentlyContinue
    Import-Module Microsoft.Graph.Groups -ErrorAction SilentlyContinue
    Import-Module Microsoft.Graph.Users -ErrorAction SilentlyContinue

    $requiredScopes = @(
        "Application.ReadWrite.All",
        "AppRoleAssignment.ReadWrite.All",
        "Group.ReadWrite.All"
    )

    $ctx = Get-MgContext
    $needConnect = $true

    if ($ctx -and $ctx.Account) {
        # If already connected, ensure required scopes are present
        $missing = $requiredScopes | Where-Object { $_ -notin $ctx.Scopes }
        if (-not $missing) { $needConnect = $false }
        else {
            Write-Host "Connected as $($ctx.Account) but missing scopes: $($missing -join ', '). Reconnecting..." -ForegroundColor Yellow
        }
    }

    if ($needConnect) {
        Connect-MgGraph -NoWelcome -Scopes $requiredScopes -ErrorAction Stop
    }

    $ctx = Get-MgContext
    Write-Host "Connected to Microsoft Graph as $($ctx.Account)." -ForegroundColor Green
}
catch {
    throw "Failed to import/connect to Microsoft Graph. $($_.Exception.Message)"
}

# -------------------------
# Ensure group exists (create if missing)
# -------------------------
$escapedName = Escape-ODataString -Value $GroupDisplayName

$groups = Get-MgGroup -Filter "displayName eq '$escapedName'" -ErrorAction SilentlyContinue

if ($groups -and $groups.Count -gt 1) {
    throw "Multiple groups found named '$GroupDisplayName'. Use a unique name or query by Id."
}

$group = $null
if (-not $groups) {
    Write-Host "Group '$GroupDisplayName' not found. Creating..." -ForegroundColor Cyan

    # MailNickname is required even when MailEnabled = $false
    $mailNick = ($GroupDisplayName -replace '[^a-zA-Z0-9]', '')
    if ([string]::IsNullOrWhiteSpace($mailNick)) { $mailNick = "AppAccess" }
    $base = $mailNick.Substring(0, [Math]::Min(40, $mailNick.Length))
    $mailNick = "$base-$([guid]::NewGuid().ToString('N').Substring(0,8))"

    $group = New-MgGroup `
        -DisplayName $GroupDisplayName `
        -MailEnabled:$false `
        -MailNickname $mailNick `
        -SecurityEnabled:$true `
        -Description "Grants access to locked-down Microsoft CLI/dev tools service principals." `
        -ErrorAction Stop

    if (-not $group) { throw "Failed to create group '$GroupDisplayName'." }
}
else {
    $group = $groups | Select-Object -First 1
}

# -------------------------
# Validate group is security-enabled
# -------------------------
$secEnabled = (Get-MgGroup -GroupId $group.Id -Property "securityEnabled" -ErrorAction Stop).SecurityEnabled
if (-not $secEnabled) {
    throw "Group '$($group.DisplayName)' ($($group.Id)) is NOT security-enabled. App role assignment requires a security group."
}

Write-Host "Using group '$($group.DisplayName)' ($($group.Id)) [security-enabled]." -ForegroundColor Green

# -------------------------
# Ensure SPs exist, lock down, and assign group
# -------------------------
foreach ($appId in $Apps) {
    try {
        $sp = Get-OrCreateServicePrincipalByAppId -AppId $appId
        if (-not $sp) {
            Write-Host "Failed to create/find service principal for $appId. Skipping." -ForegroundColor Red
            continue
        }

        # Lock down: require assignment
        Write-Host "Locking down $($sp.DisplayName)..." -ForegroundColor Yellow
        Update-MgServicePrincipal -ServicePrincipalId $sp.Id -AppRoleAssignmentRequired:$true -ErrorAction Stop

        # Avoid duplicate assignment
        $existing = Get-MgServicePrincipalAppRoleAssignedTo `
            -ServicePrincipalId $sp.Id `
            -Filter "principalId eq $($group.Id)" `
            -All `
            -ErrorAction SilentlyContinue

        if ($existing) {
            Write-Host "Already assigned: group '$($group.DisplayName)' -> $($sp.DisplayName)" -ForegroundColor DarkGray
            continue
        }

        # Assign group to app (default app role)
        New-MgServicePrincipalAppRoleAssignedTo `
            -ServicePrincipalId $sp.Id `
            -PrincipalId $group.Id `
            -ResourceId $sp.Id `
            -AppRoleId "00000000-0000-0000-0000-000000000000" `
            -ErrorAction Stop | Out-Null

        Write-Host "Assigned: group '$($group.DisplayName)' -> $($sp.DisplayName)" -ForegroundColor Green
    }
    catch {
        Write-Host "Error processing appId $appId $($_.Exception.Message)" -ForegroundColor Red
        continue
    }
}

Write-Host "`nDone! Apps are locked down and the group is created/validated + assigned." -ForegroundColor Green
Write-Host "Users must be in '$GroupDisplayName' (or otherwise assigned) to use these apps." -ForegroundColor Green