# Engineering notes

Condensed findings from building and validating this patch set.
All numbers below are measured on the reference device unless marked otherwise.

## 1. Why the stock path fails on Android

`-display egl-headless` requires a DRM render node:

```c
egl_rendernode_init() -> qemu_drm_rendernode_open() -> gbm_create_device()
```

Android applications have no `/dev/dri/renderD*` (`graphics_device` is HAL-only), so the init fails:

```
qemu-system-aarch64: egl: no drm render node available
qemu-system-aarch64: egl: render node init failed
```

## 2. The working EGL configuration on Android

| Attempt | Result |
|---|---|
| `eglGetDisplay(EGL_DEFAULT_DISPLAY)` + Termux Mesa | `eglInitialize` = `0x3001` (NOT_INITIALIZED) |
| `EGL_PLATFORM_SURFACELESS_MESA` (0x31DD) + `EGL_WINDOW_BIT` | `eglChooseConfig` fails (surfaceless advertises pbuffer only) |
| **surfaceless + `EGL_PBUFFER_BIT` + ES3 context** | **works**: `OpenGL ES 3.2 Mesa`, `zink Vulkan 1.4 (Turnip Adreno)` |

Driver selection that produced the GPU path:

```bash
export MESA_LOADER_DRIVER_OVERRIDE=zink
export GALLIUM_DRIVER=zink
```

## 3. The crash and its cause

Symptom: guest boots, then within 30–60 s QEMU dies silently (no message on stderr).

```
Fatal signal 11 (SIGSEGV), fault addr 0xee8
tid "CPU 0/TCG"
```

Symbolized stack:

```
#00 libGLESv2.so + 0x11e9c
#01 egl_fb_destroy                    ui/egl-helpers.c
#02 egl_scanout_disable               ui/egl-headless.c
#03 qemu_console_gl_scanout_disable
#04 virtio_gpu_virgl_reset_scanout
#05 virtio_gpu_gl_reset               hw/display/virtio-gpu-gl.c
#06 virtio_reset
#07 virtio_pci_reset
#08 memory_region_write_accessor
#09 access_with_adjusted_size
#10 memory_region_dispatch_write
#11 do_st_mmio_leN                    accel/tcg/cputlb.c
```

The reset is triggered synchronously by a guest MMIO write on the TCG vCPU thread, which has no
current EGL context. Mesa dereferences a null context pointer.

Control experiment: `GALLIUM_DRIVER=llvmpipe` crashes at the **same** instruction address with the
same frames, so this is not driver-specific — it is a thread-affinity bug in QEMU's reset path.

Fix: add `VirtIOGPUClass::reset_scanout`, invoke it from `virtio_gpu_reset_bh()` (main loop thread)
before `reset_finished` is signalled, and reduce `virtio_gpu_gl_reset()` to flipping `renderer_state`.

Related invariant: display FBOs must be created, used and destroyed with the display context bound
(`qemu_egl_rn_ctx`). GLES3 shares textures between contexts but **not** framebuffer objects.

## 4. Linker facts specific to Android

- NDK stub `libEGL.so` exports only the core API; extension entry points
  (`eglGetPlatformDisplayEXT`, `eglCreateImageKHR`, `eglExportDMABUFImageMESA`,
  `eglDupNativeFenceFDANDROID`, `glEGLImageTargetTexture2DOES`) are absent, and so are they in Mesa's
  `libEGL.so`. They must be reached via `eglGetProcAddress` — that is what `libeglshim.so` does.
- `DT_NEEDED` entries from hand-built stubs record the absolute link path unless the stub is linked
  with `-Wl,-soname,<name>`.
- Meson does not place `-lepoxy/-lGLESv2/-lEGL` on the executable link line for this cross build;
  they were injected into `build.ninja` rules containing ` -pie ` only.

## 5. Measured performance

| Metric | SwiftShader | virgl |
|---|---|---|
| SurfaceFlinger CPU | 72 % | 16–20 % |
| Guest boot to usable | ~10 min | ~4 min |
| QEMU stability | fine | 40+ min, 0 crashes |

Guest `top` under load showed `89 % irq`, dominated by `arch_timer` (~120k interrupts per CPU),
not by virtio. Timer interrupts are a fixed per-trap cost under TCG.

## 6. Thread placement

TCG runs one thread per vCPU (`thread=multi`). Measurement on the reference SoC showed the scheduler
leaving the prime/medium cores at their minimum frequency (614 MHz) while placing translator threads on
the little cores. Pinning all threads to the big-core mask raised the cluster to 2.4–2.6 GHz with no
other change. Best layout found:

```
vCPU threads ("CPU n/TCG")  -> medium cores (one each)
main loop / IO / VNC        -> remaining cores
little cores                -> unused
```

`-object iothread` was tested and rejected: it produced `SIGILL` inside the TCG thread
(`longjmp` frame) on this build.

## 7. Hard limits on this hardware

- `CONFIG_KVM=y` in the host kernel but **no `/dev/kvm`** (EL2 owned by vendor firmware);
  `ro.boot.hypervisor.protected_vm.supported=false`. Therefore TCG only.
- `# CONFIG_UDMABUF is not set` on the host: `blob=on` and venus are impossible, regardless of guest
  policy.
- `egl-headless` reads back every frame to the CPU (~4.6 MB at 720×1600), so this is not zero-copy.
- End-to-end TCG throughput stays around 10–15 % of native; the realistic ceiling after tuning is
  15–25 %, never 50 %.
