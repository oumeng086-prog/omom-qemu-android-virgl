L=/data/data/com.termux/files/home/serial_gl.log
H=/data/data/com.termux/files/home/hvc0_gl.log
echo "=== serial 大小 / 最后一条 ==="
wc -c $L 2>/dev/null
tail -c 400 $L 2>/dev/null
echo
echo "=== 关键进程痕迹 ==="
grep -a -o -E "SurfaceFlinger|surfaceflinger|OpenGLRenderer|adbd|zygote|system_server|gralloc|minigbm|virgl|virglrenderer" $L 2>/dev/null | sort | uniq -c | sort -rn | head -12
echo
echo "=== 错误/致命 ==="
grep -a -i -E "FATAL|panic|watchdog|segfault|BUG:|call trace" $L 2>/dev/null | tail -6
echo
echo "=== hvc0 尾部 ==="
tail -c 300 $H 2>/dev/null
