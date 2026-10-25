#!/system/bin/sh
# 把 QEMU 的全部线程钉到大核（排除 cpu0/cpu1 两个小核）
# 用法: pin_qemu.sh [mask]   默认 fc = cpu2..cpu7
MASK="${1:-fc}"

q=""
for p in /proc/[0-9]*; do
  tr '\0' ' ' < $p/cmdline 2>/dev/null | grep -q 'qemu-system-aarch64' && { q=${p#/proc/}; break; }
done
[ -z "$q" ] && { echo "pin_qemu: no qemu running"; exit 1; }

ok=0; fail=0
for t in /proc/$q/task/*; do
  if taskset -p "$MASK" "${t##*/}" >/dev/null 2>&1; then ok=$((ok+1)); else fail=$((fail+1)); fi
done
echo "pin_qemu: pid=$q mask=0x$MASK pinned=$ok failed=$fail"
