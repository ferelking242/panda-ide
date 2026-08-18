package com.pandaide.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Extension
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pandaide.app.model.IdeTheme
import com.pandaide.app.model.PluginItem

@Composable
fun PluginsPanel(
    plugins: List<PluginItem>,
    theme: IdeTheme,
    onToggleInstall: (String) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(theme.surface)
            .padding(10.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(bottom = 8.dp)
        ) {
            Icon(Icons.Default.Extension, contentDescription = "Extensions", tint = theme.primary, modifier = Modifier.size(16.dp))
            Spacer(modifier = Modifier.width(6.dp))
            Text("EXTENSIONS & MARKETPLACE", fontWeight = FontWeight.Bold, fontSize = 11.sp, color = theme.textSecondary, letterSpacing = 1.sp)
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize()
        ) {
            items(plugins) { plugin ->
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(theme.surfaceVariant)
                        .padding(10.dp)
                ) {
                    Column {
                        Row(
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(plugin.name, fontWeight = FontWeight.Bold, fontSize = 13.sp, color = theme.textPrimary)
                                Text("${plugin.author} • v${plugin.version}", fontSize = 10.sp, color = theme.textSecondary)
                            }
                            Button(
                                onClick = { onToggleInstall(plugin.id) },
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = if (plugin.isInstalled) theme.surface else theme.primary
                                ),
                                contentPadding = PaddingValues(horizontal = 10.dp, vertical = 2.dp),
                                modifier = Modifier.height(28.dp).testTag("plugin_toggle_${plugin.id}")
                            ) {
                                Text(
                                    text = if (plugin.isInstalled) "Désinstaller" else "Installer",
                                    fontSize = 10.sp,
                                    color = if (plugin.isInstalled) theme.textSecondary else theme.background
                                )
                            }
                        }
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(plugin.description, fontSize = 11.sp, color = theme.textPrimary.copy(alpha = 0.8f))
                    }
                }
            }
        }
    }
}
