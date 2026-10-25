# qemu-android-virgl

**Offload an Android guest's composition to the host GPU inside QEMU — on an unrooted Android phone.**

This is a patch set plus a build recipe. It makes `-display egl-headless` work on a host that has
GL/GLES but **no DRM render node** (an Android app sandbox), so the guest's SurfaceFlinger composites
through `virgl → zink → Turnip → KGSL → Adreno` instead of SwiftShader.

```
------------RE GLES (Ganesh)------------
GLES: Mesa, virgl (zink Vulkan 1.4(Turnip Adreno (TM) 750 (MESA_TURNIP))), OpenGL ES 3.2 Mesa 26.2.3
```

Be precise about what this buys you: **composition is offloaded, and every frame is then read back to
the CPU** (`egl-headless` has no scanout path back to a display). It removes rasterisation work from
the emulated cores. It does **not** make a GPU-bound workload fast, and for fill-rate-heavy content
(games, video) it can be slower than SwiftShader.

Reference environment: Xiaomi 14 (`houji` / SM8650 / Adreno 750), Android 16, Termux, QEMU 11.1.2
cross-compiled with NDK r27c.

---

## Results (measured, same guest image, `-cpu cortex-a72`, `-smp 4`, 3 GB)

| Metric | SwiftShader | virgl |
|---|---|---|
| SurfaceFlinger process CPU | 72 % | 16–20 % |
| Guest boot to console prompt | ~10 min | ~4 min |
| Guest `ro.hardware.egl` | `angle` | `mesa` |
| Guest `ro.hardware.vulkan` | — | `virtio` |

Read that first row correctly: it is **SurfaceFlinger's own CPU time**, not whole-system CPU. The work
moves to the TCG threads plus the host GPU process, and every frame adds a ~4.6 MB readback memcpy at
720×1600. Guest-side totals show the freed time largely reappearing as `arch_timer` interrupt
processing (~120k interrupts per CPU) — see `docs/findings.md` §5–6. Measure `/proc/stat` or whole-VM
`top` if you need the total.

Stability: one 40-minute session (≈4 min boot + ≈36 min up) with no QEMU crash, previously SIGSEGV
within 30–60 s. That is not a stress-test result — no 3D workload, no suspend/resume cycles, no guest
reboot was run.

## Patches

`patches/` holds the changes against QEMU 11.1.2; `patches/upstream/` holds the same two changes
rewritten as a mailing-list series (commit message + `Signed-off-by`) for `git am` / `git send-email`.

### 1. Surfaceless EGL platform (`ui/egl-helpers.c`, `ui/console-gl.c`, `ui/egl-headless.c`)

`egl_rendernode_init()` needs `qemu_drm_rendernode_open()` → `gbm_create_device()`. Hosts without
`/dev/dri/renderD*` fail at init. The fallback (`EGL_PLATFORM_SURFACELESS_MESA`, pbuffer-only configs,
an **ES3** context because the display shaders are `#version 300 es`, and display-context binding
around FBO create/use/destroy) is reached from the `#elif defined(CONFIG_GBM)` branch — see the build
notes below, `CONFIG_GBM` **must** be on or the whole fallback is compiled out.

### 2. Scanout reset on the main loop (`hw/display/virtio-gpu*.c`)

Guest reset arrives as an MMIO write on a TCG vCPU thread, so `virtio_gpu_gl_reset()` used to call
`glDeleteFramebuffers()` with no current EGL context. On Android Mesa that is a hard SIGSEGV
(`fault addr 0xee8`); forcing `GALLIUM_DRIVER=llvmpipe` crashes at the same address, which proves it
is a threading bug and not a driver bug. Fix: `VirtIOGPUClass::reset_scanout`, invoked from
`virtio_gpu_reset_bh()` on the main loop; `virtio_gpu_gl_reset()` only sets `RS_RESET`.

## Build

Everything below is required; the pieces in `scripts/toolchain/` exist because a plain
`./configure && ninja` does not work for this cross build.

**Prerequisites**

- Android NDK r27c, QEMU 11.1.2 source, a Termux-like sysroot with prebuilt `glib`, `pixman`, `slirp`,
  `libepoxy`, `gbm`, `virglrenderer`
- Linux build host (WSL is fine)

**Steps**

