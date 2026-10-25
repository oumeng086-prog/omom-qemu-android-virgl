#!/bin/bash
set -e
Q=/root/work/qemu-11.1.2
TAR=/mnt/d/qemu-android/qemu-11.1.2.tar.xz
OUT=/mnt/d/qemu-android/patches
mkdir -p $OUT
rm -rf /tmp/pristine2 && mkdir -p /tmp/pristine2 && cd /tmp/pristine2
tar xf $TAR \
  qemu-11.1.2/ui/egl-helpers.c \
  qemu-11.1.2/ui/egl-headless.c \
  qemu-11.1.2/ui/console-gl.c \
  qemu-11.1.2/hw/display/virtio-gpu.c \
  qemu-11.1.2/hw/display/virtio-gpu-gl.c \
  qemu-11.1.2/include/hw/virtio/virtio-gpu.h 2>/dev/null

: > $OUT/android-virgl.patch
for f in ui/egl-helpers.c ui/console-gl.c ui/egl-headless.c hw/display/virtio-gpu.c hw/display/virtio-gpu-gl.c include/hw/virtio/virtio-gpu.h; do
  diff -u "/tmp/pristine2/qemu-11.1.2/$f" "$Q/$f" \
    --label "a/$f" --label "b/$f" >> $OUT/android-virgl.patch || true
done

echo "=== 补丁大小 / 变更文件 ==="
wc -l $OUT/android-virgl.patch
grep -c '^+++' $OUT/android-virgl.patch
grep '^+++' $OUT/android-virgl.patch

echo
echo "=== 关键 hunk 摘要 ==="
grep -E '^\+.*(EGL_PBUFFER_BIT|EGL_OPENGL_ES3_BIT|CLIENT_VERSION|SURFACELESS|reset_scanout|qemu_egl_rn_ctx_enter|__ANDROID__)' $OUT/android-virgl.patch | head -20
