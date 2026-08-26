package com.pandaide.app.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.pandaide.app.ui.components.*
import com.pandaide.app.viewmodel.ActivityPanel
import com.pandaide.app.viewmodel.IdeViewModel

@Composable
fun PandaIdeApp(
    viewModel: IdeViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsState()
    val theme = state.activeTheme
    val activeTab = state.openTabs.getOrNull(state.activeTabIndex)

    val commands = listOf(
        CommandItem("c1", "Enregistrer le fichier", "Ctrl+S") { viewModel.saveActiveTab() },
        CommandItem("c2", "Exécuter Flutter / Gradle", "F5") { viewModel.executeTerminalCommand("flutter run") },
        CommandItem("c3", "Ouvrir / Fermer Terminal", "Ctrl+`") { viewModel.toggleTerminal() },
        CommandItem("c4", "Basculer Thème One Dark Pro", "Theme") { viewModel.setTheme(com.pandaide.app.model.IdeTheme.OneDarkPro) },
        CommandItem("c5", "Basculer Thème Dracula", "Theme") { viewModel.setTheme(com.pandaide.app.model.IdeTheme.Dracula) },
        CommandItem("c6", "Demander au Panda AI Agent", "Ctrl+I") { viewModel.selectActivityPanel(ActivityPanel.AGENT) },
        CommandItem("c7", "Statut Git", "Git") { viewModel.executeTerminalCommand("git status") }
    )

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = theme.background
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
        ) {
            // Top App Bar
            PandaAppBar(
                workspaceName = state.workspaceName,
                activeFileName = activeTab?.name,
                theme = theme,
                onToggleSidebar = { viewModel.toggleSidebar() },
                onToggleTerminal = { viewModel.toggleTerminal() },
                onOpenCommandPalette = { viewModel.toggleCommandPalette() },
                onRunCode = { viewModel.executeTerminalCommand("flutter run") },
                onOpenAgent = { viewModel.selectActivityPanel(ActivityPanel.AGENT) }
            )

            Row(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
            ) {
                // Activity Bar + Sidebar (seamless unit, no gap)
                if (state.isSidebarVisible && state.activePanel != ActivityPanel.NONE) {
                    ActivityBar(
                        activePanel = state.activePanel,
                        isSidebarVisible = state.isSidebarVisible,
                        theme = theme,
                        gitChangesCount = state.gitChanges.size,
                        onSelectPanel = { panel -> viewModel.selectActivityPanel(panel) },
                        onOpenWelcome = { viewModel.openWelcomeTab() }
                    )

                    Box(
                        modifier = Modifier
                            .width(260.dp)
                            .fillMaxHeight()
                            .background(theme.surface)
                    ) {
                        when (state.activePanel) {
                            ActivityPanel.EXPLORER -> {
                                FileExplorerPanel(
                                    workspaceName = state.workspaceName,
                                    fileTree = state.fileTree,
                                    theme = theme,
                                    onOpenFile = { node -> viewModel.openFile(node) }
                                )
                            }
                            ActivityPanel.OUTLINE -> {
                                OutlinePanel(
                                    openTabs = state.openTabs,
                                    theme = theme
                                )
                            }
                            ActivityPanel.TIMELINE -> {
                                TimelinePanel(
                                    theme = theme
                                )
                            }
                            ActivityPanel.SEARCH -> {
                                SearchPanel(
                                    query = state.searchQuery,
                                    results = state.searchResults,
                                    theme = theme,
                                    onSearch = { query -> viewModel.searchInWorkspace(query) }
                                )
                            }
                            ActivityPanel.GIT -> {
                                GitPanel(
                                    branchName = state.gitBranch,
                                    changes = state.gitChanges,
                                    theme = theme,
                                    onStageToggle = { item -> viewModel.stageGitItem(item) },
                                    onCommit = { msg -> viewModel.commitGitChanges(msg) }
                                )
                            }
                            ActivityPanel.AGENT -> {
                                AgentPanel(
                                    messages = state.agentMessages,
                                    isThinking = state.isAgentThinking,
                                    suggestions = state.agentSuggestions,
                                    theme = theme,
                                    onSendPrompt = { prompt -> viewModel.sendAgentPrompt(prompt) }
                                )
                            }
                            ActivityPanel.PLUGINS -> {
                                PluginsPanel(
                                    plugins = state.plugins,
                                    theme = theme,
                                    onToggleInstall = { id -> viewModel.togglePluginInstall(id) }
                                )
                            }
                            ActivityPanel.SETTINGS -> {
                                SettingsPanel(
                                    activeTheme = theme,
                                    fontSizeSp = state.fontSizeSp,
                                    showLineNumbers = state.showLineNumbers,
                                    wordWrap = state.wordWrap,
                                    onSetTheme = { th -> viewModel.setTheme(th) },
                                    onSetFontSize = { size -> viewModel.setFontSize(size) },
                                    onToggleLineNumbers = { viewModel.toggleLineNumbers() },
                                    onToggleWordWrap = { viewModel.toggleWordWrap() }
                                )
                            }
                            ActivityPanel.NONE -> {}
                        }
                    }
                } else if (state.isSidebarVisible) {
                    ActivityBar(
                        activePanel = state.activePanel,
                        isSidebarVisible = state.isSidebarVisible,
                        theme = theme,
                        gitChangesCount = state.gitChanges.size,
                        onSelectPanel = { panel -> viewModel.selectActivityPanel(panel) },
                        onOpenWelcome = { viewModel.openWelcomeTab() }
                    )
                }

                // Center Editor Canvas & Bottom Terminal
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                ) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth()
                    ) {
                        CodeEditorArea(
                            tabs = state.openTabs,
                            activeTabIndex = state.activeTabIndex,
                            theme = theme,
                            fontSizeSp = state.fontSizeSp,
                            showLineNumbers = state.showLineNumbers,
                            wordWrap = state.wordWrap,
                            onSelectTab = { index -> viewModel.selectTab(index) },
                            onCloseTab = { index -> viewModel.closeTab(index) },
                            onContentChange = { newContent -> viewModel.updateActiveTabContent(newContent) },
                            onInsertSymbol = { sym -> viewModel.insertQuickToolSymbol(sym) },
                            onSaveFile = { viewModel.saveActiveTab() },
                            onOpenAgent = { viewModel.selectActivityPanel(ActivityPanel.AGENT) },
                            onOpenExplorer = { viewModel.selectActivityPanel(ActivityPanel.EXPLORER) }
                        )
                    }

                    if (state.isTerminalVisible) {
                        TerminalPanel(
                            lines = state.terminalLines,
                            theme = theme,
                            onExecuteCmd = { cmd -> viewModel.executeTerminalCommand(cmd) },
                            onCloseTerminal = { viewModel.toggleTerminal() }
                        )
                    }
                }
            }

            // Bottom Status Bar
            StatusBar(
                activeLanguage = activeTab?.language ?: "Plain Text",
                currentLine = activeTab?.currentLine ?: 1,
                currentCol = activeTab?.currentCol ?: 1,
                gitBranch = state.gitBranch,
                theme = theme
            )
        }

        if (state.isCommandPaletteOpen) {
            CommandPaletteDialog(
                theme = theme,
                onDismiss = { viewModel.toggleCommandPalette() },
                commands = commands
            )
        }
    }
}
