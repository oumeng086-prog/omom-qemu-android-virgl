# qemu-android-virgl

**Real GPU acceleration (Adreno) for an Android guest running inside QEMU on an unrooted Android phone.**

No root. No KVM. No `/dev/dri`. The guest's SurfaceFlinger composites through
`virgl → zink → Turnip → KGSL → Adreno`, i.e. the phone's actual GPU, instead of SwiftShader.

```
------------RE GLES (Ganesh)------------
GLES: Mesa, virgl (zink Vulkan 1.4(Turnip Adreno (TM) 750 (MESA_TURNIP))), OpenGL ES 3.2 Mesa 26.2.3
```

Tested on: Xiaomi 14 (`houji` / SM8650 / Adreno 750), Android 16, Termux (app uid, no root),
QEMU 11.1.2 cross-compiled with NDK r27c for `aarch64-linux-android30`.

---

## Why this exists

Running a full Android VM on an Android phone normally means QEMU with TCG (software CPU) plus
SwiftShader (software GPU). Both are CPU-bound and fight for the same emulated cores.

Android gives apps no `/dev/dri/renderD*`, and QEMU's `-display egl-headless` hard-requires a DRM
render node (`gbm_create_device`), so the stock path is:

```
qemu-system-aarch64: egl: no drm render node available
qemu-system-aarch64: egl: render node init failed
```

This project replaces that path with a **surfaceless EGL** context that reaches the real GPU, and fixes
a crash that makes the guest unusable once GL is enabled.

## Measured results

Same guest image, same VM configuration, `-cpu cortex-a72`, `-smp 4`, 3 GB:

| Metric | SwiftShader | virgl (this project) |
|---|---|---|
| SurfaceFlinger CPU | **72 %** | **16–20 %** |
| Boot → usable | ~10 min | **~4 min** |
| Guest renderer | SwiftShader / llvmpipe | **virgl (zink/Turnip → Adreno 750)** |
| Guest `ro.hardware.egl` | `angle` | **`mesa`** |
| Guest `ro.hardware.vulkan` | — | **`virtio`** |

Stable for 40+ minutes with zero QEMU crashes (previously SIGSEGV within 30–60 s).

## What actually had to be fixed

### 1. EGL platform on Android: surfaceless, pbuffer configs, ES 3

`eglGetDisplay(EGL_DEFAULT_DISPLAY)` returns `EGL_NOT_INITIALIZED (0x3001)` with Termux's Mesa.
The working combination is:

```c
EGL_PLATFORM_SURFACELESS_MESA  /* 0x31DD */
+ EGL_SURFACE_TYPE = EGL_PBUFFER_BIT      /* surfaceless only advertises pbuffer configs */
+ EGL_OPENGL_ES3_BIT / EGL_CONTEXT_CLIENT_VERSION = 3
```

On this host it yields `OpenGL ES 3.2 Mesa`, which satisfies QEMU's `#version 300 es` shaders.

### 2. SIGSEGV: GL called from the TCG vCPU thread

Guest writes the virtio-gpu reset register → MMIO → **TCG vCPU thread** → `virtio_gpu_gl_reset()` →
`virtio_gpu_virgl_reset_scanout()` → `egl_scanout_disable()` → `egl_fb_destroy()` → `glDeleteFramebuffers()`
— on a thread that has **no current EGL context**. Android's Mesa dereferences NULL (`fault addr 0xee8`)
and the process dies.

Symbolized stack (`llvm-addr2line` on the cross-built binary):

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
#11 do_st_mmio_leN                    accel/tcg/cputlb.c     ← TCG vCPU thread
```

Proof it is a threading bug and not a driver bug: forcing `GALLIUM_DRIVER=llvmpipe` crashes at the
**identical address** with the same frames.

Fix (`patches/0002`): add a `reset_scanout` class callback and run the scanout/GL cleanup inside the
existing `virtio_gpu_reset_bh()` — i.e. on the main loop thread — before `reset_finished` is signalled.
`virtio_gpu_gl_reset()` only flips `renderer_state` to `RS_RESET`.

### 3. EGL/GL extension entry points are not exported

Neither Android's stub `libEGL.so` nor Mesa's `libEGL.so` exports `eglGetPlatformDisplayEXT`,
`eglCreateImageKHR`, `eglExportDMABUFImageMESA`, `eglDupNativeFenceFDANDROID`, `glEGLImageTargetTexture2DOES`.
`libeglshim.so` (`scripts/toolchain/eglshim.c`) forwards each of them through `eglGetProcAddress()`.

### 4. Meson/NDK build friction

Documented in `docs/`; highlights:

- QEMU's `standard-headers` must stay **pristine** — do not patch `virtio_*.h`, do not add
  `include/standard-headers` to `-I`, do not add `-I/root/uapi` (Ubuntu uapi headers break bionic's
  `arpa/inet.h` → `in_addr_t` unknown).
- Keep only `glib-2.0 / pixman-1 / slirp` under the Termux sysroot's `include/`; all system headers
  must come from the NDK bionic sysroot.
- `-lepoxy -lGLESv2 -lEGL -leglshim` are **not** on meson's link line; they must be injected into the
  executable link rules in `build.ninja` (only lines containing ` -pie `, never `ar` lines).
- Every hand-built stub needs `-Wl,-soname,<name>`, otherwise `DT_NEEDED` records an absolute build path
  and the binary cannot start on the device.

## Layout

```
patches/
  0001-ui-android-surfaceless-egl-es3.patch      # EGL platform + pbuffer + ES3 + context binding
  0002-virtio-gpu-defer-scanout-reset-to-bh.patch # run scanout/GL cleanup on the main loop
