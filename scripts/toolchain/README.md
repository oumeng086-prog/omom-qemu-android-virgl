# toolchain

Two kinds of files live here.

**Reusable recipes (parameterized, use these):**

| file | purpose |
|---|---|
| `00-shim-ndk.sh` | create the `aarch64-linux-android30-*` prefix configure expects (NDK ships clang only) |
| `05-pc-rewrite.sh` | rewrite the captured `.pc` files to your own `SYSROOT` / `STUBS` |
| `pc/` | the `.pc` set configure must find — includes **gbm**, **epoxy**, **virglrenderer** |
| `include/shm_compat.h` | declarations forced in with `-include`; bionic has no `shm_open` |
| `eglshim.c` | `libeglshim.so` — EGL/GL extension entry points resolved through `eglGetProcAddress` |
| `link-inject.py` | inject `-lepoxy -lGLESv2 -lEGL -leglshim` into `build.ninja` executable links |

**Captured run logs (`wsl_build*.sh`, `wsl_mkpatch.sh`, `wsl_apkdisk.sh`):**

These are verbatim records of what was actually executed while bringing the build up. They contain
hard-coded paths from that machine (`/root/work/qemu-11.1.2`, `/root/sysroot`, `/root/stubs`) and are
kept for the *sequence and flags*, not as a runnable script. Follow the recipe in the top-level README
instead.
