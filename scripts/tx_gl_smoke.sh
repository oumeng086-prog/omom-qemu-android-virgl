PREFIX=/data/data/com.termux/files/usr
H=/data/data/com.termux/files/home
B=$H/gl-bin
export HOME=$H
export LD_LIBRARY_PATH=$B:$PREFIX/lib
export PATH=$PREFIX/bin:$PATH

echo "=== 版本 ==="
$B/qemu-system-aarch64 --version 2>&1 | head -3

echo
echo "=== 能力 ==="
$B/qemu-system-aarch64 -device help 2>&1 | grep -i 'virtio-gpu' | head -6
$B/qemu-system-aarch64 -display help 2>&1 | sed -n '1,10p'

echo
echo "=== 决定性测试 A：egl-headless + virtio-gpu-gl（默认驱动）==="
timeout 25 $B/qemu-system-aarch64 -M virt -m 512 -S -monitor none -serial none \
  -display egl-headless -device virtio-gpu-gl-pci,blob=off 2>&1 | head -8
echo "rcA=$?"

echo
echo "=== 决定性测试 B：强制 zink ==="
MESA_LOADER_DRIVER_OVERRIDE=zink GALLIUM_DRIVER=zink timeout 25 $B/qemu-system-aarch64 \
  -M virt -m 512 -S -monitor none -serial none \
  -display egl-headless,gl=es -device virtio-gpu-gl-pci,blob=off 2>&1 | head -8
echo "rcB=$?"
