package com.pandaide.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pandaide.app.model.EditorTab
import com.pandaide.app.model.IdeTheme

@Composable
fun CodeEditorArea(
    tabs: List<EditorTab>,
    activeTabIndex: Int,
    theme: IdeTheme,
    fontSizeSp: Float,
    showLineNumbers: Boolean,
    wordWrap: Boolean,
    onSelectTab: (Int) -> Unit,
    onCloseTab: (Int) -> Unit,
    onContentChange: (String) -> Unit,
    onInsertSymbol: (String) -> Unit,
    onSaveFile: () -> Unit,
    onOpenAgent: () -> Unit = {},
    onOpenExplorer: () -> Unit = {}
) {
    val activeTab = tabs.getOrNull(activeTabIndex)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(theme.background)
    ) {
        // Tab Strip
        TabStrip(
            tabs = tabs,
            activeTabIndex = activeTabIndex,
            theme = theme,
            onSelectTab = onSelectTab,
            onCloseTab = onCloseTab
        )

        HorizontalDivider(color = theme.surfaceVariant, thickness = 1.dp)

        if (activeTab == null || activeTab.isWelcome) {
            WelcomeScreen(
                theme = theme,
                onOpenTab = { if (tabs.size > 1) onSelectTab(1) },
                onOpenAgent = onOpenAgent,
                onOpenExplorer = onOpenExplorer
            )
        } else {
            // Active Editor & Quick Tools
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
            ) {
                EditorCanvas(
                    tab = activeTab,
                    theme = theme,
                    fontSizeSp = fontSizeSp,
                    showLineNumbers = showLineNumbers,
                    wordWrap = wordWrap,
                    onContentChange = onContentChange
                )
            }

            // Quick Tools Accessory Keyboard Row
            QuickToolsRow(
                theme = theme,
                onInsertSymbol = onInsertSymbol,
                onSaveFile = onSaveFile
            )
        }
    }
}

