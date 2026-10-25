#!/system/bin/sh
q=""
for p in /proc/[0-9]*; do
  tr '\0' ' ' < $p/cmdline 2>/dev/null | grep -q 'qemu-system-aarch64' && { q=${p#/proc/}; break; }
done
[ -z "$q" ] && { echo "no qemu"; exit 1; }
echo "qemu pid=$q  tid  ->  cpu"
echo "--- 线程当前所在 CPU ---"
for t in /proc/$q/task/*; do
  tid=${t#/proc/$q/task/}
  cpu=$(awk '{print $39}' $t/stat 2>/dev/null)
  utime=$(awk '{print $14}' $t/stat 2>/dev/null)
  echo "tid=$tid cpu=$cpu utime=$utime"
done | sort -t= -k4 -rn | head -12

echo
echo "--- 各核当前频率 / 在线状态 ---"
for c in 0 1 2 3 4 5 6 7; do
  on=$(cat /sys/devices/system/cpu/cpu$c/online 2>/dev/null || echo 1)
  f=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq 2>/dev/null)
  echo "cpu$c online=$on cur=${f}kHz"
done

echo
echo "--- 热控状态 ---"
cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -8 | tr '\n' ' '
echo
