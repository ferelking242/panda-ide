---
name: Node terminal policy
description: The project’s durable rule for obtaining and launching Node.js.
---

Node.js is owned by the active Panda terminal environment. The app must not bundle, download, copy, extract, or fall back to an Android-host Node binary; `panda update` is the only installation path, and app processes must use the terminal/PRoot environment.

**Why:** The user explicitly rejected embedded runtimes and fallback paths because they bypass the terminal environment that already installs the required toolchain.

**How to apply:** When adding or changing Extension Host, Copilot, Vite, or Node-based LSP process launching, route it through the terminal launcher and fail with an explicit `panda update` message when Node is unavailable.