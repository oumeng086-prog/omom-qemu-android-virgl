#!/system/bin/sh
# GL 版 + APK 投递盘 (vdc)
PREFIX=/data/data/com.termux/files/usr
H=/data/data/com.termux/files/home
B=$H/gl-bin
export HOME=$H
export LD_LIBRARY_PATH=$B
export PATH=$PREFIX/bin:$PATH
export MESA_LOADER_DRIVER_OVERRIDE=zink
export GALLIUM_DRIVER=zink

T=/data/local/tmp
SYS=$T/vda24u.qcow2
DAT=$T/vdb24.qcow2
APK=$T/apkdisk.img
VARS=$T/QEMU_VARS.img
CODE=$PREFIX/share/qemu/edk2-aarch64-code.fd
SER=$H/serial_apk.log
HVC=$H/hvc0_apk.log
OUT=$H/qemu_apk.log
rm -f $SER $HVC $OUT

nohup setsid $B/qemu-system-aarch64 \
  -name android24apk \
  -L $PREFIX/share/qemu \
  -machine virt -smbios type=0,vendor=Qualcomm,version=1.0,date=06/20/2024 \
  -smbios type=1,manufacturer=Xiaomi,product=houji,version=OS2.0.1.0,serial=SN5D2A1B7C,family=SM8650 \
  -cpu cortex-a72 -accel tcg,tb-size=1024,thread=multi \
  -m 3072 -smp 4 \
  -drive if=pflash,unit=0,file=$CODE,file.locking=off,format=raw,readonly=on \
  -drive if=pflash,unit=1,file=$VARS,format=raw \
  -device virtio-blk-pci,drive=vda,bootindex=0 \
  -device virtio-blk-pci,drive=vdb,bootindex=1 \
  -device virtio-blk-pci,drive=vdc \
  -drive file=$SYS,if=none,id=vda,discard=unmap,detect-zeroes=unmap,cache=writeback \
  -drive file=$DAT,if=none,id=vdb,discard=unmap,detect-zeroes=unmap,cache=writeback \
  -drive file=$APK,if=none,id=vdc,format=raw,readonly=on \
  -device virtio-net-pci,netdev=net0,mac=34:ce:00:5a:1b:7c \
  -netdev user,id=net0,dns=223.5.5.5,ipv6=off,hostfwd=tcp:127.0.0.1:5556-:5555,hostfwd=tcp:127.0.0.1:5554-:5554 \
  -device virtio-rng-pci \
  -device virtio-gpu-gl-pci,id=gpu0,blob=off,edid=on,xres=720,yres=1600 \
  -device usb-ehci,id=usb-bus \
  -device virtio-multitouch-pci,display=gpu0,head=0 \
  -device usb-kbd,bus=usb-bus.0 \
  -device virtio-serial-pci,id=vser0 \
  -device virtconsole,chardev=hvc0port \
  -chardev socket,id=hvc0port,host=127.0.0.1,port=5558,server=on,wait=off,logfile=$HVC,logappend=on \
  -chardev socket,id=ser0,host=127.0.0.1,port=5557,server=on,wait=off,logfile=$SER,logappend=on \
  -serial chardev:ser0 \
  -display egl-headless,gl=es \
  -vnc 127.0.0.1:0 \
  -qmp tcp:127.0.0.1:4444,server=on,wait=off \
  > $OUT 2>&1 < /dev/null &

echo "started pid=$! uid=$(id -u) (+vdc apkdisk, ipv6=off)"
sleep 4
head -4 $OUT 2>/dev/null
