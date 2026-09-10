---
name: Terminal shortcuts
description: Gboard and hardware terminal shortcuts must preserve shell control bytes while supporting Panda's visible selection action.
---

The terminal accessory CTRL modifier must send POSIX control bytes through the PTY for both Gboard text input and physical key events. Ctrl+C always sends 0x03, even when xterm has a selection; Ctrl+A may also select the visible buffer, but must still send 0x01 to readline.

**Why:** Copying Ctrl+C when a selection was present prevented shell interrupts, leaving Bash continuation prompts (`>`) stuck. Tapping the accessory modifier could also move focus away from the terminal input path.

**How to apply:** Keep copy/paste as explicit actions or Shift-modified shortcuts, request terminal focus when an accessory modifier is toggled, and test both Gboard and hardware-key paths on Android.