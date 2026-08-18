package com.pandaide.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pandaide.app.model.IdeTheme

data class CommandItem(
    val id: String,
    val title: String,
    val shortcut: String,
    val action: () -> Unit
)

@Composable
fun CommandPaletteDialog(
    theme: IdeTheme,
    onDismiss: () -> Unit,
    commands: List<CommandItem>
) {
    var query by remember { mutableStateOf("") }
    val filtered = remember(query, commands) {
        if (query.isEmpty()) commands
        else commands.filter { it.title.contains(query, ignoreCase = true) }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = null,
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(300.dp)
            ) {
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    placeholder = { Text("Taper une commande (ex: Save, Run, Theme)...", fontSize = 12.sp, color = theme.textSecondary) },
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = "Search", tint = theme.textSecondary, modifier = Modifier.size(16.dp)) },
                    singleLine = true,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("command_palette_input")
                )

                Spacer(modifier = Modifier.height(8.dp))

                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    items(filtered) { cmd ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 3.dp)
                                .clip(RoundedCornerShape(6.dp))
                                .background(theme.surfaceVariant)
                                .clickable {
                                    cmd.action()
                                    onDismiss()
                                }
                                .padding(10.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(cmd.title, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = theme.textPrimary)
                            Text(cmd.shortcut, fontSize = 10.sp, color = theme.primary)
                        }
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Fermer", color = theme.textSecondary)
            }
        },
        containerColor = theme.surface
    )
}
