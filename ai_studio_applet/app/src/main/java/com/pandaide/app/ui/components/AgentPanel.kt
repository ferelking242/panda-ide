package com.pandaide.app.ui.components

import androidx.compose.animation.*
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pandaide.app.model.AgentMessage
import com.pandaide.app.model.AgentRole
import com.pandaide.app.model.IdeTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AgentPanel(
    messages: List<AgentMessage>,
    isThinking: Boolean,
    suggestions: List<String>,
    theme: IdeTheme,
    onSendPrompt: (String) -> Unit
) {
    var promptInput by remember { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(theme.surface)
            .padding(8.dp)
    ) {
        // Panel Header
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(bottom = 6.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(24.dp)
                    .clip(CircleShape)
                    .background(Color(0xFFCBA6F7)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.AutoAwesome,
                    contentDescription = "Panda AI",
                    tint = theme.background,
                    modifier = Modifier.size(14.dp)
                )
            }
            Spacer(modifier = Modifier.width(6.dp))
            Text(
                text = "PANDA AGENT (CURSOR AI)",
                fontWeight = FontWeight.Bold,
                fontSize = 11.sp,
                color = theme.textPrimary
            )
        }

        HorizontalDivider(color = theme.surfaceVariant, thickness = 1.dp)

        // Dynamic, Contextual Suggestions (Only visible when not empty - empty by default!)
        if (suggestions.isNotEmpty()) {
            Text(
                text = "Suggestions",
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                color = theme.textSecondary,
                modifier = Modifier.padding(top = 8.dp, bottom = 2.dp)
            )
            FlowRow(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                suggestions.forEachIndexed { i, s ->
                    AgentChip(s, theme, index = i) { onSendPrompt(s) }
                }
            }
        }

        // Chat Conversation List
        LazyColumn(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            contentPadding = PaddingValues(vertical = 8.dp)
        ) {
            items(messages) { msg ->
                when (msg.role) {
                    AgentRole.USER -> {
                        UserMessageBubble(msg = msg, theme = theme)
                    }
                    AgentRole.SYSTEM -> {
                        ThinkingBubble(msg = msg, theme = theme)
                    }
                    AgentRole.TOOL -> {
                        ToolCallBubble(msg = msg, theme = theme)
                    }
                    AgentRole.ASSISTANT -> {
                        AssistantMessageBubble(msg = msg, theme = theme, onResend = { onSendPrompt(msg.text) })
                    }
                }
            }

            if (isThinking) {
                item {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.padding(vertical = 6.dp)
                    ) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(14.dp),
                            color = theme.primary,
                            strokeWidth = 2.dp
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = "L'Agent réfléchit...",
                            fontSize = 10.sp,
                            color = theme.textSecondary
                        )
                    }
                }
            }
        }

        // Chat Input Bar
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 6.dp)
        ) {
            OutlinedTextField(
                value = promptInput,
                onValueChange = { promptInput = it },
                placeholder = { Text("Demander à Panda AI...", fontSize = 11.sp, color = theme.textSecondary) },
                singleLine = true,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = theme.primary,
                    unfocusedBorderColor = theme.surfaceVariant,
                    focusedContainerColor = theme.background,
                    unfocusedContainerColor = theme.background,
                    focusedTextColor = theme.textPrimary,
                    unfocusedTextColor = theme.textPrimary
                ),
                modifier = Modifier
                    .weight(1f)
                    .testTag("agent_prompt_input")
            )
            Spacer(modifier = Modifier.width(6.dp))
            IconButton(
                onClick = {
                    if (promptInput.isNotBlank()) {
                        onSendPrompt(promptInput)
                        promptInput = ""
                    }
                },
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .background(theme.primary)
                    .size(42.dp)
                    .testTag("agent_send_btn")
            ) {
                Icon(
                    imageVector = Icons.Default.Send,
                    contentDescription = "Send",
                    tint = theme.background,
                    modifier = Modifier.size(18.dp)
                )
            }
        }

        Spacer(modifier = Modifier.height(4.dp))

        // Footer indicators row
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp, vertical = 2.dp),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            // Circular Token Counter
            val totalChars = messages.sumOf { it.text.length + (it.toolName?.length ?: 0) } + promptInput.length
            val estTokens = (totalChars / 4)
            if (estTokens > 0) {
                val label = if (estTokens < 1000) "~$estTokens" else "~${String.format("%.1f", estTokens / 1000.0)}k"
                val badgeColor = if (estTokens > 80000) Color(0xFFF38BA8) else if (estTokens > 40000) Color(0xFFFAB387) else Color(0xFFA6E3A1)
                
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .background(badgeColor.copy(alpha = 0.15f))
                        .border(BorderStroke(1.dp, badgeColor.copy(alpha = 0.3f)), RoundedCornerShape(8.dp))
                        .padding(horizontal = 6.dp, vertical = 3.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(6.dp)
                            .clip(CircleShape)
                            .background(badgeColor)
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        text = label,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = theme.textSecondary
                    )
                }
            } else {
                Spacer(modifier = Modifier.width(1.dp))
            }

            // Status pills mirroring the flutter layout
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(
                    text = "Local",
                    fontSize = 10.sp,
                    color = theme.textSecondary.copy(alpha = 0.7f),
                    modifier = Modifier
                        .clip(RoundedCornerShape(4.dp))
                        .background(theme.surfaceVariant)
                        .padding(horizontal = 5.dp, vertical = 2.dp)
                )
                Text(
                    text = "Contrôle manuel",
                    fontSize = 10.sp,
                    color = Color(0xFF89B4FA),
                    modifier = Modifier
                        .clip(RoundedCornerShape(4.dp))
                        .background(Color(0xFF89B4FA).copy(alpha = 0.15f))
                        .padding(horizontal = 5.dp, vertical = 2.dp)
                )
            }
        }
    }
}

