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

`Test-WhfbLocalEnrollmentCount.ps1`:

- Runs directly on a Windows device.
- Inspects the local Windows Hello for Business NGC store.
- Counts validated user WHfB containers while excluding system cache folders such as `PregenPool`.
- Is designed for Intune remediation detection scripts.
- Exits `1` when the warning threshold is reached so the device is reported as requiring attention.

## Required Microsoft Graph permissions

Create an Entra app registration using certificate authentication or managed identity. For certificate authentication, grant the app these **application permissions** and provide admin consent:

| Permission | Required | Purpose |
|---|---:|---|
| `User.Read.All` or `Directory.Read.All` | Yes | Enumerate users |
| `UserAuthenticationMethod.Read.All` | Yes | Read users' WHfB authentication methods |
| `AuditLog.Read.All` | Recommended | Correlate recent device-registration sign-in events to a device |
| `DeviceManagementManagedDevices.Read.All` | Optional | Useful if extending the script to resolve Intune managed device metadata |

The script does **not** require write permissions.

## Local device detection with Intune remediations

For devices that may already have historic WHfB enrolments, local detection is more reliable than central Graph-only reporting. Deploy `Test-WhfbLocalEnrollmentCount.ps1` as an **Intune remediation detection script**.

Recommended Intune settings:

| Setting | Value |
|---|---|
| Run this script using the logged-on credentials | No |
| Enforce script signature check | No, unless you sign the script |
| Run script in 64-bit PowerShell | Yes |
| Schedule | Daily |

The local detection script requires no Microsoft Graph permissions. It should run as **Local System** so it can read the protected NGC store at:

```text
C:\Windows\ServiceProfiles\LocalService\AppData\Local\Microsoft\NGC
```

Example local run:

```powershell
.\Test-WhfbLocalEnrollmentCount.ps1 -WarningThreshold 8 -LimitThreshold 10 -Json
```

Exit codes:

| Exit code | Meaning |
|---:|---|
| `0` | Below warning threshold |
| `1` | At or above warning threshold |
| `2` | Could not inspect the local NGC store |

Where this is reported in Intune:

1. Go to **Intune admin center**.
2. Open **Devices** > **Scripts and remediations** > **Remediations**.
3. Select the WHfB enrolment detection package.
4. Open **Monitor** > **Device status**.

Intune uses the detection script exit code to determine whether the device is healthy or has an issue:

| Detection exit code | Intune interpretation |
|---:|---|
| `0` | No issue detected |
| `1` | Issue detected; run remediation if a remediation script is configured |
| `2` | Detection failed or could not complete successfully |

The script also writes structured output, including the device name, count, threshold and status. This appears in the remediation run output/device status details, subject to Intune output-size limits. For central reporting, export the device status report from Intune or collect the JSON output into Log Analytics using a separate collection workflow.

No remediation script is included by default because deleting WHfB/NGC artefacts is disruptive and should not be automated without a support process. Use the detection output to trigger a review of the device, user assignment pattern, and any stale local profiles.

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
- For historic devices, deploy the local detection script. It reads the device-side NGC store and does not depend on Graph sign-in log retention.
- On Windows builds that use GUID-named NGC folders, the local script counts only folders containing both `Container.json` and `Protectors.json`. It does not count `PregenPool`, which is a Local Service pre-generation cache rather than a user enrolment.
- For shared devices approaching the limit, review stale registrations, reduce the number of WHfB users on the device, or consider FIDO2 security keys for high-user-count shared-device scenarios.
