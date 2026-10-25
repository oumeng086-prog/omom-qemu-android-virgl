#!/bin/bash
set -e
NDK=/root/ndk/android-ndk-r27c/toolchains/llvm/prebuilt/linux-x86_64
QEMU=/root/work/qemu-11.1.2
LOG=/root/build.log
: > $LOG

echo "=== 1. Android 下用 ES3 上下文 ===" | tee -a $LOG
python3 - <<'PY' | tee -a /root/build.log
p = "/root/work/qemu-11.1.2/ui/egl-helpers.c"
s = open(p).read()
changed = []

# (a) 配置属性：ES3 可渲染位
old_a = """    static const EGLint conf_att_gles[] = {
        EGL_SURFACE_TYPE, QEMU_EGL_SURFACE_TYPE,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,"""
new_a = """    static const EGLint conf_att_gles[] = {
        EGL_SURFACE_TYPE, QEMU_EGL_SURFACE_TYPE,
#ifdef __ANDROID__
        EGL_RENDERABLE_TYPE, 0x00000040 /* EGL_OPENGL_ES3_BIT */,
#else
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
#endif"""
if old_a in s:
    s = s.replace(old_a, new_a, 1); changed.append("conf_att_gles")
else:
    print("WARN: conf_att_gles anchor miss")

# (b) context 版本 2 -> 3
old_b = """    static const EGLint ctx_att_gles[] = {
        EGL_CONTEXT_CLIENT_VERSION, 2,
        EGL_NONE
    };"""
new_b = """    static const EGLint ctx_att_gles[] = {
#ifdef __ANDROID__
        EGL_CONTEXT_CLIENT_VERSION, 3,
#else
        EGL_CONTEXT_CLIENT_VERSION, 2,
#endif
        EGL_NONE
    };"""
if old_b in s:
    s = s.replace(old_b, new_b, 1); changed.append("ctx_att_gles")
else:
    print("WARN: ctx_att_gles anchor miss")

open(p, "w").write(s)
print("patched:", changed)
PY

echo "=== 2. 重编 + 重链接 ===" | tee -a $LOG
cd $QEMU/build
export PATH=/root/shim:$NDK/bin:$PATH
nice -n 5 ninja -j18 qemu-system-aarch64 > /root/make.log 2>&1 || true
grep -E 'error:|undefined symbol' /root/make.log | sort -u | head -5 | tee -a $LOG || true
tail -2 /root/make.log | tee -a $LOG
cp qemu-system-aarch64 /mnt/d/qemu-android/gl-bin/qemu-system-aarch64
chmod 755 /mnt/d/qemu-android/gl-bin/qemu-system-aarch64
ls -l /mnt/d/qemu-android/gl-bin/qemu-system-aarch64 | tee -a $LOG
echo BUILD_DONE | tee -a $LOG