@Composable
private fun TabStrip(
    tabs: List<EditorTab>,
    activeTabIndex: Int,
    theme: IdeTheme,
    onSelectTab: (Int) -> Unit,
    onCloseTab: (Int) -> Unit
) {
    Surface(
        color = theme.surface,
        modifier = Modifier
            .fillMaxWidth()
            .height(34.dp)
    ) {
        LazyRow(
            modifier = Modifier.fillMaxSize(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            itemsIndexed(tabs) { index, tab ->
                val isActive = index == activeTabIndex
                val bg = if (isActive) theme.background else theme.surface

                Row(
                    modifier = Modifier
                        .height(34.dp)
                        .background(bg)
                        .clickable { onSelectTab(index) }
                        .padding(horizontal = 10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    val fileIconColor = when (tab.language) {
                        "Dart" -> Color(0xFF89B4FA)
                        "Kotlin" -> Color(0xFFCBA6F7)
                        "Python" -> Color(0xFFF9E2AF)
                        "JavaScript", "TypeScript" -> Color(0xFFA6E3A1)
                        else -> theme.textSecondary
                    }

                    Icon(
                        imageVector = if (tab.isWelcome) Icons.Default.Home else Icons.Default.Code,
                        contentDescription = "Tab Icon",
                        tint = fileIconColor,
                        modifier = Modifier.size(14.dp)
                    )

                    Spacer(modifier = Modifier.width(6.dp))

                    Text(
                        text = tab.name + if (tab.isModified) " •" else "",
                        fontSize = 12.sp,
                        fontWeight = if (isActive) FontWeight.Bold else FontWeight.Normal,
                        color = if (isActive) theme.textPrimary else theme.textSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )

                    Spacer(modifier = Modifier.width(8.dp))

                    if (!tab.isWelcome) {
                        IconButton(
                            onClick = { onCloseTab(index) },
                            modifier = Modifier.size(16.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Default.Close,
                                contentDescription = "Close Tab",
                                tint = theme.textSecondary,
                                modifier = Modifier.size(12.dp)
                            )
                        }
                    }
                }

                Box(
                    modifier = Modifier
                        .width(1.dp)
                        .fillMaxHeight()
                        .background(theme.surfaceVariant)
                )
            }
        }
    }
}

@Composable
private fun EditorCanvas(
    tab: EditorTab,
    theme: IdeTheme,
    fontSizeSp: Float,
    showLineNumbers: Boolean,
    wordWrap: Boolean,
    onContentChange: (String) -> Unit
) {
    val scrollState = rememberScrollState()
    val lines = remember(tab.content) { tab.content.split("\n") }

    Row(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(scrollState)
            .padding(vertical = 4.dp)
    ) {
        // Line Numbers Gutter
        if (showLineNumbers) {
            Column(
                modifier = Modifier
                    .background(theme.surface.copy(alpha = 0.5f))
                    .padding(horizontal = 8.dp),
                horizontalAlignment = Alignment.End
            ) {
                lines.forEachIndexed { i, _ ->
                    Text(
                        text = "${i + 1}",
                        fontSize = fontSizeSp.sp,
                        fontFamily = FontFamily.Monospace,
                        color = theme.textSecondary.copy(alpha = 0.5f),
                        lineHeight = (fontSizeSp + 6).sp
                    )
                }
            }
            Box(
                modifier = Modifier
                    .width(1.dp)
                    .fillMaxHeight()
                    .background(theme.surfaceVariant)
            )
        }

        // Code Text Editor
        Box(
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 8.dp)
        ) {
            BasicTextField(
                value = tab.content,
                onValueChange = onContentChange,
                textStyle = TextStyle(
                    color = theme.textPrimary,
                    fontSize = fontSizeSp.sp,
                    fontFamily = FontFamily.Monospace,
                    lineHeight = (fontSizeSp + 6).sp
                ),
                cursorBrush = SolidColor(theme.primary),
                visualTransformation = { text ->
                    androidx.compose.ui.text.input.TransformedText(
                        highlightSyntax(text.text, tab.language, theme),
                        androidx.compose.ui.text.input.OffsetMapping.Identity
                    )
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("code_editor_text_field")
            )
        }
    }
}

private fun highlightSyntax(code: String, language: String, theme: IdeTheme): AnnotatedString {
    return buildAnnotatedString {
        val keywords = setOf(
            "import", "package", "class", "fun", "val", "var", "if", "else", "return",
            "while", "for", "in", "void", "async", "await", "const", "final", "extension",
            "enum", "data", "override", "public", "private", "protected", "def", "from", "as"
        )
        val types = setOf(
            "String", "Int", "Double", "Boolean", "Float", "Long", "List", "Map", "Set",
            "Widget", "StatefulWidget", "StatelessWidget", "BuildContext", "AppState", "IdeTheme"
        )

        val words = code.split(Regex("(?<=\\b)|(?=\\b)|(?<=[^\\w])|(?=[^\\w])"))
        for (token in words) {
            when {
                keywords.contains(token) -> {
                    withStyle(SpanStyle(color = theme.syntaxKeyword, fontWeight = FontWeight.Bold)) {
                        append(token)
                    }
                }
                types.contains(token) -> {
                    withStyle(SpanStyle(color = theme.syntaxType)) {
                        append(token)
                    }
                }
                token.startsWith("\"") || token.endsWith("\"") || token.startsWith("'") || token.endsWith("'") -> {
                    withStyle(SpanStyle(color = theme.syntaxString)) {
                        append(token)
                    }
                }
                token.startsWith("//") -> {
                    withStyle(SpanStyle(color = theme.syntaxComment)) {
                        append(token)
                    }
                }
                token.toIntOrNull() != null || token.toDoubleOrNull() != null -> {
                    withStyle(SpanStyle(color = theme.syntaxNumber)) {
                        append(token)
                    }
                }
                else -> {
                    append(token)
                }
            }
        }
    }
}

@Composable
private fun QuickToolsRow(
    theme: IdeTheme,
    onInsertSymbol: (String) -> Unit,
    onSaveFile: () -> Unit
) {
    val symbols = listOf("{", "}", "(", ")", ";", "=", "=>", "<", ">", "\"", "'", "/", "\\", "|", "tab")

    Surface(
        color = theme.surface,
        modifier = Modifier
            .fillMaxWidth()
            .height(38.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxSize()
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(
                onClick = onSaveFile,
                modifier = Modifier
                    .size(30.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(theme.primary.copy(alpha = 0.2f))
                    .testTag("quick_save_btn")
            ) {
                Icon(
                    imageVector = Icons.Default.Save,
                    contentDescription = "Save File",
                    tint = theme.primary,
                    modifier = Modifier.size(16.dp)
                )
            }

            Spacer(modifier = Modifier.width(6.dp))

            symbols.forEach { sym ->
                Box(
                    modifier = Modifier
                        .padding(horizontal = 2.dp)
                        .height(28.dp)
                        .clip(RoundedCornerShape(6.dp))
                        .background(theme.surfaceVariant)
                        .clickable {
                            if (sym == "tab") onInsertSymbol("  ") else onInsertSymbol(sym)
                        }
                        .padding(horizontal = 10.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = sym,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        fontFamily = FontFamily.Monospace,
                        color = theme.textPrimary
                    )
                }
            }
        }
    }
}
