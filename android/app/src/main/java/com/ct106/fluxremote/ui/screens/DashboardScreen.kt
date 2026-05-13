package com.ct106.fluxremote.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ct106.fluxremote.R
import com.ct106.fluxremote.core.RemoteAPIClient
import com.ct106.fluxremote.core.ServerManager
import com.ct106.fluxremote.model.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.Json

data class MetricPoint(val cpu: Double, val memory: Double, val netIn: Double, val netOut: Double)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen(
    serverManager: ServerManager,
    apiClient: RemoteAPIClient,
    onNavigateToServers: () -> Unit,
    onNavigate: (String) -> Unit
) {
    val server = serverManager.getSelectedServer()
    var stats by remember { mutableStateOf<RemoteSystemStats?>(null) }
    var history by remember { mutableStateOf<List<MetricPoint>>(emptyList()) }
    var prevNetBytes by remember { mutableStateOf<RemoteNetBytes?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    // Summary states
    var dockerSummary by remember { mutableStateOf(Pair(0, 0)) }
    var nginxSummary by remember { mutableStateOf(Pair(0, 0)) }
    var procSummary by remember { mutableStateOf(Triple(0, "", "")) }
    var agentSummary by remember { mutableStateOf(Pair(0, 0)) }
    var logSummary by remember { mutableStateOf(Pair(0, "")) }
    var configSummary by remember { mutableStateOf(Triple(0, 0, 0)) }

    val scope = rememberCoroutineScope()
    var lastSummaryFetch by remember { mutableStateOf(0L) }

    val authenticatedIds by serverManager.authenticatedServerIds.collectAsState()
    val isCurrentAuthenticated = server?.id?.let { authenticatedIds.contains(it) } ?: false
    val hasSavedPassword = server?.id?.let { serverManager.hasSavedPassword(it) } ?: false

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
    }

    suspend fun fetchStats() {
        try {
            val api = apiClient.getApi()
            if (api == null) {
                errorMessage = "API Client not initialized"
                return
            }
            val response = api.getStats()
            if (response.isSuccessful) {
                val s = response.body()?.data
                if (s != null) {
                    stats = s
                    errorMessage = null
                    updateHistory(s)
                } else {
                    errorMessage = "Empty data received"
                }
            } else {
                // Silence errors if we have a saved password but are not yet authenticated
                if (!isCurrentAuthenticated && hasSavedPassword) {
                    // Ignore error, wait for background login
                } else {
                    errorMessage = "Server error: ${response.code()} ${response.message()}"
                }
            }
        } catch (e: Exception) {
            if (!isCurrentAuthenticated && hasSavedPassword) {
                // Ignore error
            } else {
                errorMessage = e.message ?: "Unknown error"
            }
            e.printStackTrace()
        }
    }

    suspend fun fetchSummaries() {
        val api = apiClient.getApi() ?: return
        
        // Docker
        try {
            val dr = api.getDockerContainers()
            if (dr.isSuccessful) {
                val containers = dr.body()?.data ?: emptyList()
                dockerSummary = Pair(containers.count { it.state.lowercase().contains("running") || it.state.lowercase().contains("up") }, containers.size)
            }
        } catch (e: Exception) { e.printStackTrace() }

        // Nginx
        try {
            val nr = api.getNginxSites()
            if (nr.isSuccessful) {
                val sites = nr.body()?.data ?: emptyList()
                nginxSummary = Pair(sites.count { it.status.lowercase().contains("enabled") || it.status.lowercase().contains("active") || it.status.lowercase().contains("running") }, sites.size)
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
                if (data != null) {
                    val logs = Json { ignoreUnknownKeys = true }.decodeFromJsonElement(kotlinx.serialization.builtins.ListSerializer(LogItem.serializer()), data)
                    val sorted = logs.sortedByDescending { it.mtime }
                    logSummary = Pair(logs.size, sorted.firstOrNull()?.name ?: "")
                }
            }
        } catch (e: Exception) { e.printStackTrace() }

        // Configs
        try {
            val cr = api.getConfigs()
            if (cr.isSuccessful) {
                val configs = cr.body()?.data ?: emptyList()
                val sysCount = configs.count { it.category.lowercase() in listOf("system", "sys") }
                configSummary = Triple(configs.size, sysCount, configs.size - sysCount)
            }
        } catch (e: Exception) { e.printStackTrace() }
    }


    LaunchedEffect(server?.id, isCurrentAuthenticated) {
        if (server != null && (isCurrentAuthenticated || hasSavedPassword)) {
            fetchStats()
            fetchSummaries()
            lastSummaryFetch = System.currentTimeMillis()
        }
        
        while (true) {
            if (server != null && (serverManager.isServerAuthenticated(server.id) || serverManager.hasSavedPassword(server.id))) {
                fetchStats()
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
                title = { Text(server?.name ?: stringResource(R.string.dashboard)) },
                navigationIcon = {
                    IconButton(onClick = onNavigateToServers) {
                        Icon(Icons.Default.Menu, contentDescription = null)
                    }
                },
                actions = {
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
        if (stats == null && (errorMessage == null || (hasSavedPassword && !isCurrentAuthenticated))) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
            return@Scaffold
        }

        if (errorMessage != null && stats == null) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Default.WifiOff, contentDescription = null, modifier = Modifier.size(48.dp), tint = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.height(16.dp))
                    Text(errorMessage ?: "", color = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.height(16.dp))
                    Button(onClick = { 
                        scope.launch { 
                            fetchStats()
                            fetchSummaries()
                            lastSummaryFetch = System.currentTimeMillis()
                        } 
                    }) { Text(stringResource(R.string.refresh)) }
                }
            }
            return@Scaffold
        }

        val configuration = androidx.compose.ui.platform.LocalConfiguration.current
        val isLandscape = configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE

        LazyColumn(
            modifier = Modifier.padding(padding).fillMaxSize(),
            contentPadding = PaddingValues(bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            item {
                if (isLandscape) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                        horizontalArrangement = Arrangement.spacedBy(20.dp)
                    ) {
                        // Left Column: Metrics
                        Column(modifier = Modifier.weight(1f)) {
                            SectionHeader(stringResource(R.string.metrics_section))
                            Spacer(Modifier.height(12.dp))
                            val s = stats!!
                            val cpuVal = (s.cpu?.user ?: 0.0) + (s.cpu?.sys ?: 0.0)
                            val memPct = s.memory.usedMB.toDouble() / s.memory.totalMB * 100
                            val netIn = history.lastOrNull()?.netIn ?: 0.0
                            val netOut = history.lastOrNull()?.netOut ?: 0.0

                            MetricChartCard(
                                title = stringResource(R.string.cpu),
                                value = "${cpuVal.toInt()}%",
                                subValue = "User: ${s.cpu?.user?.toInt() ?: 0}% | Sys: ${s.cpu?.sys?.toInt() ?: 0}%",
                                color = Color(0xFF4A90D9),
                                data = history.map { it.cpu },
                                domain = 0.0..100.0
                            )
                            Spacer(Modifier.height(12.dp))
                            MetricChartCard(
                                title = stringResource(R.string.memory),
                                value = "${memPct.toInt()}%",
                                subValue = "${s.memory.usedMB} MB / ${s.memory.totalMB} MB",
                                color = Color(0xFFE8873A),
                                data = history.map { it.memory },
                                domain = 0.0..100.0
                            )
                            Spacer(Modifier.height(12.dp))
                            NetworkChartCard(
                                netIn = netIn,
                                netOut = netOut,
                                data = history
                            )
                        }

                        // Right Column: Service Summaries
                        Column(modifier = Modifier.weight(1f)) {
                            SectionHeader(stringResource(R.string.sections_section))
                            Spacer(Modifier.height(12.dp))
                            
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                SummaryCard(
                                    modifier = Modifier.weight(1f),
                                    icon = Icons.Default.Memory,
                                    title = stringResource(R.string.process_mgmt),
                                    value = if (procSummary.second.isNotEmpty()) procSummary.second else "${procSummary.first}",
                                    subtitle = if (procSummary.second.isNotEmpty()) "${procSummary.first} ${stringResource(R.string.processes)}" else "",
                                    rightLabel = procSummary.third,
                                    onClick = { onNavigate("process") }
                                )
                                SummaryCard(
                                    modifier = Modifier.weight(1f),
                                    icon = Icons.Default.Description,
                                    title = stringResource(R.string.logs_mgmt),
                                    value = if (logSummary.second.isNotEmpty()) logSummary.second else stringResource(R.string.none),
                                    subtitle = "${logSummary.first} ${stringResource(R.string.logs)}",
                                    onClick = { onNavigate("logs") }
                                )
                            }
                            Spacer(Modifier.height(12.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                SummaryCard(
                                    modifier = Modifier.weight(1f),
                                    icon = Icons.Default.Settings,
                                    title = stringResource(R.string.configs_mgmt),
                                    value = "${configSummary.second} sys | ${configSummary.third} usr",
                                    subtitle = "${configSummary.first} ${stringResource(R.string.configs)}",
                                    onClick = { onNavigate("configs") }
                                )
                                SummaryCard(
                                    modifier = Modifier.weight(1f),
                                    icon = Icons.Default.Bolt,
                                    title = stringResource(R.string.launchagents_mgmt),
                                    value = "${agentSummary.first} / ${agentSummary.second}",
                                    subtitle = stringResource(R.string.agents_loaded),
                                    onClick = { onNavigate("launchagent") }
                                )
                            }
                            Spacer(Modifier.height(12.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                SummaryCard(
                                    modifier = Modifier.weight(1f),
                                    icon = Icons.Default.Storage,
                                    title = stringResource(R.string.docker_mgmt),
                                    value = "${dockerSummary.first} / ${dockerSummary.second}",
                                    subtitle = stringResource(R.string.docker_running),
                                    onClick = { onNavigate("docker") }
                                )
                                SummaryCard(
                                    modifier = Modifier.weight(1f),
                                    icon = Icons.Default.Public,
                                    title = stringResource(R.string.nginx_mgmt),
                                    value = "${nginxSummary.first} / ${nginxSummary.second}",
                                    subtitle = stringResource(R.string.nginx_active),
                                    onClick = { onNavigate("nginx") }
                                )
                            }

                            Spacer(Modifier.height(20.dp))
                            SectionHeader(stringResource(R.string.system_info_section))
                            Spacer(Modifier.height(12.dp))
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                val s = stats!!
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    SystemDetailTile(Modifier.weight(1f), icon = Icons.Default.Computer, title = stringResource(R.string.hostname), value = s.hostname)
                                    SystemDetailTile(Modifier.weight(1f), icon = Icons.Default.Info, title = stringResource(R.string.os_version), value = s.osVersion)
                                }
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    SystemDetailTile(Modifier.weight(1f), icon = Icons.Default.AccessTime, title = stringResource(R.string.uptime), value = s.uptime.split(",").firstOrNull() ?: s.uptime)
                                    SystemDetailTile(Modifier.weight(1f), icon = Icons.Default.DeveloperBoard, title = stringResource(R.string.arch), value = s.arch)
                                }
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    SystemDetailTile(Modifier.weight(1f), icon = Icons.Default.Storage, title = stringResource(R.string.disk_usage), value = "${s.disk.used} / ${s.disk.total}")
                                    SystemDetailTile(Modifier.weight(1f), icon = Icons.Default.Speed, title = stringResource(R.string.load_avg), value = s.loadAvg)
                                }
                            }
                        }
                    }
                } else {
                    // Portrait - Single Column
                    Column {
                        SectionHeader(stringResource(R.string.metrics_section))
                        Spacer(Modifier.height(12.dp))
                        val s = stats!!
                        val cpuVal = (s.cpu?.user ?: 0.0) + (s.cpu?.sys ?: 0.0)
                        val memPct = s.memory.usedMB.toDouble() / s.memory.totalMB * 100
                        val netIn = history.lastOrNull()?.netIn ?: 0.0
                        val netOut = history.lastOrNull()?.netOut ?: 0.0

                        Column(
                            modifier = Modifier.padding(horizontal = 16.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            MetricChartCard(
                                modifier = Modifier.fillMaxWidth(),
                                title = stringResource(R.string.cpu),
                                value = "${cpuVal.toInt()}%",
                                subValue = "User: ${s.cpu?.user?.toInt() ?: 0}% | Sys: ${s.cpu?.sys?.toInt() ?: 0}%",
                                color = Color(0xFF4A90D9),
                                data = history.map { it.cpu },
                                domain = 0.0..100.0
                            )
                            MetricChartCard(
                                modifier = Modifier.fillMaxWidth(),
                                title = stringResource(R.string.memory),
                                value = "${memPct.toInt()}%",
                                subValue = "${s.memory.usedMB} MB / ${s.memory.totalMB} MB",
                                color = Color(0xFFE8873A),
                                data = history.map { it.memory },
                                domain = 0.0..100.0
                            )
                            NetworkChartCard(
                                modifier = Modifier.fillMaxWidth(),
                                netIn = netIn,
                                netOut = netOut,
                                data = history
                            )
                        }
                    }
                }
            }

            if (!isLandscape) {
                item {
                    SectionHeader(stringResource(R.string.sections_section))
                    Spacer(Modifier.height(12.dp))
                    Column(
                        modifier = Modifier.padding(horizontal = 16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            SummaryCard(
                                modifier = Modifier.weight(1f),
                                icon = Icons.Default.Memory,
                                title = stringResource(R.string.process_mgmt),
                                value = if (procSummary.second.isNotEmpty()) procSummary.second else "${procSummary.first}",
                                subtitle = if (procSummary.second.isNotEmpty()) "${procSummary.first} ${stringResource(R.string.processes)}" else "",
                                rightLabel = procSummary.third,
                                onClick = { onNavigate("process") }
                            )
                            SummaryCard(
                                modifier = Modifier.weight(1f),
                                icon = Icons.Default.Description,
                                title = stringResource(R.string.logs_mgmt),
                                value = if (logSummary.second.isNotEmpty()) logSummary.second else stringResource(R.string.none),
                                subtitle = "${logSummary.first} ${stringResource(R.string.logs)}",
                                onClick = { onNavigate("logs") }
                            )
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            SummaryCard(
                                modifier = Modifier.weight(1f),
                                icon = Icons.Default.Settings,
                                title = stringResource(R.string.configs_mgmt),
                                value = "${configSummary.second} sys | ${configSummary.third} usr",
                                subtitle = "${configSummary.first} ${stringResource(R.string.configs)}",
                                onClick = { onNavigate("configs") }
                            )
                            SummaryCard(
                                modifier = Modifier.weight(1f),
                                icon = Icons.Default.Bolt,
                                title = stringResource(R.string.launchagents_mgmt),
                                value = "${agentSummary.first} / ${agentSummary.second}",
                                subtitle = stringResource(R.string.agents_loaded),
                                onClick = { onNavigate("launchagent") }
                            )
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            SummaryCard(
                                modifier = Modifier.weight(1f),
                                icon = Icons.Default.Storage,
                                title = stringResource(R.string.docker_mgmt),
                                value = "${dockerSummary.first} / ${dockerSummary.second}",
                                subtitle = stringResource(R.string.docker_running),
                                onClick = { onNavigate("docker") }
                            )
                            SummaryCard(
                                modifier = Modifier.weight(1f),
                                icon = Icons.Default.Public,
                                title = stringResource(R.string.nginx_mgmt),
                                value = "${nginxSummary.first} / ${nginxSummary.second}",
                                subtitle = stringResource(R.string.nginx_active),
                                onClick = { onNavigate("nginx") }
                            )
                        }
                    }
                }

                // System Info Section (Portrait)
                item {
                    val s = stats!!
                    SectionHeader(stringResource(R.string.system_info_section))
                    Spacer(Modifier.height(12.dp))
                    Column(
                        modifier = Modifier.padding(horizontal = 16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            SystemDetailTile(Modifier.weight(1f), icon = Icons.Default.Computer, title = stringResource(R.string.hostname), value = s.hostname)
                            SystemDetailTile(Modifier.weight(1f), icon = Icons.Default.Info, title = stringResource(R.string.os_version), value = s.osVersion)
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            SystemDetailTile(Modifier.weight(1f), icon = Icons.Default.AccessTime, title = stringResource(R.string.uptime), value = s.uptime.split(",").firstOrNull() ?: s.uptime)
                            SystemDetailTile(Modifier.weight(1f), icon = Icons.Default.DeveloperBoard, title = stringResource(R.string.arch), value = s.arch)
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            SystemDetailTile(Modifier.weight(1f), icon = Icons.Default.Storage, title = stringResource(R.string.disk_usage), value = "${s.disk.used} / ${s.disk.total}")
                            SystemDetailTile(Modifier.weight(1f), icon = Icons.Default.Speed, title = stringResource(R.string.load_avg), value = s.loadAvg)
                        }
                        if (s.battery != null) {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                SystemDetailTile(Modifier.weight(1f), icon = Icons.Default.BatteryFull, title = stringResource(R.string.battery), value = s.battery)
                                Spacer(Modifier.weight(1f))
                            }
                        }
                    }
                }
            }

            item { Spacer(Modifier.height(16.dp)) }
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(horizontal = 16.dp)
    )
}

