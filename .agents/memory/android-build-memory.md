---
name: Android build memory
description: Durable CI memory guidance for Panda IDE Android builds.
---

The GitHub Actions Android build should retain the 8 GB Gradle heap configuration that has been proven to complete reliably.

**Why:** On September 9, 2026, reducing Gradle from 8 GB to 2 GB caused the APK step to remain in progress far beyond its normal ~10-minute duration. Restoring 8 GB produced a successful APK build in about 10 minutes.

**How to apply:** Treat Gradle heap reductions as a regression risk for this repository; if memory pressure must be addressed, measure a complete GitHub Actions APK build before keeping the change.