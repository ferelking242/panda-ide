/// Central widget library for Panda IDE.
/// Individual components have been extracted to their own files
/// for better architecture (VS Code-style).
///
/// This file re-exports everything for backward compatibility.

// ── Editor components ──
export 'editor/code_editor.dart';
export 'editor/find_panel.dart';
export 'editor/editor_area.dart';
export 'editor/directory_tree.dart';
export 'editor/find_word.dart';

// ── Panels ──
export 'panels/source_control.dart';
export 'panels/api_testing.dart';

// ── Shared components ──
export 'components/ai_chat.dart';
export 'components/git_graph.dart';
export 'components/gguf_download.dart';
export 'components/flutter_switch.dart';
