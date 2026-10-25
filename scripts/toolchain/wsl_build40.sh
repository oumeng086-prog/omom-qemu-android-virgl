#!/bin/bash
set -e
NDK=/root/ndk/android-ndk-r27c/toolchains/llvm/prebuilt/linux-x86_64
Q=/root/work/qemu-11.1.2
LOG=/root/build.log
: > $LOG

python3 - <<'PY' | tee -a /root/build.log
import re

Q = "/root/work/qemu-11.1.2"
def rd(p): return open(p).read()
def wr(p, s): open(p, "w").write(s)
done = []

# ---------- 1. VirtIOGPUClass: reset_scanout ----------
p = Q + "/include/hw/virtio/virtio-gpu.h"
s = rd(p)
if "reset_scanout" not in s:
    anchor = """    void (*resource_destroy)(VirtIOGPU *g,
                             struct virtio_gpu_simple_resource *res,
                             Error **errp);
};"""
    assert anchor in s, "hdr anchor"
    s = s.replace(anchor, """    void (*resource_destroy)(VirtIOGPU *g,
                             struct virtio_gpu_simple_resource *res,
                             Error **errp);
    void (*reset_scanout)(VirtIOGPU *g);
};""", 1)
    wr(p, s); done.append("virtio-gpu.h")

# ---------- 2. virtio-gpu.c: reset_bh 里调用 ----------
p = Q + "/hw/display/virtio-gpu.c"
s = rd(p)
if "reset_scanout" not in s:
    anchor = """    for (i = 0; i < g->parent_obj.conf.max_outputs; i++) {
        qemu_console_set_surface(g->parent_obj.scanout[i].con, NULL);
    }

    g->reset_finished = true;"""
    assert anchor in s, "reset_bh anchor"
    s = s.replace(anchor, """    for (i = 0; i < g->parent_obj.conf.max_outputs; i++) {
        qemu_console_set_surface(g->parent_obj.scanout[i].con, NULL);
    }

    /* scanout/GL cleanup must run here, on the main loop thread */
    if (vgc->reset_scanout) {
        vgc->reset_scanout(g);
    }

    g->reset_finished = true;""", 1)
    wr(p, s); done.append("virtio-gpu.c")

# ---------- 3. virtio-gpu-gl.c ----------
p = Q + "/hw/display/virtio-gpu-gl.c"
s = rd(p)
if "virtio_gpu_gl_reset_scanout" not in s:
    old_reset = """    if (gl->renderer_state == RS_INITED) {
        virtio_gpu_virgl_reset_scanout(g);
        gl->renderer_state = RS_RESET;
    }"""
    assert old_reset in s, "gl reset anchor"
    s = s.replace(old_reset, """    if (gl->renderer_state == RS_INITED) {
        /* scanout cleanup is deferred to virtio_gpu_reset_bh() which runs
         * on the main loop thread (reset_scanout class callback). */
        gl->renderer_state = RS_RESET;
    }""", 1)

    anchor = "static void virtio_gpu_gl_class_init(ObjectClass *klass, const void *data)"
    assert anchor in s
    s = s.replace(anchor, """static void virtio_gpu_gl_reset_scanout(VirtIOGPU *g)
{
    VirtIOGPUGL *gl = VIRTIO_GPU_GL(g);

    if (gl->renderer_state == RS_INITED) {
        virtio_gpu_virgl_reset_scanout(g);
    }
}

""" + anchor, 1)

    reg = "    vgc->resource_destroy = virtio_gpu_virgl_resource_destroy;"
    assert reg in s
    s = s.replace(reg, reg + "\n    vgc->reset_scanout = virtio_gpu_gl_reset_scanout;", 1)
    wr(p, s); done.append("virtio-gpu-gl.c")

