package com.ct106.fluxremote.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ct106.fluxremote.R
import com.ct106.fluxremote.core.RemoteAPIClient
import com.ct106.fluxremote.model.LogItem
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.JsonPrimitive

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LogsScreen(
    apiClient: RemoteAPIClient,
    onViewLog: (LogItem) -> Unit,
    onBack: () -> Unit
) {
    var logs by remember { mutableStateOf<List<LogItem>>(emptyList()) }
    var isLoading by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun fetchData() {
        scope.launch {
            isLoading = true
            try {
                val api = apiClient.getApi() ?: return@launch
                val response = api.getLogs()
                if (response.isSuccessful) {
                    val data = response.body()?.data
                    if (data != null) {
                        val json = kotlinx.serialization.json.Json { ignoreUnknownKeys = true }
                        try {
                            logs = Json { ignoreUnknownKeys = true }.decodeFromJsonElement(kotlinx.serialization.builtins.ListSerializer(LogItem.serializer()), data)
                        } catch (e: Exception) {
                            e.printStackTrace()
                        }
                    }
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
                title = { Text(stringResource(R.string.logs_mgmt)) },
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
        if (isLoading && logs.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            LazyColumn(Modifier.padding(padding)) {
                items(logs) { log ->
                    ListItem(
                        headlineContent = { Text(log.name) },
                        supportingContent = { Text(log.path, fontSize = 11.sp, color = Color.Gray) },
                        trailingContent = { Text("${log.size / 1024} KB", fontSize = 11.sp) },
                        modifier = Modifier.clickable { onViewLog(log) }
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LogContentScreen(
    apiClient: RemoteAPIClient,
    logItem: LogItem,
    onBack: () -> Unit
) {
    var content by remember { mutableStateOf("") }
    var isLoading by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(logItem) {
        isLoading = true
        try {
            val api = apiClient.getApi() ?: return@LaunchedEffect
            val response = api.getLogContent(logItem.path)
            if (response.isSuccessful) {
                val data = response.body()?.data
                if (data != null) {
                    content = if (data is kotlinx.serialization.json.JsonPrimitive) {
                        data.content
                    } else {
                        data.toString()
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        isLoading = false
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(logItem.name) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.Menu, contentDescription = stringResource(R.string.modules))
                    }
                }
            )
        }
    ) { padding ->
        if (isLoading) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            Box(Modifier.padding(padding).fillMaxSize()) {
                LazyColumn(Modifier.fillMaxSize()) {
                    item {
                        Text(
                            text = content,
                            modifier = Modifier.padding(8.dp),
                            fontFamily = FontFamily.Monospace,
                            fontSize = 12.sp
                        )
                    }
                }
            }
        }
    }
}
