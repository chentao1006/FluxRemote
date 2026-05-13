package com.ct106.fluxremote.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.ct106.fluxremote.R
import com.ct106.fluxremote.core.ServerConfig
import com.ct106.fluxremote.core.ServerManager
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ServerListScreen(
    serverManager: ServerManager,
    onAddServer: () -> Unit,
    onSelectServer: (ServerConfig) -> Unit
) {
    val servers by serverManager.servers.collectAsState()
    val selectedServerId by serverManager.selectedServerId.collectAsState()
    val reachabilityStatuses by serverManager.reachabilityStatuses.collectAsState()
    val scope = rememberCoroutineScope()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.server_list)) },
                actions = {
                    IconButton(onClick = { onAddServer() }) {
                        Icon(Icons.Default.Add, contentDescription = stringResource(R.string.add_server))
                    }
                }
            )
        }
    ) { padding ->
        if (servers.isEmpty()) {
            EmptyServerState(onAddServer, modifier = Modifier.padding(padding))
        } else {
            LazyColumn(modifier = Modifier.padding(padding)) {
                items(servers) { server ->
                    ServerRow(
                        server = server,
                        isSelected = server.id == selectedServerId,
                        isOffline = reachabilityStatuses[server.id],
                        onSelect = {
                            scope.launch {
                                serverManager.selectServer(server)
                                onSelectServer(server)
                            }
                        },
                        onDelete = {
                            scope.launch {
                                serverManager.removeServer(server)
                            }
                        }
                    )
                }
            }
        }
    }
}

@Composable
fun ServerRow(
    server: ServerConfig,
    isSelected: Boolean,
    isOffline: Boolean?,
    onSelect: () -> Unit,
    onDelete: () -> Unit
) {
    ListItem(
        headlineContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(server.name)
                if (server.isLauncher) {
                    Spacer(Modifier.width(8.dp))
                    Surface(
                        color = MaterialTheme.colorScheme.tertiaryContainer,
                        shape = MaterialTheme.shapes.extraSmall
                    ) {
                        Text(
                            stringResource(R.string.launcher),
                            modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp),
                            style = MaterialTheme.typography.labelSmall
                        )
                    }
                }
            }
        },
        supportingContent = { Text(server.url) },
        leadingContent = {
            val statusColor = when (isOffline) {
                false -> Color.Green
                true -> Color.Red
                null -> Color.Gray
            }
            Surface(
                modifier = Modifier.size(12.dp),
                shape = MaterialTheme.shapes.extraSmall,
                color = statusColor
            ) {}
        },
        trailingContent = {
            Row {
                if (isSelected) {
                    Icon(Icons.Default.Check, contentDescription = stringResource(R.string.selected))
                }
                IconButton(onClick = onDelete) {
                    Icon(Icons.Default.Delete, contentDescription = stringResource(R.string.delete))
                }
            }
        },
        modifier = Modifier.clickable { onSelect() }
    )
}

@Composable
fun EmptyServerState(onAddServer: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(stringResource(R.string.no_servers), style = MaterialTheme.typography.headlineMedium)
        Spacer(Modifier.height(16.dp))
        Button(onClick = onAddServer) {
            Icon(Icons.Default.Add, contentDescription = null)
            Spacer(Modifier.width(8.dp))
            Text(stringResource(R.string.add_first_server))
        }
    }
}
