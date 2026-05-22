[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$GroupDisplayName,
    [ValidateSet("baseline-dev-tools", "strict-admin-only")][string]$ProfileName = "baseline-dev-tools",
    [string[]]$IncludeAppIds = @(),
    [string[]]$ExcludeAppIds = @(),
    [string]$TargetsFilePath = (Join-Path -Path $PSScriptRoot -ChildPath "AppTargets-AuthCodeFix.json"),
    [string]$TranscriptPath = (Join-Path -Path $PSScriptRoot -ChildPath ("ConsentFix-Run-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date)))
)
& (Join-Path $PSScriptRoot "EntraAppRole-AuthCodeFix.ps1") -Mode RunAll -GroupDisplayName $GroupDisplayName -ProfileName $ProfileName -IncludeAppIds $IncludeAppIds -ExcludeAppIds $ExcludeAppIds -TargetsFilePath $TargetsFilePath -Transcript -TranscriptPath $TranscriptPath -WhatIf:$WhatIfPreference
