#Requires -Version 5.1

<#
.SYNOPSIS
Counts Windows Hello for Business enrolment artefacts on the local device.

.DESCRIPTION
This script is designed for Microsoft Intune remediation detection scripts,
Configuration Manager baselines, or local administrative checks.

It inspects the local Windows Hello for Business NGC store:

  C:\Windows\ServiceProfiles\LocalService\AppData\Local\Microsoft\NGC

The NGC store is protected by Windows and should be treated as read-only. Do not
delete or change its contents as part of monitoring.

For best results, run as Local System. Intune remediation scripts run as System
when "Run this script using the logged-on credentials" is set to No.

The script exits:
  0 = below warning threshold
  1 = at or above warning threshold
  2 = could not inspect the local NGC store
#>

[CmdletBinding()]
param(
    [int] $WarningThreshold = 8,

    [int] $LimitThreshold = 10,

    [string] $NgcPath = "$env:windir\ServiceProfiles\LocalService\AppData\Local\Microsoft\NGC",

    [switch] $Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-Result {
    param(
        [Parameter(Mandatory)]
        [string] $Status,

        [Parameter(Mandatory)]
        [int] $EnrollmentCount,

        [string[]] $Sids = @(),

        [string[]] $ContainerNames = @(),

        [string] $Message
    )

    [pscustomobject]@{
        ComputerName     = $env:COMPUTERNAME
        NgcPath          = $NgcPath
        EnrollmentCount  = $EnrollmentCount
        WarningThreshold = $WarningThreshold
        LimitThreshold   = $LimitThreshold
        Status           = $Status
        Sids             = $Sids
        ContainerNames   = $ContainerNames
        Message          = $Message
        CheckedAtUtc     = (Get-Date).ToUniversalTime().ToString('o')
    }
}
function Write-ResultOutput {
    param(
        [Parameter(Mandatory)]
        [psobject] $Result
    )

    if ($Json) {
        $Result | ConvertTo-Json -Depth 5 -Compress
        return
    }

    Write-Output ('ComputerName={0};EnrollmentCount={1};Status={2};WarningThreshold={3};LimitThreshold={4};Message={5};CheckedAtUtc={6}' -f `
        $Result.ComputerName,
        $Result.EnrollmentCount,
        $Result.Status,
        $Result.WarningThreshold,
        $Result.LimitThreshold,
        $Result.Message,
        $Result.CheckedAtUtc)
}

try {
    if (-not (Test-Path -LiteralPath $NgcPath)) {
        $result = New-Result `
            -Status 'OK' `
            -EnrollmentCount 0 `
            -Message 'NGC folder was not found. No local WHfB enrolment artefacts were detected.'

        Write-ResultOutput -Result $result

        exit 0
    }

    $sidPattern = '^S-1-5-21-\d+-\d+-\d+-\d+$'

    $directories = Get-ChildItem -LiteralPath $NgcPath -Directory -Recurse -Force -ErrorAction Stop

    $sids = $directories |
        Where-Object { $_.Name -match $sidPattern } |
        Select-Object -ExpandProperty Name -Unique |
        Sort-Object

    # On some builds the local NGC store may not expose SID-named directories to
    # normal enumeration. If no SIDs are visible, fall back to top-level NGC
    # containers as a conservative local device artefact count.
    $topLevelContainers = Get-ChildItem -LiteralPath $NgcPath -Directory -Force -ErrorAction Stop |
        Select-Object -ExpandProperty Name |
        Sort-Object

    if (@($sids).Count -gt 0) {
        $count = @($sids).Count
        $message = 'Counted distinct user SIDs found in the local NGC store.'
    }
    else {
        $count = @($topLevelContainers).Count
        $message = 'No SID-named folders were visible. Counted top-level NGC containers instead.'
    }

    $status = if ($count -ge $LimitThreshold) {
        'AtLimit'
    }
    elseif ($count -ge $WarningThreshold) {
        'Warning'
    }
    else {
        'OK'
    }

    $result = New-Result `
        -Status $status `
        -EnrollmentCount $count `
        -Sids @($sids) `
        -ContainerNames @($topLevelContainers) `
        -Message $message

    Write-ResultOutput -Result $result

    if ($count -ge $WarningThreshold) {
        exit 1
    }

    exit 0
}
catch {
    $result = New-Result `
        -Status 'Unknown' `
        -EnrollmentCount 0 `
        -Message "Could not inspect the local NGC store. Run as Local System or elevated administrator. $($_.Exception.Message)"

    Write-ResultOutput -Result $result

    exit 2
}

