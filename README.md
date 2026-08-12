<p align="center">
  <img src="assets/icons/about-512.png" width="96" alt="Panda IDE logo"/>
</p>

<h1 align="center">Panda IDE</h1>
<p align="center">A powerful, mobile-first IDE for Android — built with Flutter.</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter" />
  <img src="https://img.shields.io/badge/Android-5.0%2B-green?logo=android" />
  <img src="https://img.shields.io/badge/License-MIT-lightgrey" />
</p>

---

## Features

- **Code editor** powered by [code_forge](https://github.com/heckmon/code_forge) with syntax highlighting for 50+ languages
- **Integrated terminal** — built-in PTY, Termux support, SSH remote connections
- **Git & GitHub** — clone, commit, push, pull, branch management
- **AI assistance** — local LLaMA model + GitHub Copilot integration + Panda Agent
- **Marketplace** — VSCode extensions (Open VSX), runtimes (Node.js, Python, Java, Go, Flutter SDK, …)
- **File manager** — full filesystem access with project workspace
- **WebView** — in-app browser for preview and documentation
- **VSCode-inspired UI** — activity bar, tabbed workspace, status bar, command palette

## Getting Started

```bash
git clone https://github.com/ferelking242/panda-ide
cd panda-ide
flutter pub get
flutter run
```

> Requires Flutter ≥ 3.12 and Android SDK 21+.

## Architecture

```
lib/
├── bloc/           # BLoC state management
├── extensions/     # VSCode extension host (IPC bridge, Open VSX marketplace)
│   ├── models/     # Extension manifest, IPC messages, marketplace models
│   ├── ui/         # Marketplace page, extensions panel, webview
│   └── …
├── gateway/        # Gateway AI webview bridge
├── services/       # Flutter SDK service, Shizuku
├── terminal/       # PTY terminal (native + stub)
├── ui/             # All screens (home, editor, settings, downloads, …)
└── utils/          # Constants, themes, functions, package catalog
assets/
├── extension_host/ # Node.js IPC bridge + vscode.* API shim
├── fonts/          # Iconsax Broken icon font
└── icons/
```

## VSCode Extension Host

Panda IDE includes a full VSCode extension host that allows running real `.vsix` extensions on Android:

| Phase | Status |
|-------|--------|
| Foundation (models, IPC, registry) | ✅ |
| vscode.window API | ✅ |
| vscode.workspace API | ✅ |
| vscode.languages API | ✅ |
| vscode.commands | ✅ |
| vscode.extensions / env | ✅ |
| Open VSX Marketplace UI | ✅ |
| WebView panels | ✅ |
| SCM / Tasks / Debug | ✅ |
| CI/CD (Jest tests) | ✅ |

Extensions are installed from [Open VSX Registry](https://open-vsx.org) (Microsoft Marketplace is legally restricted to VS Code).

## Runtimes

Install language runtimes directly from the Marketplace → Runtimes tab:

| Runtime | Version |
|---------|---------|
| Node.js | 22.x LTS |
| Python  | 3.13 |
| Java (OpenJDK) | 21 LTS |
| Kotlin  | 2.x |
| Clang/LLVM | 21 |
| Dart    | 3.x |
| Go      | 1.22 |
| Rust    | stable |
| Ruby    | 3.3 |
| Lua     | 5.4 |
| Flutter SDK | 3.x stable |

## Icon set

Panda IDE uses the **Iconsax Broken** icon family. The `.ttf` files are bundled in `assets/fonts/`.

## License

[MIT](LICENCE)
