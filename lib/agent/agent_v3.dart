/// Panda Agent V3 — Architecture et composants.
///
/// Import this file to access all agent V3 components:
/// ```dart
/// import 'package:panda/agent/agent_v3.dart';
/// ```

// Events
export 'events/agent_event.dart';
export 'events/agent_event_bus.dart';
export 'events/event_ui_bridge.dart';

// Tools
export 'tools/tool_definition.dart';
export 'tools/tool_registry.dart';
export 'tools/tool_executor.dart';
export 'tools/native_tool_bridge.dart';

// Modes
export 'modes/mode_registry.dart';

// Agents
export 'agents/agent_definition.dart';
export 'agents/agent_registry.dart';

// Subagents

// Context
export 'context/context_manager.dart';
export 'context/context_budget.dart';
export 'context/context_pruner.dart';
export 'context/project_tree.dart';
export 'context/relevant_files.dart';

// Verification

// Environment
export 'environment/environment_manager.dart';
export 'environment/executable_detector.dart';

// MCP

// Sessions
export 'sessions/session_manager.dart';

// Runtime
export 'runtime/retry_manager.dart';
export 'runtime/error_classifier.dart';
