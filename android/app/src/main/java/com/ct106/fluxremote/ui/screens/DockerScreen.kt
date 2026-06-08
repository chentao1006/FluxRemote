package com.ct106.flux_remote.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.ct106.flux_remote.R
import com.ct106.flux_remote.core.RemoteAPIClient
import com.ct106.flux_remote.model.DockerContainer
import com.ct106.flux_remote.model.DockerImage
import com.ct106.flux_remote.ui.components.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DockerScreen(
    apiClient: RemoteAPIClient,
    onBack: () -> Unit
) {
    var selectedTab by remember { mutableIntStateOf(0) }
    val tabs = listOf(stringResource(R.string.containers), stringResource(R.string.images))
    var isLoading by remember { mutableStateOf(false) }
    var loadingAction by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }

    val containers = apiClient.dockerContainers
    val images = apiClient.dockerImages

    fun fetchData() {
        scope.launch {
            isLoading = true
            try {
                val api = apiClient.getApi() ?: return@launch
                if (selectedTab == 0) {
                    val response = api.getDockerContainers()
                    if (response.isSuccessful) {
                        apiClient.dockerContainers = response.body()?.data ?: emptyList()
                    }
                } else {
                    val response = api.getDockerImages()
                    if (response.isSuccessful) {
                        apiClient.dockerImages = response.body()?.data ?: emptyList()
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
            isLoading = false
        }
    }

    fun performAction(action: String, id: String) {
        scope.launch {
            loadingAction = loadingAction + (id to action)
            try {
                val api = apiClient.getApi() ?: return@launch
                val response = api.dockerAction(mapOf("action" to action, "id" to id))
                if (response.isSuccessful && response.body()?.success == true) {
                    fetchData()
                } else {
                    val error = response.body()?.details ?: response.body()?.error ?: "Action failed"
                    snackbarHostState.showSnackbar(error)
                }
            } catch (e: Exception) {
                snackbarHostState.showSnackbar(e.localizedMessage ?: "Network error")
            }
            loadingAction = loadingAction - id
        }
    }

    LaunchedEffect(selectedTab) {
        if (selectedTab == 0 && containers.isEmpty()) fetchData()
        else if (selectedTab == 1 && images.isEmpty()) fetchData()
    }

    // State for Sheets and Dialogs
    var selectedContainerForDetail by remember { mutableStateOf<DockerContainer?>(null) }
    var selectedContainerForLogs by remember { mutableStateOf<DockerContainer?>(null) }
    var containerToAction by remember { mutableStateOf<Pair<DockerContainer, String>?>(null) }
    var imageToDelete by remember { mutableStateOf<DockerImage?>(null) }
    var showingPruneConfirm by remember { mutableStateOf(false) }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            Column {
                TopAppBar(
                    title = { Text(stringResource(R.string.docker_mgmt)) },
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(Icons.Default.Menu, contentDescription = stringResource(R.string.modules))
                        }
                    },
                    actions = {
                        if (selectedTab == 1) {
                            IconButton(onClick = { showingPruneConfirm = true }) {
                                Icon(Icons.Default.DeleteSweep, contentDescription = stringResource(R.string.docker_prune), tint = Color.Red)
                            }
                        }
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
            LoadingView(Modifier.padding(padding))
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f))
            ) {
                if (selectedTab == 0) {
                    itemsIndexed(items = containers) { index, container ->
                        DockerContainerCard(
                            container = container,
                            isLoading = loadingAction[container.id] != null,
                            loadingAction = loadingAction[container.id],
                            onAction = { action ->
                                if (action == "start") {
                                    performAction(action, container.id)
                                } else {
                                    containerToAction = container to action
                                }
                            },
                            onLogs = { selectedContainerForLogs = container },
                            onClick = { selectedContainerForDetail = container }
                        )
                        if (index < containers.size - 1) {
                            HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp), thickness = 0.5.dp, color = Color.Gray.copy(alpha = 0.2f))
                        }
                    }
                } else {
                    itemsIndexed(items = images) { index, image ->
                        DockerImageCard(
                            image = image,
                            isLoading = loadingAction[image.id] == "rmi",
                            onDelete = { imageToDelete = image }
                        )
                        if (index < images.size - 1) {
                            HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp), thickness = 0.5.dp, color = Color.Gray.copy(alpha = 0.2f))
                        }
                    }
                }
            }
        }
    }

    // Detail Bottom Sheet
    if (selectedContainerForDetail != null) {
        ModalBottomSheet(
            onDismissRequest = { selectedContainerForDetail = null },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ) {
            DockerContainerDetailContent(
                container = selectedContainerForDetail!!,
                onAction = { action ->
                    if (action == "start") {
                        performAction(action, selectedContainerForDetail!!.id)
                    } else {
                        containerToAction = selectedContainerForDetail!! to action
                    }
                },
                onLogs = {
                    val c = selectedContainerForDetail
                    selectedContainerForDetail = null
                    selectedContainerForLogs = c
                }
            )
        }
    }

    // Log Dialog
    if (selectedContainerForLogs != null) {
        DockerLogDialog(
            container = selectedContainerForLogs!!,
            apiClient = apiClient,
            onDismiss = { selectedContainerForLogs = null }
        )
    }

    // Confirmation Dialogs
    containerToAction?.let { (container, action) ->
        val title = when (action) {
            "stop" -> stringResource(R.string.stop)
            "restart" -> stringResource(R.string.restart)
            else -> stringResource(R.string.delete)
        }
        val message = when (action) {
            "stop" -> stringResource(R.string.docker_confirm_stop, container.name)
            "restart" -> stringResource(R.string.docker_confirm_restart, container.name)
            else -> stringResource(R.string.docker_confirm_rm, container.name)
        }
        ConfirmationDialog(
            title = title,
            message = message,
            onConfirm = { performAction(action, container.id) },
            onDismiss = { containerToAction = null },
            isDestructive = action == "rm" || action == "stop"
        )
    }

    imageToDelete?.let { image ->
        ConfirmationDialog(
            title = stringResource(R.string.docker_delete_image_title),
            message = stringResource(R.string.docker_delete_image_message, image.repository),
            onConfirm = { performAction("rmi", image.id) },
            onDismiss = { imageToDelete = null },
            isDestructive = true
        )
    }

    if (showingPruneConfirm) {
        ConfirmationDialog(
            title = stringResource(R.string.docker_prune_title),
            message = stringResource(R.string.docker_prune_message),
            onConfirm = { performAction("prune", "") },
            onDismiss = { showingPruneConfirm = false },
            isDestructive = true
        )
    }
}

