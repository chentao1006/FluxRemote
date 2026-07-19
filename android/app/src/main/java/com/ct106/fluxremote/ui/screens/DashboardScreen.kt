package com.ct106.flux_remote.ui.screens

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.CameraAlt
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.ct106.flux_remote.R
import com.ct106.flux_remote.core.AIService
import com.ct106.flux_remote.core.RemoteAPIClient
import com.ct106.flux_remote.core.ServerManager
import com.ct106.flux_remote.core.ServerConfig
import com.ct106.flux_remote.model.*
import com.ct106.flux_remote.ui.components.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.decodeFromJsonElement

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen(
    serverManager: ServerManager,
    apiClient: RemoteAPIClient,
    onNavigateToServers: () -> Unit,
    onSelectServer: (ServerConfig) -> Unit,
    onManageServers: () -> Unit,
    onNavigate: (String) -> Unit
) {
    val context = LocalContext.current
    val server = serverManager.getSelectedServer()
    var stats by remember { mutableStateOf<RemoteSystemStats?>(null) }
    var history by remember { mutableStateOf<List<MetricPoint>>(emptyList()) }
    var prevNetBytes by remember { mutableStateOf<RemoteNetBytes?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var isRecovering by remember { mutableStateOf(false) }

    // Summary states
    var dockerSummary by remember { mutableStateOf(Pair(0, 0)) }
    var nginxSummary by remember { mutableStateOf(Pair(0, 0)) }
    var procSummary by remember { mutableStateOf(Triple(0, "", "")) }
    var portSummary by remember { mutableStateOf(PortSummary()) }
    var agentSummary by remember { mutableStateOf(Pair(0, 0)) }
    var logSummary by remember { mutableStateOf(Pair(0, "")) }
    var configSummary by remember { mutableStateOf(Triple(0, 0, 0)) }

    // AI states
    var aiAnalysis by remember { mutableStateOf<String?>(null) }
    var isAnalyzing by remember { mutableStateOf(false) }
    
    // Screenshot states
    var isCapturingScreenshot by remember { mutableStateOf(false) }
    var capturedImage by remember { mutableStateOf<ImageBitmap?>(null) }

    val scope = rememberCoroutineScope()
    var lastSummaryFetch by remember { mutableStateOf(0L) }
    var aiJob by remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }

    val authenticatedIds by serverManager.authenticatedServerIds.collectAsState()
    val isCurrentAuthenticated = server?.id?.let { authenticatedIds.contains(it) } ?: false
    val hasSavedPassword = server?.id?.let { serverManager.hasSavedPassword(it) } ?: false

    if (server == null) {
        ServerListScreen(
            serverManager = serverManager,
            apiClient = apiClient,
            onAddServer = { onNavigate("login") },
            onEditServer = { selected -> onNavigate("login?serverId=${selected.id}") },
            onSelectServer = {}
        )
        return
    }

    fun updateHistory(s: RemoteSystemStats) {
        val cpu = (s.cpu?.user ?: 0.0) + (s.cpu?.sys ?: 0.0)
        val mem = s.memory.usedMB.toDouble() / s.memory.totalMB.toDouble() * 100.0
        var netIn = 0.0; var netOut = 0.0
        val prev = prevNetBytes
        val cur = s.netBytes
        if (cur != null && prev != null) {
            netIn = (cur.`in` - prev.`in`).toDouble() / 1024.0 / 2.0
            netOut = (cur.out - prev.out).toDouble() / 1024.0 / 2.0
        }
        prevNetBytes = s.netBytes
        val newHistory = history + MetricPoint(cpu, mem, maxOf(0.0, netIn), maxOf(0.0, netOut))
        history = if (newHistory.size > 60) newHistory.drop(newHistory.size - 60) else newHistory
        apiClient.dashboardHistory.clear()
        apiClient.dashboardHistory.addAll(history)
    }

    // Returns true on success. Pass reportError=false to suppress UI error during silent probes.
    suspend fun fetchStats(reportError: Boolean = true): Boolean {
        return try {
            val api = apiClient.getApi() ?: return false
            val response = api.getStats()
            if (response.isSuccessful) {
                val s = response.body()?.data
                if (s != null) {
                    stats = s
                    apiClient.dashboardStats = s
                    errorMessage = null
                    updateHistory(s)
                    true
                } else false
            } else {
                if (stats == null && reportError) {
                    errorMessage = "HTTP Error ${response.code()}"
                }
                false
            }
        } catch (e: Exception) {
            e.printStackTrace()
            if (stats == null && reportError) {
                errorMessage = e.message ?: "Failed to connect"
            }
            false
        }
    }

    suspend fun fetchSummaries() {
        val api = apiClient.getApi() ?: return
        
        // Docker
        try {
            val dr = api.getDockerContainers()
            if (dr.isSuccessful) {
                val containers = dr.body()?.data ?: emptyList()
                dockerSummary = Pair(containers.count { it.state == "running" }, containers.size)
            }
        } catch (e: Exception) { e.printStackTrace() }

        // Nginx
        try {
            val nr = api.getNginxSites()
            if (nr.isSuccessful) {
                val sites = nr.body()?.data ?: emptyList()
                nginxSummary = Pair(sites.count { it.status == "enabled" }, sites.size)
            }
        } catch (e: Exception) { e.printStackTrace() }

        // Processes
        try {
            val pr = api.getProcesses()
            if (pr.isSuccessful) {
                val procs = pr.body()?.data ?: emptyList()
                val top = procs.firstOrNull()
                procSummary = Triple(procs.size, top?.command ?: "", if (top != null) "${top.cpu}%" else "")
            }
        } catch (e: Exception) { e.printStackTrace() }

        // Ports
        try {
            val ports = api.getPorts()
            if (ports.isSuccessful) {
                portSummary = ports.body()?.summary ?: PortSummary()
            }
        } catch (e: Exception) { e.printStackTrace() }

        // LaunchAgents
        try {
            val ar = api.getLaunchAgents()
            if (ar.isSuccessful) {
                val agents = ar.body()?.data ?: emptyList()
                agentSummary = Pair(agents.count { it.isLoaded }, agents.size)
            }
        } catch (e: Exception) { e.printStackTrace() }

        // Logs
        try {
            val lr = api.getLogs()
            if (lr.isSuccessful) {
                val data = lr.body()?.data
                if (data is JsonArray) {
                    val logs = Json { ignoreUnknownKeys = true }.decodeFromJsonElement<List<LogItem>>(data)
                    val topCategory = logs.groupBy { it.category }.maxByOrNull { it.value.size }?.key ?: ""
                    logSummary = Pair(logs.size, topCategory)
                }
            }
        } catch (e: Exception) { e.printStackTrace() }

        // Configs
        try {
            val cr = api.getConfigs()
            if (cr.isSuccessful) {
                val configs = cr.body()?.data ?: emptyList()
                val sysCount = configs.count { it.category.lowercase() == "system" }
                val usrCount = configs.count { it.category.lowercase() == "user" }
                configSummary = Triple(configs.size, sysCount, usrCount)
            }
        } catch (e: Exception) { e.printStackTrace() }
    }

    fun analyzeSystem() {
        val currentStats = stats ?: return
        isAnalyzing = true
        aiAnalysis = null
        val content = """
            Hostname: ${currentStats.hostname}
            OS: ${currentStats.osVersion}
            CPU: ${((currentStats.cpu?.user ?: 0.0) + (currentStats.cpu?.sys ?: 0.0)).toInt()}%
            Memory: ${currentStats.memory.usedMB}/${currentStats.memory.totalMB}MB
            Disk: ${currentStats.disk.percent}
            Load: ${currentStats.loadAvg}
            Processes: ${procSummary.first} Total, Top: ${procSummary.second} (${procSummary.third})
            Ports: ${portSummary.ports} Used, ${portSummary.listening} Listening
            Docker: ${dockerSummary.first}/${dockerSummary.second} Running
            Nginx: ${nginxSummary.first}/${nginxSummary.second} Active
            LaunchAgents: ${agentSummary.first}/${agentSummary.second} Loaded
        """.trimIndent()
        val langName = context.getString(R.string.lang_name)
        val systemPrompt = context.getString(R.string.system_expert_role, langName)

        aiJob?.cancel()
        aiJob = scope.launch {
            AIService.getInstance(context).analyzeStream(content, systemPrompt, apiClient)
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

    fun takeScreenshot() {
        isCapturingScreenshot = true
        scope.launch {
            try {
                val api = apiClient.getApi() ?: return@launch
                val response = api.getScreenshot()
                if (response.isSuccessful && response.body()?.success == true) {
                    val base64 = response.body()?.data?.substringAfter(",") ?: ""
                    val decodedString = Base64.decode(base64, Base64.DEFAULT)
                    val bitmap = BitmapFactory.decodeByteArray(decodedString, 0, decodedString.size)
                    capturedImage = bitmap.asImageBitmap()
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
            isCapturingScreenshot = false
        }
    }

    // Returns true if re-login succeeded after fetching latest URL via MQTT
    suspend fun attemptMqttRecovery(): Boolean {
        val mqttSync = com.ct106.flux_remote.core.MQTTRemoteSync.getInstance(context)
        val serverTopic = server.mqttTopic ?: return false
        val serverKey = server.mqttKey ?: return false

        val deferred = kotlinx.coroutines.CompletableDeferred<com.ct106.flux_remote.core.MQTTRemoteSync.FetchResult?>()
        mqttSync.fetchLatestData(serverTopic, serverKey, timeoutMs = 15000) { deferred.complete(it) }
        val data = deferred.await()
        val newUrl = data?.url ?: return false

        if (newUrl != server.url) {
            server.url = newUrl
            if (!data.user.isNullOrEmpty()) server.username = data.user
            if (!data.hostname.isNullOrEmpty() && server.name == "Remote Mac") server.name = data.hostname
            if (!data.pass.isNullOrEmpty()) serverManager.setPassword(server.id, data.pass)
            serverManager.updateServer(server)
        }
        val testPass = if (!data.pass.isNullOrEmpty()) data.pass else serverManager.getPassword(server.id)
        return apiClient.login(
            mapOf("username" to (server.username ?: ""), "password" to (testPass ?: "")),
            server
        )
    }

    LaunchedEffect(server.id, isCurrentAuthenticated) {
        if (isCurrentAuthenticated || hasSavedPassword) {
            // Silent probe first — no error flash
            if (!fetchStats(reportError = false)) {
                // MQTT recovery: show loading indicator, never show error mid-recovery
                isRecovering = true
                errorMessage = null
                val recovered = attemptMqttRecovery()
                isRecovering = false
                if (!recovered) {
                    // Both failed — now surface the error
                    fetchStats(reportError = true)
                }
                // If recovered: login succeeded; while loop will fetch stats silently
            }
            fetchSummaries()
            lastSummaryFetch = System.currentTimeMillis()
        }

        var consecutiveFailures = 0
        while (true) {
            if (serverManager.isServerAuthenticated(server.id) || serverManager.hasSavedPassword(server.id)) {
                val ok = fetchStats(reportError = false)
                if (ok) {
                    consecutiveFailures = 0
                } else {
                    consecutiveFailures++
                    if (consecutiveFailures >= 3) {
                        // ~6 s of consecutive failures — try MQTT recovery
                        consecutiveFailures = 0
                        isRecovering = true
                        errorMessage = null
                        val recovered = attemptMqttRecovery()
                        isRecovering = false
                        if (!recovered) fetchStats(reportError = true)
                    }
                }
                val now = System.currentTimeMillis()
                if (now - lastSummaryFetch > 30_000) {
                    fetchSummaries()
                    lastSummaryFetch = now
                }
            }
            delay(2000)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    ServerSwitcherTitle(
                        title = stringResource(R.string.dashboard),
                        serverManager = serverManager,
                        onSelectServer = onSelectServer,
                        onManageServers = onManageServers
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onNavigateToServers) {
                        Icon(Icons.Default.Menu, contentDescription = null)
                    }
                },
                actions = {
                    IconButton(onClick = { analyzeSystem() }, enabled = !isAnalyzing && stats != null) {
                        if (isAnalyzing) CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                        else Icon(Icons.Default.AutoAwesome, contentDescription = stringResource(R.string.ai_analyze), tint = MaterialTheme.colorScheme.primary)
                    }
                    IconButton(onClick = { takeScreenshot() }, enabled = !isCapturingScreenshot) {
                        if (isCapturingScreenshot) CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                        else Icon(Icons.Default.CameraAlt, contentDescription = stringResource(R.string.monitor_screenshot))
                    }
                    IconButton(onClick = { onNavigate("settings") }) {
                        Icon(Icons.Default.Settings, contentDescription = null)
                    }
                    IconButton(onClick = {
                        scope.launch { 
                            fetchStats()
                            fetchSummaries()
                            lastSummaryFetch = System.currentTimeMillis() 
                        }
                    }) {
                        Icon(Icons.Default.Refresh, contentDescription = null)
                    }
                }
            )
        }
    ) { padding ->
        if (stats == null) {
            val msg = if (isRecovering) stringResource(R.string.reconnecting) else errorMessage
            LoadingView(
                Modifier.padding(padding),
                message = msg
            )
            return@Scaffold
        }

        val configuration = androidx.compose.ui.platform.LocalConfiguration.current
        val isLandscape = configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE

        LazyColumn(
            modifier = Modifier.padding(padding).fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            item {
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

            item {
                if (isLandscape) {
                    Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                        Column(modifier = Modifier.weight(1f)) {
                            MetricsSection(stats!!, history)
                        }
                        Column(modifier = Modifier.weight(1f)) {
                            ServicesSection(dockerSummary, nginxSummary, procSummary, portSummary, agentSummary, configSummary, logSummary, onNavigate)
                            Spacer(Modifier.height(20.dp))
                            SystemInfoSection(stats!!)
                        }
                    }
                } else {
                    Column {
                        MetricsSection(stats!!, history)
                        Spacer(Modifier.height(20.dp))
                        ServicesSection(dockerSummary, nginxSummary, procSummary, portSummary, agentSummary, configSummary, logSummary, onNavigate)
                        Spacer(Modifier.height(20.dp))
                        SystemInfoSection(stats!!)
                    }
                }
            }
        }
    }

    // Screenshot Preview Dialog
    if (capturedImage != null) {
        Dialog(
            onDismissRequest = { capturedImage = null },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            Surface(modifier = Modifier.fillMaxSize(), color = Color.Black) {
                Box {
                    Image(
                        bitmap = capturedImage!!,
                        contentDescription = null,
                        modifier = Modifier.fillMaxSize(),
                        contentScale = ContentScale.Fit
                    )
                    TopAppBar(
                        title = { Text(stringResource(R.string.monitor_screenshot), color = Color.White) },
                        navigationIcon = {
                            IconButton(onClick = { capturedImage = null }) {
                                Icon(Icons.Default.Close, contentDescription = null, tint = Color.White)
                            }
                        },
                        colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent)
                    )
                }
            }
        }
    }
}

@Composable
private fun MetricsSection(stats: RemoteSystemStats, history: List<MetricPoint>) {
    SectionHeader(stringResource(R.string.monitor_metrics))
    Spacer(Modifier.height(12.dp))
    val cpuVal = (stats.cpu?.user ?: 0.0) + (stats.cpu?.sys ?: 0.0)
    val memPct = stats.memory.usedMB.toDouble() / stats.memory.totalMB * 100
    val netIn = history.lastOrNull()?.netIn ?: 0.0
    val netOut = history.lastOrNull()?.netOut ?: 0.0

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        MetricChartCard(
            title = stringResource(R.string.cpu),
            value = "${cpuVal.toInt()}%",
            subValue = stringResource(R.string.cpu_usage_detail, stats.cpu?.user?.toInt() ?: 0, stats.cpu?.sys?.toInt() ?: 0),
            color = Color(0xFF4A90D9),
            data = history.map { it.cpu },
            domain = 0.0..100.0
        )
        MetricChartCard(
            title = stringResource(R.string.memory),
            value = "${memPct.toInt()}%",
            subValue = "${stats.memory.usedMB} MB / ${stats.memory.totalMB} MB",
            color = Color(0xFFE8873A),
            data = history.map { it.memory },
            domain = 0.0..100.0
        )
        NetworkChartCard(
            netIn = netIn,
            netOut = netOut,
            data = history
        )
    }
}

