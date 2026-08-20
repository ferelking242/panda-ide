---
name: Alpine rootfs packaging
description: Packaging rules for the embedded Alpine runtime used by Panda IDE.
---

Panda IDE ships the official Alpine aarch64 minirootfs as a tar.gz and extracts it with a static BusyBox tar binary. Never replace this with a ZIP or runtime chmod/symlink repair pass.

**Why:** ZIP packaging loses symlinks, directory entries and executable permissions; the official tarball also preserves Alpine apk keys and repository metadata so signed package installs work immediately.

**How to apply:** Keep the tarball and libbusybox.so outside Git LFS, gate extraction with a rootfs version marker, validate `/bin/sh`, BusyBox, apk, musl and apk keys, and fail explicitly when any required asset is absent.