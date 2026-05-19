package com.ct106.fluxremote.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ct106.fluxremote.R
import com.ct106.fluxremote.core.RemoteAPIClient
import com.ct106.fluxremote.model.PortEntry
import com.ct106.fluxremote.model.PortProcessGroup
import com.ct106.fluxremote.ui.components.ActionIconButton
import com.ct106.fluxremote.ui.components.ConfirmationDialog
import com.ct106.fluxremote.ui.components.LoadingView
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PortsScreen(
    apiClient: RemoteAPIClient,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }
    val groups = apiClient.portGroups
    val summary = apiClient.portSummary
    var isLoading by remember { mutableStateOf(false) }
    var searchQuery by remember { mutableStateOf("") }
    var stateFilter by remember { mutableStateOf("all") }
    var groupToActOn by remember { mutableStateOf<PortProcessGroup?>(null) }
    var actionType by remember { mutableStateOf<String?>(null) }

    fun fetchData(silent: Boolean = false) {
        scope.launch {
            if (!silent) isLoading = groups.isEmpty()
            try {
                val api = apiClient.getApi() ?: return@launch
                val response = api.getPorts()
                if (response.isSuccessful) {
                    response.body()?.let {
                        apiClient.portGroups = it.data
                        apiClient.portSummary = it.summary
                    }
                }
            } catch (e: Exception) {
                snackbarHostState.showSnackbar(e.localizedMessage ?: context.getString(R.string.network_error))
            }
            isLoading = false
        }
    }

    fun performAction(pid: String, action: String) {
        scope.launch {
            try {
                val api = apiClient.getApi() ?: return@launch
                val response = api.portAction(mapOf("action" to action, "pid" to pid))
                if (response.isSuccessful && response.body()?.success == true) {
                    snackbarHostState.showSnackbar(context.getString(R.string.common_success))
                    fetchData()
                } else {
                    val error = response.body()?.details ?: response.body()?.error ?: context.getString(R.string.action_failed)
                    snackbarHostState.showSnackbar(error)
                }
            } catch (e: Exception) {
                snackbarHostState.showSnackbar(e.localizedMessage ?: context.getString(R.string.network_error))
            }
        }
    }

    LaunchedEffect(Unit) {
        fetchData()
        while (true) {
            delay(20_000)
            fetchData(silent = true)
        }
    }

    val stateOptions = remember(groups) {
        groups.flatMap { group -> group.ports.mapNotNull { it.state.takeIf(String::isNotBlank) } }
            .distinct()
            .sorted()
    }

    val filteredGroups = remember(groups, searchQuery, stateFilter) {
        val keyword = searchQuery.trim().lowercase()
        groups.mapNotNull { group ->
            val ports = group.ports.filter { port ->
                val matchesState = stateFilter == "all" || port.state == stateFilter
                val haystack = listOf(
                    group.command,
                    group.pid,
                    group.user,
                    group.fullCommand,
                    port.protocol,
                    port.port.toString(),
                    port.endpoint,
                    port.state
                ).joinToString(" ").lowercase()
                matchesState && (keyword.isBlank() || haystack.contains(keyword))
            }
            if (ports.isEmpty()) null else group.copy(ports = ports)
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            Column {
                TopAppBar(
                    title = { Text(stringResource(R.string.ports_mgmt)) },
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(Icons.Default.Menu, contentDescription = stringResource(R.string.modules))
                        }
                    },
                    actions = {
                        IconButton(onClick = { fetchData() }) {
                            if (isLoading) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                            else Icon(Icons.Default.Refresh, contentDescription = stringResource(R.string.refresh))
                        }
                    }
                )

                TextField(
                    value = searchQuery,
                    onValueChange = { searchQuery = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    placeholder = { Text(stringResource(R.string.ports_search), fontSize = 14.sp) },
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = null, modifier = Modifier.size(18.dp)) },
                    trailingIcon = {
                        if (searchQuery.isNotEmpty()) {
                            IconButton(onClick = { searchQuery = "" }) {
                                Icon(Icons.Default.Close, contentDescription = null, modifier = Modifier.size(18.dp))
                            }
                        }
                    },
                    singleLine = true,
                    shape = MaterialTheme.shapes.medium,
                    colors = TextFieldDefaults.colors(
                        focusedIndicatorColor = Color.Transparent,
                        unfocusedIndicatorColor = Color.Transparent
                    )
                )

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    AssistChip(
                        onClick = {},
                        label = {
                            Text(
                                stringResource(
                                    R.string.ports_summary,
                                    summary.ports,
                                    summary.processes,
                                    summary.listening
                                )
                            )
                        },
                        leadingIcon = { Icon(Icons.Default.Lan, null, Modifier.size(18.dp)) }
                    )

                    var showStateMenu by remember { mutableStateOf(false) }
                    FilterChip(
                        selected = stateFilter != "all",
                        onClick = { showStateMenu = true },
                        label = { Text(if (stateFilter == "all") stringResource(R.string.ports_all_states) else localizedPortState(stateFilter)) },
                        leadingIcon = { Icon(Icons.Default.FilterList, null, Modifier.size(18.dp)) }
                    )
                    DropdownMenu(expanded = showStateMenu, onDismissRequest = { showStateMenu = false }) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.ports_all_states)) },
                            onClick = { stateFilter = "all"; showStateMenu = false }
                        )
                        stateOptions.forEach { state ->
                            DropdownMenuItem(
                                text = { Text(localizedPortState(state)) },
                                onClick = { stateFilter = state; showStateMenu = false }
                            )
                        }
                    }
                }
            }
        }
    ) { padding ->
        if (isLoading && groups.isEmpty()) {
            LoadingView(Modifier.padding(padding))
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)),
                contentPadding = PaddingValues(vertical = 8.dp)
            ) {
                if (filteredGroups.isEmpty()) {
                    item {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(260.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(stringResource(R.string.ports_no_data), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                } else {
                    items(filteredGroups, key = { it.pid }) { group ->
                        PortGroupCard(
                            group = group,
                            onTerm = {
                                groupToActOn = group
                                actionType = "term"
                            },
                            onKill = {
                                groupToActOn = group
                                actionType = "kill"
                            }
                        )
                    }
                }
            }
        }
    }

    groupToActOn?.let { group ->
        val isKill = actionType == "kill"
        ConfirmationDialog(
            title = if (isKill) stringResource(R.string.process_force_kill) else stringResource(R.string.process_terminate),
            message = stringResource(R.string.ports_kill_confirm, group.command, group.pid),
            onConfirm = {
                performAction(group.pid, actionType ?: "term")
                groupToActOn = null
                actionType = null
            },
            onDismiss = {
                groupToActOn = null
                actionType = null
            },
            isDestructive = true
        )
    }
}