@Composable
fun MetricChartCard(
    modifier: Modifier = Modifier,
    title: String,
    value: String,
    subValue: String,
    color: Color,
    data: List<Double>,
    domain: ClosedRange<Double>
) {
    val surfaceColor = MaterialTheme.colorScheme.surfaceVariant
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f))
    ) {
        Column(Modifier.padding(12.dp)) {
            Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(4.dp))
            Text(value, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = color)
            Text(subValue, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
            Spacer(Modifier.height(8.dp))
            SparklineChart(data = data, color = color, domain = domain, modifier = Modifier.fillMaxWidth().height(55.dp))
        }
    }
}

@Composable
fun NetworkChartCard(
    modifier: Modifier = Modifier,
    netIn: Double,
    netOut: Double,
    data: List<MetricPoint>
) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f))
    ) {
        Column(Modifier.padding(12.dp)) {
            Text("Network", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(4.dp))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("↓${netIn.toInt()}", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Color(0xFF4A90D9))
                Text("↑${netOut.toInt()}", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Color(0xFF5CB85C))
                Text("KB/s", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text("", style = MaterialTheme.typography.labelSmall)
            Spacer(Modifier.height(8.dp))
            Box(Modifier.fillMaxWidth().height(55.dp)) {
                SparklineChart(data = data.map { it.netIn }, color = Color(0xFF4A90D9), domain = let {
                    val max = data.maxOfOrNull { maxOf(it.netIn, it.netOut) } ?: 10.0
                    0.0..maxOf(10.0, max * 1.2)
                }, modifier = Modifier.matchParentSize())
                SparklineChart(data = data.map { it.netOut }, color = Color(0xFF5CB85C), domain = let {
                    val max = data.maxOfOrNull { maxOf(it.netIn, it.netOut) } ?: 10.0
                    0.0..maxOf(10.0, max * 1.2)
                }, modifier = Modifier.matchParentSize(), fillAlpha = 0.08f)
            }
        }
    }
}

