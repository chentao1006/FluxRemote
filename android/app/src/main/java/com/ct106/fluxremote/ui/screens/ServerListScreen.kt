package com.ct106.flux_remote.ui.screens

import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.unit.dp
import com.ct106.flux_remote.R
import com.ct106.flux_remote.core.RemoteAPIClient
import com.ct106.flux_remote.core.ServerConfig
import com.ct106.flux_remote.core.ServerManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ServerListScreen(
    serverManager: ServerManager,
    apiClient: RemoteAPIClient,
    onAddServer: () -> Unit,
    onEditServer: (ServerConfig) -> Unit,
    onSelectServer: (ServerConfig) -> Unit
) {
    val servers by serverManager.servers.collectAsState()
    val selectedServerId by serverManager.selectedServerId.collectAsState()
    val reachabilityStatuses by serverManager.reachabilityStatuses.collectAsState()
    val scope = rememberCoroutineScope()
    val context = androidx.compose.ui.platform.LocalContext.current

    var isRefreshingAll by remember { mutableStateOf(false) }

    val refreshAll = {
        if (!isRefreshingAll && servers.isNotEmpty()) {
            isRefreshingAll = true
            scope.launch {
                var pendingCount = servers.size
                
                servers.forEach { server ->
                    val serverTopic = server.mqttTopic
                    val serverKey = server.mqttKey
                    // A global pairing belongs to one Mac. Never use it to refresh arbitrary
                    // saved servers, or it will overwrite every URL with that Mac's URL.
                    if (serverTopic != null && serverKey != null) {
                        com.ct106.flux_remote.core.MQTTRemoteSync.getInstance(context)
                            .fetchLatestData(serverTopic, serverKey, timeoutMs = 15000) { data ->
                                scope.launch {
                                    val newUrl = data?.url
                                    if (newUrl != null && newUrl != server.url) {
                                        server.url = newUrl
                                        if (!data.user.isNullOrEmpty()) server.username = data.user
                                        if (!data.hostname.isNullOrEmpty() && server.name == "Remote Mac") server.name = data.hostname
                                        if (!data.pass.isNullOrEmpty()) {
                                            serverManager.setPassword(server.id, data.pass)
                                        }
                                        serverManager.updateServer(server)
                                    }
                                    pendingCount--
                                    if (pendingCount <= 0) {
                                        isRefreshingAll = false
                                    }
                                }
                            }
                    } else {
                        pendingCount--
                    }
                }
                if (pendingCount <= 0) {
                    isRefreshingAll = false
                }
            }
        }
    }

    LaunchedEffect(servers.isNotEmpty()) {
        if (servers.isNotEmpty()) {
            refreshAll()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.server_list)) },
                actions = {
                    if (isRefreshingAll) {
                        CircularProgressIndicator(
                            modifier = Modifier
                                .padding(end = 16.dp)
                                .size(24.dp),
                            strokeWidth = 2.dp
                        )
                    } else {
                        IconButton(onClick = { refreshAll() }) {
                            Icon(Icons.Default.Refresh, contentDescription = stringResource(R.string.refresh))
                        }
                    }
                    IconButton(onClick = { onAddServer() }) {
                        Icon(Icons.Default.Add, contentDescription = stringResource(R.string.add_server))
                    }
                }
            )
        }
    ) { padding ->
        var loadingServerId by remember { mutableStateOf<String?>(null) }

        // Probe each server's reachability whenever the list changes
        LaunchedEffect(servers) {
            servers.forEach { server ->
                launch {
                    val isOffline = withContext(Dispatchers.IO) {
                        try {
                            val conn = URL(server.baseURL).openConnection() as HttpURLConnection
                            conn.connectTimeout = 4000
                            conn.readTimeout = 4000
                            conn.requestMethod = "HEAD"
                            conn.connect()
                            val code = conn.responseCode
                            conn.disconnect()
                            // 5xx = service unavailable/error = treat as offline
                            code !in 200..499
                        } catch (e: Exception) {
                            true // unreachable
                        }
                    }
                    serverManager.updateReachability(server.id, isOffline)
                }
            }
        }

        if (servers.isEmpty()) {
            EmptyServerState(onAddServer, modifier = Modifier.padding(padding))
        } else {
            LazyColumn(modifier = Modifier.padding(padding)) {
                items(servers) { server ->
                    ServerRow(
                        server = server,
                        isSelected = server.id == selectedServerId,
                        isOffline = reachabilityStatuses[server.id],
                        isUpdating = loadingServerId == server.id,
                        onSelect = {
                            if (loadingServerId != null) return@ServerRow // block while any server is loading
                            if (server.url.isEmpty()) {
                                onEditServer(server)
                            } else {
                                scope.launch {
                                    loadingServerId = server.id
                                    try {
                                        if (serverManager.isServerAuthenticated(server.id)) {
                                            loadingServerId = null
                                            onSelectServer(server)
                                        } else {
                                            val password = serverManager.getPassword(server.id)
                                            if (server.autoLogin && password != null) {
                                                // Try auto login
                                                var success = apiClient.login(
                                                    mapOf("username" to (server.username ?: ""), "password" to password),
                                                    server
                                                )
                                                if (success) {
                                                    loadingServerId = null
                                                    onSelectServer(server)
                                                } else {
                                                    val mqttSync = com.ct106.flux_remote.core.MQTTRemoteSync.getInstance(context)
                                                    val serverTopic = server.mqttTopic
                                                    val serverKey = server.mqttKey
                                                    // A global pairing must not be applied to another saved Mac.
                                                    if (serverTopic != null && serverKey != null) {
                                                            mqttSync.fetchLatestData(serverTopic, serverKey, timeoutMs = 15000) { data ->
                                                                scope.launch {
                                                                    val newUrl = data?.url
                                                                    if (newUrl != null && newUrl != server.url) {
                                                                        server.url = newUrl
                                                                        if (!data.user.isNullOrEmpty()) server.username = data.user
                                                                        if (!data.hostname.isNullOrEmpty() && server.name == "Remote Mac") server.name = data.hostname
                                                                        if (!data.pass.isNullOrEmpty()) {
                                                                            serverManager.setPassword(server.id, data.pass)
                                                                        }
                                                                        serverManager.updateServer(server)
                                                                    }
                                                                    // Always retry login after MQTT fetch (URL or session may have changed)
                                                                    if (newUrl != null) {
                                                                        val testPass = if (!data.pass.isNullOrEmpty()) data.pass else password
                                                                        success = apiClient.login(
                                                                            mapOf("username" to (server.username ?: ""), "password" to testPass),
                                                                            server
                                                                        )
                                                                    }
                                                                    if (success) {
                                                                        onSelectServer(server)
                                                                    } else {
                                                                        onEditServer(server)
                                                                    }
                                                                    loadingServerId = null
                                                                }
                                                            }
                                                            return@launch // Let mqtt callback handle loadingServerId
                                                    }
                                                    loadingServerId = null
                                                    onEditServer(server)
                                                }
                                            } else {
                                                loadingServerId = null
                                                onEditServer(server)
                                            }
                                        }
                                    } catch (e: Exception) {
                                        loadingServerId = null
                                        e.printStackTrace()
                                    }
                                }
                            }
                        },
                        onEdit = { onEditServer(server) },
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

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun ServerRow(
    server: ServerConfig,
    isSelected: Boolean,
    isOffline: Boolean?,
    isUpdating: Boolean = false,
    onSelect: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {
    var showMenu by remember { mutableStateOf(false) }

    Box {
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
            supportingContent = {
                if (isUpdating) {
                    Text(
                        stringResource(R.string.syncing_url),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary
                    )
                } else {
                    Text(server.url)
                }
            },
            leadingContent = {
                when (isOffline) {
                    null -> CircularProgressIndicator(
                        modifier = Modifier.size(12.dp),
                        strokeWidth = 1.5.dp
                    )
                    false -> Surface(
                        modifier = Modifier.size(12.dp),
                        shape = MaterialTheme.shapes.extraSmall,
                        color = Color.Green
                    ) {}
                    true -> Surface(
                        modifier = Modifier.size(12.dp),
                        shape = MaterialTheme.shapes.extraSmall,
                        color = Color.Red
                    ) {}
                }
            },
            trailingContent = {
                if (isUpdating) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp
                    )
                } else if (isSelected) {
                    Icon(Icons.Default.Check, contentDescription = stringResource(R.string.selected))
                }
            },
            modifier = Modifier.combinedClickable(
                onClick = onSelect,
                onLongClick = { showMenu = true }
            )
        )

        DropdownMenu(
            expanded = showMenu,
            onDismissRequest = { showMenu = false }
        ) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.edit)) },
                onClick = {
                    showMenu = false
                    onEdit()
                },
                leadingIcon = { Icon(Icons.Default.Edit, contentDescription = null) }
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.delete)) },
                onClick = {
                    showMenu = false
                    onDelete()
                },
                leadingIcon = { Icon(Icons.Default.Delete, contentDescription = null) }
            )
        }
    }
}

@Composable
fun EmptyServerState(onAddServer: () -> Unit, modifier: Modifier = Modifier) {
    val uriHandler = LocalUriHandler.current

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(stringResource(R.string.no_servers), style = MaterialTheme.typography.headlineMedium)
        Spacer(Modifier.height(12.dp))
        Text(
            text = stringResource(R.string.server_setup_description),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center
        )
        Spacer(Modifier.height(16.dp))
        OutlinedButton(onClick = { uriHandler.openUri("https://flux.ct106.com/") }) {
            Text(
                text = "flux.ct106.com",
                style = MaterialTheme.typography.titleLarge
            )
        }
        Spacer(Modifier.height(24.dp))
        Button(onClick = onAddServer) {
            Icon(Icons.Default.Add, contentDescription = null)
            Spacer(Modifier.width(8.dp))
            Text(stringResource(R.string.add_first_server))
        }
    }
}
