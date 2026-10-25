# 冒烟测试：起机 → 等 boot_completed → 抓 SF renderer → 退出
# 用法: powershell -File smoke_test.ps1 [-Launcher /data/data/com.termux/files/home/tx_vm_gl.sh] [-TimeoutSec 900]
param(
    [string]$Launcher = "/data/data/com.termux/files/home/tx_vm_gl.sh",
    [int]$TimeoutSec = 900,
    $Serial = $env:ANDROID_SERIAL  # set ANDROID_SERIAL to your device serial
)
$ErrorActionPreference = 'Continue'
$ADB = 'C:\Users\q1581\android-sdk\platform-tools\adb.exe'
$G   = Join-Path $PSScriptRoot 'guestcon.ps1'
$fail = 0

function Say($m) { Write-Output ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }

# 0. 清理旧实例
$n = (& $ADB -s $Serial shell "ps -A -o PID,NAME 2>/dev/null | grep -c qemu-system" 2>&1) -join ''
if ("$n".Trim() -match '^[1-9]') {
    Say "发现已有 QEMU，先停止"
    & $ADB -s $Serial shell "ps -A -o PID,NAME 2>/dev/null | grep qemu-system | awk '{print `$1}' | xargs -r kill -9" 2>&1 | Out-Null
    Start-Sleep -Seconds 3
}

# 1. 起机
Say "启动: $Launcher"
& $ADB -s $Serial shell "run-as com.termux sh $Launcher" 2>&1 | Select-Object -First 4 | ForEach-Object { Say $_ }
Start-Sleep -Seconds 15

$alive = (& $ADB -s $Serial shell "ps -A -o PID,NAME 2>/dev/null | grep -c qemu-system" 2>&1) -join ''
if ("$alive".Trim() -eq '0') { Say "FAIL: QEMU 未存活"; exit 1 }
Say "QEMU 存活 (pid 数=$("$alive".Trim()))"

# 2. 等 boot_completed（走客机控制台，因为 adbd 可能起不来）
& $ADB -s $Serial forward tcp:5558 tcp:5558 2>&1 | Out-Null
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$booted = $false
while ((Get-Date) -lt $deadline) {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $G -Cmd "getprop sys.boot_completed" -WaitMs 2000 2>&1
    if (("$out" -join '') -match '(?m)^\s*1\s*$') { $booted = $true; break }
    Say "等待 boot_completed ..."
    Start-Sleep -Seconds 30
}
if (-not $booted) {
    Say "FAIL: ${TimeoutSec}s 内未 boot_completed"
    Say "--- 可能原因：GL 路径不可用（见 README 第 2.3 节）---"
    $fail = 1
} else {
    Say "PASS: sys.boot_completed=1"
}

# 3. 抓 SurfaceFlinger renderer
if ($booted) {
    $r = & powershell -NoProfile -ExecutionPolicy Bypass -File $G -Cmd "dumpsys SurfaceFlinger 2>/dev/null | grep -m1 GLES:" -WaitMs 6000 2>&1
    Say ("SF: " + (("$r" -join ' ').Trim()))
    if (("$r" -join '') -match 'virgl') { Say "PASS: renderer = virgl" }
    elseif (("$r" -join '') -match 'SwiftShader|llvmpipe|ANGLE') { Say "INFO: 软件渲染（预期基线）" }
    else { Say "WARN: 未取到 renderer 串"; $fail = 1 }
}

# 4. 收尾
Say "停止 QEMU"
& $ADB -s $Serial shell "ps -A -o PID,NAME 2>/dev/null | grep qemu-system | awk '{print `$1}' | xargs -r kill -9" 2>&1 | Out-Null
exit $fail