scripts/
  tx_vm_gl.sh          # working launch line (virtio-gpu-gl-pci, blob=off, egl-headless,gl=es)
  tx_vm_apk.sh         # same + an extra virtio-blk carrying an ext4 image with APKs
  pin_qemu.sh          # pin all QEMU threads to the big-core mask
  tx_pin_split.sh      # vCPU threads → medium cores, IO/main → remaining cores
  guestcon.ps1         # drive the guest console over a virtio-console socket (no adb needed)
  smoke_test.ps1       # boot → wait for boot_completed → read SF renderer → exit
scripts/toolchain/
  eglshim.c            # libeglshim.so source
  wsl_build*.sh        # configure + link recipe used to produce the binary
docs/                  # full engineering logs (Chinese) incl. three rounds of expert review
```

## Build

Cross-compile QEMU 11.1.2 with NDK r27c, `aarch64-linux-android30`, against Termux's prebuilt
glib/pixman/slirp. Apply `patches/0001` and `patches/0002`, configure with:

```
--target-list=aarch64-softmmu --cpu=aarch64 --cross-prefix=aarch64-linux-android30- \
--enable-opengl --enable-virglrenderer \
--disable-virtfs --disable-gnutls --disable-nettle --disable-gcrypt \
--disable-vhost-user --disable-vhost-kernel --disable-vhost-net --disable-vhost-vdpa \
--disable-vhost-crypto --disable-vhost-user-blk-server \
--disable-docs --disable-tools --disable-guest-agent --disable-plugins \
--disable-werror --disable-debug-info
```

then inject the GL/EGL libs into the executable link rules and `ninja qemu-system-aarch64`.
`docs/` contains the exact scripts and every error encountered.

## Run (Termux, app uid, no root)

```bash
export LD_LIBRARY_PATH=$HOME/gl-bin            # qemu + libeglshim/librt, other libs symlinked to $PREFIX/lib
export MESA_LOADER_DRIVER_OVERRIDE=zink GALLIUM_DRIVER=zink

$HOME/gl-bin/qemu-system-aarch64 \
  -M virt -cpu cortex-a72 -accel tcg,tb-size=1024,thread=multi -m 3072 -smp 4 \
  -device virtio-gpu-gl-pci,id=gpu0,blob=off,edid=on,xres=720,yres=1600 \
  -display egl-headless,gl=es -vnc 127.0.0.1:0
```

Guest-side requirements (this project was validated with a LineageOS-for-QEMU image):

- the ROM must ship `libgallium_dri` (virgl) + `mapper.minigbm_upstream`
- `ro.vendor.graphics=mesa` / `ro.hardware.egl=mesa` / `ro.hardware.vulkan=virtio` are selected
  automatically by the ROM's `virtgpu_detect` once 3D is advertised

## Tuning that measured well

- **Pin the TCG vCPU threads to the medium cores.** Android's scheduler otherwise leaves the big
  cores at their minimum frequency (measured: 614 MHz idle) and puts translator threads on the little
  cores. Pinning raised the cluster to 2.4–2.6 GHz for free.
- `-accel tcg,thread=multi` is required; verify with per-thread `/proc/<pid>/task/*/stat` that the four
  `CPU n/TCG` threads run in parallel.
- Avoid `-object iothread` on this build: it produced `SIGILL` inside the TCG thread (`longjmp` frame).

## Limitations (measured, not guessed)

- **TCG has no hardware virtualization.** This host exposes `CONFIG_KVM=y` but no `/dev/kvm`
  (EL2 is owned by vendor firmware) and pKVM reports `supported=false`. Expect ~10 % of native CPU;
  the ceiling after all tuning is ~15–25 %, not 50 %.
- **`blob=on` / venus are impossible here**: the host kernel has `# CONFIG_UDMABUF is not set`.
- **`egl-headless` reads every frame back to the CPU** (~4.6 MB/frame at 720×1600), so this is not
  zero-copy and not a win for fill-rate-bound workloads beyond what is measured above.
- On the reference ROM, booting with GL enabled required permissive SELinux (`system_server` was
  denied `/dev/udmabuf`); returning to enforcing needs targeted policy work. This patch set does not
  change SELinux behaviour.

## License

GPL-2.0-or-later.

The patches under `patches/` modify QEMU 11.1.2 and are therefore derivative works of QEMU,
distributed under the same license. No QEMU source, no prebuilt binaries, no ROM images and no
third-party APKs are included in this repository — only patches, scripts and documentation.
The build instructions reference (but do not bundle) virglrenderer, Mesa, libepoxy and the Termux
packages, each under its own license.

---

## 中文摘要

在**未 root 的 Android 手机**上，给 QEMU 里的 Android 客机接上**真实 GPU**（Adreno）：

- 客机 SurfaceFlinger 实测走 `virgl → zink → Turnip → Adreno 750`，OpenGL ES 3.2
- 合成开销从 **72 % CPU → 16–20 %**，开机从 **~10 分钟 → ~4 分钟**
- 关键修复：QEMU 在 **TCG vCPU 线程**里调 GL 导致 SIGSEGV，改为在主循环的 `reset_bh` 里做
  scanout 清理；以及 Android 上必须用 **surfaceless EGL + pbuffer config + ES3 上下文**
- 附带 `libeglshim.so`：Android 的 `libEGL.so` 不导出 EGL 扩展入口，需经 `eglGetProcAddress` 转发
- 硬件限制：宿主内核 `CONFIG_KVM=y` 但无 `/dev/kvm`、`CONFIG_UDMABUF` 未开，因此
  **blob/venus 不可行**，TCG 天花板约 15–25 % 原生性能
