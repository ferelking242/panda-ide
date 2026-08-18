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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pandaide.app.model.IdeTheme
import com.pandaide.app.viewmodel.ActivityPanel

@Composable
fun ActivityBar(
    activePanel: ActivityPanel,
    isSidebarVisible: Boolean,
    theme: IdeTheme,
    gitChangesCount: Int,
    onSelectPanel: (ActivityPanel) -> Unit,
    onOpenWelcome: () -> Unit
) {
    Surface(
        color = theme.surface,
        modifier = Modifier
            .width(48.dp)
            .fillMaxHeight()
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.padding(top = 8.dp)
            ) {
                ActivityItem(
                    icon = Icons.Default.Folder,
                    label = "Explorer",
                    isSelected = isSidebarVisible && activePanel == ActivityPanel.EXPLORER,
                    theme = theme,
                    onClick = { onSelectPanel(ActivityPanel.EXPLORER) }
                )
                ActivityItem(
                    icon = Icons.Default.Search,
                    label = "Search",
                    isSelected = isSidebarVisible && activePanel == ActivityPanel.SEARCH,
                    theme = theme,
                    onClick = { onSelectPanel(ActivityPanel.SEARCH) }
                )
                ActivityItem(
                    icon = Icons.Default.AccountTree,
                    label = "Git",
                    isSelected = isSidebarVisible && activePanel == ActivityPanel.GIT,
                    theme = theme,
                    badgeCount = gitChangesCount,
                    onClick = { onSelectPanel(ActivityPanel.GIT) }
                )
                ActivityItem(
                    icon = Icons.Default.AutoAwesome,
                    label = "Panda AI",
                    isSelected = isSidebarVisible && activePanel == ActivityPanel.AGENT,
                    theme = theme,
                    isAi = true,
                    onClick = { onSelectPanel(ActivityPanel.AGENT) }
                )
            }

            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.padding(bottom = 8.dp)
            ) {
                ActivityItem(
                    icon = Icons.Default.Extension,
                    label = "Marketplace",
                    isSelected = isSidebarVisible && activePanel == ActivityPanel.PLUGINS,
                    theme = theme,
                    onClick = { onSelectPanel(ActivityPanel.PLUGINS) }
                )
                ActivityItem(
                    icon = "🐼",
                    label = "Panda IDE",
                    isSelected = false,
                    theme = theme,
                    onClick = { onOpenWelcome() }
                )
                ActivityItem(
                    icon = Icons.Default.Settings,
                    label = "Settings",
                    isSelected = isSidebarVisible && activePanel == ActivityPanel.SETTINGS,
                    theme = theme,
                    onClick = { onSelectPanel(ActivityPanel.SETTINGS) }
                )
            }
        }
    }
}

@Composable
private fun ActivityItem(
    icon: Any,
    label: String,
    isSelected: Boolean,
    theme: IdeTheme,
    badgeCount: Int = 0,
    isAi: Boolean = false,
    onClick: () -> Unit
) {
    val activeBg = if (isSelected) theme.surfaceVariant else Color.Transparent
    val iconTint = when {
        isSelected -> theme.primary
        isAi -> Color(0xFFCBA6F7)
        else -> theme.textSecondary
    }

    Box(
        modifier = Modifier
            .padding(vertical = 4.dp)
            .size(40.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(activeBg)
            .clickable { onClick() }
            .testTag("activity_item_$label"),
        contentAlignment = Alignment.Center
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (isSelected) {
                Box(
                    modifier = Modifier
                        .width(3.dp)
                        .height(20.dp)
                        .background(theme.primary, RoundedCornerShape(2.dp))
                )
                Spacer(modifier = Modifier.width(2.dp))
            }

            Box(contentAlignment = Alignment.TopEnd) {
                if (icon is ImageVector) {
                    Icon(
                        imageVector = icon,
                        contentDescription = label,
                        tint = iconTint,
                        modifier = Modifier.size(22.dp)
                    )
                } else if (icon is String) {
                    Text(
                        text = icon,
                        fontSize = 18.sp,
                        modifier = Modifier.size(22.dp)
                    )
                }

                if (badgeCount > 0) {
                    Box(
                        modifier = Modifier
                            .offset(x = 6.dp, y = (-4).dp)
                            .size(14.dp)
                            .clip(RoundedCornerShape(7.dp))
                            .background(theme.primary),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = badgeCount.toString(),
                            fontSize = 8.sp,
                            color = theme.background
                        )
                    }
                }
            }
        }
    }
}
