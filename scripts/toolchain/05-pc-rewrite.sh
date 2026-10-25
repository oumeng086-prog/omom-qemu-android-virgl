#!/bin/bash
# The .pc files in ./pc were captured from the build machine. They carry
# absolute paths for the Termux sysroot and the local stub dir; rewrite both
# to the caller's layout before running configure.
#   SYSROOT=/path/to/sysroot STUBS=/path/to/stubs ./05-pc-rewrite.sh
set -e
: "${SYSROOT:?set SYSROOT}"
: "${STUBS:?set STUBS}"
cd "$(dirname "$0")/pc"
for f in *.pc; do
    sed -i \
        -e "s|/root/sysroot|$SYSROOT|g" \
        -e "s|/root/stubs|$STUBS|g" \
        "$f"
done
echo "rewrote $(ls *.pc | wc -l) .pc files for SYSROOT=$SYSROOT STUBS=$STUBS"
