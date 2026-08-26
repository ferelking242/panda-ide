package com.pandaide.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Settings
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

@Composable
fun SettingsPanel(
    activeTheme: IdeTheme,
    fontSizeSp: Float,
    showLineNumbers: Boolean,
    wordWrap: Boolean,
    onSetTheme: (IdeTheme) -> Unit,
    onSetFontSize: (Float) -> Unit,
    onToggleLineNumbers: () -> Unit,
    onToggleWordWrap: () -> Unit
) {
    val themes = listOf(
        IdeTheme.DarkModern,
        IdeTheme.OneDarkPro,
        IdeTheme.Dracula,
        IdeTheme.Monokai
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(activeTheme.surface)
            .padding(10.dp)
            .verticalScroll(rememberScrollState())
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(bottom = 12.dp)
        ) {
            Icon(Icons.Default.Settings, contentDescription = "Settings", tint = activeTheme.primary, modifier = Modifier.size(18.dp))
            Spacer(modifier = Modifier.width(6.dp))
            Text("PARAMÈTRES DE L'ÉDITEUR", fontWeight = FontWeight.Bold, fontSize = 12.sp, color = activeTheme.textPrimary)
        }

        // Themes section
        Text("THÈME VS CODE / IDE", fontWeight = FontWeight.Bold, fontSize = 11.sp, color = activeTheme.textSecondary, letterSpacing = 1.sp)
        Spacer(modifier = Modifier.height(6.dp))

        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 16.dp)
        ) {
            items(themes) { th ->
                val isSelected = th.id == activeTheme.id
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .background(th.background)
                        .border(
                            width = if (isSelected) 2.dp else 1.dp,
                            color = if (isSelected) activeTheme.primary else activeTheme.surfaceVariant,
                            shape = RoundedCornerShape(8.dp)
                        )
                        .clickable { onSetTheme(th) }
                        .padding(horizontal = 12.dp, vertical = 8.dp)
                        .testTag("theme_chip_${th.id}")
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            modifier = Modifier
                                .size(12.dp)
                                .clip(RoundedCornerShape(6.dp))
                                .background(th.primary)
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(th.name, fontSize = 11.sp, color = th.textPrimary, fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal)
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Font size section
        Text("TAILLE DE LA POLICE (${fontSizeSp.toInt()} SP)", fontWeight = FontWeight.Bold, fontSize = 11.sp, color = activeTheme.textSecondary)
        Slider(
            value = fontSizeSp,
            onValueChange = onSetFontSize,
            valueRange = 10f..22f,
            steps = 12,
            colors = SliderDefaults.colors(
                thumbColor = activeTheme.primary,
                activeTrackColor = activeTheme.primary
            ),
            modifier = Modifier.testTag("font_size_slider")
        )

        Spacer(modifier = Modifier.height(8.dp))

        // Toggles
        Row(
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 4.dp)
        ) {
            Text("Numéros de ligne", fontSize = 12.sp, color = activeTheme.textPrimary)
            Switch(
                checked = showLineNumbers,
                onCheckedChange = { onToggleLineNumbers() },
                colors = SwitchDefaults.colors(checkedThumbColor = activeTheme.primary),
                modifier = Modifier.testTag("toggle_line_numbers_switch")
            )
        }

        Row(
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 4.dp)
        ) {
            Text("Retour à la ligne automatique (Word Wrap)", fontSize = 12.sp, color = activeTheme.textPrimary)
            Switch(
                checked = wordWrap,
                onCheckedChange = { onToggleWordWrap() },
                colors = SwitchDefaults.colors(checkedThumbColor = activeTheme.primary),
                modifier = Modifier.testTag("toggle_word_wrap_switch")
            )
        }
    }
}
