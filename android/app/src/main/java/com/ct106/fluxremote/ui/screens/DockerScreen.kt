package com.ct106.fluxremote.ui.screens

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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ct106.fluxremote.R
import com.ct106.fluxremote.core.RemoteAPIClient
import com.ct106.fluxremote.model.DockerContainer
import com.ct106.fluxremote.model.DockerImage
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DockerScreen(
    apiClient: RemoteAPIClient,
    onBack: () -> Unit
) {
    var selectedTab by remember { mutableIntStateOf(0) }
    val tabs = listOf(stringResource(R.string.containers), stringResource(R.string.images))
    var containers by remember { mutableStateOf<List<DockerContainer>>(emptyList()) }
    var images by remember { mutableStateOf<List<DockerImage>>(emptyList()) }
    var isLoading by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun fetchData() {
        scope.launch {
            isLoading = true
            try {
                val api = apiClient.getApi() ?: return@launch
                if (selectedTab == 0) {
                    val response = api.getDockerContainers()
                    if (response.isSuccessful) {
                        containers = response.body()?.data ?: emptyList()
                    }
                } else {
                    val response = api.getDockerImages()
                    if (response.isSuccessful) {
                        images = response.body()?.data ?: emptyList()
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
            isLoading = false
        }
    }

    LaunchedEffect(selectedTab) {
        fetchData()
    }

    Scaffold(
        topBar = {
            Column {
                TopAppBar(
                    title = { Text(stringResource(R.string.docker_mgmt)) },
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(Icons.Default.ArrowBack, contentDescription = stringResource(R.string.back))
                        }
                    },
                    actions = {
                        IconButton(onClick = { fetchData() }) {
                            Icon(Icons.Default.Refresh, contentDescription = stringResource(R.string.refresh))
                        }
                    }
                )
                TabRow(selectedTabIndex = selectedTab) {
                    tabs.forEachIndexed { index, title ->
                        Tab(
                            selected = selectedTab == index,
                            onClick = { selectedTab = index },
                            text = { Text(title) }
                        )
                    }
                }
            }
        }
    ) { padding ->
        if (isLoading && (if (selectedTab == 0) containers.isEmpty() else images.isEmpty())) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            LazyColumn(Modifier.padding(padding)) {
                if (selectedTab == 0) {
                    itemsIndexed(containers) { _, container ->
                        DockerContainerRow(container, onAction = { action ->
                            scope.launch {
                                val api = apiClient.getApi() ?: return@launch
                                api.dockerAction(mapOf("action" to action, "id" to container.id))
                                fetchData()
                            }
                        })
                    }
                } else {
                    itemsIndexed(images) { _, image ->
                        DockerImageRow(image, onDelete = {
                            scope.launch {
                                val api = apiClient.getApi() ?: return@launch
                                api.dockerAction(mapOf("action" to "rmi", "id" to image.id))
                                fetchData()
                            }
                        })
                    }
                }
            }
        }
    }
}

@Composable
fun DockerContainerRow(container: DockerContainer, onAction: (String) -> Unit) {
    ListItem(
        headlineContent = { Text(container.name) },
        supportingContent = {
            Column {
                Text(container.image, fontSize = 12.sp, color = Color.Gray)
                Text(container.status, fontSize = 11.sp, color = Color.Gray)
                if (container.ports.isNotBlank()) {
                    Text(container.ports, fontSize = 11.sp, fontFamily = FontFamily.Monospace, color = MaterialTheme.colorScheme.primary)
                }
            }
        },
        leadingContent = {
            val color = if (container.state == "running") Color.Green else Color.Red
            Surface(Modifier.size(10.dp), shape = MaterialTheme.shapes.extraSmall, color = color) {}
        },
        trailingContent = {
            Row {
                if (container.state == "running") {
                    IconButton(onClick = { onAction("stop") }) {
                        Icon(Icons.Default.Stop, contentDescription = stringResource(R.string.stop), tint = Color.Red)
                    }
                    IconButton(onClick = { onAction("restart") }) {
                        Icon(Icons.Default.Refresh, contentDescription = stringResource(R.string.restart), tint = Color.Yellow)
                    }
                } else {
                    IconButton(onClick = { onAction("start") }) {
                        Icon(Icons.Default.PlayArrow, contentDescription = stringResource(R.string.start), tint = Color.Green)
                    }
                    IconButton(onClick = { onAction("rm") }) {
                        Icon(Icons.Default.Delete, contentDescription = stringResource(R.string.delete), tint = Color.Red)
                    }
                }
            }
        }
    )
}

@Composable
fun DockerImageRow(image: DockerImage, onDelete: () -> Unit) {
    ListItem(
        headlineContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(image.repository)
                Spacer(Modifier.width(8.dp))
                Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = MaterialTheme.shapes.extraSmall) {
                    Text(image.tag, modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp), style = MaterialTheme.typography.labelSmall)
                }
            }
        },
        supportingContent = {
            Text("ID: ${image.id.take(12)} | Size: ${image.size}", fontSize = 11.sp, fontFamily = FontFamily.Monospace)
        },
        trailingContent = {
            if (image.inUse != true) {
                IconButton(onClick = onDelete) {
                    Icon(Icons.Default.Delete, contentDescription = stringResource(R.string.delete), tint = Color.Red)
                }
            }
        }
    )
}
