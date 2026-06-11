#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Intune Win32 app UNINSTALL script for TokenLock.
    Kills the monitor process, removes the scheduled task, and cleans up files.
#>

$ErrorActionPreference = 'SilentlyContinue'

$InstallDir = 'C:\ProgramData\TokenLock'
$TaskName   = 'TokenLock-HardwareTokenMonitor'

function Write-Log {
    param([string]$Msg)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Msg"
    Write-Host $line
}

try {
    # Kill wscript launcher
    Get-CimInstance Win32_Process -Filter "Name = 'wscript.exe'" |
        Where-Object { $_.CommandLine -like '*Launch-TokenLock*' } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            Write-Log "Killed wscript launcher (PID $($_.ProcessId))"
        }

    # Kill PowerShell monitor process
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -like '*Monitor-HardwareToken*' } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            Write-Log "Killed monitor process (PID $($_.ProcessId))"
        }

    # Stop and remove scheduled task
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Log "Scheduled task '$TaskName' removed"
    }

    # Remove install directory
    if (Test-Path $InstallDir) {
        Remove-Item -Path $InstallDir -Recurse -Force
        Write-Log "Removed $InstallDir"
    }

    Write-Log 'TokenLock uninstalled successfully'
    exit 0
} catch {
    Write-Log "Uninstall error (non-fatal): $_"
    exit 0
}
