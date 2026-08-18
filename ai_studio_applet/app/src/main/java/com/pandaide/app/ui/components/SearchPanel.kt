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
import com.pandaide.app.model.SearchResult

@Composable
fun SearchPanel(
    query: String,
    results: List<SearchResult>,
    theme: IdeTheme,
    onSearch: (String) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(theme.surface)
            .padding(10.dp)
    ) {
        Text(
            text = "RECHERCHER DANS LE WORKSPACE",
            fontWeight = FontWeight.Bold,
            fontSize = 11.sp,
            color = theme.textSecondary,
            letterSpacing = 1.sp,
            modifier = Modifier.padding(bottom = 8.dp)
        )

        OutlinedTextField(
            value = query,
            onValueChange = onSearch,
            placeholder = { Text("Rechercher (ex: main, AppState, import)...", color = theme.textSecondary, fontSize = 12.sp) },
            leadingIcon = { Icon(Icons.Default.Search, contentDescription = "Search", tint = theme.textSecondary, modifier = Modifier.size(16.dp)) },
            singleLine = true,
            modifier = Modifier
                .fillMaxWidth()
                .testTag("workspace_search_input")
        )

        Spacer(modifier = Modifier.height(10.dp))

        Text(
            text = "${results.size} résultat(s) trouvé(s)",
            fontSize = 11.sp,
            color = theme.textSecondary,
            modifier = Modifier.padding(bottom = 6.dp)
        )

        LazyColumn(
            modifier = Modifier.fillMaxSize()
        ) {
            items(results) { res ->
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 3.dp)
                        .clip(RoundedCornerShape(6.dp))
                        .background(theme.surfaceVariant)
                        .clickable { }
                        .padding(8.dp)
                ) {
                    Column {
                        Row(
                            horizontalArrangement = Arrangement.SpaceBetween,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(
                                text = res.fileName,
                                fontWeight = FontWeight.Bold,
                                fontSize = 12.sp,
                                color = theme.primary
                            )
                            Text(
                                text = "Ligne ${res.lineNumber}",
                                fontSize = 10.sp,
                                color = theme.textSecondary
                            )
                        }
                        Spacer(modifier = Modifier.height(2.dp))
                        Text(
                            text = res.lineContent.trim(),
                            fontSize = 11.sp,
                            color = theme.textPrimary
                        )
                    }
                }
            }
        }
    }
}
