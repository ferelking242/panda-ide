package com.pandaide.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pandaide.app.model.FileNode
import com.pandaide.app.model.IdeTheme

@Composable
fun FileExplorerPanel(
    workspaceName: String,
    fileTree: List<FileNode>,
    theme: IdeTheme,
    onOpenFile: (FileNode) -> Unit
) {
    var showNewFileDialog by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(theme.surface)
            .padding(8.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = workspaceName.uppercase(),
                fontWeight = FontWeight.Bold,
                fontSize = 11.sp,
                color = theme.textSecondary,
                letterSpacing = 1.sp
            )

            Row {
                IconButton(
                    onClick = { showNewFileDialog = true },
                    modifier = Modifier
                        .size(24.dp)
                        .testTag("add_file_btn")
                ) {
                    Icon(
                        imageVector = Icons.Default.Add,
                        contentDescription = "New File",
                        tint = theme.textSecondary,
                        modifier = Modifier.size(16.dp)
                    )
                }
            }
        }

        HorizontalDivider(color = theme.surfaceVariant, thickness = 1.dp)

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(top = 4.dp)
        ) {
            items(fileTree) { node ->
                FileTreeNodeItem(
                    node = node,
                    level = 0,
                    theme = theme,
                    onOpenFile = onOpenFile
                )
            }
        }
    }

    if (showNewFileDialog) {
        NewFileDialog(
            theme = theme,
            onDismiss = { showNewFileDialog = false },
            onCreate = { filename ->
                showNewFileDialog = false
                val newFile = FileNode(
                    id = "f_${System.currentTimeMillis()}",
                    name = filename,
                    path = "/panda-ide/$filename",
                    isDirectory = false,
                    extension = filename.substringAfterLast('.', "txt"),
                    content = "// New file: $filename\n"
                )
                onOpenFile(newFile)
            }
        )
    }
}

@Composable
private fun FileTreeNodeItem(
    node: FileNode,
    level: Int,
    theme: IdeTheme,
    onOpenFile: (FileNode) -> Unit
) {
    var isExpanded by remember { mutableStateOf(node.isExpanded) }

    Column {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(30.dp)
                .padding(start = (level * 12).dp)
                .clip(RoundedCornerShape(4.dp))
                .clickable {
                    if (node.isDirectory) {
                        isExpanded = !isExpanded
                    } else {
                        onOpenFile(node)
                    }
                }
                .padding(horizontal = 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (node.isDirectory) {
                Icon(
                    imageVector = if (isExpanded) Icons.Default.KeyboardArrowDown else Icons.Default.KeyboardArrowRight,
                    contentDescription = "Expand/Collapse",
                    tint = theme.textSecondary,
                    modifier = Modifier.size(16.dp)
                )
                Spacer(modifier = Modifier.width(4.dp))
                Icon(
                    imageVector = Icons.Default.Folder,
                    contentDescription = "Folder",
                    tint = Color(0xFFF9E2AF),
                    modifier = Modifier.size(16.dp)
                )
            } else {
                Spacer(modifier = Modifier.width(20.dp))
                val extColor = when (node.extension.lowercase()) {
                    "dart" -> Color(0xFF89B4FA)
                    "kt", "kts" -> Color(0xFFCBA6F7)
                    "py" -> Color(0xFFF9E2AF)
                    "js", "ts" -> Color(0xFFA6E3A1)
                    "json", "yaml" -> Color(0xFF89DCEB)
                    else -> theme.textSecondary
                }
                Icon(
                    imageVector = Icons.Default.Description,
                    contentDescription = "File",
                    tint = extColor,
                    modifier = Modifier.size(15.dp)
                )
            }

            Spacer(modifier = Modifier.width(6.dp))

            Text(
                text = node.name,
                fontSize = 12.sp,
                color = if (node.isDirectory) theme.textPrimary else theme.textPrimary.copy(alpha = 0.9f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }

        if (node.isDirectory && isExpanded) {
            node.children.forEach { child ->
                FileTreeNodeItem(
                    node = child,
                    level = level + 1,
                    theme = theme,
                    onOpenFile = onOpenFile
                )
            }
        }
    }
}

@Composable
private fun NewFileDialog(
    theme: IdeTheme,
    onDismiss: () -> Unit,
    onCreate: (String) -> Unit
) {
    var filename by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text("Créer un fichier", color = theme.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
        },
        text = {
            OutlinedTextField(
                value = filename,
                onValueChange = { filename = it },
                label = { Text("Nom du fichier (ex: utils.dart, main.kt)", color = theme.textSecondary) },
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("new_filename_input")
            )
        },
        confirmButton = {
            Button(
                onClick = { if (filename.isNotBlank()) onCreate(filename) },
                colors = ButtonDefaults.buttonColors(containerColor = theme.primary)
            ) {
                Text("Créer", color = theme.background)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Annuler", color = theme.textSecondary)
            }
        },
        containerColor = theme.surface
    )
}
