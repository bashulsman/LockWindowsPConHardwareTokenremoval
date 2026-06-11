#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Intune Win32 app INSTALL script for TokenLock.
    Deploys Monitor-HardwareToken.ps1 and registers a persistent Scheduled Task.

.NOTES
    Intune deployment:
      Install command : powershell.exe -NonInteractive -ExecutionPolicy Bypass -File Install-TokenLock.ps1
      Uninstall command: powershell.exe -NonInteractive -ExecutionPolicy Bypass -File Uninstall-TokenLock.ps1
      Detection rule  : File exists  C:\ProgramData\TokenLock\TokenLock.installed
      Run as          : System
      Architecture    : 64-bit
#>

$ErrorActionPreference = 'Stop'

$InstallDir   = 'C:\ProgramData\TokenLock'
$ScriptDest   = Join-Path $InstallDir 'Monitor-HardwareToken.ps1'
$MarkerFile   = Join-Path $InstallDir 'TokenLock.installed'
$LogFile      = Join-Path $InstallDir 'Install.log'
$TaskName     = 'TokenLock-HardwareTokenMonitor'
$ScriptSource = Join-Path $PSScriptRoot 'Monitor-HardwareToken.ps1'

function Write-Log {
    param([string]$Msg)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Msg"
    Write-Host $line
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch {}
}

try {
    # 1. Create install directory
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    Write-Log "Install directory: $InstallDir"

    # 2. Copy monitor script and VBS launcher
    Copy-Item -Path $ScriptSource -Destination $ScriptDest -Force
    Write-Log "Monitor script deployed to $ScriptDest"


    # 3. Remove any existing scheduled task
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Log "Existing task '$TaskName' removed"
    }

    # 4. Register via raw XML - avoids all cmdlet parameter set issues
    #    Principal: S-1-5-32-545 = BUILTIN\Users (runs in the logged-on user session)
    #    Trigger: LogonTrigger fires for any user logon (30s delay to let desktop settle)
    $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Locks the workstation when a hardware security token is removed.</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <Delay>PT30S</Delay>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <GroupId>S-1-5-32-545</GroupId>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>5</Count>
    </RestartOnFailure>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>cmd.exe</Command>
      <Arguments>/c start /min "" powershell.exe -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "$ScriptDest"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

    Register-ScheduledTask -TaskName $TaskName -Xml $taskXml -Force | Out-Null
    Write-Log "Scheduled task '$TaskName' registered"

    # 5. Start immediately for current session (no reboot/logoff required)
    Start-ScheduledTask -TaskName $TaskName
    Write-Log "Task started"

    # 6. Detection marker
    "Installed $(Get-Date -Format 'o')`nVersion: 1.3" | Set-Content -Path $MarkerFile -Encoding UTF8
    Write-Log "Detection marker written"

    Write-Log 'TokenLock installation completed successfully'
    exit 0

} catch {
    Write-Log "INSTALL FAILED: $_"
    exit 1
}
