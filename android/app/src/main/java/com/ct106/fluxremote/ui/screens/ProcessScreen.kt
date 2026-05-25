package com.ct106.flux_remote.ui.screens

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ct106.flux_remote.R
import com.ct106.flux_remote.core.AIService
import com.ct106.flux_remote.core.RemoteAPIClient
import com.ct106.flux_remote.model.*
import com.ct106.flux_remote.ui.components.*
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProcessScreen(
    apiClient: RemoteAPIClient,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    var isLoading by remember { mutableStateOf(false) }
    var sortOrder by remember { mutableStateOf("cpu") }
    var selectedUser by remember { mutableStateOf("All") }
    var searchQuery by remember { mutableStateOf("") }
    
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }
    
    val processes = apiClient.processItems

    // State for Sheets and Dialogs
    var selectedProcessForDetail by remember { mutableStateOf<RemoteProcess?>(null) }
    var processToActOn by remember { mutableStateOf<RemoteProcess?>(null) }
    var actionType by remember { mutableStateOf<String?>(null) } // "stop" or "kill"

    fun fetchData() {
        scope.launch {
            isLoading = true
            try {
                val api = apiClient.getApi() ?: return@launch
                val response = api.getProcesses(sortOrder)
                if (response.isSuccessful) {
                    apiClient.processItems = response.body()?.data ?: emptyList()
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
            isLoading = false
        }
    }

    fun performAction(pid: String, action: String) {
        scope.launch {
            try {
                val api = apiClient.getApi() ?: return@launch
                val response = api.processAction(mapOf("action" to action, "pid" to pid))
                if (response.isSuccessful && response.body()?.success == true) {
                    fetchData()
                    val msgId = if (action == "kill") R.string.process_killed else R.string.common_success
                    snackbarHostState.showSnackbar(context.getString(msgId))
                } else {
                    val error = response.body()?.details ?: response.body()?.error ?: "Action failed"
                    snackbarHostState.showSnackbar(error)
                }
            } catch (e: Exception) {
                snackbarHostState.showSnackbar(e.localizedMessage ?: "Network error")
            }
        }
    }

    LaunchedEffect(sortOrder) {
        if (processes.isEmpty()) {
            fetchData()
        }
    }

    val users = remember(processes) {
        listOf("All") + processes.map { it.user }.distinct().sorted()
    }

    val filteredProcesses = processes.filter { process ->
        (selectedUser == "All" || process.user == selectedUser) &&
        (searchQuery.isBlank() || process.command.contains(searchQuery, ignoreCase = true) || process.pid.contains(searchQuery))
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            Column {
                TopAppBar(
                    title = { Text(stringResource(R.string.process_mgmt)) },
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
                
                // Search Bar
                TextField(
                    value = searchQuery,
                    onValueChange = { searchQuery = it },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                    placeholder = { Text(stringResource(R.string.process_search), fontSize = 14.sp) },
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = null, modifier = Modifier.size(18.dp)) },
                    singleLine = true,
                    shape = MaterialTheme.shapes.medium,
                    colors = TextFieldDefaults.colors(
                        focusedIndicatorColor = Color.Transparent,
                        unfocusedIndicatorColor = Color.Transparent
                    )
                )

                // Filters Row
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    // Sort Menu
                    var showSortMenu by remember { mutableStateOf(false) }
                    FilterChip(
                        selected = true,
                        onClick = { showSortMenu = true },
                        label = {
                            val sortLabel = when(sortOrder) {
                                "cpu" -> stringResource(R.string.process_sort_cpu)
                                "mem" -> stringResource(R.string.process_sort_mem)
                                "pid" -> stringResource(R.string.process_sort_pid)
                                else -> stringResource(R.string.process_sort_name)
                            }
                            Text(sortLabel)
                        },
                        leadingIcon = { Icon(Icons.Default.Sort, null, Modifier.size(18.dp)) }
                    )
                    DropdownMenu(expanded = showSortMenu, onDismissRequest = { showSortMenu = false }) {
                        DropdownMenuItem(text = { Text(stringResource(R.string.process_sort_cpu)) }, onClick = { sortOrder = "cpu"; showSortMenu = false })
                        DropdownMenuItem(text = { Text(stringResource(R.string.process_sort_mem)) }, onClick = { sortOrder = "mem"; showSortMenu = false })
                        DropdownMenuItem(text = { Text(stringResource(R.string.process_sort_pid)) }, onClick = { sortOrder = "pid"; showSortMenu = false })
                        DropdownMenuItem(text = { Text(stringResource(R.string.process_sort_name)) }, onClick = { sortOrder = "command"; showSortMenu = false })
                    }

                    // User Menu
                    var showUserMenu by remember { mutableStateOf(false) }
                    FilterChip(
                        selected = selectedUser != "All",
                        onClick = { showUserMenu = true },
                        label = { Text(if (selectedUser == "All") stringResource(R.string.all) else selectedUser) },
                        leadingIcon = { Icon(Icons.Default.Person, null, Modifier.size(18.dp)) }
                    )
                    DropdownMenu(expanded = showUserMenu, onDismissRequest = { showUserMenu = false }) {
                        users.forEach { user ->
                            DropdownMenuItem(
                                text = { Text(if (user == "All") stringResource(R.string.all) else user) },
                                onClick = { selectedUser = user; showUserMenu = false }
                            )
                        }
                    }
                }
            }
        }
    ) { padding ->
        if (isLoading && processes.isEmpty()) {
            LoadingView(Modifier.padding(padding))
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f))
            ) {
                itemsIndexed(filteredProcesses) { index, process ->
                    ProcessCard(
                        process = process,
                        onClick = { selectedProcessForDetail = process },
                        onStop = { 
                            processToActOn = process
                            actionType = "stop"
                        },
                        onKill = { 
                            processToActOn = process
                            actionType = "kill"
                        }
                    )
                    if (index < filteredProcesses.size - 1) {
                        HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp), thickness = 0.5.dp, color = Color.Gray.copy(alpha = 0.2f))
                    }
                }
            }
        }
    }

    // Detail Sheet
    if (selectedProcessForDetail != null) {
        ModalBottomSheet(
            onDismissRequest = { selectedProcessForDetail = null },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ) {
            ProcessDetailScreen(
                apiClient = apiClient,
                process = selectedProcessForDetail!!,
                onDismiss = { selectedProcessForDetail = null }
            )
        }
    }

    // Confirmation Dialogs
    processToActOn?.let { process ->
        val title = if (actionType == "kill") stringResource(R.string.process_force_kill) else stringResource(R.string.process_terminate)
        val msg = if (actionType == "kill") stringResource(R.string.process_force_kill_confirm, process.command) else stringResource(R.string.process_terminate_confirm, process.command)
        
        ConfirmationDialog(
            title = title,
            message = msg,
            onConfirm = { 
                performAction(process.pid, actionType!!)
                processToActOn = null
                actionType = null
            },
            onDismiss = { 
                processToActOn = null
                actionType = null
            },
            isDestructive = true
        )
    }
}

