PREFIX=/data/data/com.termux/files/usr
H=/data/data/com.termux/files/home
B=$H/gl-bin
export HOME=$H
export LD_LIBRARY_PATH=$B
export MESA_LOADER_DRIVER_OVERRIDE=zink
export GALLIUM_DRIVER=zink

echo "=== 最小 GL 测试（暂停态，512M）==="
timeout 25 $B/qemu-system-aarch64 -M virt -m 512 -S \
  -display egl-headless,gl=es -device virtio-gpu-gl-pci,blob=off \
  -monitor none -serial none 2>&1
echo "exit_code=$?"

echo
echo "=== 再测：带 -L 与 virtio-net（复现缺 rom）==="
timeout 25 $B/qemu-system-aarch64 -M virt -m 512 -S -L $PREFIX/share/qemu \
  -device virtio-net-pci,netdev=n0 -netdev user,id=n0 \
  -display egl-headless,gl=es -device virtio-gpu-gl-pci,blob=off \
  -monitor none -serial none 2>&1
echo "exit_code2=$?"