@Composable
private fun UserMessageBubble(msg: AgentMessage, theme: IdeTheme) {
    Column(
        horizontalAlignment = Alignment.End,
        modifier = Modifier.fillMaxWidth()
    ) {
        Text(
            text = "Vous",
            fontSize = 9.sp,
            fontWeight = FontWeight.Bold,
            color = theme.primary,
            modifier = Modifier.padding(bottom = 2.dp)
        )
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(12.dp, 4.dp, 12.dp, 12.dp))
                .background(theme.primary.copy(alpha = 0.15f))
                .border(1.dp, theme.primary.copy(alpha = 0.2f), RoundedCornerShape(12.dp, 4.dp, 12.dp, 12.dp))
                .padding(10.dp)
        ) {
            Text(
                text = msg.text,
                fontSize = 11.sp,
                color = theme.textPrimary,
                lineHeight = 15.sp
            )
        }
    }
}

@Composable
private fun ThinkingBubble(msg: AgentMessage, theme: IdeTheme) {
    var isExpanded by remember { mutableStateOf(true) }

    Card(
        colors = CardDefaults.cardColors(
            containerColor = theme.surfaceVariant.copy(alpha = 0.3f)
        ),
        border = BorderStroke(1.dp, theme.syntaxComment.copy(alpha = 0.15f)),
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp)
    ) {
        Column(modifier = Modifier.padding(10.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { isExpanded = !isExpanded }
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("🧠", fontSize = 12.sp)
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = "Pensée de l'Agent",
                        fontSize = 10.5.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = theme.syntaxComment
                    )
                }
                Icon(
                    imageVector = if (isExpanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                    contentDescription = "Toggle",
                    tint = theme.textSecondary,
                    modifier = Modifier.size(14.dp)
                )
            }
            if (isExpanded) {
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    text = msg.text,
                    fontSize = 10.sp,
                    fontStyle = FontStyle.Italic,
                    color = theme.textSecondary,
                    lineHeight = 14.sp
                )
            }
        }
    }
}

