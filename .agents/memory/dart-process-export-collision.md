---
name: Dart Process export collision
description: Prevent legacy Git compatibility facades from shadowing dart:io Process across shared imports.
---

Legacy Git helper modules contain compatibility facades named `Process`. Re-exporting that name from a shared utility barrel can shadow `dart:io Process` in unrelated files, causing incorrect types, missing `stdout`/`kill`, and invalid `Process.start` parameters.

**Why:** The collision only appeared in CI's Flutter 3.47 compilation because many modules import both the barrel and `dart:io`; local validation was unavailable in this workspace.

**How to apply:** Hide compatibility facade names from barrel exports and keep native process callers importing `dart:io` directly. Preserve the Git helper functions in the barrel.