@Composable
fun DockerContainerCard(
    container: DockerContainer,
    isLoading: Boolean,
    loadingAction: String?,
    onAction: (String) -> Unit,
    onLogs: () -> Unit,
    onClick: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .background(MaterialTheme.colorScheme.surface)
            .padding(16.dp)
    ) {
        Row(verticalAlignment = Alignment.Top) {
            StatusBadge(status = container.state, size = 14)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(text = container.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(text = container.image, style = MaterialTheme.typography.bodySmall, color = Color.Gray, maxLines = 1)
            }
            ActionIconButton(
                icon = Icons.Outlined.Description,
                color = MaterialTheme.colorScheme.primary,
                onClick = onLogs,
                contentDescription = stringResource(R.string.docker_view_logs)
            )
        }
        Spacer(Modifier.height(12.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(text = container.status, fontSize = 11.sp, color = Color.Gray)
                if (container.ports.isNotBlank()) {
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 4.dp)) {
                        Icon(Icons.Default.NetworkCheck, contentDescription = null, modifier = Modifier.size(10.dp), tint = MaterialTheme.colorScheme.primary)
                        Spacer(Modifier.width(4.dp))
                        Text(text = container.ports, fontSize = 10.sp, fontFamily = FontFamily.Monospace, color = MaterialTheme.colorScheme.primary)
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (container.state == "running") {
                    ActionIconButton(
                        icon = Icons.Default.Refresh,
                        color = Color(0xFFFFA000),
                        isLoading = isLoading && loadingAction == "restart",
                        onClick = { onAction("restart") }
                    )
                    ActionIconButton(
                        icon = Icons.Default.Stop,
                        color = Color.Red,
                        isLoading = isLoading && loadingAction == "stop",
                        onClick = { onAction("stop") }
                    )
                } else {
                    ActionIconButton(
                        icon = Icons.Default.PlayArrow,
                        color = Color(0xFF4CAF50),
                        isLoading = isLoading && loadingAction == "start",
                        onClick = { onAction("start") }
                    )
                    ActionIconButton(
                        icon = Icons.Default.Delete,
                        color = Color.Red,
                        isLoading = isLoading && loadingAction == "rm",
                        onClick = { onAction("rm") }
                    )
                }
            }
        }
    }
}

