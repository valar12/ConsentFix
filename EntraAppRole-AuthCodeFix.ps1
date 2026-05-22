<#
.SYNOPSIS
Unified ConsentFix mitigation script for identify, enforce, validate, and orchestrated execution.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Identify","Enforce","Validate","RunAll")]
    [string]$Mode,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$GroupDisplayName,

    [Parameter(Mandatory = $false)]
    [ValidateSet("baseline-dev-tools", "strict-admin-only")]
    [string]$ProfileName = "baseline-dev-tools",

    [Parameter(Mandatory = $false)]
    [string[]]$IncludeAppIds = @(),

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludeAppIds = @(),

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$TargetsFilePath = (Join-Path -Path $PSScriptRoot -ChildPath "AppTargets-AuthCodeFix.json"),

    [Parameter(Mandatory = $false)]
    [switch]$Transcript,

    [Parameter(Mandatory = $false)]
    [string]$TranscriptPath = (Join-Path -Path $PSScriptRoot -ChildPath ("ConsentFix-Run-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date)))
)

function Get-AppsFromProfile {
    param([string]$Path,[string]$Profile,[string[]]$Include,[string[]]$Exclude)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Targets file not found: $Path" }
    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    if (-not $config.profiles.PSObject.Properties.Name.Contains($Profile)) {
        throw "Profile '$Profile' not found."
    }
    $map = @{}
    foreach ($p in $config.profiles.$Profile.apps.PSObject.Properties) { $map[$p.Name] = [string]$p.Value }
    foreach ($id in $Include) { if (-not $map.ContainsKey($id)) { $map[$id] = "Custom include" } }
    foreach ($id in $Exclude) { if ($map.ContainsKey($id)) { $map.Remove($id) } }
    if ($map.Count -eq 0) { throw "No app IDs remain after include/exclude processing." }
    return $map
}

function Connect-GraphForMode {
    param([string]$SelectedMode)
    $scopes = switch ($SelectedMode) {
        "Identify" { @("Application.Read.All","Directory.Read.All") }
        "Validate" { @("Application.Read.All","Directory.Read.All") }
        default { @("Application.ReadWrite.All","AppRoleAssignment.ReadWrite.All","Group.ReadWrite.All") }
    }
    Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop
}

function Invoke-Identify {
    param([hashtable]$AppMap)
    $results = foreach ($appId in $AppMap.Keys) {
        $filter = "AppId eq '$appId'"
        $status = "Unknown"; $cmdStatus = "Failed"; $objectId = $null; $matches = 0
        try {
            $sp = Get-MgServicePrincipal -Filter $filter -ConsistencyLevel eventual -All -ErrorAction Stop
            $cmdStatus = "Succeeded"
            if ($sp) { $status = "Exists"; $matches = @($sp).Count; $objectId = ($sp | Select-Object -First 1).Id } else { $status = "Missing" }
        } catch { }
        [PSCustomObject]@{ Name=$AppMap[$appId]; AppId=$appId; SP_Status=$status; Cmd_Status=$cmdStatus; Matches=$matches; ObjectId=$objectId }
    }
    $results | Sort-Object SP_Status, Name | Format-Table -AutoSize
}

function Invoke-Enforce {
    param([hashtable]$AppMap,[string]$TargetGroup)
    if ([string]::IsNullOrWhiteSpace($TargetGroup)) { throw "-GroupDisplayName is required for Enforce/RunAll." }
    $group = Get-MgGroup -Filter "displayName eq '$($TargetGroup -replace "'","''")'" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $group) {
        if ($PSCmdlet.ShouldProcess("Group($TargetGroup)", "Create")) {
            $mailNick = (($TargetGroup -replace '[^a-zA-Z0-9]', '') + "-" + [guid]::NewGuid().ToString('N').Substring(0,8))
            $group = New-MgGroup -DisplayName $TargetGroup -MailEnabled:$false -MailNickname $mailNick.Substring(0,[Math]::Min(64,$mailNick.Length)) -SecurityEnabled:$true -Description "Grants access to locked-down Microsoft CLI/dev tools service principals." -ErrorAction Stop
        }
    }
    if (-not $group) { throw "Group '$TargetGroup' was not created/found." }

    foreach ($appId in $AppMap.Keys) {
        $sp = Get-MgServicePrincipal -Filter "appId eq '$appId'" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $sp -and $PSCmdlet.ShouldProcess("ServicePrincipal($appId)", "Create")) {
            New-MgServicePrincipal -AppId $appId -ErrorAction Stop | Out-Null
            Start-Sleep -Seconds 2
            $sp = Get-MgServicePrincipal -Filter "appId eq '$appId'" -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if (-not $sp) { Write-Host "Skipping appId $appId (SP unavailable)." -ForegroundColor Yellow; continue }
        if ($PSCmdlet.ShouldProcess("ServicePrincipal($($sp.DisplayName))", "Set AppRoleAssignmentRequired=true")) {
            Update-MgServicePrincipal -ServicePrincipalId $sp.Id -AppRoleAssignmentRequired:$true -ErrorAction Stop
        }
        $existing = Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $sp.Id -Filter "principalId eq $($group.Id)" -All -ErrorAction SilentlyContinue
        if (-not $existing -and $PSCmdlet.ShouldProcess("Assignment($($group.DisplayName) -> $($sp.DisplayName))", "Create")) {
            New-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $sp.Id -PrincipalId $group.Id -ResourceId $sp.Id -AppRoleId "00000000-0000-0000-0000-000000000000" -ErrorAction Stop | Out-Null
        }
    }
}

