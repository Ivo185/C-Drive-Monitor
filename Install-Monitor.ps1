<#
.SYNOPSIS
    Installs the C: Drive Monitor as a Scheduled Task.
#>

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script requires Administrator privileges to create the Scheduled Task."
    Write-Warning "Attempting to elevate..."
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$taskName = "C Drive Monitor"
$scriptPath = Join-Path $PSScriptRoot "C_Drive_Monitor.ps1"

if (-not (Test-Path $scriptPath)) {
    Write-Error "Cannot find $scriptPath!"
    Pause
    exit
}

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Write-Host "Task already exists. Updating..."
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$vbsPath = Join-Path $PSScriptRoot "run_hidden.vbs"
$vbsContent = "Set objShell = CreateObject(""WScript.Shell"")`r`nobjShell.Run ""powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File """"$scriptPath"""" "", 0, False"
Set-Content -Path $vbsPath -Value $vbsContent -Encoding Ascii
$action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$vbsPath`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Days 0) -MultipleInstances IgnoreNew

try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
    Write-Host "Scheduled Task '$taskName' successfully created."
} catch {
    Write-Error "Failed to create Scheduled Task. Error: $_"
    Pause
    exit
}

Write-Host "Starting monitor..."
Start-ScheduledTask -TaskName $taskName

Start-Sleep -Seconds 3
$status = (Get-ScheduledTask -TaskName $taskName).State
Write-Host "Task status: $status"

$LogPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "C_Drive_Monitor.txt"
Write-Host "Monitor is installed and running."
Write-Host "Log file will be created at: $LogPath"
Write-Host "Press any key to close this window..."
$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
