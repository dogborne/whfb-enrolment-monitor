# Windows Hello for Business enrolment monitor

PowerShell script to identify how many Windows Hello for Business (WHfB) enrolments are associated with a shared Windows device.

This is useful for shared devices, labs, kiosk-like scenarios, front-counter machines, training rooms, or any environment where multiple users may configure WHfB on the same physical device. Microsoft commonly documents a practical WHfB per-device enrolment limit of 10 users, so monitoring at 8 or more enrolments is a sensible early-warning threshold.

## What the script does

`Get-WhfbDeviceEnrollmentCount.ps1`:

- Connects to Microsoft Graph using app-only certificate authentication.
- Reads users' registered WHfB authentication methods.
- Counts methods that directly reference the target device name.
- Optionally correlates recent successful device-registration sign-in events, which helps where Graph returns a blank WHfB method display name.
- Returns a clear status of `OK`, `Warning`, or `AtLimit`.
- Can export the evidence rows to CSV.

## Required Microsoft Graph permissions

Create an Entra app registration using certificate authentication or managed identity. For certificate authentication, grant the app these **application permissions** and provide admin consent:

| Permission | Required | Purpose |
|---|---:|---|
| `User.Read.All` or `Directory.Read.All` | Yes | Enumerate users |
| `UserAuthenticationMethod.Read.All` | Yes | Read users' WHfB authentication methods |
| `AuditLog.Read.All` | Recommended | Correlate recent device-registration sign-in events to a device |
| `DeviceManagementManagedDevices.Read.All` | Optional | Useful if extending the script to resolve Intune managed device metadata |

The script does **not** require write permissions.

## Example

```powershell
.\Get-WhfbDeviceEnrollmentCount.ps1 `
  -TenantId "<tenant-id>" `
  -ClientId "<app-registration-client-id>" `
  -CertificateThumbprint "<certificate-thumbprint>" `
  -DeviceName "CORP-2741163601" `
  -WarningThreshold 8 `
  -LimitThreshold 10 `
  -ExportCsv ".\whfb-device-enrolments.csv"
```

## Example output

```text
DeviceName      : CORP-2741163601
EnrollmentCount : 2
WarningThreshold: 8
LimitThreshold  : 10
Status          : OK
Users           : user1@contoso.com; user2@contoso.com
```

## Notes

- WHfB authentication method `displayName` can sometimes be blank even when setup completed successfully. For that reason, use `-IncludeRecentRegistrationEvents` (enabled by default) and grant `AuditLog.Read.All`.
- If a device is already close to the limit from historic WHfB registrations, the script can identify those registrations only when the WHfB method still has the target device name, or when matching device-registration events are still available in sign-in logs.
- Sign-in log retention depends on the tenant's licensing and audit configuration. If the WHfB method has a blank device name and the relevant sign-in logs have expired, Microsoft Graph does not provide a reliable central way to reconstruct which device that older WHfB method belongs to. Start collecting this report before devices reach the threshold, and retain the outputs as your longitudinal evidence.
- For shared devices approaching the limit, review stale registrations, reduce the number of WHfB users on the device, or consider FIDO2 security keys for high-user-count shared-device scenarios.
