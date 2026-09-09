class AutoApprovalRule {
  final String pattern; // Glob or command prefix e.g. "flutter build *" or "*.dart"
  final String toolName;
  final bool isAllowed;

  AutoApprovalRule({
    required this.pattern,
    required this.toolName,
    this.isAllowed = true,
  });
}

class AgentApprovalRules {
  static final List<AutoApprovalRule> defaultRules = [
    AutoApprovalRule(pattern: 'flutter build *', toolName: 'runShellCommand'),
    AutoApprovalRule(pattern: 'flutter test *', toolName: 'runShellCommand'),
    AutoApprovalRule(pattern: 'npm test', toolName: 'runShellCommand'),
    AutoApprovalRule(pattern: 'git status', toolName: 'runShellCommand'),
    AutoApprovalRule(pattern: 'git diff', toolName: 'runShellCommand'),
    AutoApprovalRule(pattern: '*.dart', toolName: 'writeFile'),
    AutoApprovalRule(pattern: '*.ts', toolName: 'writeFile'),
  ];

  static bool isAutoApproved(String toolName, Map<String, dynamic> args) {
    // Check if tool arguments match any approval rule
    final command = args['command']?.toString() ?? args['filePath']?.toString() ?? '';
    for (final rule in defaultRules) {
      if (rule.toolName == toolName) {
        final regexPattern = rule.pattern.replaceAll('*', '.*');
        if (RegExp(regexPattern).hasMatch(command)) {
          return rule.isAllowed;
        }
      }
    }
    return false;
  }
}
