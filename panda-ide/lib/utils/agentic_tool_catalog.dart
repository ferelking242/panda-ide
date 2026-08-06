class AgenticToolSpec {
  final String name;
  final String label;
  final String description;
  final bool requiresWriteAccess;

  const AgenticToolSpec({
    required this.name,
    required this.label,
    required this.description,
    required this.requiresWriteAccess,
  });
}

const List<AgenticToolSpec> agenticToolSpecs = [
  // ── Lecture de contexte ─────────────────────────────────────────────────
  AgenticToolSpec(
    name: 'activeEditorFile',
    label: 'Active editor file',
    description: 'Gets the path of the currently active editor file.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'getLspDiagnostics',
    label: 'LSP diagnostics',
    description: 'Gets diagnostics from open LSP-backed editors.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'getFileInfo',
    label: 'File info',
    description: 'Gets metadata about a file or directory.',
    requiresWriteAccess: false,
  ),

  // ── Lecture de fichiers ─────────────────────────────────────────────────
  AgenticToolSpec(
    name: 'readFile',
    label: 'Read file',
    description: 'Reads the contents of a file.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'readFilesBatch',
    label: 'Read files batch',
    description: 'Reads multiple files in one call.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'listFiles',
    label: 'List files',
    description: 'Lists files in a directory.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'globSearchFiles',
    label: 'Glob search files',
    description: 'Finds files by glob pattern.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'grepInFiles',
    label: 'Grep in files',
    description: 'Searches files and returns matching lines with context.',
    requiresWriteAccess: false,
  ),

  // ── Écriture de fichiers ────────────────────────────────────────────────
  AgenticToolSpec(
    name: 'editFile',
    label: 'Edit file',
    description: 'Applies a targeted diff/patch to a file (preferred for edits).',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'writeFile',
    label: 'Write file',
    description: 'Writes content to a file, creating it if it doesn\'t exist.',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'replaceAllInFile',
    label: 'Replace in file',
    description: 'Replaces matching text in a file with pending diff tracking.',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'createDirectory',
    label: 'Create directory',
    description: 'Creates a new directory at the given path.',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'rename',
    label: 'Rename path',
    description: 'Renames or moves a file or directory path.',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'deleteFile',
    label: 'Delete file',
    description: 'Deletes a file from the workspace.',
    requiresWriteAccess: true,
  ),

  // ── Git ─────────────────────────────────────────────────────────────────
  AgenticToolSpec(
    name: 'gitStatus',
    label: 'Git status',
    description: 'Returns git status details including branch, ahead/behind, and changed files.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'gitDiff',
    label: 'Git diff',
    description: 'Returns git diff output.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'gitLog',
    label: 'Git log',
    description: 'Returns recent git commits.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'gitCommit',
    label: 'Git commit',
    description: 'Stages all changes and creates a commit with the given message.',
    requiresWriteAccess: true,
  ),

  // ── Exécution ───────────────────────────────────────────────────────────
  AgenticToolSpec(
    name: 'runShellCommand',
    label: 'Run terminal command',
    description: 'Runs a command in the project terminal and returns its output.',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'runTests',
    label: 'Run tests',
    description: 'Runs the project test suite and returns results.',
    requiresWriteAccess: true,
  ),

  // ── Web ─────────────────────────────────────────────────────────────────
  AgenticToolSpec(
    name: 'searchInWeb',
    label: 'Search in web',
    description: 'Searches the web using DuckDuckGo and returns results.',
    requiresWriteAccess: false,
  ),

  // ── Agent ───────────────────────────────────────────────────────────────
  AgenticToolSpec(
    name: 'updateProjectMemory',
    label: 'Update project memory',
    description: 'Writes or updates .panda/memory.md — persistent project notes injected at the start of every conversation.',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'loadRules',
    label: 'Load rules',
    description: 'Reads and injects project rules from .panda/rules.md into the agent context.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'askFollowUpQuestion',
    label: 'Ask follow-up question',
    description: 'Asks the user a precise clarifying question before acting on an ambiguous task.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'attemptCompletion',
    label: 'Attempt completion',
    description: 'Signals the end of a task with a result summary. Never ends with a question.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'getPendingEditsForFile',
    label: 'Pending edits',
    description: 'Gets pending agentic diff hunks for a file.',
    requiresWriteAccess: false,
  ),
];

Map<String, bool> normalizeAgenticToolSelections(
  Map<String, bool>? selections,
) {
  return {
    for (final spec in agenticToolSpecs)
      spec.name: selections?[spec.name] ?? true,
  };
}

List<Map<String, dynamic>> filterAgenticToolsBySelection(
  List<Map<String, dynamic>> tools,
  Map<String, bool>? selections,
) {
  if (selections == null || selections.isEmpty) {
    return tools;
  }

  return tools.where((tool) {
    final function = tool['function'];
    if (function is! Map) return true;
    final toolName = function['name']?.toString();
    if (toolName == null || toolName.isEmpty) return true;
    return selections[toolName] ?? true;
  }).toList();
}

bool isAgenticWriteTool(String toolName) {
  return agenticToolSpecs.any(
    (spec) => spec.name == toolName && spec.requiresWriteAccess,
  );
}
