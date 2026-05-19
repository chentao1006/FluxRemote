package com.ct106.fluxremote.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ct106.fluxremote.R
import com.ct106.fluxremote.core.AIService
import com.ct106.fluxremote.core.RemoteAPIClient
import com.ct106.fluxremote.model.LaunchAgentItem
import com.ct106.fluxremote.ui.components.*
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LaunchAgentEditScreen(
    apiClient: RemoteAPIClient,
    agent: LaunchAgentItem?,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    var filename by remember { mutableStateOf(agent?.name ?: "") }
    var content by remember { mutableStateOf("") }
    var isLoading by remember { mutableStateOf(false) }
    var isSaving by remember { mutableStateOf(false) }
    
    // AI states
    var aiAnalysis by remember { mutableStateOf<String?>(null) }
    var isAnalyzing by remember { mutableStateOf(false) }

    val scope = rememberCoroutineScope()
    var aiJob by remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(agent) {
        if (agent != null) {
            isLoading = true
            try {
                val api = apiClient.getApi() ?: return@LaunchedEffect
                val response = api.launchAgentAction(mapOf("action" to "read", "filePath" to agent.path))
                if (response.isSuccessful) {
                    content = response.body()?.data ?: ""
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
            isLoading = false
        } else {
            content = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/executable</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
            """.trimIndent()
        }
    }

    fun save() {
        if (filename.isBlank()) return
        scope.launch {
            isSaving = true
            try {
                val api = apiClient.getApi() ?: return@launch
                
                // Determine full path if it's a new agent
                val path = if (agent != null) agent.path else {
                    // Try to guess base path from existing agents or use a default
                    val existingPath = apiClient.agentItems.firstOrNull()?.path
                    val basePath = if (existingPath != null) {
                        existingPath.substringBeforeLast("/") + "/"
                    } else {
                        "/Users/chentao/Library/LaunchAgents/"
                    }
                    val fullName = if (filename.endsWith(".plist")) filename else "$filename.plist"
                    basePath + fullName
                }

                val body = mapOf(
                    "action" to "write",
                    "filePath" to path,
                    "content" to content
                )
                val response = api.launchAgentAction(body)
                if (response.isSuccessful) {
                    onBack()
                } else {
                    snackbarHostState.showSnackbar("Save failed: ${response.code()}")
                }
            } catch (e: Exception) {
                snackbarHostState.showSnackbar(e.localizedMessage ?: "Error")
            }
            isSaving = false
        }
    }

    fun analyze() {
        if (content.isBlank()) return
        isAnalyzing = true
        aiAnalysis = null
        val langName = context.getString(R.string.lang_name)
        val prompt = context.getString(R.string.agent_analyze_prompt, langName, content)
        val systemPrompt = context.getString(R.string.agent_expert_role, langName)

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
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text(if (agent == null) stringResource(R.string.agent_add_config) else agent.name) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.Close, contentDescription = null)
                    }
                },
                actions = {
                    IconButton(onClick = { analyze() }, enabled = !isAnalyzing && content.isNotEmpty()) {
                        if (isAnalyzing) CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                        else Icon(Icons.Default.AutoAwesome, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                    }
                    IconButton(onClick = { save() }, enabled = !isSaving && filename.isNotEmpty()) {
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

            if (agent == null) {
                TextField(
                    value = filename,
                    onValueChange = { filename = it },
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    label = { Text(stringResource(R.string.agent_filename_placeholder)) },
                    singleLine = true
                )
            }

            if (isLoading) {
                LoadingView()
            } else {
                TextField(
                    value = content,
                    onValueChange = { content = it },
                    modifier = Modifier.fillMaxSize(),
                    textStyle = LocalTextStyle.current.copy(
                        fontFamily = FontFamily.Monospace,
                        fontSize = 12.sp
                    ),
                    placeholder = { Text(stringResource(R.string.agent_config_content)) },
                    colors = TextFieldDefaults.colors(
                        focusedIndicatorColor = Color.Transparent,
                        unfocusedIndicatorColor = Color.Transparent,
                        focusedContainerColor = Color.Black.copy(alpha = 0.05f),
                        unfocusedContainerColor = Color.Black.copy(alpha = 0.02f)
                    )
                )
            }
        }
    }
}
