# TokenLock — Hardware Token Removal → Workstation Lock
## Intune Win32 App Deployment Guide

### What it does
A lightweight PowerShell background service (Scheduled Task) that:
1. Subscribes to WMI USB device-removal events
2. Matches removed devices against a list of known hardware token Vendor IDs (YubiKey, Feitian, Nitrokey, Gemalto, SafeNet eToken, and more)
3. Calls `LockWorkStation()` the moment a token is unplugged while a user is logged in

CPU impact: near-zero (WMI event subscription with 5-second blocking wait, no polling loop)

---

### Files
```
src/
  Monitor-HardwareToken.ps1   # The persistent monitor (runs as Scheduled Task)
  Install-TokenLock.ps1       # Intune install script
  Uninstall-TokenLock.ps1     # Intune uninstall script
```

---

### Step 1 — Package as .intunewin

Download the Win32 Content Prep Tool:
https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool

```cmd
IntuneWinAppUtil.exe -c .\src -s Install-TokenLock.ps1 -o .\package
```

This produces `package\Install-TokenLock.intunewin`.

---

### Step 2 — Add as Win32 App in Intune

**Intune > Apps > All apps > + Add > Windows app (Win32)**

| Field | Value |
|---|---|
| App package file | `Install-TokenLock.intunewin` |
| Name | `TokenLock - Hardware Token Monitor` |
| Publisher | IT Administration |
| Install command | `powershell.exe -NonInteractive -ExecutionPolicy Bypass -File Install-TokenLock.ps1` |
| Uninstall command | `powershell.exe -NonInteractive -ExecutionPolicy Bypass -File Uninstall-TokenLock.ps1` |
| Install behavior | **System** |
| Device restart behavior | No specific action |
| Return codes | 0 = Success (default is fine) |

**Detection rule** (manual):
| Type | Path | File/folder name | Detection method |
|---|---|---|---|
| File | `C:\ProgramData\TokenLock` | `TokenLock.installed` | File exists |

**Assignments**: assign to your target device group as **Required**.

---

### Customising Vendor IDs

Edit the `$TokenVendorIDs` array in `Monitor-HardwareToken.ps1` before packaging.

To find the VID of a token already plugged into a machine, run:
```powershell
Get-PnpDevice -Class USB | Where-Object Status -eq 'OK' |
    Select-Object FriendlyName, InstanceId |
    Where-Object InstanceId -match 'USB\\VID_'
```
The four hex digits after `VID_` are the Vendor ID.

Currently included vendors:
| VID  | Vendor |
|------|--------|
| 1050 | Yubico (all YubiKey models) |
| 096E | Feitian Technologies |
| 20A0 | Clay Logic / Nitrokey |
| 2581 | Plug-up International / HyperFIDO |
| 04E6 | SCM Microsystems (smart card readers) |
| 08E6 | Gemalto / Thales smart card readers |
| 1A44 | VASCO Data Security |
| 2CCF | Hypersecu |
| 0529 | Aladdin (SafeNet eToken) |
| 0DC3 | Athena Smartcard Solutions |
| 15E1 | Todos Sweden |
| 24DC | IOGEAR |
| 18D5 | Identiv uTrust |
| 1FC9 | NXP Semiconductors (FIDO keys) |

---

### Logs
- Monitor log: `C:\ProgramData\TokenLock\TokenLock.log`
- Install log:  `C:\ProgramData\TokenLock\Install.log`

---

### Scheduled Task details
- **Task name**: `TokenLock-HardwareTokenMonitor`
- **Runs as**: SYSTEM
- **Trigger**: At system startup (30 s delay) — auto-restarted up to 5× if it crashes
- **Started immediately** on install (no reboot required)

---

### Verifying on a test machine

```powershell
# Check task is running
Get-ScheduledTask -TaskName 'TokenLock-HardwareTokenMonitor' | Select-Object State

# Tail the monitor log
Get-Content C:\ProgramData\TokenLock\TokenLock.log -Wait -Tail 20

# Then unplug your YubiKey — screen should lock within ~1 second
```

---

### Notes
- The monitor runs as SYSTEM so it receives WMI events regardless of which user is logged in.
- `LockWorkStation()` only locks an active interactive session; if the machine is already at the login screen or locked, it's a no-op.
- If you want to lock **only when a specific user's** token is removed (multi-user environments), the VID list approach is sufficient for most fleets — every token is unique per user.
- Smart Card Policy alternative: Windows Group Policy has a built-in *"Interactive logon: Smart card removal behavior"* = Lock Workstation. This works for PIV-mode tokens (e.g. YubiKey in PIV mode with certificates). TokenLock covers OTP / FIDO2 tokens that Windows doesn't see as smart cards.