@Composable
fun SparklineChart(
    data: List<Double>,
    color: Color,
    domain: ClosedRange<Double>,
    modifier: Modifier = Modifier,
    fillAlpha: Float = 0.15f
) {
    Canvas(modifier = modifier) {
        if (data.size < 2) return@Canvas
        val w = size.width; val h = size.height
        val domainRange = (domain.endInclusive - domain.start).coerceAtLeast(1.0)
        // Fixed 2-minute window (60 points at 2s, so 59 segments). Align to the RIGHT.
        val offset = 60 - data.size
        fun xOf(i: Int) = (i + offset).toFloat() / 59f * w
        fun yOf(v: Double) = h - ((v - domain.start) / domainRange * h).toFloat()

        val fillPath = Path().apply {
            moveTo(xOf(0), h)
            data.forEachIndexed { i, v -> lineTo(xOf(i), yOf(v)) }
            lineTo(xOf(data.lastIndex), h)
            close()
        }
        drawPath(fillPath, color.copy(alpha = fillAlpha))

        val linePath = Path().apply {
            data.forEachIndexed { i, v ->
                if (i == 0) moveTo(xOf(i), yOf(v)) else lineTo(xOf(i), yOf(v))
            }
        }
        drawPath(linePath, color, style = Stroke(width = 2.dp.toPx()))
    }
}

@Composable
fun SummaryCard(
    modifier: Modifier = Modifier,
    icon: ImageVector,
    title: String,
    value: String,
    subtitle: String,
    rightLabel: String = "",
    onClick: () -> Unit
) {
    Card(
        modifier = modifier.clickable { onClick() },
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f))
    ) {
        Column(Modifier.padding(12.dp).fillMaxWidth()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, contentDescription = null, modifier = Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.width(4.dp))
                Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                if (rightLabel.isNotEmpty()) {
                    Spacer(Modifier.weight(1f))
                    Text(rightLabel, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
                }
            }
            Spacer(Modifier.height(8.dp))
            Text(value, fontSize = 18.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            if (subtitle.isNotEmpty()) {
                Text(subtitle, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
            }
        }
    }
}

@Composable
fun SystemDetailTile(
    modifier: Modifier = Modifier,
    icon: ImageVector,
    title: String,
    value: String
) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f))
    ) {
        Column(Modifier.padding(12.dp).fillMaxWidth().defaultMinSize(minHeight = 64.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, contentDescription = null, modifier = Modifier.size(12.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.width(4.dp))
                Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Spacer(Modifier.height(6.dp))
            Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 1)
        }
    }
}
