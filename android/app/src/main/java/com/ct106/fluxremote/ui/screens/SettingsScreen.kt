package com.ct106.fluxremote.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.ct106.fluxremote.R
import com.ct106.fluxremote.core.RemoteAPIClient
import com.ct106.fluxremote.core.ServerManager
import com.ct106.fluxremote.model.ServerSettings
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    serverManager: ServerManager,
    apiClient: RemoteAPIClient,
    onBack: () -> Unit,
    onLogout: () -> Unit
) {
    val server = serverManager.getSelectedServer()
    var settings by remember { mutableStateOf<ServerSettings?>(null) }
    var isLoading by remember { mutableStateOf(false) }
    var showingLogoutAlert by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(Unit) {
        isLoading = true
        try {
            val api = apiClient.getApi() ?: return@LaunchedEffect
            val response = api.getSettings()
            if (response.isSuccessful) {
                settings = response.body()?.data
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        isLoading = false
    }

    if (showingLogoutAlert) {
        AlertDialog(
            onDismissRequest = { showingLogoutAlert = false },
            title = { Text(stringResource(R.string.logout)) },
            text = { Text(stringResource(R.string.logout_confirm)) },
            confirmButton = {
                TextButton(onClick = {
                    showingLogoutAlert = false
                    scope.launch {
                        server?.let { serverManager.setAuthenticated(it.id, false) }
                        onLogout()
                    }
                }) {
                    Text(stringResource(R.string.logout), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showingLogoutAlert = false }) {
                    Text(stringResource(R.string.back))
                }
            }
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.settings)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                }
            )
        }
    ) { padding ->
        if (isLoading) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = androidx.compose.ui.Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            LazyColumn(Modifier.padding(padding).fillMaxSize()) {
                item {
                    SettingsHeader(stringResource(R.string.connection))
                }
                item {
                    SettingsRow(stringResource(R.string.server), server?.name ?: "")
                }
                item {
                    SettingsRow(stringResource(R.string.version), settings?.version ?: "")
                }
                
                item {
                    SettingsHeader(stringResource(R.string.account))
                }
                item {
                    SettingsRow(stringResource(R.string.username), server?.username ?: "")
                }
                item {
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.logout), color = MaterialTheme.colorScheme.error) },
                        modifier = androidx.compose.foundation.clickable { showingLogoutAlert = true }
                    )
                }

                item {
                    SettingsHeader(stringResource(R.string.feature_control))
                }
                settings?.features?.let { features ->
                    item { FeatureToggle(stringResource(R.string.docker_mgmt), features.docker ?: true) }
                    item { FeatureToggle(stringResource(R.string.nginx_mgmt), features.nginx ?: true) }
                    item { FeatureToggle(stringResource(R.string.process_mgmt), features.processes ?: true) }
                    item { FeatureToggle(stringResource(R.string.logs_mgmt), features.logs ?: true) }
                }
            }
        }
    }
}

@Composable
fun SettingsHeader(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
    )
}

@Composable
fun SettingsRow(label: String, value: String) {
    ListItem(
        headlineContent = { Text(label) },
        trailingContent = { Text(value, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.secondary) }
    )
}

@Composable
fun FeatureToggle(label: String, enabled: Boolean) {
    var isChecked by remember { mutableStateOf(enabled) }
    ListItem(
        headlineContent = { Text(label) },
        trailingContent = {
            Switch(checked = isChecked, onCheckedChange = { isChecked = it })
        }
    )
}
