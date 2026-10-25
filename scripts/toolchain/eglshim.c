#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <stddef.h>

static void *egl_sym(const char *n) { return (void *)eglGetProcAddress(n); }

EGLDisplay eglGetPlatformDisplayEXT(EGLenum platform, void *native, const EGLint *attribs)
{
    static PFNEGLGETPLATFORMDISPLAYEXTPROC fn;
    if (!fn) fn = (PFNEGLGETPLATFORMDISPLAYEXTPROC)egl_sym("eglGetPlatformDisplayEXT");
    return fn ? fn(platform, native, attribs) : EGL_NO_DISPLAY;
}

EGLImageKHR eglCreateImageKHR(EGLDisplay dpy, EGLContext ctx, EGLenum target, EGLClientBuffer buffer, const EGLint *attrs)
{
    static PFNEGLCREATEIMAGEKHRPROC fn;
    if (!fn) fn = (PFNEGLCREATEIMAGEKHRPROC)egl_sym("eglCreateImageKHR");
    return fn ? fn(dpy, ctx, target, buffer, attrs) : EGL_NO_IMAGE_KHR;
}

EGLBoolean eglDestroyImageKHR(EGLDisplay dpy, EGLImageKHR image)
{
    static PFNEGLDESTROYIMAGEKHRPROC fn;
    if (!fn) fn = (PFNEGLDESTROYIMAGEKHRPROC)egl_sym("eglDestroyImageKHR");
    return fn ? fn(dpy, image) : EGL_FALSE;
}

EGLSyncKHR eglCreateSyncKHR(EGLDisplay dpy, EGLenum type, const EGLint *attrs)
{
    static PFNEGLCREATESYNCKHRPROC fn;
    if (!fn) fn = (PFNEGLCREATESYNCKHRPROC)egl_sym("eglCreateSyncKHR");
    return fn ? fn(dpy, type, attrs) : EGL_NO_SYNC_KHR;
}

EGLBoolean eglDestroySyncKHR(EGLDisplay dpy, EGLSyncKHR sync)
{
    static PFNEGLDESTROYSYNCKHRPROC fn;
    if (!fn) fn = (PFNEGLDESTROYSYNCKHRPROC)egl_sym("eglDestroySyncKHR");
    return fn ? fn(dpy, sync) : EGL_FALSE;
}

EGLint eglClientWaitSyncKHR(EGLDisplay dpy, EGLSyncKHR sync, EGLint flags, EGLTimeKHR timeout)
{
    static PFNEGLCLIENTWAITSYNCKHRPROC fn;
    if (!fn) fn = (PFNEGLCLIENTWAITSYNCKHRPROC)egl_sym("eglClientWaitSyncKHR");
    return fn ? fn(dpy, sync, flags, timeout) : EGL_FALSE;
}

EGLint eglDupNativeFenceFDANDROID(EGLDisplay dpy, EGLSyncKHR sync)
{
    PFNEGLDUPNATIVEFENCEFDANDROIDPROC fn =
        (PFNEGLDUPNATIVEFENCEFDANDROIDPROC)egl_sym("eglDupNativeFenceFDANDROID");
    return fn ? fn(dpy, sync) : -1;
}

EGLBoolean eglExportDMABUFImageQueryMESA(EGLDisplay dpy, EGLImageKHR image, int *fourcc, int *planes, EGLuint64KHR *mods)
{
    PFNEGLEXPORTDMABUFIMAGEQUERYMESAPROC fn =
        (PFNEGLEXPORTDMABUFIMAGEQUERYMESAPROC)egl_sym("eglExportDMABUFImageQueryMESA");
    return fn ? fn(dpy, image, fourcc, planes, mods) : EGL_FALSE;
}

EGLBoolean eglExportDMABUFImageMESA(EGLDisplay dpy, EGLImageKHR image, int *fds, EGLint *strides, EGLint *offsets)
{
    PFNEGLEXPORTDMABUFIMAGEMESAPROC fn =
        (PFNEGLEXPORTDMABUFIMAGEMESAPROC)egl_sym("eglExportDMABUFImageMESA");
    return fn ? fn(dpy, image, fds, strides, offsets) : EGL_FALSE;
}

void glEGLImageTargetTexture2DOES(GLenum target, void *image)
{
    typedef void (*PFN)(GLenum, void *);
    static PFN fn;
    if (!fn) fn = (PFN)egl_sym("glEGLImageTargetTexture2DOES");
    if (fn) fn(target, image);
}
