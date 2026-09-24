#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $TenantId,

    [Parameter(Mandatory)]
    [string] $ClientId,

    [Parameter(Mandatory)]
    [string] $CertificateThumbprint,

    [Parameter(Mandatory)]
    [string] $DeviceName,

    [int] $WarningThreshold = 8,

    [int] $LimitThreshold = 10,

    [switch] $IncludeRecentRegistrationEvents = $true,

    [int] $RecentRegistrationEventLimit = 100,

    [string] $ExportCsv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

Connect-MgGraph `
    -TenantId $TenantId `
    -ClientId $ClientId `
    -CertificateThumbprint $CertificateThumbprint `
    -NoWelcome `
    -ErrorAction Stop

function Invoke-GraphPagedRequest {
    param(
        [Parameter(Mandatory)]
        [string] $Uri
    )

    $items = @()
    $next = $Uri

    while ($next) {
        $page = Invoke-MgGraphRequest -Method GET -Uri $next
        $items += @($page.value)
        $next = $page.'@odata.nextLink'
    }

    return $items
}

$usersUri = "https://graph.microsoft.com/v1.0/users?`$select=id,userPrincipalName,displayName,userType&`$top=999"
$users = Invoke-GraphPagedRequest -Uri $usersUri

$whfbEvidence = foreach ($user in $users) {
    try {
        $methods = Invoke-MgGraphRequest `
            -Method GET `
            -Uri "https://graph.microsoft.com/v1.0/users/$($user.id)/authentication/windowsHelloForBusinessMethods"

        foreach ($method in @($methods.value)) {
            if ($method.displayName -eq $DeviceName) {
                [pscustomobject]@{
                    EvidenceType       = 'WindowsHelloForBusinessMethod'
                    UserPrincipalName  = $user.userPrincipalName
                    UserDisplayName    = $user.displayName
                    UserType           = $user.userType
                    DeviceName         = $method.displayName
                    DeviceId           = $null
                    CreatedDateTime    = $method.createdDateTime
                    MethodId           = $method.id
                    KeyStrength        = $method.keyStrength
                    ConditionalAccess  = $null
                    ErrorCode          = $null
                }
            }
        }
    }
    catch {
        Write-Verbose "Could not read WHfB methods for $($user.userPrincipalName): $($_.Exception.Message)"
    }
}

$registrationEvidence = @()

if ($IncludeRecentRegistrationEvents) {
    try {
        $eventsUri = "https://graph.microsoft.com/v1.0/auditLogs/signIns?" +
            "`$filter=appDisplayName eq 'Microsoft Device Registration Client'&" +
            "`$top=$RecentRegistrationEventLimit&" +
            "`$orderby=createdDateTime desc"

        $events = Invoke-MgGraphRequest -Method GET -Uri $eventsUri

        $registrationEvidence = $events.value |
            Where-Object {
                $_.deviceDetail.displayName -eq $DeviceName -and
                $_.status.errorCode -eq 0
            } |
            ForEach-Object {
                [pscustomobject]@{
                    EvidenceType       = 'SuccessfulDeviceRegistrationSignIn'
                    UserPrincipalName  = $_.userPrincipalName
                    UserDisplayName    = $_.userDisplayName
                    UserType           = $null
                    DeviceName         = $_.deviceDetail.displayName
                    DeviceId           = $_.deviceDetail.deviceId
                    CreatedDateTime    = $_.createdDateTime
                    MethodId           = $null
                    KeyStrength        = $null
                    ConditionalAccess  = $_.conditionalAccessStatus
                    ErrorCode          = $_.status.errorCode
                }
            }
    }
    catch {
        Write-Warning "Could not read sign-in logs. Grant AuditLog.Read.All or run without -IncludeRecentRegistrationEvents. $($_.Exception.Message)"
    }
}

$allEvidence = @($whfbEvidence) + @($registrationEvidence)

$knownUsers = $allEvidence |
    Where-Object { $_.UserPrincipalName } |
    Select-Object -ExpandProperty UserPrincipalName -Unique |
    Sort-Object

$count = @($knownUsers).Count

$status = if ($count -ge $LimitThreshold) {
    'AtLimit'
}
elseif ($count -ge $WarningThreshold) {
    'Warning'
}
else {
    'OK'
}

$summary = [pscustomobject]@{
    DeviceName       = $DeviceName
    EnrollmentCount  = $count
    WarningThreshold = $WarningThreshold
    LimitThreshold   = $LimitThreshold
    Status           = $status
    Users            = ($knownUsers -join '; ')
}

if ($ExportCsv) {
    $allEvidence |
        Sort-Object UserPrincipalName, EvidenceType, CreatedDateTime |
        Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
}

$summary

Write-Host ''
Write-Host 'Evidence rows:'
$allEvidence |
    Sort-Object UserPrincipalName, EvidenceType, CreatedDateTime |
    Format-Table EvidenceType, UserPrincipalName, DeviceName, CreatedDateTime, ConditionalAccess, ErrorCode -AutoSize
