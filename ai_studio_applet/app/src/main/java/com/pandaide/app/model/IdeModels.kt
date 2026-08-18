package com.pandaide.app.model

import androidx.compose.ui.graphics.Color

data class FileNode(
    val id: String,
    val name: String,
    val path: String,
    val isDirectory: Boolean,
    val children: List<FileNode> = emptyList(),
    val extension: String = "",
    var content: String = "",
    val isExpanded: Boolean = false,
    val isModified: Boolean = false
)

data class EditorTab(
    val id: String,
    val path: String,
    val name: String,
    var content: String = "",
    var savedContent: String = "",
    val isWelcome: Boolean = false,
    val isTerminal: Boolean = false,
    val isAgent: Boolean = false,
    var currentLine: Int = 1,
    var currentCol: Int = 1
) {
    val isModified: Boolean
        get() = !isSpecial && content != savedContent

    val isSpecial: Boolean
        get() = isWelcome || isTerminal || isAgent

    val language: String
        get() {
            if (isTerminal) return "Terminal"
            if (isAgent) return "Panda Agent"
            val dot = name.lastIndexOf('.')
            if (dot == -1) return "Plain Text"
            return when (name.substring(dot + 1).lowercase()) {
                "dart" -> "Dart"
                "kt", "kts" -> "Kotlin"
                "py" -> "Python"
                "js", "mjs", "cjs" -> "JavaScript"
                "ts", "tsx" -> "TypeScript"
                "rs" -> "Rust"
                "java" -> "Java"
                "go" -> "Go"
                "cpp", "cxx", "cc" -> "C++"
                "c" -> "C"
                "json" -> "JSON"
                "yaml", "yml" -> "YAML"
                "md", "markdown" -> "Markdown"
                "html" -> "HTML"
                "css" -> "CSS"
                "sql" -> "SQL"
                "sh", "bash" -> "Shell"
                "gradle" -> "Gradle"
                else -> "Plain Text"
            }
        }

    companion object {
        fun welcome() = EditorTab(
            id = "__welcome__",
            path = "",
            name = "Welcome",
            isWelcome = true
        )

        fun terminal() = EditorTab(
            id = "__terminal__",
            path = "",
            name = "Terminal",
            isTerminal = true
        )

        fun agent() = EditorTab(
            id = "__agent__",
            path = "",
            name = "Panda Agent",
            isAgent = true
        )
    }
}

enum class GitStatusType {
    UNTRACKED, MODIFIED, STAGED, DELETED
}

data class GitStatusItem(
    val path: String,
    val fileName: String,
    val status: GitStatusType,
    val isStaged: Boolean = false
)

enum class AgentRole {
    USER, ASSISTANT, SYSTEM, TOOL
}

data class AgentMessage(
    val id: String,
    val role: AgentRole,
    val text: String,
    val timestamp: Long = System.currentTimeMillis(),
    val isStreaming: Boolean = false,
    val toolName: String? = null
)

data class SearchResult(
    val filePath: String,
    val fileName: String,
    val lineNumber: Int,
    val lineContent: String
)

data class PluginItem(
    val id: String,
    val name: String,
    val author: String,
    val version: String,
    val description: String,
    val isInstalled: Boolean = false,
    val iconName: String = "code"
)

data class IdeTheme(
    val id: String,
    val name: String,
    val isDark: Boolean,
    val background: Color,
    val surface: Color,
    val surfaceVariant: Color,
    val primary: Color,
    val secondary: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val lineHighlight: Color,
    val syntaxKeyword: Color,
    val syntaxString: Color,
    val syntaxComment: Color,
    val syntaxFunction: Color,
    val syntaxNumber: Color,
    val syntaxType: Color
) {
    companion object {
        val DarkModern = IdeTheme(
            id = "dark_modern",
            name = "VS Code Dark Modern",
            isDark = true,
            background = Color(0xFF1E1E2E),
            surface = Color(0xFF181825),
            surfaceVariant = Color(0xFF313244),
            primary = Color(0xFF89B4FA),
            secondary = Color(0xFFA6E3A1),
            textPrimary = Color(0xFFCDD6F4),
            textSecondary = Color(0xFFA6ADC8),
            lineHighlight = Color(0xFF2A2B3C),
            syntaxKeyword = Color(0xFFCBA6F7),
            syntaxString = Color(0xFFA6E3A1),
            syntaxComment = Color(0xFF6C7086),
            syntaxFunction = Color(0xFF89B4FA),
            syntaxNumber = Color(0xFFF9E2AF),
            syntaxType = Color(0xFF89DCEB)
        )

        val OneDarkPro = IdeTheme(
            id = "one_dark_pro",
            name = "One Dark Pro",
            isDark = true,
            background = Color(0xFF282C34),
            surface = Color(0xFF21252B),
            surfaceVariant = Color(0xFF353B45),
            primary = Color(0xFF61AFEF),
            secondary = Color(0xFF98C379),
            textPrimary = Color(0xFFABB2BF),
            textSecondary = Color(0xFF5C6370),
            lineHighlight = Color(0xFF2C313C),
            syntaxKeyword = Color(0xFFE06C75),
            syntaxString = Color(0xFF98C379),
            syntaxComment = Color(0xFF5C6370),
            syntaxFunction = Color(0xFF61AFEF),
            syntaxNumber = Color(0xFFD19A66),
            syntaxType = Color(0xFFE5C07B)
        )

        val Dracula = IdeTheme(
            id = "dracula",
            name = "Dracula",
            isDark = true,
            background = Color(0xFF282A36),
            surface = Color(0xFF21222C),
            surfaceVariant = Color(0xFF44475A),
            primary = Color(0xFFBD93F9),
            secondary = Color(0xFF50FA7B),
            textPrimary = Color(0xFFF8F8F2),
            textSecondary = Color(0xFF6272A4),
            lineHighlight = Color(0xFF44475A),
            syntaxKeyword = Color(0xFFFF79C6),
            syntaxString = Color(0xFFF1FA8C),
            syntaxComment = Color(0xFF6272A4),
            syntaxFunction = Color(0xFF50FA7B),
            syntaxNumber = Color(0xFFBD93F9),
            syntaxType = Color(0xFF8BE9FD)
        )

        val Monokai = IdeTheme(
            id = "monokai",
            name = "Monokai Pro",
            isDark = true,
            background = Color(0xFF2D2A2E),
            surface = Color(0xFF221F22),
            surfaceVariant = Color(0xFF403E41),
            primary = Color(0xFFFF6188),
            secondary = Color(0xFFA9DC76),
            textPrimary = Color(0xFFFCFCFA),
            textSecondary = Color(0xFF727072),
            lineHighlight = Color(0xFF3A383B),
            syntaxKeyword = Color(0xFFFF6188),
            syntaxString = Color(0xFFFFD866),
            syntaxComment = Color(0xFF727072),
            syntaxFunction = Color(0xFFA9DC76),
            syntaxNumber = Color(0xFFAB9DF2),
            syntaxType = Color(0xFF78DCE8)
        )
    }
}
