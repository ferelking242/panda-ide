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
  AgenticToolSpec(
    name: 'activeEditorFile',
    label: 'Active editor file',
    description: 'Gets the path of the currently active editor file.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'currentlySelectedText',
    label: 'Selected text',
    description: 'Gets the currently selected text in the active editor.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'getLspDiagnostics',
    label: 'LSP diagnostics',
    description: 'Gets diagnostics from open LSP-backed editors.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'readFile',
    label: 'Read file',
    description: 'Reads the contents of a file.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'deleteFile',
    label: 'Delete file',
    description: 'Deletes a file from the workspace.',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'rename',
    label: 'Rename path',
    description: 'Renames or moves a file or directory path.',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'renamePath',
    label: 'Rename path (alt)',
    description: 'Renames or moves a file or directory path.',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'insertAtLine',
    label: 'Insert at line',
    description: 'Inserts text before or after a specific line.',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'replaceAllInFile',
    label: 'Replace in file',
    description: 'Replaces matching text in a file with pending diff tracking.',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'readFilesBatch',
    label: 'Read files batch',
    description: 'Reads multiple files in one call.',
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
  AgenticToolSpec(
    name: 'gitStatus',
    label: 'Git status',
    description: 'Returns git status details.',
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
    name: 'searchInFiles',
    label: 'Search in files',
    description: 'Searches for text across workspace files.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'writeFile',
    label: 'Write file',
    description: 'Writes content to a file.',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'listFiles',
    label: 'List files',
    description: 'Lists files in a directory.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'editFile',
    label: 'Edit file',
    description: 'Applies a diff or patch to a file.',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'getPendingEditsForFile',
    label: 'Pending edits',
    description: 'Gets pending agentic diff hunks for a file.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'getFileInfo',
    label: 'File info',
    description: 'Gets metadata about a file or directory.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'openLinks',
    label: 'Open links',
    description: 'Opens links in the workspace context.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'searchInWeb',
    label: 'Search in web',
    description: 'Searches the web for relevant information.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'runShellCommand',
    label: 'Run terminal command',
    description: 'Runs a command in the project terminal and returns its output.',
    requiresWriteAccess: true,
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