```bash
# 1. fake the aarch64-linux-android30-* compiler prefix QEMU's configure expects
NDK=/path/to/android-ndk-r27c SHIM=/root/shim scripts/toolchain/00-shim-ndk.sh

# 2. lay out the stub sysroot + .pc files and rewrite their absolute paths
SYSROOT=/root/sysroot STUBS=/root/stubs scripts/toolchain/05-pc-rewrite.sh

# 3. build the small stubs (each MUST be linked with a soname, otherwise
#    DT_NEEDED records the build path and the binary cannot start)
clang --target=aarch64-linux-android30 -shared -fPIC -Wl,-soname,libeglshim.so \
      -o /root/stubs/libeglshim.so scripts/toolchain/eglshim.c -lEGL
clang --target=aarch64-linux-android30 -shared -fPIC -Wl,-soname,librt.so \
      -o /root/stubs/librt.so ...

# 4. configure. The -include forces our shm_open/shm_unlink declarations,
#    which bionic does not provide.
PKG_CONFIG_PATH=/root/stubs/pc:/root/sysroot/lib/pkgconfig \
../configure --target-list=aarch64-softmmu --cpu=aarch64 \
  --cross-prefix=/root/shim/aarch64-linux-android30- \
  --extra-cflags="-I/root/stubs/include -include /root/stubs/include/shm_compat.h" \
  --enable-opengl --enable-virglrenderer \
  --disable-virtfs --disable-gnutls --disable-nettle --disable-gcrypt \
  --disable-vhost-user --disable-vhost-kernel --disable-vhost-net --disable-vhost-vdpa \
  --disable-docs --disable-tools --disable-guest-agent --disable-plugins \
  --disable-werror

# 5. THE STEP THAT IS EASY TO MISS: meson does not put the GL libs on the
#    link line for this cross build. Inject them into executable links only.
python3 scripts/toolchain/link-inject.py build.ninja /root/stubs

# 6. build
ninja -C build qemu-system-aarch64
```

**sysroot whitelist — this is the part people get wrong.** The Termux sysroot's `include/` must keep
only the libraries whose headers QEMU includes directly, and the `.pc` set must include everything
configure probes:

| Keep in sysroot include/ | Why |
|---|---|
| `glib-2.0` | core |
| `pixman-1` | core |
| `slirp` | `-netdev user` |
| **`gbm`** | **without it there is no `CONFIG_GBM`, and the Android EGL fallback is compiled out entirely** |
| **`epoxy`** | `ui/*.c` include `<epoxy/gl.h>` |
| **`virglrenderer`** | `--enable-virglrenderer` |

All other system headers must come from the NDK bionic sysroot. Do **not** add
`include/standard-headers` to `-I` and do not patch `standard-headers/linux/virtio_*.h`.

## Run

```bash
export LD_LIBRARY_PATH=$HOME/gl-bin            # qemu + libeglshim/librt; rest symlinked to $PREFIX/lib
export MESA_LOADER_DRIVER_OVERRIDE=zink GALLIUM_DRIVER=zink

$HOME/gl-bin/qemu-system-aarch64 \
  -M virt -cpu cortex-a72 -accel tcg,tb-size=1024,thread=multi -m 3072 -smp 4 \
  -device virtio-gpu-gl-pci,id=gpu0,blob=off,edid=on,xres=720,yres=1600 \
  -display egl-headless,gl=es -vnc 127.0.0.1:0
```

The guest ROM needs a virgl-capable gallium driver plus `mapper.minigbm_upstream`, and must select
`ro.hardware.egl=mesa` / `ro.hardware.vulkan=virtio` once 3D is advertised.

## Host prerequisites this recipe depends on

These are load-bearing and easy to overlook:

- **`run-as <app>` or a `shell` uid is how QEMU is started.** The scripts use `run-as com.termux`,
  which requires the Termux build to be debuggable — the **F-Droid build is**, the Play Store build is
  not. Without it you cannot start QEMU from `adb shell` at all.
- **adb is assumed.** `taskset` on the QEMU threads works only because `run-as` gives the same uid;
  `adb shell` alone cannot change another app's affinity.
- Guest images live in `/data/local/tmp` (world-readable, writable by `shell`), not in app-private
  storage.
- No root anywhere. Every file this project touches is under the app's private dir or
  `/data/local/tmp`.

