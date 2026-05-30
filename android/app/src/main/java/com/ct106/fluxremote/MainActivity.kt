package com.ct106.flux_remote

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import androidx.navigation.NavGraph.Companion.findStartDestination
import com.ct106.flux_remote.R
import com.ct106.flux_remote.core.RemoteAPIClient
import com.ct106.flux_remote.core.ServerManager
import com.ct106.flux_remote.ui.screens.*
import kotlinx.coroutines.launch
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext

class MainActivity : ComponentActivity() {
    private lateinit var serverManager: ServerManager
    private lateinit var apiClient: RemoteAPIClient

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        serverManager = ServerManager(this)
        apiClient = RemoteAPIClient(serverManager)

        enableEdgeToEdge()

        setContent {
            val isInitializing by serverManager.isInitializing.collectAsState()
            val selectedLanguage by serverManager.language.collectAsState()
            
            val context = LocalContext.current
            val localizedContext = remember(context, selectedLanguage) {
                val locale = when (selectedLanguage) {
                    "zh" -> java.util.Locale.SIMPLIFIED_CHINESE
                    "en" -> java.util.Locale.ENGLISH
                    else -> java.util.Locale.getDefault()
                }
                val config = android.content.res.Configuration(context.resources.configuration)
                config.setLocale(locale)
                context.createConfigurationContext(config)
            }
            
            CompositionLocalProvider(LocalContext provides localizedContext) {
                FluxRemoteTheme {
                    if (isInitializing) {
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator()
                        }
                    } else {
                        MainNavigation(serverManager, apiClient)
                    }
                }
            }
        }
    }
}

