---
name: Panda Agent stream lifecycle
description: Rules for keeping AgentRunner and its UI state consistent when setup or provider resolution fails before streaming begins.
---

Panda Agent must treat all pre-stream setup as part of the request lifecycle: tool-schema construction, provider resolution, preferences, and workspace lookup can fail before any network call. The runner must create and close its stream inside the error boundary, and the UI must surface setup failures and stop its generating state.

**Why:** A setup exception before the stream listener was attached left the controller open with no emitted log or terminal event, so the mobile UI stayed indefinitely on “Génération…”.

**How to apply:** Keep request setup inside `try/catch/finally`; add bounded timeouts around provider/preference resolution; invalidate late callbacks after cancellation; never represent cancellation as a successful completion.