@Composable
private fun ToolCallBubble(msg: AgentMessage, theme: IdeTheme) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = theme.background
        ),
        border = BorderStroke(1.dp, theme.secondary.copy(alpha = 0.25f)),
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp)
    ) {
        Column(modifier = Modifier.padding(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("🛠️", fontSize = 12.sp)
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = "Outil exécuté : ${msg.toolName ?: "agent_tool"}",
                    fontSize = 10.5.sp,
                    fontWeight = FontWeight.Bold,
                    color = theme.secondary,
                    fontFamily = FontFamily.Monospace
                )
            }
            Spacer(modifier = Modifier.height(6.dp))
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(theme.surface, RoundedCornerShape(6.dp))
                    .padding(8.dp)
            ) {
                Text(
                    text = msg.text,
                    fontSize = 9.sp,
                    fontFamily = FontFamily.Monospace,
                    color = theme.textSecondary,
                    lineHeight = 12.sp
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AssistantMessageBubble(msg: AgentMessage, theme: IdeTheme, onResend: () -> Unit) {
    val clipboardManager = LocalClipboardManager.current
    var isSourcesOpen by remember { mutableStateOf(false) }
    var isStreamingDone by remember { mutableStateOf(!msg.isStreaming) }

    Column(
        horizontalAlignment = Alignment.Start,
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(bottom = 2.dp)
        ) {
            Text(
                text = "Panda AI",
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFFCBA6F7)
            )
            if (!isStreamingDone) {
                Spacer(modifier = Modifier.width(4.dp))
                Box(
                    modifier = Modifier
                        .size(6.dp)
                        .clip(CircleShape)
                        .background(theme.primary)
                )
            }
        }

        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(4.dp, 12.dp, 12.dp, 12.dp))
                .background(theme.surfaceVariant)
                .border(1.dp, theme.surfaceVariant.copy(alpha = 0.5f), RoundedCornerShape(4.dp, 12.dp, 12.dp, 12.dp))
                .padding(10.dp)
        ) {
            Column {
                if (msg.isStreaming && !isStreamingDone) {
                    StreamingText(
                        text = msg.text,
                        theme = theme,
                        onDone = { isStreamingDone = true }
                    )
                } else {
                    Text(
                        text = msg.text,
                        fontSize = 11.sp,
                        color = theme.textPrimary,
                        lineHeight = 15.sp
                    )
                }

                // Inline citations and follow-up tools (only when stream is done)
                if (isStreamingDone) {
                    Spacer(modifier = Modifier.height(8.dp))

                    // Citation domains chips (just like the React preview!)
                    FlowRow(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        CitationChip("scoopdata.io", theme)
                        CitationChip("trends.google.com", theme)
                    }

                    Spacer(modifier = Modifier.height(8.dp))

                    // Action tools row: Copy, Retry, Like, Dislike
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        IconButton(
                            onClick = { clipboardManager.setText(AnnotatedString(msg.text)) },
                            modifier = Modifier.size(24.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Default.ContentCopy,
                                contentDescription = "Copy",
                                tint = theme.textSecondary,
                                modifier = Modifier.size(13.dp)
                            )
                        }

                        IconButton(
                            onClick = onResend,
                            modifier = Modifier.size(24.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Default.Refresh,
                                contentDescription = "Retry",
                                tint = theme.textSecondary,
                                modifier = Modifier.size(13.dp)
                            )
                        }

                        IconButton(
                            onClick = {},
                            modifier = Modifier.size(24.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Default.ThumbUp,
                                contentDescription = "Like",
                                tint = theme.textSecondary,
                                modifier = Modifier.size(13.dp)
                            )
                        }

                        IconButton(
                            onClick = {},
                            modifier = Modifier.size(24.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Default.ThumbDown,
                                contentDescription = "Dislike",
                                tint = theme.textSecondary,
                                modifier = Modifier.size(13.dp)
                            )
                        }

                        // Collapsible detailed sources accordion toggle
                        Spacer(modifier = Modifier.weight(1f))
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .clip(RoundedCornerShape(4.dp))
                                .clickable { isSourcesOpen = !isSourcesOpen }
                                .padding(horizontal = 4.dp, vertical = 2.dp)
                        ) {
                            Text(
                                text = "2 sources",
                                fontSize = 10.sp,
                                color = theme.textSecondary
                            )
                            Icon(
                                imageVector = if (isSourcesOpen) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                                contentDescription = "Arrow",
                                tint = theme.textSecondary,
                                modifier = Modifier.size(12.dp)
                            )
                        }
                    }

                    // Collapsible detailed sources accordion
                    AnimatedVisibility(
                        visible = isSourcesOpen,
                        enter = expandVertically() + fadeIn(),
                        exit = shrinkVertically() + fadeOut()
                    ) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 6.dp)
                                .background(theme.background, RoundedCornerShape(6.dp))
                                .padding(6.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            SourceDetailRow("Scoop Data", "scoopdata.io", theme)
                            SourceDetailRow("Trends Index", "trends.google.com", theme)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CitationChip(domain: String, theme: IdeTheme) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(4.dp))
            .background(theme.background)
            .border(1.dp, theme.surfaceVariant, RoundedCornerShape(4.dp))
            .padding(horizontal = 5.dp, vertical = 2.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(theme.primary)
            )
            Spacer(modifier = Modifier.width(4.dp))
            Text(
                text = domain,
                fontSize = 9.sp,
                color = theme.textSecondary,
                fontFamily = FontFamily.Monospace
            )
        }
    }
}

