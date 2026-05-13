package com.ct106.fluxremote.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Menu
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
import com.ct106.fluxremote.model.RemoteProcess
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProcessScreen(
    apiClient: RemoteAPIClient,
    onBack: () -> Unit
) {
    var processes by remember { mutableStateOf<List<RemoteProcess>>(emptyList()) }
    var isLoading by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun fetchData() {
        scope.launch {
            isLoading = true
            try {
                val api = apiClient.getApi() ?: return@launch
                val response = api.getProcesses()
                if (response.isSuccessful) {
                    processes = response.body()?.data ?: emptyList()
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
        }
    ) { padding ->
        if (isLoading && processes.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            LazyColumn(Modifier.padding(padding)) {
                items(processes) { process ->
                    ProcessRow(process, onKill = {
                        scope.launch {
                            apiClient.getApi()?.processAction(mapOf("action" to "kill", "pid" to process.pid))
                            fetchData()
                        }
                    })
                }
            }
        }
    }
}

@Composable
fun ProcessRow(process: RemoteProcess, onKill: () -> Unit) {
    ListItem(
        headlineContent = { Text(process.command, maxLines = 1) },
        supportingContent = {
            Text("PID: ${process.pid} | User: ${process.user} | CPU: ${process.cpu} | MEM: ${process.mem}", fontSize = 11.sp, fontFamily = FontFamily.Monospace)
        },
        trailingContent = {
            IconButton(onClick = onKill) {
                Icon(Icons.Default.Delete, contentDescription = stringResource(R.string.kill_process), tint = Color.Red)
            }
        }
    )
}