@Composable
private fun ServicesSection(
    docker: Pair<Int, Int>,
    nginx: Pair<Int, Int>,
    proc: Triple<Int, String, String>,
    ports: PortSummary,
    agent: Pair<Int, Int>,
    config: Triple<Int, Int, Int>,
    log: Pair<Int, String>,
    onNavigate: (String) -> Unit
) {
    SectionHeader(stringResource(R.string.monitor_sections))
    Spacer(Modifier.height(12.dp))
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            SummaryCard(Modifier.weight(1f), Icons.Default.Memory, stringResource(R.string.process_mgmt), if (proc.second.isNotEmpty()) proc.second else "${proc.first}", if (proc.second.isNotEmpty()) "${proc.first} ${stringResource(R.string.processes)}" else "", proc.third) { onNavigate("process") }
            SummaryCard(Modifier.weight(1f), Icons.Default.Lan, stringResource(R.string.ports_mgmt), "${ports.ports}", "${ports.listening} ${stringResource(R.string.ports_listening)}") { onNavigate("ports") }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            SummaryCard(Modifier.weight(1f), Icons.Default.Description, stringResource(R.string.logs_mgmt), if (log.second.isNotEmpty()) getLocalizedCategory(log.second) else stringResource(R.string.none), "${log.first} ${stringResource(R.string.logs)}") { onNavigate("logs") }
            SummaryCard(Modifier.weight(1f), Icons.Default.Settings, stringResource(R.string.configs_mgmt), "${config.second} ${stringResource(R.string.config_sys)} | ${config.third} ${stringResource(R.string.config_user)}", "${config.first} ${stringResource(R.string.configs)}") { onNavigate("configs") }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            SummaryCard(Modifier.weight(1f), Icons.Default.Bolt, stringResource(R.string.launchagents_mgmt), "${agent.first} / ${agent.second}", stringResource(R.string.agents_loaded)) { onNavigate("launchagent") }
            SummaryCard(Modifier.weight(1f), Icons.Default.Storage, stringResource(R.string.docker_mgmt), "${docker.first} / ${docker.second}", stringResource(R.string.docker_running)) { onNavigate("docker") }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            SummaryCard(Modifier.weight(1f), Icons.Default.Public, stringResource(R.string.nginx_mgmt), "${nginx.first} / ${nginx.second}", stringResource(R.string.nginx_active)) { onNavigate("nginx") }
            Spacer(Modifier.weight(1f))
        }
    }
}

@Composable
private fun SystemInfoSection(stats: RemoteSystemStats) {
    SectionHeader(stringResource(R.string.monitor_info))
    Spacer(Modifier.height(12.dp))
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SystemDetailTile(Modifier.weight(1f), Icons.Default.Computer, stringResource(R.string.hostname), stats.hostname)
            SystemDetailTile(Modifier.weight(1f), Icons.Default.Info, stringResource(R.string.os_version), stats.osVersion)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SystemDetailTile(Modifier.weight(1f), Icons.Default.AccessTime, stringResource(R.string.uptime), stats.uptime.split(",").firstOrNull() ?: stats.uptime)
            SystemDetailTile(Modifier.weight(1f), Icons.Default.DeveloperBoard, stringResource(R.string.arch), stats.arch)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SystemDetailTile(Modifier.weight(1f), Icons.Default.Storage, stringResource(R.string.disk_usage), "${stats.disk.used} / ${stats.disk.total}")
            SystemDetailTile(Modifier.weight(1f), Icons.Default.Speed, stringResource(R.string.load_avg), stats.loadAvg)
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(text = title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
}
