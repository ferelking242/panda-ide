---
name: Flutter validation
description: Environment constraint affecting local verification of the Flutter application.
---

The repository depends on Flutter, but the current Replit workspace exposes no Flutter SDK or Flutter module. Dart tooling alone is not sufficient to run the app or verify Flutter package resolution.

**Why:** The new Panda Agent workspace-tools views were checked statically, but `flutter analyze` and a device build could not be run here.

**How to apply:** When making future Flutter UI changes, use an environment with Flutter installed for the final analyze/build and runtime verification.