#!/bin/bash
# Create the aarch64-linux-android30-* "cross compiler" prefix that QEMU's
# configure expects. NDK r27c ships clang, not this GCC-style prefix, so we
# generate thin wrappers. Requires NDK and SHIM to be set.
#   NDK=/path/to/android-ndk-r27c SHIM=/root/shim ./00-shim-ndk.sh
set -e
: "${NDK:?set NDK to the android-ndk root}"
: "${SHIM:=/root/shim}"
BIN=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin
API=${API:-30}
ARCH=aarch64-linux-android$API
mkdir -p "$SHIM"

for t in ar as nm objcopy objdump ranlib readelf strip; do
    ln -sf "$BIN/llvm-$t" "$SHIM/aarch64-linux-android$API-$t"
done

# clang needs the target triple; the NDK driver form is <triple><api>-clang
cat > "$SHIM/aarch64-linux-android$API-gcc" <<WRAP
#!/bin/sh
exec "$BIN/$ARCH-clang" "\$@"
WRAP
cat > "$SHIM/aarch64-linux-android$API-g++" <<WRAP
#!/bin/sh
exec "$BIN/$ARCH-clang++" "\$@"
WRAP
chmod +x "$SHIM/aarch64-linux-android$API-gcc" "$SHIM/aarch64-linux-android$API-g++"
echo "shim ready in $SHIM"
