---
name: Panda Agent provider navigation
description: Durable navigation and configuration rule for the embedded Panda Agent provider settings.
---

Panda Agent provider configuration should use one embedded provider-only settings page rather than a second inline or legacy settings shell. Agent model resolution must prefer the saved `agent_` profile and report a missing API key explicitly before attempting a request.

**Why:** Duplicated provider forms drifted apart, and older/non-Agent selections caused the panel to report a provider that the Agent could not actually resolve.

**How to apply:** Route every “add provider” and empty-provider action to the embedded Providers page; keep model/profile selection and request-time validation tolerant of legacy key names.