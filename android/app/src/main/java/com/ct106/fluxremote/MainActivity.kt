package com.ct106.fluxremote

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.lifecycle.lifecycleScope
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.ct106.fluxremote.core.RemoteAPIClient
import com.ct106.fluxremote.core.ServerManager
import com.ct106.fluxremote.model.ConfigItem
import com.ct106.fluxremote.model.LogItem
import com.ct106.fluxremote.ui.screens.*
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private lateinit var serverManager: ServerManager
    private lateinit var apiClient: RemoteAPIClient

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        serverManager = ServerManager(applicationContext)
        apiClient = RemoteAPIClient(serverManager)

        lifecycleScope.launch {
            serverManager.loadInitialData()
        }

        setContent {
            FluxRemoteTheme {
                MainScreen(serverManager, apiClient)
            }
        }
    }
}

@Composable
fun MainScreen(serverManager: ServerManager, apiClient: RemoteAPIClient) {
    val navController = rememberNavController()
    val servers by serverManager.servers.collectAsState()
    val isInitializing by serverManager.isInitializing.collectAsState()
    
    if (isInitializing) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = androidx.compose.ui.Alignment.Center) {
            CircularProgressIndicator()
        }
        return
    }

    Scaffold { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = if (servers.isEmpty()) "server_list" else "dashboard",
            modifier = Modifier.padding(innerPadding)
        ) {
            composable("server_list") {
                ServerListScreen(
                    serverManager = serverManager,
                    onAddServer = { navController.navigate("login") },
                    onSelectServer = { server ->
                        if (serverManager.isServerAuthenticated(server.id)) {
                            navController.navigate("dashboard")
                        } else {
                            navController.navigate("login")
                        }
                    }
                )
            }
            composable("login") {
                LoginScreen(
                    serverManager = serverManager,
                    apiClient = apiClient,
                    onLoginSuccess = {
                        navController.navigate("dashboard") {
                            popUpTo("server_list") { inclusive = false }
                        }
                    },
                    onBack = { navController.popBackStack() }
                )
            }
            composable("dashboard") {
                DashboardScreen(
                    serverManager = serverManager,
                    apiClient = apiClient,
                    onNavigateToServers = { navController.navigate("server_list") },
                    onNavigate = { route -> navController.navigate(route) }
                )
            }
            composable("docker") {
                DockerScreen(apiClient = apiClient, onBack = { navController.popBackStack() })
            }
            composable("nginx") {
                NginxScreen(apiClient = apiClient, onBack = { navController.popBackStack() })
            }
            composable("process") {
                ProcessScreen(apiClient = apiClient, onBack = { navController.popBackStack() })
            }
            composable("logs") {
                LogsScreen(
                    apiClient = apiClient,
                    onViewLog = { log -> 
                        // Simplified passing for now, in a real app use arguments or a shared state
                        navController.navigate("log_content?path=${log.path}&name=${log.name}")
                    },
                    onBack = { navController.popBackStack() }
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
                    logItem = LogItem(path, name, "", "", 0, 0, false),
                    onBack = { navController.popBackStack() }
                )
            }
            composable("configs") {
                ConfigsScreen(
                    apiClient = apiClient,
                    onViewConfig = { config -> 
                        navController.navigate("config_content?path=${config.path}&name=${config.name}")
                    },
                    onBack = { navController.popBackStack() }
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
                    configItem = ConfigItem("", name, path, "", 0, 0.0),
                    onBack = { navController.popBackStack() }
                )
            }
            composable("launchagent") {
                LaunchAgentScreen(apiClient = apiClient, onBack = { navController.popBackStack() })
            }
            composable("settings") {
                SettingsScreen(
                    serverManager = serverManager,
                    apiClient = apiClient,
                    onBack = { navController.popBackStack() },
                    onLogout = {
                        navController.navigate("server_list") {
                            popUpTo(0) { inclusive = true }
                        }
                    }
                )
            }
        }
    }
}

@Composable
fun FluxRemoteTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(),
        content = content
    )
}
