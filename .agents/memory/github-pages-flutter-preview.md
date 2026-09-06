---
name: GitHub Pages Flutter preview
description: Flutter Pages screenshots may capture the splash frame before the routed UI finishes loading.
---

Treat a successful GitHub Pages workflow and HTTP 200 as the deployment check; an external screenshot can still show only the splash frame because capture timing does not wait for Flutter route initialization.

**Why:** The published Panda IDE page can be healthy while automated visual capture stops during the initial splash screen.

**How to apply:** Use the workflow SHA, Pages response headers, and asset availability to verify the release; do not infer that UI changes are absent from a splash-only screenshot.