@Composable
private fun PortGroupCard(
    group: PortProcessGroup,
    onTerm: () -> Unit,
    onKill: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 6.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(group.command, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        SuggestionChip(onClick = {}, label = { Text("PID ${group.pid}", fontSize = 11.sp) })
                    }
                    Spacer(Modifier.height(4.dp))
                    Text(
                        text = "${stringResource(R.string.process_user)}: ${group.user.ifBlank { stringResource(R.string.none) }} · CPU ${group.cpu}% · MEM ${group.mem}%",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    if (group.fullCommand.isNotBlank()) {
                        Text(
                            text = group.fullCommand,
                            style = MaterialTheme.typography.labelSmall.copy(fontFamily = FontFamily.Monospace),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.padding(top = 6.dp)
                        )
                    }
                }

                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    ActionIconButton(Icons.Default.Stop, Color(0xFFFF9800), onClick = onTerm)
                    ActionIconButton(Icons.Default.Delete, Color.Red, onClick = onKill)
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                group.ports.forEach { port ->
                    PortRow(port)
                }
            }
        }
    }
}

@Composable
private fun PortRow(port: PortEntry) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f), MaterialTheme.shapes.small)
            .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        val dotColor = when (port.state) {
            "LISTEN" -> Color(0xFF4CAF50)
            "ESTABLISHED" -> Color(0xFF2196F3)
            else -> Color(0xFFFF9800)
        }

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Surface(Modifier.size(8.dp), shape = CircleShape, color = dotColor) {}
            Text(port.port.toString(), fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
            Text(port.protocol, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if ((port.connectionCount ?: 1) > 1) {
                Text("x${port.connectionCount}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.secondary)
            }
            Spacer(Modifier.weight(1f))
            if (port.state.isNotBlank()) {
                AssistChip(onClick = {}, label = { Text(localizedPortState(port.state), fontSize = 10.sp) })
            }
        }

        Text(
            port.endpoint,
            style = MaterialTheme.typography.labelSmall.copy(fontFamily = FontFamily.Monospace),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun localizedPortState(state: String): String {
    return when (state) {
        "LISTEN" -> stringResource(R.string.ports_state_listen)
        "ESTABLISHED" -> stringResource(R.string.ports_state_established)
        "TIME_WAIT" -> stringResource(R.string.ports_state_time_wait)
        "CLOSE_WAIT" -> stringResource(R.string.ports_state_close_wait)
        "SYN_SENT" -> stringResource(R.string.ports_state_syn_sent)
        "SYN_RECV" -> stringResource(R.string.ports_state_syn_recv)
        "FIN_WAIT1" -> stringResource(R.string.ports_state_fin_wait1)
        "FIN_WAIT2" -> stringResource(R.string.ports_state_fin_wait2)
        "LAST_ACK" -> stringResource(R.string.ports_state_last_ack)
        "CLOSING" -> stringResource(R.string.ports_state_closing)
        "CLOSED" -> stringResource(R.string.ports_state_closed)
        else -> state
    }
}
