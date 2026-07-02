package com.ct106.flux_remote.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ct106.flux_remote.R
import com.ct106.flux_remote.core.ServerManager
import com.ct106.flux_remote.core.ServerConfig

@Composable
fun StatusBadge(
    status: String,
    modifier: Modifier = Modifier,
    size: Int = 12,
    showLabel: Boolean = false
) {
    val color = when (status.lowercase()) {
        "running", "online", "up", "enabled" -> Color(0xFF4CAF50)
        "exited", "offline", "down", "disabled" -> Color(0xFFF44336)
        "starting", "restarting" -> Color(0xFFFFC107)
        else -> Color.Gray
    }

    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Surface(
            modifier = Modifier.size(size.dp),
            shape = CircleShape,
            color = color.copy(alpha = 0.2f)
        ) {
            Box(contentAlignment = Alignment.Center) {
                Surface(
                    modifier = Modifier.size((size / 2).dp),
                    shape = CircleShape,
                    color = color
                ) {}
            }
        }
        if (showLabel) {
            Text(
                text = status.replaceFirstChar { it.uppercase() },
                fontSize = (size * 0.9f).sp,
                color = color,
                fontWeight = FontWeight.Medium
            )
        }
    }
}

@Composable
fun ActionIconButton(
    icon: ImageVector,
    color: Color,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    label: String? = null,
    isLoading: Boolean = false,
    contentDescription: String? = null,
    enabled: Boolean = true
) {
    Surface(
        onClick = onClick,
        modifier = modifier.height(32.dp),
        shape = CircleShape,
        color = color.copy(alpha = 0.1f),
        contentColor = color,
        enabled = enabled && !isLoading
    ) {
        Row(
            modifier = Modifier.padding(horizontal = if (label != null) 12.dp else 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center
        ) {
            if (isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(16.dp),
                    color = color,
                    strokeWidth = 2.dp
                )
            } else {
                Icon(
                    imageVector = icon,
                    contentDescription = contentDescription,
                    modifier = Modifier.size(16.dp)
                )
            }
            if (label != null) {
                Spacer(Modifier.width(6.dp))
                Text(label, fontSize = 12.sp, fontWeight = FontWeight.Medium)
            }
        }
    }
}

@Composable
fun DetailRow(
    label: String,
    value: String,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurface
        )
    }
}

@Composable
fun LoadingView(
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        CircularProgressIndicator()
    }
}

@Composable
fun ServerSwitcherTitle(
    title: String,
    serverManager: ServerManager,
    onSelectServer: (ServerConfig) -> Unit,
    onManageServers: () -> Unit,
    modifier: Modifier = Modifier
) {
    val servers by serverManager.servers.collectAsState()
    val selectedServerId by serverManager.selectedServerId.collectAsState()
    val selectedServer = serverManager.getSelectedServer()
    var expanded by remember { mutableStateOf(false) }

    Box(modifier = modifier) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .clickable { expanded = true }
                .padding(end = 4.dp)
        ) {
            Text(
                text = selectedServer?.name ?: title,
                style = MaterialTheme.typography.titleMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.widthIn(max = 220.dp)
            )
            Icon(Icons.Default.ArrowDropDown, contentDescription = null)
        }

        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            servers.forEach { server ->
                DropdownMenuItem(
                    text = { Text(server.name) },
                    onClick = {
                        expanded = false
                        onSelectServer(server)
                    },
                    leadingIcon = { Icon(Icons.Default.Dns, contentDescription = null) },
                    trailingIcon = {
                        if (server.id == selectedServerId) {
                            Icon(Icons.Default.Check, contentDescription = null)
                        }
                    }
                )
            }
            HorizontalDivider()
            DropdownMenuItem(
                text = { Text(stringResource(R.string.manage_servers)) },
                onClick = {
                    expanded = false
                    onManageServers()
                },
                leadingIcon = { Icon(Icons.Default.Settings, contentDescription = null) }
            )
        }
    }
}

@Composable
fun ConfirmationDialog(
    title: String,
    message: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
    confirmText: String = stringResource(R.string.common_ok),
    dismissText: String = stringResource(R.string.common_cancel),
    isDestructive: Boolean = false
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = {
            TextButton(
                onClick = {
                    onConfirm()
                    onDismiss()
                }
            ) {
                Text(
                    text = confirmText,
                    color = if (isDestructive) Color.Red else MaterialTheme.colorScheme.primary
                )
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(dismissText)
            }
        }
    )
}
@Composable
fun MetricChartCard(
    title: String,
    value: String,
    subValue: String,
    color: Color,
    data: List<Double>,
    domain: ClosedFloatingPointRange<Double>
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(title, style = MaterialTheme.typography.titleSmall)
                Spacer(Modifier.weight(1f))
                Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = color)
            }
            Text(subValue, style = MaterialTheme.typography.labelSmall, color = Color.Gray)
            Spacer(Modifier.height(12.dp))
            
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(60.dp)
            ) {
                androidx.compose.foundation.Canvas(modifier = Modifier.fillMaxSize()) {
                    if (data.isEmpty()) return@Canvas
                    
                    val path = androidx.compose.ui.graphics.Path()
                    val width = size.width
                    val height = size.height
                    val maxVal = domain.endInclusive
                    val minVal = domain.start
                    val range = maxVal - minVal
                    
                    // Fixed 60 points for 2 minutes (at 2s interval)
                    val maxPoints = 60
                    val stepX = width / (maxPoints - 1)
                    
                    // Draw from right to left
                    data.asReversed().forEachIndexed { index, d ->
                        val x = width - (index * stepX)
                        val normalizedY = ((d - minVal) / range).coerceIn(0.0, 1.0)
                        val y = height - (normalizedY.toFloat() * height)
                        
                        if (index == 0) {
                            path.moveTo(x, y)
                        } else {
                            path.lineTo(x, y)
                        }
                    }
                    
                    drawPath(
                        path = path,
                        color = color,
                        style = androidx.compose.ui.graphics.drawscope.Stroke(
                            width = 2.dp.toPx(),
                            cap = androidx.compose.ui.graphics.StrokeCap.Round,
                            join = androidx.compose.ui.graphics.StrokeJoin.Round
                        )
                    )
                    
                    // Fill gradient
                    val fillPath = androidx.compose.ui.graphics.Path().apply {
                        addPath(path)
                        val lastX = width - ((data.size - 1) * stepX)
                        lineTo(lastX, height)
                        lineTo(width, height)
                        close()
                    }
                    
                    drawPath(
                        path = fillPath,
                        brush = androidx.compose.ui.graphics.Brush.verticalGradient(
                            colors = listOf(color.copy(alpha = 0.3f), color.copy(alpha = 0f))
                        )
                    )
                }
            }
        }
    }
}