@Composable
fun ProcessCard(
    process: RemoteProcess, 
    onClick: () -> Unit, 
    onStop: () -> Unit,
    onKill: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .background(MaterialTheme.colorScheme.surface)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(text = process.command, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 1)
            Spacer(Modifier.height(4.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(text = "${stringResource(R.string.process_pid)}: ${process.pid}", fontSize = 11.sp, color = Color.Gray)
                Text(text = "${stringResource(R.string.process_user)}: ${process.user}", fontSize = 11.sp, color = Color.Gray)
            }
        }
        
        Column(horizontalAlignment = Alignment.End, modifier = Modifier.padding(horizontal = 8.dp)) {
            Text(text = "${process.cpu}% CPU", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color(0xFF4A90D9))
            Text(text = "${process.mem}% MEM", fontSize = 11.sp, color = Color.Gray)
        }
        
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            ActionIconButton(
                icon = Icons.Default.Stop,
                color = Color(0xFFFFA500),
                onClick = onStop
            )
            ActionIconButton(
                icon = Icons.Default.Delete,
                color = Color.Red,
                onClick = onKill
            )
        }
    }
}

@Composable
fun ProcessDetailScreen(
    apiClient: RemoteAPIClient,
    process: RemoteProcess,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var aiJob by remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }
    var detailedProcess by remember { mutableStateOf<DetailedProcess?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    
    // AI states
    var aiAnalysis by remember { mutableStateOf<String?>(null) }
    var isAnalyzing by remember { mutableStateOf(false) }

    fun fetchDetail() {
        scope.launch {
            isLoading = true
            try {
                val api = apiClient.getApi() ?: return@launch
                val response = api.getProcessDetail(process.pid)
                if (response.isSuccessful) {
                    detailedProcess = response.body()?.data
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
            isLoading = false
        }
    }

    fun analyzeProcess() {
        val dp = detailedProcess ?: return
        isAnalyzing = true
        aiAnalysis = null
        
        val info = "PID: ${dp.pid}, PPID: ${dp.ppid} (${dp.ppidName}), Command: ${dp.command}, Full Command: ${dp.fullCommand}, CPU: ${dp.cpu}%, MEM: ${dp.mem}%, State: ${dp.state}, Start: ${dp.start}, User: ${dp.user}, Open Files: ${dp.openFiles.joinToString(", ")}"
        val langName = context.getString(R.string.lang_name)
        val prompt = context.getString(R.string.process_analyze_prompt, langName, info)
        val systemPrompt = context.getString(R.string.system_expert_role, langName)

        aiJob?.cancel()
        aiJob = scope.launch {
            AIService.getInstance(context).analyzeStream(prompt, systemPrompt, apiClient)
                .catch { e ->
                    aiAnalysis = context.getString(R.string.error_prefix, e.message ?: "")
                    isAnalyzing = false
                }
                .collect { chunk ->
                    if (aiAnalysis == null) aiAnalysis = ""
                    aiAnalysis = aiAnalysis + chunk
                    isAnalyzing = false
                }
        }
    }

    LaunchedEffect(process.pid) {
        fetchDetail()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(bottom = 32.dp)
    ) {
        // Header
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(process.command, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, maxLines = 1)
            Spacer(Modifier.weight(1f))
            IconButton(onClick = onDismiss) {
                Icon(Icons.Default.Close, null)
            }
        }

        if (isLoading) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else if (detailedProcess != null) {
            val dp = detailedProcess!!
            Box(Modifier.weight(1f)) {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    // AI Analysis Card
                    if (aiAnalysis != null || isAnalyzing) {
                        AIAnalysisCard(
                            analysis = aiAnalysis,
                            isAnalyzing = isAnalyzing,
                            onDismiss = { 
                                aiAnalysis = null
                                isAnalyzing = false
                                aiJob?.cancel()
                                aiJob = null
                            },
                            modifier = Modifier.padding(16.dp)
                        )
                    }

                    // Basic Info Section
                    SettingsHeader(stringResource(R.string.common_basic_info))
                    DetailRow(stringResource(R.string.process_pid), dp.pid)
                    DetailRow(stringResource(R.string.process_parent_pid), "${dp.ppidName} (${dp.ppid})")
                    DetailRow(stringResource(R.string.process_state), dp.state)
                    DetailRow(stringResource(R.string.process_user), dp.user)
                    DetailRow(stringResource(R.string.process_start_time), dp.start)
                    DetailRow(stringResource(R.string.process_cpu_time), dp.time)

                    // Resource Usage Section
                    SettingsHeader(stringResource(R.string.common_resource_usage))
                    DetailRow(stringResource(R.string.process_cpu), "${dp.cpu}%")
                    DetailRow(stringResource(R.string.process_mem), "${dp.mem}%")

                    // Full Command Section
                    SettingsHeader(stringResource(R.string.process_full_command))
                    Text(
                        text = dp.fullCommand,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                        style = MaterialTheme.typography.labelSmall.copy(fontFamily = FontFamily.Monospace),
                        color = Color.Gray
                    )

                    // Open Files Section
                    if (dp.openFiles.isNotEmpty()) {
                        SettingsHeader(stringResource(R.string.process_open_files))
                        dp.openFiles.forEach { file ->
                            Text(
                                text = file,
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 2.dp),
                                style = MaterialTheme.typography.labelSmall.copy(fontFamily = FontFamily.Monospace),
                                color = Color.Gray
                            )
                        }
                    }
                    
                    Spacer(Modifier.height(80.dp))
                }
                
                // Bottom Floating AI Button
                if (aiAnalysis == null && !isAnalyzing) {
                    Box(Modifier.fillMaxSize().padding(16.dp), contentAlignment = Alignment.BottomCenter) {
                        AIActionButton(
                            text = stringResource(R.string.ai_analyze),
                            icon = Icons.Default.AutoAwesome,
                            onClick = { analyzeProcess() }
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun DetailRow(label: String, value: String) {
    ListItem(
        headlineContent = { Text(label, style = MaterialTheme.typography.bodySmall, color = Color.Gray) },
        trailingContent = { Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium) }
    )
}
