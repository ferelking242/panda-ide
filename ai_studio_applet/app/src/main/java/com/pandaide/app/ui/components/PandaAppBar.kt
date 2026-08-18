package com.pandaide.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pandaide.app.model.IdeTheme

@Composable
fun PandaAppBar(
    workspaceName: String,
    activeFileName: String?,
    theme: IdeTheme,
    onToggleSidebar: () -> Unit,
    onToggleTerminal: () -> Unit,
    onOpenCommandPalette: () -> Unit,
    onRunCode: () -> Unit,
    onOpenAgent: () -> Unit
) {
    Surface(
        color = theme.surface,
        contentColor = theme.textPrimary,
        modifier = Modifier
            .fillMaxWidth()
            .height(44.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(
                onClick = onToggleSidebar,
                modifier = Modifier
                    .size(36.dp)
                    .testTag("toggle_sidebar_btn")
            ) {
                Icon(
                    imageVector = Icons.Default.MenuOpen,
                    contentDescription = "Toggle Sidebar",
                    tint = theme.primary,
                    modifier = Modifier.size(20.dp)
                )
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .clickable { onOpenAgent() }
                    .padding(end = 8.dp)
            ) {
                Text(
                    text = "🐼",
                    fontSize = 18.sp,
                    modifier = Modifier.padding(end = 4.dp)
                )
                Text(
                    text = "Panda IDE",
                    fontWeight = FontWeight.Bold,
                    fontSize = 14.sp,
                    color = theme.primary
                )
            }

            // Command Palette / File path bar
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(28.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(theme.surfaceVariant)
                    .clickable { onOpenCommandPalette() }
                    .padding(horizontal = 10.dp)
                    .testTag("command_palette_bar"),
                contentAlignment = Alignment.CenterStart
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = Icons.Default.Search,
                            contentDescription = "Search",
                            tint = theme.textSecondary,
                            modifier = Modifier
                                .size(14.dp)
                                .padding(end = 4.dp)
                        )
                        Text(
                            text = if (!activeFileName.isNull_Empty()) "$workspaceName > $activeFileName" else "Rechercher une commande... (Ctrl+P)",
                            fontSize = 11.sp,
                            color = theme.textSecondary,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    Text(
                        text = "Ctrl+P",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Medium,
                        color = theme.textSecondary.copy(alpha = 0.6f)
                    )
                }
            }

            Spacer(modifier = Modifier.width(6.dp))

            // Action Buttons: Panda Agent, Run Code, Toggle Terminal
            IconButton(
                onClick = onOpenAgent,
                modifier = Modifier
                    .size(32.dp)
                    .testTag("appbar_open_agent_btn")
            ) {
                Icon(
                    imageVector = Icons.Default.AutoAwesome,
                    contentDescription = "Panda AI Agent",
                    tint = Color(0xFFCBA6F7),
                    modifier = Modifier.size(18.dp)
                )
            }

            IconButton(
                onClick = onRunCode,
                modifier = Modifier
                    .size(32.dp)
                    .testTag("run_code_btn")
            ) {
                Icon(
                    imageVector = Icons.Default.PlayArrow,
                    contentDescription = "Run Code",
                    tint = theme.secondary,
                    modifier = Modifier.size(18.dp)
                )
            }

            IconButton(
                onClick = onToggleTerminal,
                modifier = Modifier
                    .size(32.dp)
                    .testTag("toggle_terminal_btn")
            ) {
                Icon(
                    imageVector = Icons.Default.Terminal,
                    contentDescription = "Toggle Terminal",
                    tint = theme.textPrimary,
                    modifier = Modifier.size(18.dp)
                )
            }
        }
    }
}

private fun String?.isNull_Empty(): Boolean = this == null || this.isEmpty()
