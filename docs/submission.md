# Submission record

What was actually sent, where, and what to do when review feedback arrives.

## Sent

| field | value |
|---|---|
| channel | `qemu-devel@nongnu.org` (the only channel QEMU accepts patches on) |
| date | 2026-10-25 18:34 UTC / 2026-10-26 02:34 +0800 |
| subject | `[PATCH] virtio-gpu: run scanout reset cleanup on the main loop thread` |
| Message-ID | `<20261025183403.460-1-q15817976513@163.com>` |
| patch | [`patches/upstream/0002-virtio-gpu-reset-scanout-thread.patch`](../patches/upstream/0002-virtio-gpu-reset-scanout-thread.patch) |
| base | `master` @ `d731492` (hunk 1 applies with a 110-line offset) |
| public branch | https://gitlab.com/oumeng086-prog/qemu/-/tree/virtio-gpu-reset-scanout-thread |

Size: 3 files, 5 hunks, +18 −1 (`hw/display/virtio-gpu-gl.c`, `hw/display/virtio-gpu.c`,
`include/hw/virtio/virtio-gpu.h`).

## What was *not* submitted, and why

| attempt | outcome |
|---|---|
| GitLab merge request | **impossible** — `qemu-project/qemu` has MRs disabled; `/-/merge_requests/new` returns 404 and the project description states "Pull Requests are ignored" |
| GitLab issue | not filed. The issue page exists but its body editor is a ProseMirror contenteditable that does not accept programmatic input; nothing was submitted |
| the second patch (Android surfaceless EGL) | **not sent**: it does not apply to `master` — upstream changed `ui/egl-helpers.c` and the shape of `egl_scanout_disable()`, so it needs a real rebase first |

## Tracking

- patchwork (should appear after moderation):
  https://patchwork.ozlabs.org/project/qemu-devel/list/?submitter=q15817976513%40163.com
- a non-subscriber post is held for moderator approval; silence for a few hours is normal
- subscribing to `qemu-devel` removes that queue for follow-ups: send `subscribe qemu-devel` to
  `qemu-devel-request@nongnu.org`

## When review arrives

1. keep the same subject and bump to `[PATCH v2]`; add a changelog section under the `---` line
2. `git rebase` onto current `master` before resending, not onto the base used here
3. `scripts/checkpatch.pl` lives in the QEMU tree — run it before sending, it catches most of what
   reviewers would otherwise point out
4. answer inline on the list, do not open a new thread

## Known weak points a reviewer will likely raise

- a new `reset_scanout` class method may be more than needed; reusing the existing reset flow was
  suggested as an alternative design
- if the virtio-gpu reset rework lands first, this patch may need to be rebased on top of it
- the commit message asserts a threading bug from an Android-only crash; make clear that calling GL
  from a non-GL thread is invalid everywhere and the Android crash is just the loudest symptom
