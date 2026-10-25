#!/system/bin/sh
q=""
for p in /proc/[0-9]*; do
  if tr '\0' ' ' < $p/cmdline 2>/dev/null | grep -q 'qemu-system-aarch64'; then
    q=${p#/proc/}
    break
  fi
done
echo "qemu pid: $q"
[ -z "$q" ] && exit 1
echo "cmdline: $(tr '\0' ' ' < /proc/$q/cmdline | cut -c1-120)"

echo
echo "=== 1. Cpus_allowed_list ==="
grep -E 'Cpus_allowed|Mems_allowed_list' /proc/$q/status 2>/dev/null

echo
echo "=== 2. cpuset / cgroup ==="
cat /proc/$q/cpuset 2>/dev/null
head -3 /proc/$q/cgroup 2>/dev/null

echo
echo "=== 3. 主机核心 ==="
echo "nproc=$(nproc)"
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  [ -d "$p" ] && echo "$(basename $p): cpus=$(cat $p/affected_cpus 2>/dev/null) max_khz=$(cat $p/cpuinfo_max_freq 2>/dev/null)"
done

echo
echo "=== 4. 每线程 CPU 采样 ==="
top -H -b -n 2 -d 1 -p $q 2>/dev/null | grep -E '^ *[0-9]+' | tail -25
