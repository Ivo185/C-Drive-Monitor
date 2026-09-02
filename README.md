# C: Drive Monitor

A lightweight, non-intrusive 14-day monitoring tool for Windows that tracks disk space usage, caching behavior, and identifies the root causes of C: drive storage depletion.

## Features
- **Zero Impact**: Runs silently in the background with minimal CPU/RAM usage.
- **Safe**: Does not delete, modify, or move any of your files. It only monitors.
- **Smart Tracking**:
  - **5-Minute Interval**: Monitors overall C: drive space, Windows Update cache, and system services. Logs sudden space drops.
  - **30-Minute Interval**: Identifies processes with high disk write activity, scans large folder growths (AppData, Temp, Caches, WinSxS), and spots new files larger than 100MB.
  - **24-Hour Interval**: Generates a daily summary and detects newly installed software.
- **14-Day Final Report**: Automatically generates a comprehensive report of where your space went and stops monitoring.

## Installation
1. Extract the downloaded `.zip` archive.
2. Double-click on `Install-Monitor.exe` (requires Administrator privileges).
3. The tool will register a silent Scheduled Task and begin monitoring immediately.
4. A log file named `C_Drive_Monitor.txt` will be created on your Desktop.

## Uninstallation
To remove the background monitor task at any time, simply double-click `Uninstall-Monitor.exe`. 
Note: This will not delete the generated log file on your Desktop, allowing you to review your data.

## Requirements
- Windows 10 or Windows 11
- PowerShell 5.1+

## Source Code
The `src` folder contains the raw `.ps1` scripts for review. The `.exe` files in the root are compiled wrappers for convenience.
