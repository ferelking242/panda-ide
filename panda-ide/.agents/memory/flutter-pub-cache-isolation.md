---
name: Flutter Pub cache isolation
description: Why Panda IDE assigns each Flutter workspace its own Pub cache inside PRoot.
---

Panda IDE must not share one Pub cache between Flutter workspaces. The Android/PRoot Git checkout path can otherwise retain state from another project and report a misleading missing pubspec, especially when Git dependencies use different subpaths or refs.

**Why:** Watchtower resolved cleanly in CI with a fresh cache but failed locally inside Panda IDE, where the embedded Flutter session reused a shared cache and mount environment.

**How to apply:** Keep `PUB_CACHE` project-scoped and deterministic in every interactive terminal, agent shell, and Flutter device-run path. Keep the workspace mounted at `/root/workspace`, use the same project key for all three paths, and preserve the real Pub exit code when displaying diagnostics.