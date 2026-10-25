#!/bin/bash
set -e
mkdir -p /root/apkdisk
cp "${APK_SRC:-./app.apk}" /root/apkdisk/
ls -lh /root/apkdisk/

rm -f /root/apkdisk.img
dd if=/dev/zero of=/root/apkdisk.img bs=1M count=700 status=none
mke2fs -q -t ext4 -d /root/apkdisk /root/apkdisk.img
echo "--- 校验内容 ---"
debugfs -R "ls -l /" /root/apkdisk.img 2>/dev/null | head -6
ls -lh /root/apkdisk.img
cp /root/apkdisk.img /mnt/d/qemu-android/apk/apkdisk.img
echo DONE
