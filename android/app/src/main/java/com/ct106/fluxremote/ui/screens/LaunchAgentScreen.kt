package com.ct106.fluxremote.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ct106.fluxremote.R
import com.ct106.fluxremote.core.RemoteAPIClient
import com.ct106.fluxremote.model.LaunchAgentItem
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LaunchAgentScreen(
    apiClient: RemoteAPIClient,
    onBack: () -> Unit
) {
    var agents by remember { mutableStateOf<List<LaunchAgentItem>>(emptyList()) }
    var isLoading by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun fetchData() {
        scope.launch {
            isLoading = true
            try {
                val api = apiClient.getApi() ?: return@launch
                val response = api.getLaunchAgents()
                if (response.isSuccessful) {
                    agents = response.body()?.data ?: emptyList()
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
            isLoading = false
        }
    }

    LaunchedEffect(Unit) {
        fetchData()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.launchagents_mgmt)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.Menu, contentDescription = stringResource(R.string.modules))
                    }
                },
                actions = {
                    IconButton(onClick = { fetchData() }) {
                        Icon(Icons.Default.Refresh, contentDescription = stringResource(R.string.refresh))
                    }
                }
            )
        }
    ) { padding ->
        if (isLoading && agents.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            LazyColumn(Modifier.padding(padding)) {
                items(agents) { agent ->
                    LaunchAgentRow(agent, onAction = { action ->
                        scope.launch {
                            apiClient.getApi()?.launchAgentAction(mapOf("action" to action, "path" to agent.path))
                            fetchData()
                        }
                    })
                }
            }
        }
    }
}

@Composable
fun LaunchAgentRow(agent: LaunchAgentItem, onAction: (String) -> Unit) {
    ListItem(
        headlineContent = { Text(agent.name) },
        supportingContent = { Text(agent.path, fontSize = 11.sp, color = Color.Gray) },
        leadingContent = {
            val color = if (agent.isLoaded) Color.Green else Color.Gray
            Surface(Modifier.size(10.dp), shape = MaterialTheme.shapes.extraSmall, color = color) {}
        },
        trailingContent = {
            if (agent.isLoaded) {
                IconButton(onClick = { onAction("unload") }) {
                    Icon(Icons.Default.Stop, contentDescription = stringResource(R.string.unload), tint = Color.Red)
                }
            } else {
                IconButton(onClick = { onAction("load") }) {
                    Icon(Icons.Default.PlayArrow, contentDescription = stringResource(R.string.load), tint = Color.Green)
                }
            }
        }
    )
}
