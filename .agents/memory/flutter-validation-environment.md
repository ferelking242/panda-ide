---
name: Flutter validation environment
description: The workspace shell may not include the Flutter/Dart SDK even when the repository is a Flutter project.
---

When validating Flutter changes, first check whether `flutter` or `dart` is available in the active environment; if neither exists, report that static validation could not run rather than installing an unrelated SDK automatically.

**Why:** The Panda IDE workspace had no Flutter/Dart executable available, so code verification was limited to targeted source inspection and `git diff --check`.

**How to apply:** Use the project’s configured Flutter workflow or an explicitly available SDK for analyzer/build checks when one is present.