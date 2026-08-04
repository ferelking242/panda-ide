---
name: Android first-launch storage
description: Storage-root ordering required to keep Android startup usable before MANAGE_EXTERNAL_STORAGE is granted.
---

Panda IDE must start with app-private storage roots and probe public storage only when Android permits it. The permission screen can migrate the private roots to the public Panda IDE directory after permission is granted.

**Why:** Android rejects writes to `/storage/emulated/0` during the first launch before the permission flow, so creating `.current_files.json` there aborts startup.

**How to apply:** Keep root selection before any startup filesystem setup, make all setup helpers use the active roots, and never make public-storage failure fatal.