package com.ct106.fluxremote.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.ct106.fluxremote.R
import com.ct106.fluxremote.core.RemoteAPIClient
import com.ct106.fluxremote.core.ServerManager
import com.ct106.fluxremote.model.RemoteSystemStats
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen(
    serverManager: ServerManager,
    apiClient: RemoteAPIClient,
    onNavigateToServers: () -> Unit,
    onNavigate: (String) -> Unit
) {
    val server = serverManager.getSelectedServer()
    var stats by remember { mutableStateOf<RemoteSystemStats?>(null) }
    var isLoading by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun refreshStats() {
        scope.launch {
            isLoading = true
            try {
                val api = apiClient.getApi()
                val response = api?.getStats()
                if (response?.isSuccessful == true) {
                    stats = response.body()?.data
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
            isLoading = false
        }
    }

    LaunchedEffect(server) {
        refreshStats()
    }

    val modules = listOf(
        Triple(stringResource(R.string.docker_mgmt), Icons.Default.DirectionsBoat, "docker"),
        Triple(stringResource(R.string.nginx_mgmt), Icons.Default.Public, "nginx"),
        Triple(stringResource(R.string.process_mgmt), Icons.Default.List, "process"),
        Triple(stringResource(R.string.logs_mgmt), Icons.Default.Description, "logs"),
        Triple(stringResource(R.string.configs_mgmt), Icons.Default.Settings, "configs"),
        Triple(stringResource(R.string.launchagents_mgmt), Icons.Default.PowerSettingsNew, "launchagent")
    )

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(server?.name ?: stringResource(R.string.dashboard)) },
                navigationIcon = {
                    IconButton(onClick = onNavigateToServers) {
                        Icon(Icons.Default.Menu, contentDescription = stringResource(R.string.server_list))
                    }
                },
                actions = {
                    IconButton(onClick = { onNavigate("settings") }) {
                        Icon(Icons.Default.Settings, contentDescription = stringResource(R.string.settings))
                    }
                    IconButton(onClick = { refreshStats() }) {
                        Icon(Icons.Default.Refresh, contentDescription = stringResource(R.string.refresh))
                    }
                }
            )
        }
    ) { padding ->
        if (isLoading && stats == null) {
            Box(modifier = Modifier.fillMaxSize().padding(padding), contentAlignment = androidx.compose.ui.Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .padding(padding)
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                item {
                    Text(stringResource(R.string.modules), style = MaterialTheme.typography.titleMedium)
                }
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        modules.chunked(2).forEach { row ->
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                row.forEach { (name, icon, route) ->
                                    Card(
                                        modifier = Modifier.weight(1f).clickable { onNavigate(route) },
                                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer)
                                    ) {
                                        Column(
                                            modifier = Modifier.padding(16.dp).fillMaxWidth(),
                                            horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally
                                        ) {
                                            Icon(icon, contentDescription = name)
                                            Spacer(Modifier.height(8.dp))
                                            Text(name, style = MaterialTheme.typography.labelSmall)
                                        }
                                    }
                                }
                                if (row.size == 1) Spacer(Modifier.weight(1f))
                            }
                        }
                    }
                }

                item {
                    Text(stringResource(R.string.system_status), style = MaterialTheme.typography.titleMedium)
                }

                stats?.let { s ->
                    item {
                        StatCard(title = stringResource(R.string.hostname), value = s.hostname)
                    }
                    item {
                        StatCard(title = stringResource(R.string.os_version), value = s.osVersion)
                    }
                    item {
                        StatCard(title = stringResource(R.string.load_avg), value = s.loadAvg)
                    }
                    item {
                        StatCard(title = stringResource(R.string.memory), value = "${s.memory.usedMB} MB / ${s.memory.totalMB} MB")
                    }
                    item {
                        StatCard(title = stringResource(R.string.disk_usage), value = s.disk.percent)
                    }
                }
            }
        }
    }
}

@Composable
fun StatCard(title: String, value: String) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(title, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.height(4.dp))
            Text(value, style = MaterialTheme.typography.bodyLarge)
        }
    }
}
