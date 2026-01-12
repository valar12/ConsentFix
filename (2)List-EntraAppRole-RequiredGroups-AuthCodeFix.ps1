Connect-MgGraph -Scopes "Application.Read.All","Directory.Read.All" -NoWelcome

$appIds = @(
  "04b07795-8ddb-461a-bbee-02f9e1bf7b46",  # Microsoft Azure CLI
  "1950a258-227b-4e31-a9cf-717495945fc2",  # Microsoft Azure PowerShell
  "04f0c124-f2bc-4f59-8241-bf6df9866bbd",  # Visual Studio
  "aebc6443-996d-45c2-90f0-388ff96faa56",  # Visual Studio Code
  "12128f48-ec9e-42f0-b203-ea49fb6af367"   # MS Teams Powershell Cmdlets
)

$results = foreach ($appId in $appIds) {

  $sp = Get-MgServicePrincipal -Filter "appId eq '$appId'" -Top 1 -ErrorAction Stop

  # Map roleId(string) -> role display name (if any)
  $roleMap = @{}
  foreach ($r in @($sp.AppRoles)) {
    if ($null -ne $r.Id) { $roleMap[$r.Id.ToString()] = $r.DisplayName }
  }

  $assignedTo = Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $sp.Id -All -ErrorAction Stop

  if (-not $assignedTo -or $assignedTo.Count -eq 0) {
    [PSCustomObject]@{
      ResourceDisplayName = $sp.DisplayName
      ResourceAppId       = $sp.AppId
      ResourceSpId        = $sp.Id
      AssignmentRequired  = $sp.AppRoleAssignmentRequired
      PrincipalType       = "<none>"
      PrincipalDisplayName= "<No assignments found>"
      PrincipalId         = $null
      AssignedRole        = $null
      AssignedRoleId      = $null
    }
    continue
  }

  foreach ($a in ($assignedTo | Sort-Object PrincipalType, PrincipalDisplayName)) {

    $roleIdStr = if ($null -ne $a.AppRoleId) { $a.AppRoleId.ToString() } else { $null }

    $roleName =
      if ([string]::IsNullOrWhiteSpace($roleIdStr)) { "<no app role>" }
      elseif ($roleMap.ContainsKey($roleIdStr))     { $roleMap[$roleIdStr] }
      else                                          { "<role id not in appRoles>" }

    [PSCustomObject]@{
      ResourceDisplayName  = $sp.DisplayName
      ResourceAppId        = $sp.AppId
      ResourceSpId         = $sp.Id
      AssignmentRequired   = $sp.AppRoleAssignmentRequired
      PrincipalType        = $a.PrincipalType
      PrincipalDisplayName = $a.PrincipalDisplayName
      PrincipalId          = $a.PrincipalId
      AssignedRole         = $roleName
      AssignedRoleId       = $a.AppRoleId
    }
  }
}

$results | Format-Table -AutoSize
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null