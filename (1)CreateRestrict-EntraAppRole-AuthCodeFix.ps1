[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$GroupDisplayName,
    [string]$ProfileName = "baseline-dev-tools",
    [string[]]$IncludeAppIds = @(),
    [string[]]$ExcludeAppIds = @(),
    [string]$TargetsFilePath = (Join-Path -Path $PSScriptRoot -ChildPath "AppTargets-AuthCodeFix.json")
)
& (Join-Path $PSScriptRoot "EntraAppRole-AuthCodeFix.ps1") -Mode Enforce -GroupDisplayName $GroupDisplayName -ProfileName $ProfileName -IncludeAppIds $IncludeAppIds -ExcludeAppIds $ExcludeAppIds -TargetsFilePath $TargetsFilePath -WhatIf:$WhatIfPreference
