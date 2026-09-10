---
name: Local GGUF GPU fallback
description: Android behavior to account for when loading downloaded local GGUF models.
---

The native GPU probe used by the local Llama runtime can return a null payload on some Android devices or builds. Local GGUF loading must not depend on implicit GPU detection: use CPU-safe loading by default and honor GPU layers only when explicitly configured.

**Why:** Panda Agent previously crashed with “Null check operator used on a null value” after a model was downloaded successfully, before generation began.

**How to apply:** Keep model activation and chat loading independent of `detectGpu()` success. Treat GPU detection as optional telemetry or an explicit optimization, never as a required prerequisite for using a downloaded model.