package com.pandaide.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pandaide.app.model.EditorTab
import com.pandaide.app.model.IdeTheme

data class OutlineSymbol(
    val name: String,
    val kind: String,
    val line: Int,
    val isTopLevel: Boolean = true
)

@Composable
fun OutlinePanel(
    openTabs: List<EditorTab>,
    theme: IdeTheme
) {
    val activeTab = openTabs.firstOrNull { !it.isWelcome }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(theme.surface)
            .padding(8.dp)
    ) {
        Text(
            text = "OUTLINE",
            fontWeight = FontWeight.Bold,
            fontSize = 11.sp,
            color = theme.textSecondary,
            letterSpacing = 1.sp,
            modifier = Modifier.padding(bottom = 8.dp)
        )

        if (activeTab == null) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "Aucun fichier ouvert",
                    fontSize = 12.sp,
                    color = theme.textSecondary
                )
            }
        } else {
            val symbols = remember(activeTab.content) {
                extractSymbols(activeTab.content, activeTab.language)
            }

            LazyColumn(modifier = Modifier.fillMaxSize()) {
                items(symbols) { symbol ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(26.dp)
                            .padding(start = if (symbol.isTopLevel) 4.dp else 20.dp)
                            .clip(RoundedCornerShape(4.dp))
                            .clickable { }
                            .padding(horizontal = 6.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        val iconTint = when (symbol.kind) {
                            "class" -> Color(0xFFF9E2AF)
                            "function" -> Color(0xFF89B4FA)
                            "variable" -> Color(0xFFCBA6F7)
                            "interface" -> Color(0xFF89DCEB)
                            "enum" -> Color(0xFFF38BA8)
                            "import" -> theme.textSecondary.copy(alpha = 0.6f)
                            else -> theme.textSecondary
                        }
                        Icon(
                            imageVector = when (symbol.kind) {
                                "class" -> Icons.Default.Class
                                "function" -> Icons.Default.Functions
                                "variable" -> Icons.Default.DataObject
                                "interface" -> Icons.Default.DeviceHub
                                "enum" -> Icons.Default.List
                                "import" -> Icons.Default.Input
                                else -> Icons.Default.Circle
                            },
                            contentDescription = symbol.kind,
                            tint = iconTint,
                            modifier = Modifier.size(14.dp)
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = symbol.name,
                            fontSize = 12.sp,
                            fontFamily = FontFamily.Monospace,
                            color = theme.textPrimary,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f)
                        )
                        Text(
                            text = ":${symbol.line}",
                            fontSize = 10.sp,
                            color = theme.textSecondary.copy(alpha = 0.5f)
                        )
                    }
                }
            }
        }
    }
}

private fun extractSymbols(content: String, language: String): List<OutlineSymbol> {
    val symbols = mutableListOf<OutlineSymbol>()
    val lines = content.split("\n")

    for ((index, line) in lines.withIndex()) {
        val trimmed = line.trim()
        when {
            language == "Kotlin" || language == "Java" -> {
                when {
                    trimmed.startsWith("class ") || trimmed.startsWith("data class ") -> {
                        val name = trimmed.substringAfter("class ").substringBefore("{").substringBefore("(").trim()
                        if (name.isNotBlank()) symbols.add(OutlineSymbol(name, "class", index + 1))
                    }
                    trimmed.startsWith("fun ") -> {
                        val name = trimmed.substringAfter("fun ").substringBefore("(").trim()
                        if (name.isNotBlank()) symbols.add(OutlineSymbol(name, "function", index + 1))
                    }
                    trimmed.startsWith("val ") || trimmed.startsWith("var ") -> {
                        val name = trimmed.substringAfter("val ").substringAfter("var ").substringBefore("=").substringBefore(":").trim()
                        if (name.isNotBlank() && name.length < 40) symbols.add(OutlineSymbol(name, "variable", index + 1, isTopLevel = false))
                    }
                    trimmed.startsWith("interface ") -> {
                        val name = trimmed.substringAfter("interface ").substringBefore("{").trim()
                        if (name.isNotBlank()) symbols.add(OutlineSymbol(name, "interface", index + 1))
                    }
                    trimmed.startsWith("enum class ") -> {
                        val name = trimmed.substringAfter("enum class ").substringBefore("{").trim()
                        if (name.isNotBlank()) symbols.add(OutlineSymbol(name, "enum", index + 1))
                    }
                    trimmed.startsWith("import ") -> {
                        val name = trimmed.substringAfter("import ").trim().split(".").last()
                        symbols.add(OutlineSymbol(name, "import", index + 1, isTopLevel = false))
                    }
                }
            }
            language == "Dart" -> {
                when {
                    trimmed.startsWith("class ") -> {
                        val name = trimmed.substringAfter("class ").substringBefore("{").substringBefore("extends").trim()
                        if (name.isNotBlank()) symbols.add(OutlineSymbol(name, "class", index + 1))
                    }
                    trimmed.contains("Widget build") || trimmed.contains("Widget build(") -> {
                        symbols.add(OutlineSymbol("build()", "function", index + 1))
                    }
                    trimmed.startsWith("void ") || trimmed.startsWith("Future ") || trimmed.startsWith("Future<") -> {
                        val name = trimmed.substringAfter("void ").substringAfter("Future ").substringAfter("Future<").substringBefore("(").substringBefore("<").trim()
                        if (name.isNotBlank() && name.length < 40) symbols.add(OutlineSymbol(name, "function", index + 1))
                    }
                    trimmed.startsWith("import ") -> {
                        val name = trimmed.substringAfter("import '").substringBefore("'").split("/").last()
                        symbols.add(OutlineSymbol(name, "import", index + 1, isTopLevel = false))
                    }
                }
            }
            language == "Python" -> {
                when {
                    trimmed.startsWith("class ") -> {
                        val name = trimmed.substringAfter("class ").substringBefore("(").substringBefore(":").trim()
                        if (name.isNotBlank()) symbols.add(OutlineSymbol(name, "class", index + 1))
                    }
                    trimmed.startsWith("def ") -> {
                        val name = trimmed.substringAfter("def ").substringBefore("(").trim()
                        if (name.isNotBlank()) symbols.add(OutlineSymbol(name, "function", index + 1))
                    }
                }
            }
            language == "JavaScript" || language == "TypeScript" -> {
                when {
                    trimmed.startsWith("function ") || trimmed.startsWith("async function ") -> {
                        val name = trimmed.substringAfter("function ").substringAfter("async function ").substringBefore("(").trim()
                        if (name.isNotBlank()) symbols.add(OutlineSymbol(name, "function", index + 1))
                    }
                    trimmed.startsWith("class ") -> {
                        val name = trimmed.substringAfter("class ").substringBefore("{").trim()
                        if (name.isNotBlank()) symbols.add(OutlineSymbol(name, "class", index + 1))
                    }
                    trimmed.startsWith("const ") && trimmed.contains("= (") -> {
                        val name = trimmed.substringAfter("const ").substringBefore("=").trim()
                        if (name.isNotBlank() && name.length < 40) symbols.add(OutlineSymbol(name, "function", index + 1))
                    }
                    trimmed.startsWith("export ") -> {
                        val rest = trimmed.removePrefix("export ").removePrefix("default ").removePrefix("function ")
                        if (rest.isNotBlank() && rest.length < 50) symbols.add(OutlineSymbol(rest.take(30), "variable", index + 1, isTopLevel = false))
                    }
                }
            }
        }
    }

    return symbols
}
