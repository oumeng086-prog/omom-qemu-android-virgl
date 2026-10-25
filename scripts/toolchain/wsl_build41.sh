#!/bin/bash
set -e
NDK=/root/ndk/android-ndk-r27c/toolchains/llvm/prebuilt/linux-x86_64
Q=/root/work/qemu-11.1.2
LOG=/root/build.log
: > $LOG

python3 - <<'PY' | tee -a /root/build.log
Q = "/root/work/qemu-11.1.2"
p = Q + "/include/hw/virtio/virtio-gpu.h"
s = open(p).read()
member = "    void (*reset_scanout)(VirtIOGPU *g);"
if member in s:
    print("already has member")
else:
    anchor = """    void (*resource_destroy)(VirtIOGPU *g,
                             struct virtio_gpu_simple_resource *res,
                             Error **errp);
};"""
    assert anchor in s, "anchor missing"
    s = s.replace(anchor, """    void (*resource_destroy)(VirtIOGPU *g,
                             struct virtio_gpu_simple_resource *res,
                             Error **errp);
    void (*reset_scanout)(VirtIOGPU *g);
};""", 1)
    open(p, "w").write(s)
    print("member added")
PY

echo "=== 编译 ===" | tee -a $LOG
cd $Q/build
export PATH=/root/shim:$NDK/bin:$PATH
nice -n 5 ninja -j18 qemu-system-aarch64 > /root/make.log 2>&1 || true
grep -E 'error:|undefined symbol' /root/make.log | sort -u | head -8 | tee -a $LOG || true
tail -3 /root/make.log | tee -a $LOG
cp qemu-system-aarch64 /mnt/d/qemu-android/gl-bin/qemu-system-aarch64 && chmod 755 /mnt/d/qemu-android/gl-bin/qemu-system-aarch64
ls -l /mnt/d/qemu-android/gl-bin/qemu-system-aarch64 | tee -a $LOG
echo BUILD_DONE | tee -a $LOG