@Composable
private fun SourceDetailRow(name: String, domain: String, theme: IdeTheme) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = name,
            fontSize = 10.sp,
            fontWeight = FontWeight.Bold,
            color = theme.textPrimary
        )
        Text(
            text = domain,
            fontSize = 9.sp,
            color = theme.primary,
            fontFamily = FontFamily.Monospace
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun StreamingText(
    text: String,
    theme: IdeTheme,
    modifier: Modifier = Modifier,
    onDone: () -> Unit
) {
    val words = remember(text) { text.split(" ") }
    var displayedWordsCount by remember(text) { mutableStateOf(0) }

    LaunchedEffect(words) {
        displayedWordsCount = 0
        for (i in 1..words.size) {
            delay(55) // Matches WORD_MS = 55 perfectly!
            displayedWordsCount = i
        }
        onDone()
    }

    FlowRow(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Start
    ) {
        words.take(displayedWordsCount).forEachIndexed { index, word ->
            WordToken(word = word, theme = theme, index = index)
        }
    }
}

@Composable
fun WordToken(word: String, theme: IdeTheme, index: Int) {
    val alphaAnim = remember { Animatable(0f) }
    val offsetYAnim = remember { Animatable(8f) }
    val scaleAnim = remember { Animatable(0.92f) }

    LaunchedEffect(word) {
        launch {
            alphaAnim.animateTo(
                targetValue = 1f,
                animationSpec = tween(
                    durationMillis = 420,
                    easing = CubicBezierEasing(0.22f, 0.61f, 0.25f, 1f)
                )
            )
        }
        launch {
            offsetYAnim.animateTo(
                targetValue = 0f,
                animationSpec = tween(
                    durationMillis = 420,
                    easing = CubicBezierEasing(0.22f, 0.61f, 0.25f, 1f)
                )
            )
        }
        launch {
            scaleAnim.animateTo(
                targetValue = 1f,
                animationSpec = tween(
                    durationMillis = 420,
                    easing = CubicBezierEasing(0.22f, 0.61f, 0.25f, 1f)
                )
            )
        }
    }

    Text(
        text = "$word ",
        fontSize = 11.sp,
        color = theme.textPrimary,
        lineHeight = 15.sp,
        modifier = Modifier
            .graphicsLayer {
                alpha = alphaAnim.value
                translationY = offsetYAnim.value
                scaleX = scaleAnim.value
                scaleY = scaleAnim.value
            }
    )
}

@Composable
private fun AgentChip(label: String, theme: IdeTheme, index: Int, onClick: () -> Unit) {
    val alphaAnim = remember { Animatable(0f) }
    val offsetYAnim = remember { Animatable(10f) }

    LaunchedEffect(label) {
        delay(index * 90L) // Staggered entry animation exactly like React!
        launch {
            alphaAnim.animateTo(1f, tween(350, easing = CubicBezierEasing(0.23f, 1f, 0.32f, 1f)))
        }
        launch {
            offsetYAnim.animateTo(0f, tween(350, easing = CubicBezierEasing(0.23f, 1f, 0.32f, 1f)))
        }
    }

    Box(
        modifier = Modifier
            .graphicsLayer {
                alpha = alphaAnim.value
                translationY = offsetYAnim.value
            }
            .clip(RoundedCornerShape(8.dp))
            .background(theme.surfaceVariant)
            .border(1.dp, theme.surfaceVariant.copy(alpha = 0.8f), RoundedCornerShape(8.dp))
            .clickable { onClick() }
            .padding(horizontal = 8.dp, vertical = 5.dp)
    ) {
        Text(
            text = label, 
            fontSize = 9.5.sp, 
            fontWeight = FontWeight.Medium,
            color = theme.textPrimary
        )
    }
}
