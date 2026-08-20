/// Log levels from most verbose to most critical.
enum PandaLogLevel {
  debug,
  trace,
  info,
  success,
  warning,
  error,
  fatal;

  String get label {
    switch (this) {
      case PandaLogLevel.debug:   return 'DEBUG';
      case PandaLogLevel.trace:   return 'TRACE';
      case PandaLogLevel.info:    return 'INFO';
      case PandaLogLevel.success: return 'SUCCESS';
      case PandaLogLevel.warning: return 'WARNING';
      case PandaLogLevel.error:   return 'ERROR';
      case PandaLogLevel.fatal:   return 'FATAL';
    }
  }

  /// Short prefix for JSON format.
  String get prefix {
    switch (this) {
      case PandaLogLevel.debug:   return 'D';
      case PandaLogLevel.trace:   return 'T';
      case PandaLogLevel.info:    return 'I';
      case PandaLogLevel.success: return 'S';
      case PandaLogLevel.warning: return 'W';
      case PandaLogLevel.error:   return 'E';
      case PandaLogLevel.fatal:   return 'F';
    }
  }
}

/// Log categories covering all Panda IDE subsystems.
enum PandaLogCategory {
  app,
  ui,
  agent,
  tool,
  terminal,
  file,
  git,
  build,
  network,
  extension,
  database,
  system,
  performance,
  security,
  crash;

  String get label {
    switch (this) {
      case PandaLogCategory.app:         return 'APP';
      case PandaLogCategory.ui:          return 'UI';
      case PandaLogCategory.agent:       return 'AGENT';
      case PandaLogCategory.tool:        return 'TOOL';
      case PandaLogCategory.terminal:    return 'TERMINAL';
      case PandaLogCategory.file:        return 'FILE';
      case PandaLogCategory.git:         return 'GIT';
      case PandaLogCategory.build:       return 'BUILD';
      case PandaLogCategory.network:     return 'NETWORK';
      case PandaLogCategory.extension:   return 'EXTENSION';
      case PandaLogCategory.database:    return 'DATABASE';
      case PandaLogCategory.system:      return 'SYSTEM';
      case PandaLogCategory.performance: return 'PERFORMANCE';
      case PandaLogCategory.security:    return 'SECURITY';
      case PandaLogCategory.crash:       return 'CRASH';
    }
  }

  static PandaLogCategory fromString(String s) {
    return PandaLogCategory.values.firstWhere(
      (c) => c.label == s.toUpperCase(),
      orElse: () => PandaLogCategory.app,
    );
  }
}
