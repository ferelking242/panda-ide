/// Panda Agent V3 — Architecture et composants.
///
/// Import this file to access all agent V3 components:
/// ```dart
/// import 'package:panda/agent/agent_v3.dart';
/// ```

// Events
export 'events/agent_event.dart';
export 'events/agent_event_bus.dart';
export 'events/event_activity_bridge.dart';
// export 'events/event_ui_bridge.dart'; // Not exported — defines AgentPhase which conflicts with agent_runner.dart

// Tools
export 'tools/tool_definition.dart';
export 'tools/tool_registry.dart';
export 'tools/tool_executor.dart';
export 'tools/native_tool_bridge.dart';

// Modes
export 'modes/mode_registry.dart';
export 'modes/plan_viewer.dart';

// Agents
export 'agents/agent_definition.dart';
export 'agents/agent_registry.dart';
export 'agents/agent_status_widget.dart';
export 'agents/subagent_viewer.dart';

// Subagents
export 'subagents/subagent_manager.dart';

// Context
export 'context/context_manager.dart';
export 'context/context_budget.dart';
export 'context/context_pruner.dart';
export 'context/history_compactor.dart';
export 'context/project_tree.dart';
export 'context/relevant_files.dart';
export 'context/code_map.dart';

// Verification
export 'verification/verification_pipeline.dart';
export 'verification/verification_viewer.dart';

// Environment
export 'environment/environment_manager.dart';
export 'environment/executable_detector.dart';

// MCP
export 'mcp/mcp_tool_bridge.dart';

// Sessions
export 'sessions/session_manager.dart';

// Runtime
export 'runtime/retry_manager.dart';
export 'runtime/error_classifier.dart';
