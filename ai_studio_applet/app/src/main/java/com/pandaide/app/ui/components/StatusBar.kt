package com.pandaide.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountTree
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pandaide.app.model.IdeTheme

@Composable
fun StatusBar(
    activeLanguage: String,
    currentLine: Int,
    currentCol: Int,
    gitBranch: String,
    theme: IdeTheme
) {
    Surface(
        color = theme.primary,
        contentColor = theme.background,
        modifier = Modifier
            .fillMaxWidth()
            .height(24.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Default.AccountTree,
                    contentDescription = "Branch",
                    tint = theme.background,
                    modifier = Modifier.size(12.dp)
                )
                Spacer(modifier = Modifier.width(4.dp))
                Text(
                    text = gitBranch,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    color = theme.background
                )
                Spacer(modifier = Modifier.width(12.dp))
                Icon(
                    imageVector = Icons.Default.AutoAwesome,
                    contentDescription = "AI",
                    tint = theme.background,
                    modifier = Modifier.size(12.dp)
                )
                Spacer(modifier = Modifier.width(4.dp))
                Text(
                    text = "Panda AI Ready",
                    fontSize = 10.sp,
                    color = theme.background
                )
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "Ln $currentLine, Col $currentCol",
                    fontSize = 10.sp,
                    color = theme.background
                )
                Spacer(modifier = Modifier.width(12.dp))
                Text(
                    text = "UTF-8",
                    fontSize = 10.sp,
                    color = theme.background
                )
                Spacer(modifier = Modifier.width(12.dp))
                Text(
                    text = activeLanguage,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    color = theme.background
                )
            }
        }
    }
}
