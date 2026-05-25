package com.ct106.flux_remote.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ct106.flux_remote.R
import com.ct106.flux_remote.core.RemoteAPIClient
import com.ct106.flux_remote.model.LaunchAgentItem
import com.ct106.flux_remote.ui.components.*
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LaunchAgentScreen(
    apiClient: RemoteAPIClient,
    onEditAgent: (LaunchAgentItem?) -> Unit,
    onBack: () -> Unit
) {
    var isLoading by remember { mutableStateOf(false) }
    
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }
    
    val agents = apiClient.agentItems

    // State for Sheets and Dialogs
    var agentToAction by remember { mutableStateOf<Pair<LaunchAgentItem, String>?>(null) }

    fun fetchData() {
        scope.launch {
            isLoading = true
            try {
                val api = apiClient.getApi() ?: return@launch
                val response = api.getLaunchAgents()
                if (response.isSuccessful) {
                    apiClient.agentItems = response.body()?.data ?: emptyList()
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
            isLoading = false
        }
    }

    fun performAction(action: String, path: String) {
        scope.launch {
            try {
                val api = apiClient.getApi() ?: return@launch
                val response = api.launchAgentAction(mapOf("action" to action, "filePath" to path))
                if (response.isSuccessful && response.body()?.success == true) {
                    fetchData()
                } else {
                    val error = response.body()?.details ?: response.body()?.error ?: "Action failed"
                    snackbarHostState.showSnackbar(error)
                }
            } catch (e: Exception) {
                snackbarHostState.showSnackbar(e.localizedMessage ?: "Network error")
            }
        }
    }

    LaunchedEffect(Unit) {
        if (agents.isEmpty()) {
            fetchData()
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.launchagents_mgmt)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.Menu, contentDescription = stringResource(R.string.modules))
                    }
                },
                actions = {
                    IconButton(onClick = { onEditAgent(null) }) {
                        Icon(Icons.Default.Add, contentDescription = stringResource(R.string.add))
                    }
                    IconButton(onClick = { fetchData() }) {
                        Icon(Icons.Default.Refresh, contentDescription = stringResource(R.string.refresh))
                    }
                }
            )
        }
    ) { padding ->
        if (isLoading && agents.isEmpty()) {
            LoadingView(Modifier.padding(padding))
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f))
            ) {
                itemsIndexed(agents) { index, agent ->
                    LaunchAgentCard(
                        agent = agent,
                        onClick = { onEditAgent(agent) },
                        onAction = { action -> 
                            if (action == "load" || action == "unload" || action == "reload") {
                                performAction(action, agent.path)
                            } else {
                                agentToAction = agent to action
                            }
                        }
                    )
                    if (index < agents.size - 1) {
                        HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp), thickness = 0.5.dp, color = Color.Gray.copy(alpha = 0.2f))
                    }
                }
            }
        }
    }

    // Action Confirmation
    agentToAction?.let { (agent, action) ->
        val title = if (action == "load") stringResource(R.string.load) else stringResource(R.string.delete)
        val message = if (action == "load") stringResource(R.string.agent_confirm_load, agent.name) else stringResource(R.string.agent_confirm_delete, agent.name)
        ConfirmationDialog(
            title = title,
            message = message,
            onConfirm = { performAction(action, agent.path) },
            onDismiss = { agentToAction = null },
            isDestructive = action == "delete" || action == "unload"
        )
    }
}

@Composable
fun LaunchAgentCard(agent: LaunchAgentItem, onClick: () -> Unit, onAction: (String) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .background(MaterialTheme.colorScheme.surface)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        StatusBadge(status = if (agent.isLoaded) "running" else "offline", size = 14)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(text = agent.name.replace(".plist", ""), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Text(text = agent.path, style = MaterialTheme.typography.labelSmall, color = Color.Gray, maxLines = 1)
        }
        
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            val isLoaded = agent.isLoaded
            ActionIconButton(
                icon = if (isLoaded) Icons.Default.Stop else Icons.Default.PlayArrow,
                color = if (isLoaded) Color(0xFFFFA000) else Color(0xFF4CAF50),
                onClick = { onAction(if (isLoaded) "unload" else "load") }
            )
            ActionIconButton(
                icon = Icons.Default.Refresh,
                color = Color(0xFF2196F3),
                onClick = { onAction("reload") }
            )
            ActionIconButton(
                icon = Icons.Default.Delete,
                color = Color.Red,
                onClick = { onAction("delete") }
            )
        }
    }
}
