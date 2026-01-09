Connect-MgGraph -Scopes "Application.Read.All","Directory.Read.All" -NoWelcome
# Define the apps to identify
$targetApps = @{
    "04b07795-8ddb-461a-bbee-02f9e1bf7b46" = "Microsoft Azure CLI"
    "1950a258-227b-4e31-a9cf-717495945fc2" = "Microsoft Azure PowerShell"
    "04f0c124-f2bc-4f59-8241-bf6df9866bbd" = "Visual Studio"
    "aebc6443-996d-45c2-90f0-388ff96faa56" = "Visual Studio Code"
    "12128f48-ec9e-42f0-b203-ea49fb6af367" = "MS Teams Powershell Cmdlets"
}

$results = foreach ($appId in $targetApps.Keys) {
    $filter = "AppId eq '$appId'"
    $cmd    = "Get-MgServicePrincipal -Filter `"$filter`" -ConsistencyLevel eventual -All"

    $status = "Unknown"        # Exists / Missing / Unknown
    $cmdStatus = "Failed"      # Succeeded / Failed
    $objectId = $null
    $matches = 0

    try {
        $sp = Get-MgServicePrincipal `
            -Filter $filter `
            -ConsistencyLevel eventual `
            -All `
            -ErrorAction Stop

        $cmdStatus = "Succeeded"

        if ($sp) {
            $status  = "Exists"
            $matches = @($sp).Count
            $objectId = ($sp | Select-Object -First 1).Id
        } else {
            $status = "Missing"
        }
    }
    catch {
        # Intentionally swallow errors; keep Unknown/Failed
    }

    [PSCustomObject]@{
        Name          = $targetApps[$appId]
        AppId         = $appId
        SP_Status     = $status
        Cmd_Status    = $cmdStatus
        Matches       = $matches
        ObjectId      = $objectId
        Command       = $cmd
    }
}

# Clean table view (hide the long Command by default)
$results |
    Sort-Object SP_Status, Name |
    Select-Object Name, AppId, SP_Status, Cmd_Status, Matches, ObjectId |
    Format-Table -AutoSize
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null