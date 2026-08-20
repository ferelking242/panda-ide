---
name: Android first-launch storage
description: Storage-root ordering required to keep Android startup usable before MANAGE_EXTERNAL_STORAGE is granted.
---

Panda IDE must keep app-private storage as the active root for the entire app lifetime and probe shared storage only for explicit import/export. Public projects are copied into private storage without deleting the originals.

**Why:** Android shared storage is FUSE-backed and does not reliably preserve the POSIX permissions, links and executable bits required by an IDE terminal, even when a write probe succeeds.

**How to apply:** Initialize private roots before startup filesystem setup; MANAGE_EXTERNAL_STORAGE must never block the permission screen or terminal; treat shared storage as an import/export source and destination only.