package com.pandaide.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pandaide.app.model.IdeTheme

data class TimelineEntry(
    val fileName: String,
    val action: String,
    val timestamp: String,
    val author: String = "You"
)

@Composable
fun TimelinePanel(
    theme: IdeTheme
) {
    val sampleEntries = remember {
        listOf(
            TimelineEntry("main.dart", "Modified", "Il y a 2 min"),
            TimelineEntry("app_state.dart", "Modified", "Il y a 5 min"),
            TimelineEntry("utils.dart", "Created", "Il y a 12 min"),
            TimelineEntry("README.md", "Modified", "Il y a 30 min"),
            TimelineEntry("pubspec.yaml", "Modified", "Il y a 1h"),
        )
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(theme.surface)
            .padding(8.dp)
    ) {
        Text(
            text = "TIMELINE",
            fontWeight = FontWeight.Bold,
            fontSize = 11.sp,
            color = theme.textSecondary,
            letterSpacing = 1.sp,
            modifier = Modifier.padding(bottom = 8.dp)
        )

        LazyColumn(modifier = Modifier.fillMaxSize()) {
            items(sampleEntries) { entry ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 2.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .clickable { }
                        .padding(horizontal = 6.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.Top
                ) {
                    // Timeline dot + line
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier.padding(top = 4.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(8.dp)
                                .clip(CircleShape)
                                .background(
                                    when (entry.action) {
                                        "Created" -> Color(0xFFA6E3A1)
                                        "Modified" -> Color(0xFFF9E2AF)
                                        "Deleted" -> Color(0xFFF38BA8)
                                        else -> theme.textSecondary
                                    }
                                )
                        )
                    }

                    Spacer(modifier = Modifier.width(8.dp))

                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = entry.fileName,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Medium,
                            color = theme.textPrimary,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = entry.action,
                                fontSize = 10.sp,
                                color = when (entry.action) {
                                    "Created" -> Color(0xFFA6E3A1)
                                    "Modified" -> Color(0xFFF9E2AF)
                                    "Deleted" -> Color(0xFFF38BA8)
                                    else -> theme.textSecondary
                                }
                            )
                            Text(
                                text = " • ${entry.timestamp}",
                                fontSize = 10.sp,
                                color = theme.textSecondary
                            )
                        }
                    }
                }
            }
        }
    }
}
