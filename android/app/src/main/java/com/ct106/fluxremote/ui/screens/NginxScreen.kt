package com.ct106.fluxremote.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ct106.fluxremote.R
import com.ct106.fluxremote.core.RemoteAPIClient
import com.ct106.fluxremote.model.NginxSite
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NginxScreen(
    apiClient: RemoteAPIClient,
    onBack: () -> Unit
) {
    var sites by remember { mutableStateOf<List<NginxSite>>(emptyList()) }
    var isLoading by remember { mutableStateOf(false) }
    var isRunning by remember { mutableStateOf<Boolean?>(null) }
    val scope = rememberCoroutineScope()

    fun fetchData() {
        scope.launch {
            isLoading = true
            try {
                val api = apiClient.getApi() ?: return@launch
                val response = api.getNginxSites()
                if (response.isSuccessful) {
                    sites = response.body()?.data ?: emptyList()
                    isRunning = response.body()?.running
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
                title = { Text(stringResource(R.string.nginx_mgmt)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
                actions = {
                    if (isRunning == true) {
                        IconButton(onClick = {
                            scope.launch {
                                apiClient.getApi()?.nginxAction(mapOf("action" to "stop"))
                                fetchData()
                            }
                        }) {
                            Icon(Icons.Default.Stop, contentDescription = stringResource(R.string.stop), tint = Color.Red)
                        }
                    } else if (isRunning == false) {
                        IconButton(onClick = {
                            scope.launch {
                                apiClient.getApi()?.nginxAction(mapOf("action" to "start"))
                                fetchData()
                            }
                        }) {
                            Icon(Icons.Default.PlayArrow, contentDescription = stringResource(R.string.start), tint = Color.Green)
                        }
                    }
                    IconButton(onClick = { fetchData() }) {
                        Icon(Icons.Default.Refresh, contentDescription = stringResource(R.string.refresh))
                    }
                }
            )
        }
    ) { padding ->
        if (isLoading && sites.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            LazyColumn(Modifier.padding(padding)) {
                items(sites) { site ->
                    NginxSiteRow(site)
                }
            }
        }
    }
}

@Composable
fun NginxSiteRow(site: NginxSite) {
    ListItem(
        headlineContent = { Text(site.name) },
        supportingContent = {
            Column {
                Text("Server Name: ${site.serverName}", fontSize = 12.sp, color = Color.Gray)
                Text("Port: ${site.port}", fontSize = 12.sp, color = MaterialTheme.colorScheme.primary)
            }
        },
        leadingContent = {
            val color = if (site.status == "enabled") Color.Green else Color.Gray
            Surface(Modifier.size(10.dp), shape = MaterialTheme.shapes.extraSmall, color = color) {}
        }
    )
}
