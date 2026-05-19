package com.ct106.fluxremote.ui.screens

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
import com.ct106.fluxremote.R
import com.ct106.fluxremote.core.RemoteAPIClient
import com.ct106.fluxremote.model.NginxSite
import com.ct106.fluxremote.ui.components.*
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NginxScreen(
    apiClient: RemoteAPIClient,
    onEditSite: (NginxSite?) -> Unit,
    onBack: () -> Unit
) {
    var isLoading by remember { mutableStateOf(false) }
    
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }

    val sites = apiClient.nginxSites
    val isRunning = apiClient.isNginxRunning
    val pids = apiClient.nginxPids
    val binPath = apiClient.nginxBinPath

    // State for Sheets and Dialogs
    var siteToAction by remember { mutableStateOf<Pair<NginxSite, String>?>(null) }
    var serviceActionToConfirm by remember { mutableStateOf<String?>(null) }

    fun fetchData() {
        scope.launch {
            isLoading = true
            try {
                val api = apiClient.getApi() ?: return@launch
                val response = api.getNginxSites()
                if (response.isSuccessful) {
                    apiClient.nginxSites = response.body()?.data ?: emptyList()
                    apiClient.isNginxRunning = response.body()?.running
                    apiClient.nginxPids = response.body()?.pids ?: emptyList()
                    apiClient.nginxBinPath = response.body()?.binPath ?: ""
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
            isLoading = false
        }
    }

    fun performServiceAction(action: String) {
        scope.launch {
            try {
                val api = apiClient.getApi() ?: return@launch
                val response = api.nginxAction(mapOf("action" to action))
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

    fun performSiteAction(action: String, site: NginxSite) {
        scope.launch {
            try {
                val api = apiClient.getApi() ?: return@launch
                val response = api.nginxSiteAction(mapOf("action" to action, "filename" to site.name))
                if (response.isSuccessful) {
                    fetchData()
                } else {
                    snackbarHostState.showSnackbar("Action failed: ${response.code()}")
                }
            } catch (e: Exception) {
                snackbarHostState.showSnackbar(e.localizedMessage ?: "Network error")
            }
        }
    }

    LaunchedEffect(Unit) {
        if (sites.isEmpty() || isRunning == null) {
            fetchData()
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.nginx_mgmt)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.Menu, contentDescription = stringResource(R.string.modules))
                    }
                },
                actions = {
                    IconButton(onClick = { onEditSite(null) }) {
                        Icon(Icons.Default.Add, contentDescription = stringResource(R.string.add))
                    }
                    IconButton(onClick = { fetchData() }) {
                        Icon(Icons.Default.Refresh, contentDescription = stringResource(R.string.refresh))
                    }
                }
            )
        }
    ) { padding ->
        if (isLoading && sites.isEmpty()) {
            LoadingView(Modifier.padding(padding))
        } else {
            Column(Modifier.padding(padding).fillMaxSize().background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f))) {
                // Header with status
                Card(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
                ) {
                    Column(Modifier.padding(16.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            StatusBadge(status = if (isRunning == true) "running" else "offline", size = 16, showLabel = true)
                            Spacer(Modifier.weight(1f))
                            if (pids.isNotEmpty()) {
                                Text("${stringResource(R.string.common_pids)}: ${pids.joinToString(", ")}", style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                            }
                        }
                        if (binPath.isNotEmpty()) {
                            Spacer(Modifier.height(8.dp))
                            Text(binPath, style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                        }
                        
                        Spacer(Modifier.height(16.dp))
                        
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            val running = isRunning == true
                            ActionIconButton(
                                icon = if (running) Icons.Default.Stop else Icons.Default.PlayArrow,
                                color = if (running) Color.Red else Color(0xFF4CAF50),
                                onClick = { serviceActionToConfirm = if (running) "stop" else "start" },
                                label = if (running) stringResource(R.string.stop) else stringResource(R.string.start)
                            )
                            ActionIconButton(
                                icon = Icons.Default.Refresh,
                                color = Color(0xFFFFA000),
                                onClick = { serviceActionToConfirm = "restart" },
                                label = stringResource(R.string.restart)
                            )
                        }
                    }
                }

                LazyColumn(Modifier.fillMaxSize()) {
                    itemsIndexed(sites) { index, site ->
                        NginxSiteCard(
                            site = site,
                            onClick = { onEditSite(site) },
                            onToggle = { 
                                val action = if (site.status == "enabled") "disable" else "enable"
                                performSiteAction(action, site)
                            },
                            onDelete = { siteToAction = site to "delete" }
                        )
                        if (index < sites.size - 1) {
                            HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp), thickness = 0.5.dp, color = Color.Gray.copy(alpha = 0.2f))
                        }
                    }
                }
            }
        }
    }

    // Site Action Confirmation
    siteToAction?.let { (site, action) ->
        ConfirmationDialog(
            title = stringResource(R.string.delete),
            message = stringResource(R.string.nginx_confirm_delete_site, site.name),
            onConfirm = { performSiteAction("delete", site) },
            onDismiss = { siteToAction = null },
            isDestructive = true
        )
    }

    // Service Action Confirmation
    serviceActionToConfirm?.let { action ->
        val title = when (action) {
            "stop" -> stringResource(R.string.stop)
            "restart" -> stringResource(R.string.restart)
            else -> stringResource(R.string.start)
        }
        val message = when (action) {
            "stop" -> stringResource(R.string.nginx_confirm_stop)
            "restart" -> stringResource(R.string.nginx_confirm_restart)
            else -> stringResource(R.string.nginx_confirm_start)
        }
        ConfirmationDialog(
            title = title,
            message = message,
            onConfirm = { performServiceAction(action) },
            onDismiss = { serviceActionToConfirm = null },
            isDestructive = action == "stop"
        )
    }
}

@Composable
fun NginxSiteCard(
    site: NginxSite, 
    onClick: () -> Unit,
    onToggle: () -> Unit,
    onDelete: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .background(MaterialTheme.colorScheme.surface)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        StatusBadge(status = if (site.status == "enabled") "running" else "offline", size = 14)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(text = site.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(text = "${site.serverName}:${site.port}", style = MaterialTheme.typography.bodySmall, color = Color.Gray)
        }
        
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            val isEnabled = site.status == "enabled"
            ActionIconButton(
                icon = if (isEnabled) Icons.Default.Pause else Icons.Default.PlayArrow,
                color = if (isEnabled) Color(0xFFFFA000) else Color(0xFF4CAF50),
                onClick = onToggle
            )
            ActionIconButton(
                icon = Icons.Default.Delete,
                color = Color.Red,
                onClick = onDelete
            )
        }
    }
}
