package com.ct106.flux_remote.ui.screens

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
import com.ct106.flux_remote.model.ConfigItem
import com.ct106.flux_remote.ui.components.*
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConfigsScreen(
    apiClient: RemoteAPIClient,
    onViewConfig: (ConfigItem) -> Unit,
    onBack: () -> Unit
) {
    var isLoading by remember { mutableStateOf(false) }
    var selectedCategory by remember { mutableStateOf<String?>(null) }
    var searchQuery by remember { mutableStateOf("") }
    
    val scope = rememberCoroutineScope()
    val configs = apiClient.configItems

    fun fetchData() {
        scope.launch {
            isLoading = true
            try {
                val api = apiClient.getApi() ?: return@launch
                val response = api.getConfigs()
                if (response.isSuccessful) {
                    apiClient.configItems = response.body()?.data ?: emptyList()
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
            isLoading = false
        }
    }

    LaunchedEffect(Unit) {
        if (configs.isEmpty()) {
            fetchData()
        }
    }

    val categories = configs.map { it.category }.distinct().sorted()
    val filteredConfigs = configs.filter { config ->
        (selectedCategory == null || config.category == selectedCategory) &&
        (searchQuery.isBlank() || config.name.contains(searchQuery, ignoreCase = true) || config.path.contains(searchQuery, ignoreCase = true))
    }

    Scaffold(
        topBar = {
            Column {
                TopAppBar(
                    title = { Text(stringResource(R.string.configs_mgmt)) },
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
                    placeholder = { Text(stringResource(R.string.config_search), fontSize = 14.sp) },
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
        if (isLoading && configs.isEmpty()) {
            LoadingView(Modifier.padding(padding))
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f))
            ) {
                itemsIndexed(filteredConfigs) { index, config ->
                    ConfigCard(
                        config = config,
                        onClick = { onViewConfig(config) }
                    )
                    if (index < filteredConfigs.size - 1) {
                        HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp), thickness = 0.5.dp, color = Color.Gray.copy(alpha = 0.2f))
                    }
                }
            }
        }
    }
}

@Composable
fun ConfigCard(config: ConfigItem, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .background(MaterialTheme.colorScheme.surface)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Default.Settings, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(16.dp))
        Column(Modifier.weight(1f)) {
            Text(text = config.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Text(text = config.path, style = MaterialTheme.typography.labelSmall, color = Color.Gray, maxLines = 1)
        }
        Icon(Icons.Default.ChevronRight, contentDescription = null, tint = Color.Gray, modifier = Modifier.size(16.dp))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConfigContentScreen(
    apiClient: RemoteAPIClient,
    configItem: ConfigItem,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    var content by remember { mutableStateOf("") }
    var isLoading by remember { mutableStateOf(false) }
    var isSaving by remember { mutableStateOf(false) }
    
    // AI states
    var aiAnalysis by remember { mutableStateOf<String?>(null) }
    var isAnalyzing by remember { mutableStateOf(false) }

    val scope = rememberCoroutineScope()
    var aiJob by remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }

    LaunchedEffect(configItem) {
        isLoading = true
        try {
            val api = apiClient.getApi() ?: return@LaunchedEffect
            val response = api.configAction(mapOf("action" to "read", "id" to configItem.path))
            if (response.isSuccessful) {
                content = response.body()?.content ?: ""
            } else {
                content = "Error: ${response.code()} ${response.message()}"
            }
        } catch (e: Exception) {
            content = "Error: ${e.localizedMessage}"
            e.printStackTrace()
        }
        isLoading = false
    }

    fun saveConfig() {
        scope.launch {
            isSaving = true
            try {
                val api = apiClient.getApi() ?: return@launch
                val response = api.configAction(mapOf(
                    "action" to "write",
                    "id" to configItem.path,
                    "content" to content
                ))
                if (response.isSuccessful) {
                    onBack()
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
            isSaving = false
        }
    }

    fun analyzeConfig() {
        if (content.isBlank()) return
        isAnalyzing = true
        aiAnalysis = null
        val langName = context.getString(R.string.lang_name)
        val prompt = context.getString(R.string.config_analyze_prompt, content)
        val systemPrompt = context.getString(R.string.config_expert_role, langName)

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
                title = { Text(configItem.name, fontSize = 16.sp) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = null)
                    }
                },
                actions = {
                    IconButton(onClick = { analyzeConfig() }, enabled = !isAnalyzing && content.isNotEmpty()) {
                        if (isAnalyzing) CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                        else Icon(Icons.Default.AutoAwesome, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                    }
                    IconButton(onClick = { saveConfig() }, enabled = !isSaving && content.isNotEmpty()) {
                        if (isSaving) CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                        else Icon(Icons.Default.Check, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
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
                TextField(
                    value = content,
                    onValueChange = { content = it },
                    modifier = Modifier.fillMaxSize(),
                    textStyle = LocalTextStyle.current.copy(
                        fontFamily = FontFamily.Monospace,
                        fontSize = 11.sp,
                        lineHeight = 15.sp,
                        color = MaterialTheme.colorScheme.onSurface
                    ),
                    colors = TextFieldDefaults.colors(
                        focusedContainerColor = MaterialTheme.colorScheme.surface,
                        unfocusedContainerColor = MaterialTheme.colorScheme.surface,
                        focusedIndicatorColor = Color.Transparent,
                        unfocusedIndicatorColor = Color.Transparent
                    )
                )
            }
        }
    }
}

