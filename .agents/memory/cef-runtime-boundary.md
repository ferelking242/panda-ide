---
name: CEF runtime boundary
description: Panda IDE must treat CEF as an externally supplied, validated Linux runtime rather than pretending a downloaded folder is usable.
---

CEF must be marked ready only after a manifest, version, required-file list, and every required file have been validated. Do not add a fake download URL or silently fall back to an unverified runtime.

**Why:** The upstream Panda IDE is Android-first and the current workspace has no Linux CEF host or verified CEF artifact. A false-ready state would make the Browser UI look healthy while native rendering cannot start.

**How to apply:** Keep runtime detection separate from Browser UI; add the native Linux host and signed runtime distribution before enabling installation, launch, GPU, or DevTools actions.