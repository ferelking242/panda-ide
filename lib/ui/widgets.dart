/// Central widget library for Panda IDE.
/// Individual components have been extracted to their own files
/// for better architecture (VS Code-style).
///
/// This file re-exports everything for backward compatibility.
library;

// ── Editor components ──
export 'editor/code_editor.dart';
export 'editor/find_panel.dart';
export 'editor/editor_area.dart';
export 'editor/directory_tree.dart';
export 'editor/find_word.dart';

// ── Panels ──
export 'panels/source_control.dart';
export 'panels/api_testing.dart';

// ── Editor sub-components ──
export 'editor/zen_mode.dart';
export 'editor/inlay_hints.dart';
export 'editor/timeline_view.dart';
export 'editor/codelens_provider.dart';
export 'editor/gutter_indicators.dart';
export 'editor/editor_decorations.dart';
export 'editor/tab_groups.dart' hide EditorTabBar;
export 'editor/conditional_breakpoints.dart';
export 'editor/ghost_text_engine.dart';
export 'editor/multi_cursor.dart';
export 'editor/mobile_touch_toolbar.dart';
export 'editor/side_by_side_diff_viewer.dart';
export 'editor/global_search_dialog.dart';
export 'editor/bottom_panel.dart';
export 'editor/editor_tab_bar.dart';
export 'editor/empty_editor.dart';
export 'editor/preview_panes.dart';
export 'editor/diagnostics_panel.dart' hide DiagnosticSeverity;

// ── Navigation pages ──
export 'quick_open.dart';
export 'global_search.dart';
export 'git_panel.dart';
export 'git_history_page.dart';

// ── Extracted widgets ──
export 'widgets/workspace_picker.dart';
export 'widgets/swipe_tab_view.dart';
export 'widgets/mobile_context_menu.dart';

// ── Shared components ──
export 'components/ai_chat.dart';
export 'components/git_graph.dart';
export 'components/gguf_download.dart';
export 'components/flutter_switch.dart';

// ── Editor sub-components (additional) ──
export 'editor/breadcrumbs.dart';
export 'editor/editor_breadcrumbs.dart';
export 'editor/code_folding.dart';
export 'editor/codicon.dart';

// ── Navigation pages (additional) ──
export 'keybindings_manager.dart';
export 'settings_page.dart';

// ── Welcome pages ──
export 'welcome/panda_welcome_page.dart';
export 'welcome/update_page.dart';

// ── Agent UI ──
export 'agent/agent_rooms_page.dart';
export 'agent/agent_diff_viewer.dart';
export 'agent/agent_slash_mentions_overlay.dart';
export 'agent/provider_models.dart';

// ── Agent BEUI compat (Flow UI bridge) ──
export 'agent/agent_widgets.dart';
export 'agent/flow_ui/widgets/flow_chat_view.dart';
export 'agent/flow_ui/widgets/flow_composer.dart';
export 'agent/flow_ui/widgets/flow_message.dart';
export 'agent/flow_ui/widgets/flow_markdown.dart';
export 'agent/flow_ui/widgets/flow_code_block.dart';
export 'agent/flow_ui/widgets/flow_thinking_indicator.dart';
export 'agent/flow_ui/widgets/flow_shimmer_text.dart';
export 'agent/flow_ui/widgets/flow_streaming_text.dart';
export 'agent/flow_ui/theme/flow_theme.dart';
export 'agent/flow_ui/theme/flow_colors.dart';

// ── Browser ──
export 'browser/browser_panel.dart';
export 'browser/settings/browser_settings_page.dart';

// ── Activity bar / Sidebar / Titlebar ──
export 'activitybar/panda_activity_bar.dart';
export 'sidebar/panda_sidebar.dart';
export 'titlebar/panda_title_bar.dart';

// ── Logs ──
export 'logs_ui/logs_explorer_page.dart';

// ── Services (re-exported for availability) ──
export '../services/flutter_sdk_service.dart';
export '../services/package_downloader.dart';
export '../utils/ollama_service.dart';
export '../utils/runtime_config.dart';
export '../utils/subagent_runner.dart';
export '../utils/agent_block.dart';
export '../utils/agent_checkpoint_service.dart';
export '../utils/agent_checkpoint_manager.dart';
export '../utils/agent_approval_rules.dart';
export '../utils/agent_history_service.dart';
export '../utils/agent_export_service.dart';
export '../utils/agent_settings_service.dart';

// ── Extensions (additional) ──
export '../extensions/extension_host_isolate.dart';
export '../extensions/lsp_bridge.dart';
export '../extensions/open_vsx_marketplace.dart';
export '../extensions/ui/extension_host_status_page.dart';
export '../extensions/permission_dialog.dart';

// ── Gateway ──
export '../gateway/panda_remote_gateway.dart';

// ── Indexing ──
export '../indexing/codebase_indexer.dart';
export '../indexing/semantic_workspace_indexer.dart';

// ── Local models (additional) ──
export '../local_models/services/model_notification_service.dart';
export '../local_models/services/model_selector_service.dart';
export '../local_models/ui/advanced_inference_settings_page.dart';
export '../local_models/ui/lru_manager_page.dart';

// ── MCP ──
export '../mcp/mcp_registry.dart';
export '../mcp/mcp_tool_catalog.dart';

// ── Terminal (additional) ──

// ── Web stub ──
