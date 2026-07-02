package com.ct106.flux_remote.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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
import com.ct106.flux_remote.core.ServerManager
import com.ct106.flux_remote.model.LogItem
import com.ct106.flux_remote.core.ServerConfig
import com.ct106.flux_remote.ui.components.*
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.decodeFromJsonElement

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LogsScreen(
    apiClient: RemoteAPIClient,
    serverManager: ServerManager,
    onSelectServer: (ServerConfig) -> Unit,
    onManageServers: () -> Unit,
    onViewLog: (LogItem) -> Unit,
    onBack: () -> Unit
) {
    var isLoading by remember { mutableStateOf(false) }
    var selectedCategory by remember { mutableStateOf<String?>(null) }
    var searchQuery by remember { mutableStateOf("") }
    
    val scope = rememberCoroutineScope()
    val logs = apiClient.logItems

    fun fetchData() {
        scope.launch {
            isLoading = true
            try {
                val api = apiClient.getApi() ?: return@launch
                val response = api.getLogs()
                if (response.isSuccessful) {
                    val data = response.body()?.data
                    if (data != null) {
                        apiClient.logItems = Json { ignoreUnknownKeys = true }.decodeFromJsonElement<List<LogItem>>(data)
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
            isLoading = false
        }
    }

    LaunchedEffect(Unit) {
        if (logs.isEmpty()) {
            fetchData()
        }
    }

    val categories = logs.map { it.category }.distinct().sorted()
    val filteredLogs = logs.filter { log ->
        (selectedCategory == null || log.category == selectedCategory) &&
        (searchQuery.isBlank() || log.name.contains(searchQuery, ignoreCase = true) || log.path.contains(searchQuery, ignoreCase = true))
    }

    Scaffold(
        topBar = {
            Column {
                TopAppBar(
                    title = {
                        ServerSwitcherTitle(
                            title = stringResource(R.string.logs_mgmt),
                            serverManager = serverManager,
                            onSelectServer = onSelectServer,
                            onManageServers = onManageServers
                        )
                    },
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
                    placeholder = { Text(stringResource(R.string.log_search), fontSize = 14.sp) },
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = null, modifier = Modifier.size(18.dp)) },
                    singleLine = true,
                    shape = MaterialTheme.shapes.medium,
                    colors = TextFieldDefaults.colors(
                        focusedIndicatorColor = Color.Transparent,
                        unfocusedIndicatorColor = Color.Transparent
                    )
                )

                // Category Filter
                ScrollableTabRow(
                    selectedTabIndex = if (selectedCategory == null) 0 else categories.indexOf(selectedCategory) + 1,
                    edgePadding = 16.dp,
                    divider = {},
                    containerColor = Color.Transparent
                ) {
                    Tab(
                        selected = selectedCategory == null,
                        onClick = { selectedCategory = null },
                        text = { Text(stringResource(R.string.all)) }
                    )
                    categories.forEach { category ->
                        Tab(
                            selected = selectedCategory == category,
                            onClick = { selectedCategory = category },
                            text = { Text(getLocalizedCategory(category)) }
                        )
                    }
                }
            }
        }
    ) { padding ->
        if (isLoading && logs.isEmpty()) {
            LoadingView(Modifier.padding(padding))
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f))
            ) {
                itemsIndexed(filteredLogs) { index, log ->
                    LogCard(
                        log = log,
                        onClick = { onViewLog(log) }
                    )
                    if (index < filteredLogs.size - 1) {
                        HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp), thickness = 0.5.dp, color = Color.Gray.copy(alpha = 0.2f))
                    }
                }
            }
        }
    }
}

@Composable
fun LogCard(log: LogItem, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .background(MaterialTheme.colorScheme.surface)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Default.Description, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(16.dp))
        Column(Modifier.weight(1f)) {
            Text(text = log.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Text(text = log.path, style = MaterialTheme.typography.labelSmall, color = Color.Gray, maxLines = 1)
        }
        Text(text = "${log.size / 1024} KB", style = MaterialTheme.typography.labelSmall, color = Color.Gray)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LogContentScreen(
    apiClient: RemoteAPIClient,
    logItem: LogItem,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    var content by remember { mutableStateOf("") }
    var isLoading by remember { mutableStateOf(false) }
    
    // AI states
    var aiAnalysis by remember { mutableStateOf<String?>(null) }
    var isAnalyzing by remember { mutableStateOf(false) }

    val scope = rememberCoroutineScope()
    var aiJob by remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }

    LaunchedEffect(logItem) {
        isLoading = true
        try {
            val api = apiClient.getApi() ?: return@LaunchedEffect
            val response = api.getLogContent(logItem.path)
            if (response.isSuccessful) {
                val body = response.body()
                val data = body?.data
                if (data != null) {
                    content = if (data is kotlinx.serialization.json.JsonPrimitive) {
                        data.content
                    } else {
                        data.toString()
                    }
                } else if (body?.error != null) {
                    content = "Error: ${body.error}"
                }
            } else {
                content = "Error: ${response.code()} ${response.message()}"
            }
        } catch (e: Exception) {
            content = "Error: ${e.localizedMessage}"
            e.printStackTrace()
        }
        isLoading = false
    }

    fun analyzeLogs() {
        if (content.isBlank()) return
        isAnalyzing = true
        aiAnalysis = null
        val langName = context.getString(R.string.lang_name)
        val prompt = context.getString(R.string.log_analyze_prompt, content.takeLast(2000))
        val systemPrompt = context.getString(R.string.log_expert_role, langName)

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

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(logItem.name, fontSize = 16.sp) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
                actions = {
                    IconButton(onClick = { analyzeLogs() }, enabled = !isAnalyzing && content.isNotEmpty()) {
                        if (isAnalyzing) CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                        else Icon(Icons.Default.AutoAwesome, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                    }
                }
            )
        }
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
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
            
            if (isLoading && content.isEmpty()) {
                LoadingView()
            } else {
                val scrollState = rememberScrollState()
                Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface).verticalScroll(scrollState)) {
                    Text(
                        text = content,
                        modifier = Modifier.padding(12.dp),
                        color = MaterialTheme.colorScheme.onSurface,
                        fontFamily = FontFamily.Monospace,
                        fontSize = 11.sp,
                        lineHeight = 15.sp
                    )
                }
            }
        }
    }
}