## Tuning that measured well

- **Pin the TCG threads to the big cores.** Android's scheduler otherwise leaves the prime/medium
  clusters at minimum frequency (measured 614 MHz) and places translator threads on the little cores.
  Pinning raised the cluster to 2.4–2.6 GHz. Note: read per-thread placement with
  `sed 's/.*) //' | awk ...` — the `comm` field contains spaces (`CPU 0/TCG`), so naive `awk '{print $39}'`
  is off by one field.
- `-accel tcg,thread=multi` is required; confirm parallelism in `/proc/<pid>/task/*/stat`.
- `-object iothread` was tried and produced `SIGILL` inside a TCG thread. The reason is **not**
  established (a `longjmp` frame is where it surfaced, not why); treat "do not use it here" as an
  empirical result, not an explanation.

## Known issues

1. `ui/console-gl.c`: the Android branch returns `false` for the dma-buf import path and discards
   `glGetError()`'s value to silence the unused warning. Correct for `blob=off`, but crude; upstream
   review would want the error preserved and the guard narrowed.
2. `egl_scanout_disable()`: if `qemu_egl_rn_ctx_enter()` fails (e.g. `qemu_egl_display` is
   `EGL_NO_DISPLAY` after a failed GL init) the function returns early and both framebuffers leak.
   Low probability, still an error path that creates a new error.
3. The context enter/leave added around `egl_scanout_disable()` is unconditional and changes
   `egl-headless` behaviour on Linux/Windows hosts too; expect upstream to require it be conditional.
4. `blob=on` / venus are **not** available on this host. The reason is the Android sandbox's
   permission model — an app uid cannot open `/dev/udmabuf` (SELinux label plus DAC), and Android does
   not permit cross-process dma-buf export from an app — **not** merely that a kernel config is off.
   Enabling `CONFIG_UDMABUF` elsewhere would not by itself make this work.

## Layout

```
patches/                       combined diffs against QEMU 11.1.2
patches/upstream/              the same changes as a mailing-list series (git am / send-email)
scripts/                       launch lines, pinning, guest console driver, smoke test
scripts/toolchain/             everything needed to reproduce the cross build
  00-shim-ndk.sh               generate the aarch64-linux-android30-* prefix
  05-pc-rewrite.sh             rewrite captured .pc files to your paths
  pc/                          the .pc set configure needs (includes gbm/epoxy/virglrenderer)
  include/shm_compat.h         forced in via -include (bionic lacks shm_open)
  eglshim.c                    libeglshim.so: EGL/GL extension entry points via eglGetProcAddress
  link-inject.py               patch build.ninja executable link rules
docs/findings.md               crash analysis, measurements, limits
```

## License

GPL-2.0-or-later. The patches modify QEMU 11.1.2 and are derivative works of it, distributed under the
same license. No QEMU source, no binaries, no ROM images and no third-party APKs are included — only
patches, scripts and documentation. The build references (but does not bundle) virglrenderer, Mesa,
libepoxy and Termux packages, each under its own license.

---

## 中文摘要

在**未 root 的 Android 手机**上，让 QEMU 里的 Android 客机把合成卸载到真实 GPU：

- 客机 SurfaceFlinger 走 `virgl → zink → Turnip → Adreno`，OpenGL ES 3.2
- **合成卸载 + 每帧回读**（`egl-headless` 没有回显通道）。只对光栅化友好，对 fill-rate 密集场景无益
- SurfaceFlinger 进程 CPU 72% → 16–20%，开机 ~10 分钟 → ~4 分钟；但**整机 CPU 收益远小于此**，
  省下的时间大部分转移到 TCG 线程、宿主 GPU 进程和每帧 4.6 MB 回读上
- 关键修复：reset 时在 **TCG vCPU 线程**里调 GL 导致 SIGSEGV，改为在主循环 `reset_bh` 做 scanout 清理
- 构建必读：`CONFIG_GBM` 必须开启（否则 Android EGL 回退整段不编译）、`build.ninja` 必须注入
  `-lepoxy -lGLESv2 -lEGL -leglshim`、bionic 需要 `shm_compat.h`
- 宿主前提：Termux 必须是 **F-Droid（debuggable）版**，否则 `run-as` 起不了 QEMU
