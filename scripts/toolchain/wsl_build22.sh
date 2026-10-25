#!/bin/bash
set -e
NDK=/root/ndk/android-ndk-r27c/toolchains/llvm/prebuilt/linux-x86_64
SR=/root/sysroot
STUB=/root/stubs
QEMU=/root/work/qemu-11.1.2
P=aarch64-linux-android30-
LOG=/root/build.log
: > $LOG

echo "=== 1. 精简 .pc 白名单 ===" | tee -a $LOG
mkdir -p /root/pc_all && mv $STUB/pc/*.pc /root/pc_all/ 2>/dev/null || true
KEEP="glib-2.0 gmodule-no-export-2.0 gmodule-2.0 gobject-2.0 gio-2.0 pixman-1 slirp zlib epoxy gbm virglrenderer libpcre2-8 libffi libintl libiconv"
for k in $KEEP; do
  [ -f /root/pc_all/$k.pc ] && cp /root/pc_all/$k.pc $STUB/pc/ || true
done
ls $STUB/pc | tee -a $LOG

echo "=== 2. configure ===" | tee -a $LOG
cd $QEMU
rm -rf build
export PATH=/root/shim:$NDK/bin:$PATH
export PKG_CONFIG_PATH=$STUB/pc
export PKG_CONFIG_LIBDIR=$STUB/pc
./configure \
  --target-list=aarch64-softmmu --cpu=aarch64 --cross-prefix=$P \
  --enable-opengl --enable-virglrenderer --audio-drv-list= \
  --disable-virtfs --disable-gnutls --disable-nettle --disable-gcrypt \
  --disable-vhost-user --disable-vhost-kernel --disable-vhost-net \
  --disable-vhost-vdpa --disable-vhost-crypto --disable-vhost-user-blk-server \
  --disable-docs --disable-tools --disable-guest-agent --disable-plugins \
  --disable-werror --disable-debug-info \
  --extra-cflags="-I$STUB/include -include $STUB/include/shm_compat.h" \
  --extra-ldflags="-L$SR/lib -L$SR/opt/generic/lib -L$STUB -Wl,-rpath-link,$SR/lib -lrt" \
  >> $LOG 2>&1 || { echo CONFIGURE_FAILED; tail -10 $LOG; exit 1; }
echo CONFIGURE_OK | tee -a $LOG

echo "=== 3. build ===" | tee -a $LOG
cd $QEMU/build
nice -n 5 ninja -j18 qemu-system-aarch64 > /root/make.log 2>&1 || true
grep 'error:' /root/make.log | sort -u | head -5 | tee -a $LOG || true
tail -2 /root/make.log | tee -a $LOG
ls -l qemu-system-aarch64 2>&1 | tail -1 | tee -a $LOG
echo BUILD_DONE | tee -a $LOG