@Composable
fun NetworkChartCard(
    netIn: Double,
    netOut: Double,
    data: List<com.ct106.flux_remote.model.MetricPoint>
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column(Modifier.padding(16.dp)) {
            Text(stringResource(R.string.network), style = MaterialTheme.typography.titleSmall)
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Column {
                    Text(stringResource(R.string.network_in), style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                    Text("${netIn.toInt()} KB/s", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold, color = Color(0xFF4CAF50))
                }
                Column {
                    Text(stringResource(R.string.network_out), style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                    Text("${netOut.toInt()} KB/s", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold, color = Color(0xFF2196F3))
                }
            }
            Spacer(Modifier.height(12.dp))
            
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(60.dp)
            ) {
                androidx.compose.foundation.Canvas(modifier = Modifier.fillMaxSize()) {
                    if (data.isEmpty()) return@Canvas
                    
                    val width = size.width
                    val height = size.height
                    
                    // Scale based on max value in history
                    val maxIn = data.maxOfOrNull { it.netIn } ?: 0.0
                    val maxOut = data.maxOfOrNull { it.netOut } ?: 0.0
                    val maxVal = maxOf(maxIn, maxOut, 10.0) * 1.2 // 20% margin
                    
                    val maxPoints = 60
                    val stepX = width / (maxPoints - 1)
                    
                    fun drawLine(points: List<Double>, color: Color) {
                        val path = androidx.compose.ui.graphics.Path()
                        points.asReversed().forEachIndexed { index, d ->
                            val x = width - (index * stepX)
                            val normalizedY = (d / maxVal).coerceIn(0.0, 1.0)
                            val y = height - (normalizedY.toFloat() * height)
                            
                            if (index == 0) {
                                path.moveTo(x, y)
                            } else {
                                path.lineTo(x, y)
                            }
                        }
                        drawPath(
                            path = path,
                            color = color,
                            style = androidx.compose.ui.graphics.drawscope.Stroke(
                                width = 2.dp.toPx(),
                                cap = androidx.compose.ui.graphics.StrokeCap.Round,
                                join = androidx.compose.ui.graphics.StrokeJoin.Round
                            )
                        )
                        
                        // Fill
                        val fillPath = androidx.compose.ui.graphics.Path().apply {
                            addPath(path)
                            val lastX = width - ((points.size - 1) * stepX)
                            lineTo(lastX, height)
                            lineTo(width, height)
                            close()
                        }
                        drawPath(
                            path = fillPath,
                            brush = androidx.compose.ui.graphics.Brush.verticalGradient(
                                colors = listOf(color.copy(alpha = 0.2f), color.copy(alpha = 0f))
                            )
                        )
                    }
                    
                    drawLine(data.map { it.netIn }, Color(0xFF4CAF50))
                    drawLine(data.map { it.netOut }, Color(0xFF2196F3))
                }
            }
        }
    }
}



@Composable
fun SummaryCard(
    modifier: Modifier = Modifier,
    icon: ImageVector,
    title: String,
    value: String,
    subValue: String,
    extra: String = "",
    onClick: () -> Unit
) {
    Card(
        modifier = modifier.clickable(onClick = onClick),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column(Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp), tint = MaterialTheme.colorScheme.primary)
                Text(
                    title,
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.Gray,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Spacer(Modifier.height(8.dp))
            Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Text(subValue, style = MaterialTheme.typography.labelSmall, color = Color.Gray)
            if (extra.isNotEmpty()) {
                Text(extra, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
fun SystemDetailTile(
    modifier: Modifier = Modifier,
    icon: ImageVector,
    label: String,
    value: String
) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp), tint = MaterialTheme.colorScheme.secondary)
            Spacer(Modifier.width(12.dp))
            Column {
                Text(label, style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, maxLines = 1)
            }
        }
    }
}

@Composable
fun getLocalizedCategory(category: String): String {
    return when (category.lowercase()) {
        "system" -> stringResource(R.string.cat_system)
        "web" -> stringResource(R.string.cat_web)
        "app" -> stringResource(R.string.cat_app)
        "user" -> stringResource(R.string.cat_user)
        else -> category.replaceFirstChar { it.uppercase() }
    }
}
