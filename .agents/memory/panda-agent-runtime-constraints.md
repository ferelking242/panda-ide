---
name: Panda Agent runtime constraints
description: Non-obvious runtime rules for tool approval, registry lifetimes, and agent secret lookup.
---

Tool definitions must be rebuilt for each AgentRunner turn because their closures capture the current Flutter context, workspace, approval callback, and approval mode. The agent settings service is the canonical vault; tools must not read a separate legacy preference key.

Command tools that capture stdout and stderr must use normal process I/O rather than inherited stdio, and they must resolve the currently selected terminal rootfs before launching PRoot. The interactive terminal and Agent cannot silently use different distro paths.

**Why:** Inherited stdio prevents reliable output capture, while a stale Debian path makes Agent commands fail when the terminal is running another selected rootfs.

**How to apply:** Keep Agent command execution aligned with the terminal's active runtime and capture both output streams concurrently, including cleanup on timeout or cancellation.

**Why:** Reusing the registry silently applies the first turn's approval behavior to later turns, and the old secret preference key made configured agent secrets appear missing.

**How to apply:** When changing AgentRunner or AgenticTools, re-register native tools per run and read/write secrets through AgentSettingsService, while keeping environment and workspace `.env` lookup as additional sources.