@Composable
fun DockerImageCard(
    image: DockerImage,
    isLoading: Boolean,
    onDelete: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        StatusBadge(status = if (image.inUse == true) "online" else "offline", size = 14)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(text = image.repository, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Medium)
                Spacer(Modifier.width(8.dp))
                Surface(
                    color = MaterialTheme.colorScheme.primary.copy(alpha = 0.1f),
                    shape = CircleShape
                ) {
                    Text(
                        text = image.tag,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }
            Spacer(Modifier.height(4.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(text = "ID: ${image.id.take(12)}", fontSize = 10.sp, fontFamily = FontFamily.Monospace, color = Color.Gray)
                Text(text = image.size, fontSize = 10.sp, fontFamily = FontFamily.Monospace, color = Color.Gray)
            }
        }
        if (image.inUse != true) {
            ActionIconButton(
                icon = Icons.Default.Delete,
                color = Color.Red,
                isLoading = isLoading,
                onClick = onDelete
            )
        }
    }
}

@Composable
fun DockerContainerDetailContent(
    container: DockerContainer,
    onAction: (String) -> Unit,
    onLogs: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp)
            .verticalScroll(rememberScrollState())
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(text = container.name, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Spacer(Modifier.weight(1f))
            IconButton(onClick = onLogs) {
                Icon(Icons.Outlined.Description, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            }
            if (container.state == "running") {
                IconButton(onClick = { onAction("restart") }) {
                    Icon(Icons.Default.Refresh, contentDescription = null, tint = Color(0xFFFFA000))
                }
                IconButton(onClick = { onAction("stop") }) {
                    Icon(Icons.Default.Stop, contentDescription = null, tint = Color.Red)
                }
            } else {
                IconButton(onClick = { onAction("start") }) {
                    Icon(Icons.Default.PlayArrow, contentDescription = null, tint = Color(0xFF4CAF50))
                }
                IconButton(onClick = { onAction("rm") }) {
                    Icon(Icons.Default.Delete, contentDescription = null, tint = Color.Red)
                }
            }
        }
        Spacer(Modifier.height(24.dp))
        Text(text = stringResource(R.string.docker_basic_info), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
        DetailRow(label = stringResource(R.string.common_name), value = container.name)
        DetailRow(label = stringResource(R.string.common_id), value = container.id.take(12))
        DetailRow(label = stringResource(R.string.docker_image), value = container.image)
        container.command?.let { DetailRow(label = stringResource(R.string.docker_command), value = it) }
        container.createdAt?.let { DetailRow(label = stringResource(R.string.docker_created_at), value = it) }

        Spacer(Modifier.height(16.dp))
        Text(text = stringResource(R.string.docker_status), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
        Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(text = stringResource(R.string.docker_status), style = MaterialTheme.typography.bodyMedium)
            StatusBadge(status = container.state, showLabel = true, size = 14)
        }
        DetailRow(label = stringResource(R.string.docker_status_detail), value = container.status)

        if (container.ports.isNotBlank()) {
            Spacer(Modifier.height(16.dp))
            Text(text = stringResource(R.string.docker_mappings), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
            Text(
                text = container.ports,
                modifier = Modifier.padding(vertical = 8.dp),
                style = MaterialTheme.typography.bodySmall,
                fontFamily = FontFamily.Monospace,
                color = Color.Gray
            )
        }
        Spacer(Modifier.height(32.dp))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DockerLogDialog(
    container: DockerContainer,
    apiClient: RemoteAPIClient,
    onDismiss: () -> Unit
) {
    var logs by remember { mutableStateOf("") }
    var isLoading by remember { mutableStateOf(true) }

    LaunchedEffect(Unit) {
        while (true) {
            try {
                val api = apiClient.getApi() ?: break
                val response = api.getDockerLogs(container.id)
                if (response.isSuccessful) {
                    logs = response.body()?.logs ?: ""
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
            isLoading = false
            delay(3000)
        }
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = Color.Black
        ) {
            Column {
                TopAppBar(
                    title = { Text(stringResource(R.string.docker_container_logs, container.name), fontSize = 16.sp, color = Color.White) },
                    navigationIcon = {
                        IconButton(onClick = onDismiss) {
                            Icon(Icons.Default.Close, contentDescription = null, tint = Color.White)
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Black, titleContentColor = Color.White)
                )
                if (isLoading && logs.isEmpty()) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = Color.White)
                    }
                } else {
                    val scrollState = rememberScrollState()
                    LaunchedEffect(logs) {
                        scrollState.animateScrollTo(scrollState.maxValue)
                    }
                    Box(Modifier.weight(1f).padding(8.dp).verticalScroll(scrollState)) {
                        Text(
                            text = logs,
                            color = Color.White,
                            fontFamily = FontFamily.Monospace,
                            fontSize = 11.sp,
                            lineHeight = 14.sp
                        )
                    }
                }
                // TODO: Add AI Analysis button here later
            }
        }
    }
}
