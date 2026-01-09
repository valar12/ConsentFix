Connect-MgGraph -Scopes "Application.Read.All","Directory.Read.All" -NoWelcome
$results = foreach ($appId in $targetApps.Keys) {

    $sp = Get-MgServicePrincipal `
        -Filter "appId eq '$appId'" `
        -ConsistencyLevel eventual `
        -All `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (-not $sp) {
        [PSCustomObject]@{
            AppName         = $targetApps[$appId]
            AppId           = $appId
            SP_DisplayName  = $null
            SP_ObjectId     = $null
            RequiredGroups  = "<SP not found>"
        }
        continue
    }

    # App role assignments TO this service principal (who has access)
    $assignedTo = Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $sp.Id -All -ErrorAction SilentlyContinue

    $groups = $assignedTo |
        Where-Object { $_.PrincipalType -eq "Group" } |
        Sort-Object PrincipalDisplayName |
        Select-Object -ExpandProperty PrincipalDisplayName -Unique

    [PSCustomObject]@{
        AppName         = $targetApps[$appId]
        AppId           = $appId
        SP_DisplayName  = $sp.DisplayName
        SP_ObjectId     = $sp.Id
        RequiredGroups  = if ($groups) { $groups -join "; " } else { "<No group assigned>" }
    }
}

$results | Format-Table -AutoSize
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null