---
name: iOS Llama pod build
description: The generated CocoaPods spec for llama_flutter_android needs explicit source and build-setting patches for iOS.
---

The iOS release workflow must patch the generated Llama pod before every `pod install`: keep ARC disabled for the Llama target and include the model, backend, metadata, and ARM CPU source units that the upstream podspec omits.

**Why:** Flutter regenerates and reinstalls CocoaPods during `flutter build ios`, so edits made only to generated xcconfig files are lost; the incomplete podspec otherwise produces compile or linker failures.

**How to apply:** Patch `ios/Podfile` through `post_install` and patch the generated `llama_flutter_android.podspec` before `pod install` in every iOS build/release workflow. Keep the source checks literal and fail if the podspec is not found.