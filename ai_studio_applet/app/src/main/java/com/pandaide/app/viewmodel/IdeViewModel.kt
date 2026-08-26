package com.pandaide.app.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pandaide.app.model.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

enum class ActivityPanel {
    EXPLORER, OUTLINE, TIMELINE, SEARCH, GIT, AGENT, PLUGINS, SETTINGS, NONE
}

data class IdeState(
    val activePanel: ActivityPanel = ActivityPanel.EXPLORER,
    val isSidebarVisible: Boolean = true,
    val workspaceName: String = "panda-ide",
    val fileTree: List<FileNode> = emptyList(),
    val openTabs: List<EditorTab> = emptyList(),
    val activeTabIndex: Int = -1,
    val splitViewEnabled: Boolean = false,
    val activeTheme: IdeTheme = IdeTheme.DarkModern,
    val fontSizeSp: Float = 14f,
    val showLineNumbers: Boolean = true,
    val wordWrap: Boolean = true,
    val searchQuery: String = "",
    val searchResults: List<SearchResult> = emptyList(),
    val gitBranch: String = "main",
    val gitChanges: List<GitStatusItem> = emptyList(),
    val agentMessages: List<AgentMessage> = emptyList(),
    val isAgentThinking: Boolean = false,
    val terminalLines: List<String> = emptyList(),
    val isTerminalVisible: Boolean = true,
    val isCommandPaletteOpen: Boolean = false,
    val plugins: List<PluginItem> = emptyList(),
    val selectedLanguage: String = "Auto",
    val agentSuggestions: List<String> = emptyList()
)

class IdeViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(IdeState())
    val uiState: StateFlow<IdeState> = _uiState.asStateFlow()

    init {
        loadInitialData()
    }

    private fun loadInitialData() {
        val sampleFiles = listOf(
            FileNode(
                id = "f_root",
                name = "panda-ide",
                path = "/panda-ide",
                isDirectory = true,
                isExpanded = true,
                children = listOf(
                    FileNode(
                        id = "f_lib",
                        name = "lib",
                        path = "/panda-ide/lib",
                        isDirectory = true,
                        isExpanded = true,
                        children = listOf(
                            FileNode(
                                id = "f_main_dart",
                                name = "main.dart",
                                path = "/panda-ide/lib/main.dart",
                                isDirectory = false,
                                extension = "dart",
                                content = """
                                import 'package:flutter/material.dart';
                                import 'package:provider/provider.dart';
                                import 'app.dart';
                                import 'state/app_state.dart';

                                void main() async {
                                  WidgetsFlutterBinding.ensureInitialized();
                                  runApp(
                                    ChangeNotifierProvider(
                                      create: (_) => AppState(),
                                      child: const PandaApp(),
                                    ),
                                  );
                                }
                                """.trimIndent()
                            ),
                            FileNode(
                                id = "f_app_state",
                                name = "app_state.dart",
                                path = "/panda-ide/lib/state/app_state.dart",
                                isDirectory = false,
                                extension = "dart",
                                content = """
                                import 'package:flutter/material.dart';

                                class AppState extends ChangeNotifier {
                                  String workspacePath = '/panda-ide';
                                  double fontSize = 14.0;
                                  bool wordWrap = true;
                                  
                                  void updateFontSize(double newSize) {
                                    fontSize = newSize;
                                    notifyListeners();
                                  }
                                }
                                """.trimIndent()
                            )
                        )
                    ),
                    FileNode(
                        id = "f_kt_main",
                        name = "MainActivity.kt",
                        path = "/panda-ide/app/src/MainActivity.kt",
                        isDirectory = false,
                        extension = "kt",
                        content = """
                        package com.pandaide.app

                        import android.os.Bundle
                        import androidx.activity.ComponentActivity
                        import androidx.activity.compose.setContent
                        import com.pandaide.app.ui.PandaIdeApp

                        class MainActivity : ComponentActivity() {
                            override fun onCreate(savedInstanceState: Bundle?) {
                                super.onCreate(savedInstanceState)
                                setContent {
                                    PandaIdeApp()
                                }
                            }
                        }
                        """.trimIndent()
                    ),
                    FileNode(
                        id = "f_pubspec",
                        name = "pubspec.yaml",
                        path = "/panda-ide/pubspec.yaml",
                        isDirectory = false,
                        extension = "yaml",
                        content = """
                        name: panda_ide
                        description: Panda IDE - mobile code editor
                        version: 1.1.0+3
                        environment:
                          sdk: '>=3.2.0 <4.0.0'
                        dependencies:
                          flutter:
                            sdk: flutter
                          provider: ^6.1.2
                          shared_preferences: ^2.3.2
                        """.trimIndent()
                    ),
                    FileNode(
                        id = "f_readme",
                        name = "README.md",
                        path = "/panda-ide/README.md",
                        isDirectory = false,
                        extension = "md",
                        content = """
                        # 🐼 Panda IDE
                        Next-generation multiplatform IDE — Mobile & Desktop
                        
                        ## Features
                        - Multi-tab syntax editor
                        - Integrated Git manager
                        - Cursor-style Panda AI Agent
                        - Custom VS Code themes
                        """.trimIndent()
                    )
                )
            )
        )

        val welcomeTab = EditorTab.welcome()
        val mainDartTab = EditorTab(
            id = "f_main_dart",
            path = "/panda-ide/lib/main.dart",
            name = "main.dart",
            content = """
            import 'package:flutter/material.dart';
            import 'package:provider/provider.dart';
            import 'app.dart';
            import 'state/app_state.dart';

            void main() async {
              WidgetsFlutterBinding.ensureInitialized();
              runApp(
                ChangeNotifierProvider(
                  create: (_) => AppState(),
                  child: const PandaApp(),
                ),
              );
            }
            """.trimIndent(),
            savedContent = """
            import 'package:flutter/material.dart';
            import 'package:provider/provider.dart';
            import 'app.dart';
            import 'state/app_state.dart';

            void main() async {
              WidgetsFlutterBinding.ensureInitialized();
              runApp(
                ChangeNotifierProvider(
                  create: (_) => AppState(),
                  child: const PandaApp(),
                ),
              );
            }
            """.trimIndent()
        )

        val initialGit = listOf(
            GitStatusItem("/panda-ide/lib/main.dart", "main.dart", GitStatusType.MODIFIED, false),
            GitStatusItem("/panda-ide/pubspec.yaml", "pubspec.yaml", GitStatusType.STAGED, true),
            GitStatusItem("/panda-ide/test/models_test.dart", "models_test.dart", GitStatusType.UNTRACKED, false)
        )

        val initialMessages = listOf(
            AgentMessage(
                id = "1",
                role = AgentRole.ASSISTANT,
                text = "👋 Bonjour ! Je suis **Panda AI Agent**. Je peux t'aider à analyser, formater, refactoriser ou écrire du code propre."
            )
        )

        val initialTerminal = listOf(
            "🐼 Panda IDE Terminal v1.1.0 [Linux/Android]",
            "Workspace: /panda-ide",
            "Type 'help' or 'run' to execute commands.",
            ""
        )

        val initialPlugins = listOf(
            PluginItem("p1", "Flutter Tools", "Dart Dev", "1.4.0", "Flutter SDK integration & hot reload", true),
            PluginItem("p2", "Tree-sitter Syntax", "Panda", "2.1.0", "Advanced code coloring engine", true),
            PluginItem("p3", "GitLens Mobile", "Eric A.", "12.0.1", "Inline git blame & branch visualizer", true),
            PluginItem("p4", "Prettier Formatter", "Esben Petersen", "3.0.0", "Opinionated code formatter", false),
            PluginItem("p5", "Python Linter", "PyCQA", "0.9.1", "PEP 8 code analysis for Python", false)
        )

        _uiState.value = _uiState.value.copy(
            fileTree = sampleFiles,
            openTabs = listOf(welcomeTab, mainDartTab),
            activeTabIndex = 1,
            gitChanges = initialGit,
            agentMessages = initialMessages,
            terminalLines = initialTerminal,
            plugins = initialPlugins
        )
    }

    fun selectActivityPanel(panel: ActivityPanel) {
        val current = _uiState.value.activePanel
        if (current == panel && _uiState.value.isSidebarVisible) {
            _uiState.value = _uiState.value.copy(isSidebarVisible = false)
        } else {
            _uiState.value = _uiState.value.copy(
                activePanel = panel,
                isSidebarVisible = true
            )
        }
    }

    fun toggleSidebar() {
        val currentVisible = _uiState.value.isSidebarVisible
        if (!currentVisible) {
            val panelToOpen = if (_uiState.value.activePanel == ActivityPanel.NONE) ActivityPanel.EXPLORER else _uiState.value.activePanel
            _uiState.value = _uiState.value.copy(
                isSidebarVisible = true,
                activePanel = panelToOpen
            )
        } else {
            _uiState.value = _uiState.value.copy(isSidebarVisible = false)
        }
    }

    fun openWelcomeTab() {
        val welcomeIndex = _uiState.value.openTabs.indexOfFirst { it.isWelcome }
        if (welcomeIndex != -1) {
            _uiState.value = _uiState.value.copy(
                activeTabIndex = welcomeIndex,
                isSidebarVisible = false
            )
        } else {
            val welcomeTab = EditorTab.welcome()
            val updated = listOf(welcomeTab) + _uiState.value.openTabs
            _uiState.value = _uiState.value.copy(
                openTabs = updated,
                activeTabIndex = 0,
                isSidebarVisible = false
            )
        }
    }

    fun toggleTerminal() {
        _uiState.value = _uiState.value.copy(isTerminalVisible = !_uiState.value.isTerminalVisible)
    }

    fun toggleCommandPalette() {
        _uiState.value = _uiState.value.copy(isCommandPaletteOpen = !_uiState.value.isCommandPaletteOpen)
    }

    fun openFile(fileNode: FileNode) {
        if (fileNode.isDirectory) return
        val existingIndex = _uiState.value.openTabs.indexOfFirst { it.path == fileNode.path }
        if (existingIndex != -1) {
            _uiState.value = _uiState.value.copy(activeTabIndex = existingIndex)
        } else {
            val newTab = EditorTab(
                id = fileNode.id,
                path = fileNode.path,
                name = fileNode.name,
                content = fileNode.content,
                savedContent = fileNode.content
            )
            val updated = _uiState.value.openTabs + newTab
            _uiState.value = _uiState.value.copy(
                openTabs = updated,
                activeTabIndex = updated.size - 1
            )
        }
    }

    fun closeTab(index: Int) {
        val tabs = _uiState.value.openTabs.toMutableList()
        if (index < 0 || index >= tabs.size) return
        tabs.removeAt(index)
        val newActiveIndex = when {
            tabs.isEmpty() -> -1
            _uiState.value.activeTabIndex >= tabs.size -> tabs.size - 1
            else -> _uiState.value.activeTabIndex
        }
        _uiState.value = _uiState.value.copy(
            openTabs = tabs,
            activeTabIndex = newActiveIndex
        )
    }

    fun selectTab(index: Int) {
        if (index in 0 until _uiState.value.openTabs.size) {
            _uiState.value = _uiState.value.copy(activeTabIndex = index)
        }
    }

    fun updateActiveTabContent(newContent: String) {
        val index = _uiState.value.activeTabIndex
        if (index in 0 until _uiState.value.openTabs.size) {
            val tabs = _uiState.value.openTabs.toMutableList()
            val current = tabs[index]
            tabs[index] = current.copy(content = newContent)
            _uiState.value = _uiState.value.copy(openTabs = tabs)
        }
    }

    fun saveActiveTab() {
        val index = _uiState.value.activeTabIndex
        if (index in 0 until _uiState.value.openTabs.size) {
            val tabs = _uiState.value.openTabs.toMutableList()
            val current = tabs[index]
            tabs[index] = current.copy(savedContent = current.content)
            _uiState.value = _uiState.value.copy(openTabs = tabs)
            appendTerminalLine("Saved file: ${current.name}")
        }
    }

    fun insertQuickToolSymbol(symbol: String) {
        val index = _uiState.value.activeTabIndex
        if (index in 0 until _uiState.value.openTabs.size) {
            val tabs = _uiState.value.openTabs.toMutableList()
            val current = tabs[index]
            val updated = current.content + symbol
            tabs[index] = current.copy(content = updated)
            _uiState.value = _uiState.value.copy(openTabs = tabs)
        }
    }

    fun appendTerminalLine(line: String) {
        _uiState.value = _uiState.value.copy(
            terminalLines = _uiState.value.terminalLines + line
        )
    }

    fun executeTerminalCommand(cmd: String) {
        val trimmed = cmd.trim()
        if (trimmed.isEmpty()) return
        appendTerminalLine("$ $trimmed")
        viewModelScope.launch {
            delay(300)
            when (trimmed.lowercase()) {
                "help" -> {
                    appendTerminalLine("Available commands:")
                    appendTerminalLine("  flutter run    - Build & run Flutter app")
                    appendTerminalLine("  git status     - Show git workspace status")
                    appendTerminalLine("  git commit     - Commit staged changes")
                    appendTerminalLine("  clear          - Clear terminal logs")
                    appendTerminalLine("  agent          - Query Panda AI Agent")
                }
                "clear" -> {
                    _uiState.value = _uiState.value.copy(terminalLines = emptyList())
                }
                "git status" -> {
                    appendTerminalLine("On branch main")
                    appendTerminalLine("Modified: lib/main.dart")
                    appendTerminalLine("Staged: pubspec.yaml")
                }
                "flutter run" -> {
                    appendTerminalLine("Launching lib/main.dart on Android Emulator...")
                    delay(500)
                    appendTerminalLine("✓ Gradle build completed in 2.1s")
                    appendTerminalLine("✓ Syncing files to device...")
                    appendTerminalLine("🔥 Hot Reload ready. Press R to reload.")
                }
                else -> {
                    appendTerminalLine("Exec: $trimmed")
                    appendTerminalLine("✓ Command completed successfully with code 0.")
                }
            }
        }
    }

    fun sendAgentPrompt(prompt: String) {
        if (prompt.isBlank()) return
        val userMsg = AgentMessage(
            id = System.currentTimeMillis().toString(),
            role = AgentRole.USER,
            text = prompt
        )
        // Set thinking and clear suggestions
        _uiState.value = _uiState.value.copy(
            agentMessages = _uiState.value.agentMessages + userMsg,
            isAgentThinking = true,
            agentSuggestions = emptyList()
        )

        viewModelScope.launch {
            // Step 1: Thinking block
            delay(600)
            val thinkingMsg1 = AgentMessage(
                id = "think_1_${System.currentTimeMillis()}",
                role = AgentRole.SYSTEM,
                text = "Je comprends ta demande. Laisse-moi analyser la structure du projet pour localiser les fichiers pertinents."
            )
            _uiState.value = _uiState.value.copy(
                agentMessages = _uiState.value.agentMessages + thinkingMsg1
            )

            // Step 2: Tool Call 1
            delay(800)
            val toolCall1 = AgentMessage(
                id = "tool_1_${System.currentTimeMillis()}",
                role = AgentRole.TOOL,
                toolName = "list_files",
                text = "workspacePath = \"/panda-ide\", pattern = \"*.dart\""
            )
            _uiState.value = _uiState.value.copy(
                agentMessages = _uiState.value.agentMessages + toolCall1
            )

            // Step 3: Thinking block 2
            delay(600)
            val thinkingMsg2 = AgentMessage(
                id = "think_2_${System.currentTimeMillis()}",
                role = AgentRole.SYSTEM,
                text = "Fichiers trouvés. Je vais maintenant lire le fichier 'lib/main.dart' pour évaluer la configuration actuelle."
            )
            _uiState.value = _uiState.value.copy(
                agentMessages = _uiState.value.agentMessages + thinkingMsg2
            )

            // Step 4: Tool Call 2
            delay(800)
            val toolCall2 = AgentMessage(
                id = "tool_2_${System.currentTimeMillis()}",
                role = AgentRole.TOOL,
                toolName = "read_file",
                text = "path = \"/panda-ide/lib/main.dart\""
            )
            _uiState.value = _uiState.value.copy(
                agentMessages = _uiState.value.agentMessages + toolCall2
            )

            // Step 5: Final typed response
            delay(800)
            val replyText = when {
                prompt.contains("explain", ignoreCase = true) || prompt.contains("explique", ignoreCase = true) ->
                    "Voici une explication de ton code :\n\n- `main()` initialise les bindings de l'application mobile.\n- `ChangeNotifierProvider` injecte `AppState` globalement pour gérer la taille de police et l'affichage.\n- Le widget `PandaApp` est la racine de l'interface et applique les thèmes VS Code."
                prompt.contains("refactor", ignoreCase = true) || prompt.contains("propre", ignoreCase = true) ->
                    "J'ai complété le refactoring de ton code. Voici une version propre de l'initialisation du point d'entrée avec gestion des erreurs :\n\n```dart\nvoid main() async {\n  try {\n    WidgetsFlutterBinding.ensureInitialized();\n    runApp(const PandaApp());\n  } catch (e) {\n    print('Erreur au démarrage: \$e');\n  }\n}\n```"
                else ->
                    "Analyse terminée pour : \"$prompt\". Tous les composants de ton projet Panda IDE sont à jour et structurés selon les meilleures pratiques."
            }
            val assistantMsg = AgentMessage(
                id = "assist_${System.currentTimeMillis()}",
                role = AgentRole.ASSISTANT,
                text = replyText,
                isStreaming = true
            )
            _uiState.value = _uiState.value.copy(
                agentMessages = _uiState.value.agentMessages + assistantMsg,
                isAgentThinking = false
            )

            // Step 6: Dynamic suggestions based on prompt
            delay(1500)
            val suggestions = when {
                prompt.contains("explain", ignoreCase = true) || prompt.contains("explique", ignoreCase = true) ->
                    listOf("Explique app_state.dart", "Lancer flutter run", "Vérifier statut Git")
                prompt.contains("refactor", ignoreCase = true) || prompt.contains("propre", ignoreCase = true) ->
                    listOf("Voir les différences (Diff)", "Lancer les tests", "Formater le fichier")
                else ->
                    listOf("Analyser un autre fichier", "Ouvrir les réglages", "Aide Terminal")
            }
            _uiState.value = _uiState.value.copy(
                agentSuggestions = suggestions
            )
        }
    }

    fun searchInWorkspace(query: String) {
        _uiState.value = _uiState.value.copy(searchQuery = query)
        if (query.length < 2) {
            _uiState.value = _uiState.value.copy(searchResults = emptyList())
            return
        }
        val results = listOf(
            SearchResult("/panda-ide/lib/main.dart", "main.dart", 8, "runApp(ChangeNotifierProvider("),
            SearchResult("/panda-ide/lib/state/app_state.dart", "app_state.dart", 5, "class AppState extends ChangeNotifier"),
            SearchResult("/panda-ide/pubspec.yaml", "pubspec.yaml", 1, "name: panda_ide")
        ).filter { it.lineContent.contains(query, ignoreCase = true) || it.fileName.contains(query, ignoreCase = true) }
        _uiState.value = _uiState.value.copy(searchResults = results)
    }

    fun stageGitItem(item: GitStatusItem) {
        val updated = _uiState.value.gitChanges.map {
            if (it.path == item.path) it.copy(isStaged = !it.isStaged) else it
        }
        _uiState.value = _uiState.value.copy(gitChanges = updated)
    }

    fun commitGitChanges(message: String) {
        if (message.isBlank()) return
        appendTerminalLine("git commit -m \"$message\"")
        val remaining = _uiState.value.gitChanges.filter { !it.isStaged }
        _uiState.value = _uiState.value.copy(gitChanges = remaining)
        appendTerminalLine("✓ Commit réaffecté à main ($message)")
    }

    fun setTheme(theme: IdeTheme) {
        _uiState.value = _uiState.value.copy(activeTheme = theme)
    }

    fun setFontSize(size: Float) {
        _uiState.value = _uiState.value.copy(fontSizeSp = size)
    }

    fun toggleLineNumbers() {
        _uiState.value = _uiState.value.copy(showLineNumbers = !_uiState.value.showLineNumbers)
    }

    fun toggleWordWrap() {
        _uiState.value = _uiState.value.copy(wordWrap = !_uiState.value.wordWrap)
    }

    fun togglePluginInstall(pluginId: String) {
        val updated = _uiState.value.plugins.map {
            if (it.id == pluginId) it.copy(isInstalled = !it.isInstalled) else it
        }
        _uiState.value = _uiState.value.copy(plugins = updated)
    }
}
