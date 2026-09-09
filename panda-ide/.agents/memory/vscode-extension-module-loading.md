---
name: VS Code extension module loading
description: Node module resolution behavior needed by Panda IDE's VS Code extension host shim.
---

The extension host must intercept Node's `Module._load` for the exact request
`vscode`; adding only a `require.cache['vscode']` entry does not resolve a bare
`require('vscode')` from an extension or one of its nested modules.

**Why:** Node resolves a bare module request before consulting a cache key that
is not a resolved filename, so extensions otherwise fail during startup before
their commands and WebView providers can register.

**How to apply:** Keep the interception close to host bootstrap, before loading
the extension entry point, and retain the cache entry only as a compatibility
aid for code that inspects `require.cache`.