---
name: Terminal runtime behavior
description: Durable constraints for command completion markers and device validation.
---

Command-completion OSC markers must be installed in each distro's generated login profile rather than only passed as a PTY environment variable, because the login shell can overwrite `PROMPT_COMMAND` while sourcing its profile.

**Why:** The terminal uses login Bash sessions, and environment-only prompt hooks are silently replaced by the distro profile.

**How to apply:** When adding terminal lifecycle telemetry, update the generated profile for every supported rootfs and bump its profile version so existing installations refresh.

The workspace does not provide Flutter/Dart or Android/Java toolchains, so terminal layout, hardware/Gboard shortcuts, notification permissions, and foreground-session persistence require device-level validation.

**Why:** Static checks and diff review cannot exercise Android keyboard, PTY rendering, or background lifecycle behavior.

**How to apply:** Treat real-device validation as a release gate for terminal interaction changes.