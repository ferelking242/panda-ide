package com.pandaide.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pandaide.app.model.IdeTheme

@Composable
fun WelcomeScreen(
    theme: IdeTheme,
    onOpenTab: () -> Unit,
    onOpenAgent: () -> Unit,
    onOpenExplorer: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(theme.background)
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text("🐼", fontSize = 48.sp)
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = "Panda IDE",
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
            color = theme.textPrimary
        )
        Text(
            text = "Éditeur de code mobile & Assistant IA de nouvelle génération",
            fontSize = 13.sp,
            color = theme.textSecondary,
            modifier = Modifier.padding(top = 4.dp, bottom = 24.dp)
        )

        Column(
            modifier = Modifier
                .widthIn(max = 360.dp)
                .fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            WelcomeActionCard(
                icon = Icons.Default.Code,
                title = "Ouvrir main.dart",
                subtitle = "Projet Flutter panda-ide",
                theme = theme,
                onClick = onOpenTab
            )
            WelcomeActionCard(
                icon = Icons.Default.AutoAwesome,
                title = "Demander à Panda AI Agent",
                subtitle = "Génération de code, refactoring et explications",
                theme = theme,
                onClick = onOpenAgent
            )
            WelcomeActionCard(
                icon = Icons.Default.FolderOpen,
                title = "Explorer les fichiers du workspace",
                subtitle = "Architecture multi-fichiers Dart & Kotlin",
                theme = theme,
                onClick = onOpenExplorer
            )
        }
    }
}

@Composable
private fun WelcomeActionCard(
    icon: ImageVector,
    title: String,
    subtitle: String,
    theme: IdeTheme,
    onClick: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(theme.surfaceVariant)
            .clickable { onClick() }
            .padding(14.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = icon,
                contentDescription = title,
                tint = theme.primary,
                modifier = Modifier.size(24.dp)
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column {
                Text(title, fontWeight = FontWeight.Bold, fontSize = 13.sp, color = theme.textPrimary)
                Text(subtitle, fontSize = 11.sp, color = theme.textSecondary)
            }
        }
    }
}