@Composable
fun MainNavigation(serverManager: ServerManager, apiClient: RemoteAPIClient) {
    val navController = rememberNavController()
    val drawerState = rememberDrawerState(initialValue = DrawerValue.Closed)
    val scope = rememberCoroutineScope()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route ?: ""
    val showDrawer = currentRoute !in listOf("server_list", "login", "login?serverId={serverId}")
    val servers by serverManager.servers.collectAsState()
    val selectedServerId by serverManager.selectedServerId.collectAsState()
    val selectedServer = serverManager.getSelectedServer()
    var serverDropdownExpanded by remember { mutableStateOf(false) }
    val startDestination = if (servers.isEmpty()) "server_list" else "dashboard"

    LaunchedEffect(servers.isEmpty(), currentRoute) {
        if (servers.isEmpty() && currentRoute !in listOf("server_list", "login", "login?serverId={serverId}")) {
            navController.navigate("server_list") {
                popUpTo(0)
                launchSingleTop = true
            }
        }
    }

    // Automatic background login or features fetch when server changes or app starts
    LaunchedEffect(selectedServerId) {
        val server = serverManager.getSelectedServer()
        if (server != null) {
            if (!serverManager.isServerAuthenticated(server.id)) {
                val password = serverManager.getPassword(server.id)
                if (password != null) {
                    apiClient.login(mapOf("username" to (server.username ?: "admin"), "password" to password), server)
                }
            } else {
                // Already authenticated, fetch features to update drawer
                scope.launch {
                    try {
                        val response = apiClient.getApi()?.getSettings()
                        if (response?.isSuccessful == true) {
                            response.body()?.data?.features?.let {
                                apiClient.features = it
                            }
                        }
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }
            }
        }
    }

    // Handle system back button to close drawer
    BackHandler(enabled = drawerState.isOpen) {
        scope.launch { drawerState.close() }
    }

    ModalNavigationDrawer(
        drawerState = drawerState,
        gesturesEnabled = showDrawer,
        drawerContent = {
            if (showDrawer) {
                ModalDrawerSheet {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .verticalScroll(rememberScrollState())
                    ) {
                        Spacer(Modifier.height(12.dp))
                        
                        // --- Server Switcher at Top ---
                        Box(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                            Surface(
                                onClick = { serverDropdownExpanded = true },
                                color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.4f),
                                shape = MaterialTheme.shapes.medium,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Row(
                                    modifier = Modifier.padding(16.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Icon(Icons.Default.Storage, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                                    Spacer(Modifier.width(12.dp))
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            text = selectedServer?.name ?: "Flux Remote",
                                            style = MaterialTheme.typography.titleMedium,
                                            color = MaterialTheme.colorScheme.onPrimaryContainer
                                        )
                                        Text(
                                            text = selectedServer?.url ?: "",
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
                                        )
                                    }
                                    Icon(
                                        if (serverDropdownExpanded) Icons.Default.ArrowDropUp else Icons.Default.ArrowDropDown,
                                        contentDescription = null
                                    )
                                }
                            }
                            
                            DropdownMenu(
                                expanded = serverDropdownExpanded,
                                onDismissRequest = { serverDropdownExpanded = false },
                                modifier = Modifier.fillMaxWidth(0.8f)
                            ) {
                                servers.forEach { s ->
                                    DropdownMenuItem(
                                        text = { Text(s.name) },
                                        onClick = {
                                            serverDropdownExpanded = false
                                            scope.launch {
                                                serverManager.selectServer(s)
                                                com.aptabase.Aptabase.instance.trackEvent("server_switched")
                                                drawerState.close()
                                                
                                                if (serverManager.isServerAuthenticated(s.id) || serverManager.hasSavedPassword(s.id)) {
                                                    navController.navigate("dashboard") {
                                                        popUpTo(0)
                                                    }
                                                } else {
                                                    navController.navigate("login?serverId=${s.id}")
                                                }
                                            }
                                        },
                                        leadingIcon = {
                                            Icon(
                                                Icons.Default.Dns,
                                                contentDescription = null,
                                                tint = if (s.id == selectedServer?.id) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                        },
                                        trailingIcon = {
                                            if (s.id == selectedServer?.id) {
                                                Icon(Icons.Default.Check, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                                            }
                                        }
                                    )
                                }
                                HorizontalDivider()
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.manage_servers)) },
                                    onClick = {
                                        serverDropdownExpanded = false
                                        scope.launch {
                                            drawerState.close()
                                            navController.navigate("server_list")
                                        }
                                    },
                                    leadingIcon = { Icon(Icons.Default.Settings, contentDescription = null) }
                                )
                            }
                        }
                        
                        HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
                        
                        val features = apiClient.features
                        data class DrawerMenuItem(val label: String, val route: String, val icon: ImageVector, val category: String, val enabled: Boolean = true)
                        val menuItems = listOfNotNull(
                            // Home
                            DrawerMenuItem(stringResource(R.string.dashboard), "dashboard", Icons.Default.Dashboard, "sidebar.home"),
                            
                            // System Tools
                            if (features.processes ?: true) DrawerMenuItem(stringResource(R.string.process_mgmt), "process", Icons.Default.Memory, "sidebar.systemTools") else null,
                            if (features.ports ?: true) DrawerMenuItem(stringResource(R.string.ports_mgmt), "ports", Icons.Default.Lan, "sidebar.systemTools") else null,
                            if (features.logs ?: true) DrawerMenuItem(stringResource(R.string.logs_mgmt), "logs", Icons.Default.Description, "sidebar.systemTools") else null,
                            if (features.configs ?: true) DrawerMenuItem(stringResource(R.string.configs_mgmt), "configs", Icons.Default.Tune, "sidebar.systemTools") else null,
                            
                            // Service Management
                            if (features.launchagent ?: true) DrawerMenuItem(stringResource(R.string.launchagents_mgmt), "launchagent", Icons.Default.Bolt, "sidebar.serviceManagement") else null,
                            if (features.docker ?: true) DrawerMenuItem(stringResource(R.string.docker_mgmt), "docker", Icons.Default.DirectionsBoat, "sidebar.serviceManagement") else null,
                            if (features.nginx ?: true) DrawerMenuItem(stringResource(R.string.nginx_mgmt), "nginx", Icons.Default.Public, "sidebar.serviceManagement") else null
                        )

                        var lastCategory = ""
                        for (item in menuItems) {
                            if (item.category != lastCategory) {
                                lastCategory = item.category
                                val categoryName = when(lastCategory) {
                                    "sidebar.home" -> stringResource(R.string.home)
                                    "sidebar.systemTools" -> stringResource(R.string.system_tools)
                                    "sidebar.serviceManagement" -> stringResource(R.string.service_mgmt)
                                    else -> ""
                                }
                                if (categoryName.isNotEmpty()) {
                                    Text(
                                        text = categoryName,
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.primary,
                                        modifier = Modifier.padding(start = 28.dp, top = 16.dp, bottom = 8.dp)
                                    )
                                }
                            }
                            NavigationDrawerItem(
                                label = { Text(item.label) },
                                selected = currentRoute == item.route,
                                onClick = {
                                    scope.launch { drawerState.close() }
                                    if (currentRoute != item.route) {
                                        navController.navigate(item.route) {
                                            popUpTo(navController.graph.findStartDestination().id) {
                                                this.saveState = true
                                            }
                                            launchSingleTop = true
                                            restoreState = true
                                        }
                                    }
                                },
                                icon = { Icon(item.icon, contentDescription = null) },
                                modifier = Modifier.padding(NavigationDrawerItemDefaults.ItemPadding)
                            )
                        }

                        Spacer(Modifier.height(12.dp))
                        HorizontalDivider()
                        
                        Text(
                            text = stringResource(R.string.system),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.padding(start = 28.dp, top = 16.dp, bottom = 8.dp)
                        )
                        NavigationDrawerItem(
                            label = { Text(stringResource(R.string.settings)) },
                            selected = currentRoute == "settings",
                            onClick = {
                                scope.launch { drawerState.close() }
                                if (currentRoute != "settings") {
                                    navController.navigate("settings") {
                                        popUpTo(navController.graph.findStartDestination().id) {
                                            this.saveState = true
                                        }
                                        launchSingleTop = true
                                        restoreState = true
                                    }
                                }
                            },
                            icon = { Icon(Icons.Default.Settings, contentDescription = null) },
                            modifier = Modifier.padding(NavigationDrawerItemDefaults.ItemPadding)
                        )
                        NavigationDrawerItem(
                            label = { Text(stringResource(R.string.server_list)) },
                            selected = currentRoute == "server_list",
                            onClick = {
                                scope.launch { drawerState.close() }
                                if (currentRoute != "server_list") {
                                    navController.navigate("server_list") {
                                        popUpTo(navController.graph.findStartDestination().id) {
                                            this.saveState = true
                                        }
                                        launchSingleTop = true
                                        restoreState = true
                                    }
                                }
                            },
                            icon = { Icon(Icons.Default.Dns, contentDescription = null) },
                            modifier = Modifier.padding(NavigationDrawerItemDefaults.ItemPadding)
                        )
                    }
                }
            }
        }
    ) {
        NavHost(
            navController = navController,
            startDestination = startDestination
        ) {
                composable("dashboard") {
                    DashboardScreen(
                        serverManager = serverManager,
                        apiClient = apiClient,
                        onNavigateToServers = { scope.launch { drawerState.open() } },
                        onNavigate = { route -> navController.navigate(route) }
                    )
                }
                composable("docker") {
                    DockerScreen(
                        apiClient = apiClient,
                        onBack = { scope.launch { drawerState.open() } }
                    )
                }
                composable("nginx") {
                    NginxScreen(
                        apiClient = apiClient,
                        onEditSite = { site ->
                            if (site == null) navController.navigate("nginx_edit")
                            else navController.navigate("nginx_edit?name=${site.name}")
                        },
                        onBack = { scope.launch { drawerState.open() } }
                    )
                }
                composable(
                    "nginx_edit?name={name}",
                    arguments = listOf(navArgument("name") { type = NavType.StringType; nullable = true; defaultValue = null })
                ) { backStackEntry ->
                    val name = backStackEntry.arguments?.getString("name")
                    val site = apiClient.nginxSites.find { it.name == name }
                    NginxSiteEditScreen(
                        apiClient = apiClient,
                        site = site,
                        onBack = { navController.popBackStack() }
                    )
                }
                composable("process") {
                    ProcessScreen(
                        apiClient = apiClient,
                        onBack = { scope.launch { drawerState.open() } }
                    )
                }
                composable("ports") {
                    PortsScreen(
                        apiClient = apiClient,
                        onBack = { scope.launch { drawerState.open() } }
                    )
                }
                composable("logs") {
                    LogsScreen(
                        apiClient = apiClient,
                        onViewLog = { log -> 
                            navController.navigate("log_content?path=${log.path}&name=${log.name}")
                        },
                        onBack = { scope.launch { drawerState.open() } }
                    )
                }
                composable(
                    "log_content?path={path}&name={name}",
                    arguments = listOf(
                        navArgument("path") { type = NavType.StringType },
                        navArgument("name") { type = NavType.StringType }
                    )
                ) { backStackEntry ->
                    val path = backStackEntry.arguments?.getString("path") ?: ""
                    val name = backStackEntry.arguments?.getString("name") ?: ""
                    LogContentScreen(
                        apiClient = apiClient,
                        logItem = com.ct106.flux_remote.model.LogItem(path, name, "", "", 0, 0, false),
                        onBack = { navController.popBackStack() }
                    )
                }
                composable("configs") {
                    ConfigsScreen(
                        apiClient = apiClient,
                        onViewConfig = { config -> 
                            navController.navigate("config_content?path=${config.path}&name=${config.name}")
                        },
                        onBack = { scope.launch { drawerState.open() } }
                    )
                }
                composable(
                    "config_content?path={path}&name={name}",
                    arguments = listOf(
                        navArgument("path") { type = NavType.StringType },
                        navArgument("name") { type = NavType.StringType }
                    )
                ) { backStackEntry ->
                    val path = backStackEntry.arguments?.getString("path") ?: ""
                    val name = backStackEntry.arguments?.getString("name") ?: ""
                    ConfigContentScreen(
                        apiClient = apiClient,
                        configItem = com.ct106.flux_remote.model.ConfigItem("", name, path, "", 0, 0.0),
                        onBack = { navController.popBackStack() }
                    )
                }
                composable("launchagent") {
                    LaunchAgentScreen(
                        apiClient = apiClient,
                        onEditAgent = { agent ->
                            if (agent == null) navController.navigate("agent_edit")
                            else navController.navigate("agent_edit?path=${agent.path}")
                        },
                        onBack = { scope.launch { drawerState.open() } }
                    )
                }
                composable(
                    "agent_edit?path={path}",
                    arguments = listOf(navArgument("path") { type = NavType.StringType; nullable = true; defaultValue = null })
                ) { backStackEntry ->
                    val path = backStackEntry.arguments?.getString("path")
                    val agent = apiClient.agentItems.find { it.path == path }
                    LaunchAgentEditScreen(
                        apiClient = apiClient,
                        agent = agent,
                        onBack = { navController.popBackStack() }
                    )
                }
                composable("settings") {
                    SettingsScreen(
                        serverManager = serverManager,
                        apiClient = apiClient,
                        onBack = { 
                            if (!navController.popBackStack()) {
                                scope.launch { drawerState.open() }
                            }
                        },
                        onLogout = {
                            scope.launch {
                                serverManager.logout()
                                navController.navigate("server_list") {
                                    popUpTo(0)
                                }
                            }
                        }
                    )
                }
                composable("server_list") {
                    ServerListScreen(
                        serverManager = serverManager,
                        apiClient = apiClient,
                        onAddServer = { navController.navigate("login") },
                        onEditServer = { s -> navController.navigate("login?serverId=${s.id}") },
                        onSelectServer = { s ->
                            scope.launch {
                                serverManager.selectServer(s)
                                if (serverManager.isServerAuthenticated(s.id)) {
                                    navController.navigate("dashboard") {
                                        popUpTo(0)
                                    }
                                } else {
                                    navController.navigate("login?serverId=${s.id}")
                                }
                            }
                        }
                    )
                }
                composable(
                    "login?serverId={serverId}",
                    arguments = listOf(navArgument("serverId") { 
                        type = NavType.StringType
                        nullable = true
                        defaultValue = null
                    })
                ) { backStackEntry ->
                    val serverId = backStackEntry.arguments?.getString("serverId")
                    LoginScreen(
                        serverManager = serverManager,
                        apiClient = apiClient,
                        initialServerId = serverId,
                        onLoginSuccess = {
                            navController.navigate("dashboard") {
                                popUpTo(0)
                            }
                        },
                        onBack = { navController.popBackStack() }
                    )
                }
            }
        }
    }

@Composable
fun FluxRemoteTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S -> {
            val context = androidx.compose.ui.platform.LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> darkColorScheme()
        else -> lightColorScheme()
    }

    val view = androidx.compose.ui.platform.LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as android.app.Activity).window
            androidx.core.view.WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !darkTheme
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        content = content
    )
}
