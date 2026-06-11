<#
.SYNOPSIS
    Monitors hardware security token removal and locks the workstation.
    Compatible with PowerShell Constrained Language Mode.

.DESCRIPTION
    Polls Get-PnpDevice every 2 seconds to detect token removal.
    No .NET object instantiation - works under WDAC/AppLocker CLM.

.NOTES
    Version : 1.4 - Constrained Language Mode compatible
    Log     : C:\ProgramData\TokenLock\TokenLock.log
#>

$LogDir  = 'C:\ProgramData\TokenLock'
$LogFile = Join-Path $LogDir 'TokenLock.log'
$PollIntervalSeconds = 2

$TokenVendorIDs = @(
    '1050',   # Yubico (YubiKey all models)
    '096E',   # Feitian Technologies
    '20A0',   # Clay Logic / Nitrokey
    '2581',   # Plug-up International / HyperFIDO
    '04E6',   # SCM Microsystems (smart card readers)
    '08E6',   # Gemalto / Thales smart card readers
    '1A44',   # VASCO Data Security
    '2CCF',   # Hypersecu
    '0529',   # Aladdin (SafeNet eToken)
    '0DC3',   # Athena Smartcard Solutions
    '15E1',   # Todos Sweden
    '24DC',   # IOGEAR
    '18D5',   # Identiv uTrust
    '04CC',   # Ericsson
    '1FC9'    # NXP Semiconductors (FIDO keys)
)

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    Write-Host $line
    try {
        if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    } catch {}
}

function Get-ConnectedTokenIDs {
    $devices = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match '^USB\\VID_' }

    $tokens = foreach ($device in $devices) {
        foreach ($vid in $TokenVendorIDs) {
            if ($device.InstanceId -imatch "USB\\VID_$vid") {
                $device.InstanceId
                break
            }
        }
    }
    return $tokens
}

function Lock-Workstation {
    Write-Log 'Locking workstation' 'WARN'
    Start-Process -FilePath 'rundll32.exe' -ArgumentList 'user32.dll,LockWorkStation' -WindowStyle Hidden
    Write-Log 'Lock command sent'
}

Write-Log "TokenLock v1.4 started (CLM-compatible, polling every $PollIntervalSeconds s)"

# Initial snapshot
$previousTokens = Get-ConnectedTokenIDs
Write-Log "Initial tokens detected: $(if ($previousTokens) { $previousTokens -join ', ' } else { 'none' })"

while ($true) {
    Start-Sleep -Seconds $PollIntervalSeconds

    $currentTokens = Get-ConnectedTokenIDs

    # Find tokens that were present before but are gone now
    $removed = @()
    foreach ($t in $previousTokens) {
        if ($currentTokens -notcontains $t) {
            $removed += $t
        }
    }

    if ($removed.Count -gt 0) {
        Write-Log "Token removed: $($removed -join ', ')" 'WARN'
        Lock-Workstation
    }

    $previousTokens = $currentTokens
}
