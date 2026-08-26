package com.pandaide.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pandaide.app.model.IdeTheme

@Composable
fun TerminalPanel(
    lines: List<String>,
    theme: IdeTheme,
    onExecuteCmd: (String) -> Unit,
    onCloseTerminal: () -> Unit
) {
    var cmdInput by remember { mutableStateOf("") }

    Surface(
        color = Color(0xFF11111B),
        contentColor = theme.textPrimary,
        modifier = Modifier
            .fillMaxWidth()
            .height(180.dp)
            .clip(RoundedCornerShape(bottomStart = 12.dp, bottomEnd = 12.dp))
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(6.dp)
        ) {
            // Minimal close button row (no header title)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 2.dp),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onCloseTerminal, modifier = Modifier.size(20.dp)) {
                    Text("×", fontSize = 14.sp, color = theme.textSecondary, fontWeight = FontWeight.Bold)
                }
            }

            LazyColumn(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .padding(vertical = 2.dp)
            ) {
                items(lines) { line ->
                    val lineTint = when {
                        line.startsWith("$") -> theme.primary
                        line.startsWith("✓") -> theme.secondary
                        line.startsWith("🐼") -> Color(0xFFCBA6F7)
                        else -> theme.textPrimary
                    }
                    Text(
                        text = line,
                        fontSize = 11.sp,
                        fontFamily = FontFamily.Monospace,
                        color = lineTint,
                        lineHeight = 15.sp
                    )
                }
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("$ ", fontSize = 12.sp, fontFamily = FontFamily.Monospace, color = theme.secondary, fontWeight = FontWeight.Bold)
                OutlinedTextField(
                    value = cmdInput,
                    onValueChange = { cmdInput = it },
                    placeholder = { Text("Tapez une commande...", fontSize = 11.sp, color = theme.textSecondary) },
                    singleLine = true,
                    modifier = Modifier
                        .weight(1f)
                        .height(36.dp)
                        .testTag("terminal_cmd_input")
                )
                Spacer(modifier = Modifier.width(4.dp))
                IconButton(
                    onClick = {
                        if (cmdInput.isNotBlank()) {
                            onExecuteCmd(cmdInput)
                            cmdInput = ""
                        }
                    },
                    modifier = Modifier.size(32.dp).testTag("terminal_send_btn")
                ) {
                    Icon(Icons.Default.PlayArrow, contentDescription = "Run", tint = theme.secondary, modifier = Modifier.size(16.dp))
                }
            }
        }
    }
}
