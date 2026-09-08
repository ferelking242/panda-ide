---
name: Panda Agent runtime constraints
description: Non-obvious runtime rules for tool approval, registry lifetimes, and agent secret lookup.
---

Tool definitions must be rebuilt for each AgentRunner turn because their closures capture the current Flutter context, workspace, approval callback, and approval mode. The agent settings service is the canonical vault; tools must not read a separate legacy preference key.

**Why:** Reusing the registry silently applies the first turn's approval behavior to later turns, and the old secret preference key made configured agent secrets appear missing.

**How to apply:** When changing AgentRunner or AgenticTools, re-register native tools per run and read/write secrets through AgentSettingsService, while keeping environment and workspace `.env` lookup as additional sources.