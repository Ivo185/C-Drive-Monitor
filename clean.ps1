# 🧹 C: Drive Monitor — Почистване на диска

> ⚠️ **Този скрипт е специално генериран след анализ. Прегледай всяка секция преди изпълнение.**

$ErrorActionPreference = "SilentlyContinue"
$logPath = Join-Path $PSScriptRoot "cleanup_log.txt"

function Write-Log($msg) {
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "[$ts] $msg" | Add-Content -Path $logPath -Encoding UTF8
    Write-Host $msg
}

function Get-FolderSizeMB($path) {
    if (-not (Test-Path $path)) { return 0 }
    $sum = (Get-ChildItem -Path $path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    return [math]::Round($sum / 1MB, 1)
}

function Confirm-Clean($desc, $sizeMB) {
    if ($sizeMB -gt 500) {
        $ans = Read-Host "Изтриване на $desc ($sizeMB MB) — потвърди (д/н)"
        return $ans -match "^[дДyY]"
    }
    return $true
}

Write-Log "=== СТАРТИРАНЕ НА ПОЧИСТВАНЕТО ==="

# ── 1. Windows Temp ──────────────────────────────────────
$winTemp = "C:\Windows\Temp"
$sz = Get-FolderSizeMB $winTemp
if ($sz -gt 0 -and (Confirm-Clean "Windows\Temp" $sz)) {
    Get-ChildItem -Path $winTemp -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Изчистен Windows\Temp — освободено ~$sz MB"
}

# ── 2. Потребителски Temp ────────────────────────────────
$userTemp = $env:TEMP
$sz = Get-FolderSizeMB $userTemp
if ($sz -gt 0 -and (Confirm-Clean "%TEMP%" $sz)) {
    Get-ChildItem -Path $userTemp -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Изчистен %TEMP% — освободено ~$sz MB"
}

# ── 3. Windows Update Cache (Download) ───────────────────
$wuDl = "C:\Windows\SoftwareDistribution\Download"
$sz = Get-FolderSizeMB $wuDl
Write-Host ""
Write-Host "Windows Update Download кеш: $sz MB"
Write-Host "ВНИМАНИЕ: Спиране на wuauserv е необходимо за изтриване."
Write-Host "Изпълни ръчно (като Администратор):"
Write-Host "  net stop wuauserv"
Write-Host "  Remove-Item '$wuDl\*' -Recurse -Force"
Write-Host "  net start wuauserv"
Write-Log "Windows Update Cache ($sz MB) — изисква ръчно почистване с Admin права"

# ── 4. Chrome кеш ────────────────────────────────────────
$chromeCaches = @(
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache"
)
foreach ($c in $chromeCaches) {
    $sz = Get-FolderSizeMB $c
    if ($sz -gt 50 -and (Confirm-Clean "Chrome Cache ($c)" $sz)) {
        Get-ChildItem -Path $c -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Изчистен Chrome кеш: $c — $sz MB"
    }
}

# ── 5. Edge кеш ──────────────────────────────────────────
$edgeCaches = @(
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache"
)
foreach ($e in $edgeCaches) {
    $sz = Get-FolderSizeMB $e
    if ($sz -gt 50 -and (Confirm-Clean "Edge Cache ($e)" $sz)) {
        Get-ChildItem -Path $e -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Изчистен Edge кеш: $e — $sz MB"
    }
}

# ── 6. Thumbnail кеш ─────────────────────────────────────
$thumbDb = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
$sz = Get-FolderSizeMB $thumbDb
if ($sz -gt 0 -and (Confirm-Clean "Thumbnail кеш" $sz)) {
    Get-ChildItem -Path $thumbDb -Filter "thumbcache_*.db" -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Log "Изчистен Thumbnail кеш — $sz MB"
}

# ── 7. Windows Error Reporting ────────────────────────────
$wer = "$env:LOCALAPPDATA\Microsoft\Windows\WER"
$sz = Get-FolderSizeMB $wer
if ($sz -gt 10 -and (Confirm-Clean "Windows Error Reporting" $sz)) {
    Get-ChildItem -Path $wer -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Изчистен WER — $sz MB"
}

# ── 8. Crash Dumps ────────────────────────────────────────
$crashDirs = @("$env:LOCALAPPDATA\CrashDumps", "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive")
foreach ($cd in $crashDirs) {
    $sz = Get-FolderSizeMB $cd
    if ($sz -gt 0 -and (Confirm-Clean "Crash Dumps ($cd)" $sz)) {
        Get-ChildItem -Path $cd -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Изчистени Crash Dumps: $cd — $sz MB"
    }
}

# ── 9. Gradle кеш ────────────────────────────────────────
$gradle = "$env:USERPROFILE\.gradle\caches"
$sz = Get-FolderSizeMB $gradle
if ($sz -gt 200 -and (Confirm-Clean "Gradle кеш (.gradle\caches)" $sz)) {
    Get-ChildItem -Path $gradle -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Изчистен Gradle кеш — $sz MB"
}

# ── 10. NuGet кеш ────────────────────────────────────────
$nuget = "$env:USERPROFILE\.nuget\packages"
$sz = Get-FolderSizeMB $nuget
if ($sz -gt 500 -and (Confirm-Clean "NuGet пакети (.nuget\packages)" $sz)) {
    Write-Host "За NuGet: изпълни 'dotnet nuget locals all --clear' за по-чисто почистване."
    Write-Log "NuGet кеш ($sz MB) — препоръчай dotnet nuget locals all --clear"
}

Write-Host ""
Write-Log "=== ПОЧИСТВАНЕТО ЗАВЪРШИ ==="
Write-Host "Лог файлът е записан в: $logPath"
