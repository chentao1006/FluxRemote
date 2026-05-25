package com.ct106.flux_remote.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ct106.flux_remote.R
import com.ct106.flux_remote.core.AIService
import com.ct106.flux_remote.core.RemoteAPIClient
import com.ct106.flux_remote.model.NginxSite
import com.ct106.flux_remote.ui.components.*
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NginxSiteEditScreen(
    apiClient: RemoteAPIClient,
    site: NginxSite?,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    var filename by remember { mutableStateOf(site?.name ?: "") }
    var content by remember { mutableStateOf("") }
    var isLoading by remember { mutableStateOf(false) }
    var isSaving by remember { mutableStateOf(false) }
    
    // AI states
    var aiAnalysis by remember { mutableStateOf<String?>(null) }
    var isAnalyzing by remember { mutableStateOf(false) }

    val scope = rememberCoroutineScope()
    var aiJob by remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(site) {
        if (site != null) {
            isLoading = true
            try {
                val api = apiClient.getApi() ?: return@LaunchedEffect
                val response = api.nginxSiteAction(mapOf("action" to "read", "filename" to site.name))
                if (response.isSuccessful) {
                    content = response.body()?.data ?: ""
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
            isLoading = false
        } else {
            content = """
server {
    listen 80;
    server_name example.com;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade ${'$'}http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host ${'$'}host;
        proxy_cache_bypass ${'$'}http_upgrade;
    }
}
            """.trimIndent()
        }
    }

    fun save() {
        if (filename.isBlank()) return
        scope.launch {
            isSaving = true
            try {
                val api = apiClient.getApi() ?: return@launch
                val body = mapOf(
                    "action" to "write",
                    "filename" to filename,
                    "content" to content
                )
                val response = api.nginxSiteAction(body)
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
        val prompt = context.getString(R.string.nginx_analyze_prompt, langName, content)
        val systemPrompt = context.getString(R.string.nginx_expert_role, langName)

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
                title = { Text(if (site == null) stringResource(R.string.nginx_add_site) else site.name) },
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

            if (site == null) {
                TextField(
                    value = filename,
                    onValueChange = { filename = it },
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    label = { Text(stringResource(R.string.nginx_filename_placeholder)) },
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
                    placeholder = { Text(stringResource(R.string.nginx_config_content)) },
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