function Invoke-Validate {
    param([hashtable]$AppMap)
    $results = foreach ($appId in $AppMap.Keys) {
        $sp = Get-MgServicePrincipal -Filter "appId eq '$appId'" -Top 1 -ErrorAction SilentlyContinue
        if (-not $sp) { continue }
        $assignedTo = Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $sp.Id -All -ErrorAction SilentlyContinue
        if (-not $assignedTo) {
            [PSCustomObject]@{ ResourceDisplayName=$sp.DisplayName; ResourceAppId=$sp.AppId; AssignmentRequired=$sp.AppRoleAssignmentRequired; PrincipalType="<none>"; PrincipalDisplayName="<No assignments found>" }
            continue
        }
        foreach ($a in ($assignedTo | Sort-Object PrincipalType, PrincipalDisplayName)) {
            [PSCustomObject]@{ ResourceDisplayName=$sp.DisplayName; ResourceAppId=$sp.AppId; AssignmentRequired=$sp.AppRoleAssignmentRequired; PrincipalType=$a.PrincipalType; PrincipalDisplayName=$a.PrincipalDisplayName }
        }
    }
    $results | Format-Table -AutoSize
}

$startTranscript = $Transcript -or $Mode -eq 'RunAll'
if ($startTranscript) { Start-Transcript -Path $TranscriptPath | Out-Null }
try {
    $appMap = Get-AppsFromProfile -Path $TargetsFilePath -Profile $ProfileName -Include $IncludeAppIds -Exclude $ExcludeAppIds
    Connect-GraphForMode -SelectedMode $Mode
    switch ($Mode) {
        "Identify" { Invoke-Identify -AppMap $appMap }
        "Enforce"  { Invoke-Enforce -AppMap $appMap -TargetGroup $GroupDisplayName }
        "Validate" { Invoke-Validate -AppMap $appMap }
        "RunAll" {
            Invoke-Identify -AppMap $appMap
            Invoke-Enforce -AppMap $appMap -TargetGroup $GroupDisplayName
            Invoke-Validate -AppMap $appMap
        }
    }
}
finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    if ($startTranscript) { Stop-Transcript | Out-Null }
}
