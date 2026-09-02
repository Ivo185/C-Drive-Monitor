<#
.SYNOPSIS
    14-Day C: Drive Monitor Script
#>
$ErrorActionPreference = "SilentlyContinue"

# Single Instance Mutex
$mutexName = "Global\CDriveMonitor14Day"
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0, $false)) {
    Write-Output "Monitor is already running."
    exit
}

$LogPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "C_Drive_Monitor.txt"
$StatePath = Join-Path $PSScriptRoot "monitor_state.xml"

function Format-Bytes {
    param([long]$bytes)
    if ($null -eq $bytes -or $bytes -eq 0) { return "0 B" }
    $absBytes = [Math]::Abs($bytes)
    if ($absBytes -ge 1TB) { return "{0:N2} TB" -f ($bytes / 1TB) }
    if ($absBytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
    if ($absBytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }
    if ($absBytes -ge 1KB) { return "{0:N2} KB" -f ($bytes / 1KB) }
    return "{0:N0} B" -f $bytes
}

function Write-Log {
    param($Message, $Severity = "INFO")
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logLine = "[$timestamp] [$Severity] $Message"
    Add-Content -Path $LogPath -Value $logLine -Encoding UTF8
}

function Write-Section {
    param($Title)
    $line = "=" * 48
    $content = "`r`n$line`r`n$Title`r`n$line"
    Add-Content -Path $LogPath -Value $content -Encoding UTF8
}

function Get-FolderSize {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    try {
        $fso = New-Object -ComObject Scripting.FileSystemObject
        return $fso.GetFolder($Path).Size
    } catch {
        try {
            $sum = (Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            return if ($null -eq $sum) { 0 } else { $sum }
        } catch { return 0 }
    }
}


# Init State
if (Test-Path $StatePath) {
    $state = Import-Clixml -Path $StatePath
} else {
    $drive = Get-PSDrive C
    $state = @{
        StartDate = (Get-Date)
        EndDate = (Get-Date).AddDays(14)
        Next5MinCheck = (Get-Date)
        Next30MinCheck = (Get-Date)
        Next24HrCheck = (Get-Date).AddHours(24)
        InitialFreeSpace = [long]$drive.Free
        LastFreeSpace = [long]$drive.Free
        DailyStartFreeSpace = [long]$drive.Free
        DailyMinFreeSpace = [long]$drive.Free
        DailyMaxFreeSpace = [long]$drive.Free
        WUMaxSize = [long]0
        WUGrowthCount = 0
        DayCount = 1
        FinalReportDone = $false
        BootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        FreeSpaceHistory = @()
        LastFolderSizes = @{}
        LastProcessWrites = @{}
        InstalledSoftware = @{}
    }
    Write-Section "C DRIVE MONITOR"
    Write-Log "Monitor started. Target end date: $($state.EndDate)"
    Write-Log "Initial C: Free Space: $(Format-Bytes $state.InitialFreeSpace)"
    $state | Export-Clixml -Path $StatePath
}

function Run-5MinCheck {
    $now = Get-Date
    $drive = Get-PSDrive C
    $Total = [long]($drive.Used + $drive.Free)
    $Used = [long]$drive.Used
    $Free = [long]$drive.Free
    $FreePct = ($Free / $Total) * 100
    
    $diff = $Free - $state.LastFreeSpace
    
    if ($Free -lt $state.DailyMinFreeSpace) { $state.DailyMinFreeSpace = $Free }
    if ($Free -gt $state.DailyMaxFreeSpace) { $state.DailyMaxFreeSpace = $Free }
    
    $state.FreeSpaceHistory += [PSCustomObject]@{ Time = $now; FreeSpace = $Free }
    $state.FreeSpaceHistory = @($state.FreeSpaceHistory | Where-Object { $_.Time -ge $now.AddHours(-25) })
    
    $logMsg = "C: Total=$(Format-Bytes $Total) | Used=$(Format-Bytes $Used) | Free=$(Format-Bytes $Free) | Free%=$(('{0:N1}' -f $FreePct))%"
    
    $significantDrop = $false
    $dropMsg = ""
    if ($diff -lt -1GB) { $significantDrop = $true; $dropMsg = "Drop > 1GB" }
    elseif ($diff -lt -500MB) { $significantDrop = $true; $dropMsg = "Drop > 500MB" }
    elseif ($diff -lt -100MB) { $significantDrop = $true; $dropMsg = "Drop > 100MB" }
    
    if ($significantDrop) {
        Write-Log "WARNING: C: decreased by $(Format-Bytes ([Math]::Abs($diff))) since last check. ($dropMsg)" "WARNING"
        
        # Calculate past deltas
        foreach ($h in @(1, 6, 24)) {
            $targetTime = $now.AddHours(-$h)
            $closest = $state.FreeSpaceHistory | Sort-Object { [Math]::Abs(($_.Time - $targetTime).Ticks) } | Select-Object -First 1
            if ($closest) {
                $hDiff = $Free - $closest.FreeSpace
                if ($hDiff -lt 0) {
                    Write-Log "  Change in last $h hour(s): $(Format-Bytes $hDiff)" "WARNING"
                }
            }
        }
        Write-Log $logMsg
    } else {
        if ($diff -ne 0) {
            $sign = if ($diff -gt 0) { "+" } else { "-" }
            Write-Log "C: $sign$(Format-Bytes ([Math]::Abs($diff))) (Free: $(Format-Bytes $Free))"
        }
    }
    
    $state.LastFreeSpace = $Free
    
    # Windows Update Cache Check
    $wuDir = "$env:windir\SoftwareDistribution"
    $wuDlDir = "$wuDir\Download"
    
    $wuSize = Get-FolderSize $wuDir
    if ($wuSize -gt $state.WUMaxSize) { $state.WUMaxSize = $wuSize }
    
    if (Test-Path -LiteralPath $wuDlDir) {
        $wuDlItems = Get-ChildItem -LiteralPath $wuDlDir -Recurse -Force -ErrorAction SilentlyContinue
        $wuDlSize = ($wuDlItems | Measure-Object -Property Length -Sum).Sum
        if ($null -eq $wuDlSize) { $wuDlSize = 0 }
        
        if ($state.LastFolderSizes.ContainsKey($wuDlDir)) {
            $wuDiff = $wuDlSize - $state.LastFolderSizes[$wuDlDir]
            if ($wuDiff -gt 0) {
                $files = @($wuDlItems | Where-Object { -not $_.PSIsContainer }).Count
                $dirs = @($wuDlItems | Where-Object { $_.PSIsContainer }).Count
                Write-Log "WINDOWS UPDATE CACHE GROWTH in Download: +$(Format-Bytes $wuDiff). Old: $(Format-Bytes $state.LastFolderSizes[$wuDlDir]), New: $(Format-Bytes $wuDlSize). Files: $files, Folders: $dirs" "WARNING"
                $state.WUGrowthCount++
            }
        }
        $state.LastFolderSizes[$wuDlDir] = $wuDlSize
    }
    $state.LastFolderSizes[$wuDir] = $wuSize
    
    # WU Services
    $svcs = Get-Service -Name wuauserv, bits, UsoSvc, dosvc -ErrorAction SilentlyContinue
    $svcStates = ($svcs | ForEach-Object { "$($_.Name):$($_.Status)" }) -join ", "
    if ($state.LastSvcStates -ne $svcStates) {
        Write-Log "WU Services Status: $svcStates"
        $state.LastSvcStates = $svcStates
    }
}

function Run-30MinCheck {
    $now = Get-Date
    Write-Section "30-MINUTE CHECKS"
    
    # Processes
    try {
        $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Select-Object ProcessId, Name, ExecutablePath, WriteTransferCount, ReadTransferCount
        $procDiffs = @()
        foreach ($p in $procs) {
            $pidName = "$($p.ProcessId)_$($p.Name)"
            if ($state.LastProcessWrites.ContainsKey($pidName)) {
                $prev = $state.LastProcessWrites[$pidName]
                $writeDiff = [long]$p.WriteTransferCount - [long]$prev.Write
                $readDiff = [long]$p.ReadTransferCount - [long]$prev.Read
                if ($writeDiff -gt 0 -or $readDiff -gt 0) {
                    $procDiffs += [PSCustomObject]@{ Name=$p.Name; PID=$p.ProcessId; Path=$p.ExecutablePath; WriteDiff=$writeDiff; ReadDiff=$readDiff }
                }
            }
            $state.LastProcessWrites[$pidName] = @{ Write=$p.WriteTransferCount; Read=$p.ReadTransferCount }
        }
        
        $topWriters = $procDiffs | Sort-Object WriteDiff -Descending | Select-Object -First 5
        if ($topWriters) {
            Write-Log "PROCESS DISK ACTIVITY (Top 5 Writers):"
            foreach ($tw in $topWriters) {
                Write-Log "  $($tw.Name) (PID:$($tw.PID)) - Writes: $(Format-Bytes $tw.WriteDiff) | $($tw.Path)"
            }
        }
    } catch {
        Write-Log "Process-level disk write attribution unavailable with current permissions/method." "WARNING"
    }
    
    # Large Folders
    $FoldersToMonitor = @(
        "$env:LOCALAPPDATA",
        "$env:APPDATA",
        "$env:USERPROFILE\.cache",
        "$env:USERPROFILE\.gradle",
        "$env:USERPROFILE\.m2",
        "$env:USERPROFILE\.nuget",
        "$env:USERPROFILE\Downloads",
        "$env:USERPROFILE\Desktop",
        "$env:ProgramData",
        "$env:windir\SoftwareDistribution",
        "$env:ProgramFiles",
        "${env:ProgramFiles(x86)}",
        "$env:LOCALAPPDATA\Docker",
        "$env:LOCALAPPDATA\Packages"
    )
    
    foreach ($f in $FoldersToMonitor) {
        if (-not (Test-Path -LiteralPath $f)) { continue }
        $sz = Get-FolderSize $f
        if ($state.LastFolderSizes.ContainsKey($f)) {
            $diff = $sz - $state.LastFolderSizes[$f]
            if ($diff -gt 100MB) {
                Write-Log "LARGE FOLDER GROWTH: $f grew by $(Format-Bytes $diff). New size: $(Format-Bytes $sz)" "WARNING"
            }
        }
        $state.LastFolderSizes[$f] = $sz
    }
    
    # Top AppData Local Folders
    $localDirs = Get-ChildItem -LiteralPath "$env:LOCALAPPDATA" -Directory -ErrorAction SilentlyContinue
    foreach ($d in $localDirs) {
        $dsz = Get-FolderSize $d.FullName
        if ($state.LastFolderSizes.ContainsKey($d.FullName)) {
            $diff = $dsz - $state.LastFolderSizes[$d.FullName]
            if ($diff -gt 100MB) {
                Write-Log "CACHE GROWTH DETECTED: $($d.Name) grew by $(Format-Bytes $diff)." "WARNING"
            }
        }
        $state.LastFolderSizes[$d.FullName] = $dsz
    }
    
    # Recycle Bin
    try {
        $shell = New-Object -ComObject Shell.Application
        $rb = $shell.NameSpace(10)
        $rbSize = 0
        if ($rb) { foreach ($item in $rb.Items()) { $rbSize += $item.Size } }
        if ($state.LastFolderSizes.ContainsKey("RecycleBin")) {
            $rbDiff = $rbSize - $state.LastFolderSizes["RecycleBin"]
            if ($rbDiff -gt 50MB) { Write-Log "Recycle Bin grew by $(Format-Bytes $rbDiff). New size: $(Format-Bytes $rbSize)" }
        }
        $state.LastFolderSizes["RecycleBin"] = $rbSize
    } catch {}
    
    # Temp Dirs
    $tempDirs = @("$env:windir\Temp", $env:TEMP)
    foreach ($t in $tempDirs) {
        if (-not (Test-Path -LiteralPath $t)) { continue }
        $sz = Get-FolderSize $t
        if ($state.LastFolderSizes.ContainsKey($t)) {
            $diff = $sz - $state.LastFolderSizes[$t]
            if ($diff -gt 100MB) { Write-Log "TEMP DIRECTORIES: $t grew by $(Format-Bytes $diff). New size: $(Format-Bytes $sz)" }
        }
        $state.LastFolderSizes[$t] = $sz
    }
    
    # System Files
    $sysFiles = @("C:\hiberfil.sys", "C:\pagefile.sys", "C:\swapfile.sys", "$env:windir\WinSxS")
    foreach ($sf in $sysFiles) {
        if (-not (Test-Path -LiteralPath $sf)) { continue }
        if ((Get-Item -LiteralPath $sf).PSIsContainer) {
            $sz = Get-FolderSize $sf
        } else {
            $sz = (Get-Item -LiteralPath $sf).Length
        }
        if ($state.LastFolderSizes.ContainsKey($sf)) {
            $diff = $sz - $state.LastFolderSizes[$sf]
            if ($diff -gt 100MB -or $diff -lt -100MB) { Write-Log "System File/Folder $sf changed by $(Format-Bytes $diff). New size: $(Format-Bytes $sz)" }
        }
        $state.LastFolderSizes[$sf] = $sz
    }
    
    # Large New Files
    $searchPaths = @("$env:USERPROFILE", "$env:ProgramData", "$env:windir\Temp", "$env:windir\SoftwareDistribution")
    $cutoff = $now.AddMinutes(-30)
    foreach ($sp in $searchPaths) {
        if (-not (Test-Path -LiteralPath $sp)) { continue }
        try {
            $largeFiles = Get-ChildItem -LiteralPath $sp -File -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 100MB -and $_.CreationTime -gt $cutoff }
            foreach ($lf in $largeFiles) {
                Write-Log "LARGE FILES (New): $($lf.FullName) | Size: $(Format-Bytes $lf.Length) | Created: $($lf.CreationTime) | Modified: $($lf.LastWriteTime)" "WARNING"
            }
        } catch {}
    }
}

function Run-24HrCheck {
    Write-Section "DAY $($state.DayCount) SUMMARY"
    $drive = Get-PSDrive C
    $Free = [long]$drive.Free
    $diffDay = $Free - $state.DailyStartFreeSpace
    
    Write-Log "Start of Day Free Space: $(Format-Bytes $state.DailyStartFreeSpace)"
    Write-Log "End of Day Free Space:   $(Format-Bytes $Free)"
    Write-Log "Total Change Today:      $(Format-Bytes $diffDay)"
    Write-Log "Min Free Space Today:    $(Format-Bytes $state.DailyMinFreeSpace)"
    Write-Log "Max Free Space Today:    $(Format-Bytes $state.DailyMaxFreeSpace)"
    Write-Log "Max WU Cache Size Today: $(Format-Bytes $state.WUMaxSize)"
    
    # Software
    $swPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $installedNow = @{}
    $swList = Get-ItemProperty $swPaths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
    foreach ($sw in $swList) {
        $installedNow[$sw.DisplayName] = $sw.DisplayVersion
        if (-not $state.InstalledSoftware.ContainsKey($sw.DisplayName)) {
            Write-Log "INSTALLED SOFTWARE (New): $($sw.DisplayName) (Version: $($sw.DisplayVersion))" "INFO"
        }
    }
    $state.InstalledSoftware = $installedNow
    
    # Reset
    $state.DailyStartFreeSpace = $Free
    $state.DailyMinFreeSpace = $Free
    $state.DailyMaxFreeSpace = $Free
}

function Generate-FinalReport {
    Write-Section "14-DAY FINAL REPORT"
    $drive = Get-PSDrive C
    $Free = [long]$drive.Free
    $totalDiff = $Free - $state.InitialFreeSpace
    
    Write-Log "1. Свободно място в началото: $(Format-Bytes $state.InitialFreeSpace)"
    Write-Log "2. Свободно място в края: $(Format-Bytes $Free)"
    Write-Log "3. Общо изгубено/спечелено място: $(Format-Bytes $totalDiff)"
    
    $minEver = $state.InitialFreeSpace
    $maxEver = $state.InitialFreeSpace
    foreach ($entry in $state.FreeSpaceHistory) {
        if ($entry.FreeSpace -lt $minEver) { $minEver = $entry.FreeSpace }
        if ($entry.FreeSpace -gt $maxEver) { $maxEver = $entry.FreeSpace }
    }
    Write-Log "4. Минимално свободно място през периода: $(Format-Bytes $minEver)"
    
    Write-Log "6. Windows Update cache — максимален размер: $(Format-Bytes $state.WUMaxSize)"
    Write-Log "7. Windows Update cache — пъти нараствал: $($state.WUGrowthCount)"
    
    Write-Log "`nNOTE ON DELETED FILES: Reliable deleted file tracking requires File System Auditing (Sysmon/ETW). Script polling cannot catch all file deletions securely."
    
    Write-Log "`nLIKELY CAUSE / POSSIBLE CAUSES:"
    if ($state.WUGrowthCount -gt 5) { Write-Log "- Frequent Windows Update background activity detected." }
    if ($totalDiff -lt -5GB) { Write-Log "- Significant space loss over 14 days. Review LARGE FOLDER CHANGES and CACHE MONITORING tags in the log." }
    else { Write-Log "- INSUFFICIENT DATA to pinpoint a single major cause. Review warnings above." }
}

# Main Loop
while ($true) {
    $now = Get-Date

    if ($now -ge $state.EndDate -and -not $state.FinalReportDone) {
        Generate-FinalReport
        $state.FinalReportDone = $true
        $state | Export-Clixml -Path $StatePath
        Write-Log "Monitor completed 14 days. Exiting and stopping checks."
        exit
    }
    
    if ($state.FinalReportDone) {
        exit
    }

    $currentBoot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    if ($currentBoot -ne $state.BootTime) {
        Write-Log "SYSTEM INFORMATION: System has been rebooted/started. Boot time: $currentBoot" "WARNING"
        $state.BootTime = $currentBoot
    }

    if ($now -ge $state.Next5MinCheck) {
        Run-5MinCheck
        $state.Next5MinCheck = $now.AddMinutes(5)
    }

    if ($now -ge $state.Next30MinCheck) {
        Run-30MinCheck
        $state.Next30MinCheck = $now.AddMinutes(30)
    }

    if ($now -ge $state.Next24HrCheck) {
        Run-24HrCheck
        $state.Next24HrCheck = $now.AddHours(24)
        $state.DayCount++
    }

    $state | Export-Clixml -Path $StatePath
    Start-Sleep -Seconds 60
}
