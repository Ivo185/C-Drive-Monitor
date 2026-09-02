$source = @"
using System;
using System.IO;
using System.Collections.Generic;
using System.Linq;

public class DiskScanner {
    public class ItemInfo {
        public string Path;
        public long Size;
    }
    
    private static List<ItemInfo> topF;
    private static List<ItemInfo> topFi;
    private static Dictionary<string, long> fSizes;
    private static List<ItemInfo> recentLF;
    private static DateTime weekAgo;
    
    private static void AddToTop(List<ItemInfo> list, ItemInfo item, int max) {
        if (list.Count < max) {
            list.Add(item);
            list.Sort((a, b) => b.Size.CompareTo(a.Size));
        } else if (item.Size > list[list.Count - 1].Size) {
            list[list.Count - 1] = item;
            list.Sort((a, b) => b.Size.CompareTo(a.Size));
        }
    }
    
    private static long GetSize(DirectoryInfo dir) {
        long size = 0;
        try {
            foreach (var fi in dir.EnumerateFiles()) {
                size += fi.Length;
                AddToTop(topFi, new ItemInfo { Path = fi.FullName, Size = fi.Length }, 30);
                
                if (fi.Length > 100 * 1024 * 1024 && fi.LastWriteTime > weekAgo) {
                    recentLF.Add(new ItemInfo { Path = fi.FullName, Size = fi.Length });
                }
            }
            foreach (var di in dir.EnumerateDirectories()) {
                if ((di.Attributes & FileAttributes.ReparsePoint) == 0) {
                    size += GetSize(di);
                }
            }
        } catch { }
        
        if (size > 0) {
            AddToTop(topF, new ItemInfo { Path = dir.FullName, Size = size }, 30);
        }
        fSizes[dir.FullName] = size;
        return size;
    }
    
    public static void Scan(string root, out List<ItemInfo> topFolders, out List<ItemInfo> topFiles, out Dictionary<string, long> folderSizes, out List<ItemInfo> recentLargeFiles) {
        topF = new List<ItemInfo>();
        topFi = new List<ItemInfo>();
        fSizes = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
        recentLF = new List<ItemInfo>();
        weekAgo = DateTime.Now.AddDays(-7);
        
        try {
            GetSize(new DirectoryInfo(root));
        } catch { }
        
        topFolders = topF;
        topFiles = topFi;
        folderSizes = fSizes;
        recentLargeFiles = recentLF.OrderByDescending(f => f.Size).ToList();
    }
}
"@

Add-Type -TypeDefinition $source -Language CSharp

$topFolders = New-Object 'System.Collections.Generic.List[DiskScanner+ItemInfo]'
$topFiles = New-Object 'System.Collections.Generic.List[DiskScanner+ItemInfo]'
$folderSizes = New-Object 'System.Collections.Generic.Dictionary[string, long]'
$recentLargeFiles = New-Object 'System.Collections.Generic.List[DiskScanner+ItemInfo]'

Write-Host "Scanning C: drive (this might take a minute)..."
[DiskScanner]::Scan("C:\", [ref]$topFolders, [ref]$topFiles, [ref]$folderSizes, [ref]$recentLargeFiles)

$out = @{}

$drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$out["Drive"] = @{
    TotalGB = [math]::Round($drive.Size / 1GB, 2)
    FreeGB  = [math]::Round($drive.FreeSpace / 1GB, 2)
    UsedGB  = [math]::Round(($drive.Size - $drive.FreeSpace) / 1GB, 2)
}

function Get-Sz($path) {
    if ($folderSizes.ContainsKey($path)) {
        return [math]::Round($folderSizes[$path] / 1MB, 2)
    }
    return 0
}

$out["MainFolders"] = @{
    "C:\Users" = Get-Sz "C:\Users"
    "C:\Windows" = Get-Sz "C:\Windows"
    "C:\Program Files" = Get-Sz "C:\Program Files"
    "C:\Program Files (x86)" = Get-Sz "C:\Program Files (x86)"
    "C:\ProgramData" = Get-Sz "C:\ProgramData"
}

$usersData = @{}
$usersDirs = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue
foreach ($ud in $usersDirs) {
    $uPath = $ud.FullName
    $uData = @{
        TotalMB = Get-Sz $uPath
        Downloads = Get-Sz "$uPath\Downloads"
        Desktop = Get-Sz "$uPath\Desktop"
        Documents = Get-Sz "$uPath\Documents"
        Pictures = Get-Sz "$uPath\Pictures"
        Videos = Get-Sz "$uPath\Videos"
        AppData = Get-Sz "$uPath\AppData"
        Temp = Get-Sz "$uPath\AppData\Local\Temp"
    }
    $usersData[$ud.Name] = $uData
}
$out["Users"] = $usersData

$out["SystemFolders"] = @{
    "WindowsTemp" = Get-Sz "C:\Windows\Temp"
    "UpdateCache" = Get-Sz "C:\Windows\SoftwareDistribution\Download"
    "RecycleBin" = Get-Sz "C:\`$Recycle.Bin"
    "WindowsOld" = Get-Sz "C:\Windows.old"
}

$sysFiles = @{}
foreach ($sf in @("C:\hiberfil.sys", "C:\pagefile.sys", "C:\swapfile.sys")) {
    if (Test-Path $sf) {
        $sysFiles[$sf] = [math]::Round((Get-Item $sf).Length / 1GB, 2)
    }
}
$out["SystemFilesGB"] = $sysFiles

$out["Top30Folders"] = $topFolders | ForEach-Object { @{ Path=$_.Path; SizeMB=[math]::Round($_.Size / 1MB, 2) } }
$out["Top30Files"] = $topFiles | ForEach-Object { @{ Path=$_.Path; SizeMB=[math]::Round($_.Size / 1MB, 2) } }
$out["RecentLargeFiles"] = $recentLargeFiles | ForEach-Object { @{ Path=$_.Path; SizeMB=[math]::Round($_.Size / 1MB, 2) } }

$outputPath = Join-Path $PSScriptRoot "scan_results.json"
$out | ConvertTo-Json -Depth 10 | Out-File $outputPath -Encoding utf8
Write-Host "Scan completed. Results saved to: $outputPath"
