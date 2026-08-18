package com.pandaide.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountTree
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pandaide.app.model.GitStatusItem
import com.pandaide.app.model.GitStatusType
import com.pandaide.app.model.IdeTheme

@Composable
fun GitPanel(
    branchName: String,
    changes: List<GitStatusItem>,
    theme: IdeTheme,
    onStageToggle: (GitStatusItem) -> Unit,
    onCommit: (String) -> Unit
) {
    var commitMessage by remember { mutableStateOf("") }

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
            Icon(
                imageVector = Icons.Default.AccountTree,
                contentDescription = "Git Branch",
                tint = theme.primary,
                modifier = Modifier.size(16.dp)
            )
            Spacer(modifier = Modifier.width(6.dp))
            Text(
                text = "BRANCHE: $branchName",
                fontWeight = FontWeight.Bold,
                fontSize = 12.sp,
                color = theme.textPrimary
            )
        }

        OutlinedTextField(
            value = commitMessage,
            onValueChange = { commitMessage = it },
            placeholder = { Text("Message de commit (ex: feat: clean code)...", color = theme.textSecondary, fontSize = 11.sp) },
            singleLine = false,
            maxLines = 3,
            modifier = Modifier
                .fillMaxWidth()
                .testTag("git_commit_message_input")
        )

        Spacer(modifier = Modifier.height(6.dp))

        Button(
            onClick = {
                if (commitMessage.isNotBlank()) {
                    onCommit(commitMessage)
                    commitMessage = ""
                }
            },
            colors = ButtonDefaults.buttonColors(containerColor = theme.primary),
            modifier = Modifier
                .fillMaxWidth()
                .testTag("git_commit_btn")
        ) {
            Icon(Icons.Default.Check, contentDescription = "Commit", tint = theme.background, modifier = Modifier.size(16.dp))
            Spacer(modifier = Modifier.width(6.dp))
            Text("Commit & Push Local", color = theme.background, fontSize = 12.sp, fontWeight = FontWeight.Bold)
        }

        Spacer(modifier = Modifier.height(12.dp))

        Text(
            text = "MODIFICATIONS (${changes.size})",
            fontWeight = FontWeight.Bold,
            fontSize = 11.sp,
            color = theme.textSecondary,
            letterSpacing = 1.sp
        )

        Spacer(modifier = Modifier.height(6.dp))

        LazyColumn(
            modifier = Modifier.fillMaxSize()
        ) {
            items(changes) { item ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 3.dp)
                        .clip(RoundedCornerShape(6.dp))
                        .background(theme.surfaceVariant)
                        .padding(horizontal = 8.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.weight(1f)
                    ) {
                        Checkbox(
                            checked = item.isStaged,
                            onCheckedChange = { onStageToggle(item) },
                            colors = CheckboxDefaults.colors(checkedColor = theme.primary)
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(
                            text = item.fileName,
                            fontSize = 12.sp,
                            color = theme.textPrimary
                        )
                    }

                    val badgeColor = when (item.status) {
                        GitStatusType.MODIFIED -> Color(0xFFF9E2AF)
                        GitStatusType.STAGED -> Color(0xFFA6E3A1)
                        GitStatusType.UNTRACKED -> Color(0xFF89B4FA)
                        GitStatusType.DELETED -> Color(0xFFF38BA8)
                    }
                    val badgeText = when (item.status) {
                        GitStatusType.MODIFIED -> "M"
                        GitStatusType.STAGED -> "S"
                        GitStatusType.UNTRACKED -> "U"
                        GitStatusType.DELETED -> "D"
                    }

                    Box(
                        modifier = Modifier
                            .size(18.dp)
                            .clip(RoundedCornerShape(4.dp))
                            .background(badgeColor),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = badgeText,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            color = theme.background
                        )
                    }
                }
            }
        }
    }
}