# ---------- 4. egl-helpers: enter/leave helpers ----------
p = Q + "/ui/egl-helpers.c"
s = rd(p)
if "qemu_egl_rn_ctx_enter" not in s:
    s = s.rstrip() + """

bool qemu_egl_rn_ctx_enter(EGLDisplay *prev_dpy, EGLContext *prev_ctx,
                           EGLSurface *prev_draw, EGLSurface *prev_read)
{
    *prev_dpy  = eglGetCurrentDisplay();
    *prev_ctx  = eglGetCurrentContext();
    *prev_draw = eglGetCurrentSurface(EGL_DRAW);
    *prev_read = eglGetCurrentSurface(EGL_READ);
    if (eglMakeCurrent(qemu_egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                       qemu_egl_rn_ctx) != EGL_TRUE) {
        error_report("%s: bind qemu_egl_rn_ctx failed: 0x%x", __func__, eglGetError());
        return false;
    }
    return true;
}

void qemu_egl_rn_ctx_leave(EGLDisplay prev_dpy, EGLContext prev_ctx,
                           EGLSurface prev_draw, EGLSurface prev_read)
{
    if (prev_ctx != EGL_NO_CONTEXT) {
        if (eglMakeCurrent(prev_dpy, prev_draw, prev_read, prev_ctx) != EGL_TRUE) {
            error_report("%s: restore prev ctx failed: 0x%x", __func__, eglGetError());
        }
    } else {
        eglMakeCurrent(qemu_egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    }
}
"""
    wr(p, s); done.append("egl-helpers.c(defs)")

p = Q + "/include/ui/egl-helpers.h"
s = rd(p)
if "qemu_egl_rn_ctx_enter" not in s:
    s = s.rstrip() + """

bool qemu_egl_rn_ctx_enter(EGLDisplay *prev_dpy, EGLContext *prev_ctx,
                           EGLSurface *prev_draw, EGLSurface *prev_read);
void qemu_egl_rn_ctx_leave(EGLDisplay prev_dpy, EGLContext prev_ctx,
                           EGLSurface prev_draw, EGLSurface prev_read);
"""
    wr(p, s); done.append("egl-helpers.h")

# ---------- 5. egl-headless: 三个入口绑定固定 context ----------
p = Q + "/ui/egl-headless.c"
s = rd(p)
if "qemu_egl_rn_ctx_enter" not in s:
    # scanout_disable
    old = """static void egl_scanout_disable(DisplayChangeListener *dcl)
{
    egl_dpy *edpy = container_of(dcl, egl_dpy, dcl);

    egl_fb_destroy(&edpy->guest_fb);
    egl_fb_destroy(&edpy->blit_fb);
}"""
    new = """static void egl_scanout_disable(DisplayChangeListener *dcl)
{
    egl_dpy *edpy = container_of(dcl, egl_dpy, dcl);
    EGLDisplay p_dpy; EGLContext p_ctx; EGLSurface p_draw, p_read;

    if (!qemu_egl_rn_ctx_enter(&p_dpy, &p_ctx, &p_draw, &p_read)) {
        return;
    }
    egl_fb_destroy(&edpy->guest_fb);
    egl_fb_destroy(&edpy->blit_fb);
    qemu_egl_rn_ctx_leave(p_dpy, p_ctx, p_draw, p_read);
}"""
    assert old in s, "disable anchor"
    s = s.replace(old, new, 1)
    wr(p, s); done.append("egl-headless.c(disable)")

print("PATCHED:", done if done else "nothing (already applied?)")
PY

echo "=== 编译 ===" | tee -a $LOG
cd $Q/build
export PATH=/root/shim:$NDK/bin:$PATH
nice -n 5 ninja -j18 qemu-system-aarch64 > /root/make.log 2>&1 || true
grep -E 'error:|warning: .*reset_scanout|undefined symbol' /root/make.log | sort -u | head -8 | tee -a $LOG || true
tail -3 /root/make.log | tee -a $LOG
cp qemu-system-aarch64 /mnt/d/qemu-android/gl-bin/qemu-system-aarch64 2>/dev/null && chmod 755 /mnt/d/qemu-android/gl-bin/qemu-system-aarch64
ls -l /mnt/d/qemu-android/gl-bin/qemu-system-aarch64 | tee -a $LOG
echo BUILD_DONE | tee -a $LOG
