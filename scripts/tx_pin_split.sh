#!/system/bin/sh
# vCPU 线程("CPU n/TCG") -> 中核 cpu2-5 (0x3c)，各占一个
# 其他线程(主循环/IO/VNC) -> cpu6-7 (0xc0)
q="$1"
[ -z "$q" ] && { echo "usage: $0 <pid>"; exit 1; }
[ -d /proc/$q ] || { echo "no pid $q"; exit 1; }

vcpu=0; other=0
for t in /proc/$q/task/*; do
  tid=${t##*/}
  comm=$(cat $t/comm 2>/dev/null)
  case "$comm" in
    CPU*|*TCG*)
      taskset -p 3c $tid >/dev/null 2>&1 && vcpu=$((vcpu+1)) ;;
    *)
      taskset -p c0 $tid >/dev/null 2>&1 && other=$((other+1)) ;;
  esac
done
echo "vCPU threads -> cpu2-5 (0x3c): $vcpu"
echo "other threads -> cpu6-7 (0xc0): $other"

echo "--- 线程名与落点 ---"
for t in /proc/$q/task/*; do
  tid=${t##*/}
  comm=$(cat $t/comm 2>/dev/null)
  cpu=$(awk '{print $39}' $t/stat 2>/dev/null)
  case "$comm" in CPU*|*TCG*) echo "  [vCPU] tid=$tid comm=$comm cpu=$cpu" ;; esac
done | head -6

echo "--- 频率 ---"
for c in 2 3 4 5 6 7; do printf "cpu%s=%s " $c "$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq 2>/dev/null)"; done
echo
