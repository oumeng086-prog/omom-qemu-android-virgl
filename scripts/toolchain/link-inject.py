#!/usr/bin/env python3
"""Inject -lepoxy -lGLESv2 -lEGL -leglshim into QEMU's executable link rules.

meson never puts those on the link line for this cross build, so every
executable link has to be patched after configure. Only rules that link an
executable are touched: matching every "LINK_ARGS" line also matches the
static-library archiver, and injecting -l flags there produces
"file too small to be an archive".
"""
import re, sys, pathlib

LIBS = ["-lepoxy", "-lGLESv2", "-lEGL", "-leglshim"]
path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "build.ninja")
libdir = sys.argv[2] if len(sys.argv) > 2 else ""

text = path.read_text()
out, patched, skipped = [], 0, 0
for line in text.splitlines(keepends=True):
    if "LINK_ARGS" in line and " -pie " in line and "-leglshim" not in line:
        extra = " ".join((f"-L{libdir}" if libdir else "") and [f"-L{libdir}"] + LIBS or LIBS)
        line = line.rstrip("\n") + " " + extra + "\n"
        patched += 1
    elif "LINK_ARGS" in line:
        skipped += 1
    out.append(line)

path.write_text("".join(out))
print(f"link-inject: patched {patched} executable link rules, left {skipped} other LINK_ARGS untouched")
if patched == 0:
    sys.exit("link-inject: nothing patched - refusing to continue silently")
