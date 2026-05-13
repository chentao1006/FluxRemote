package com.ct106.fluxremote.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.ct106.fluxremote.R
import com.ct106.fluxremote.core.RemoteAPIClient
import com.ct106.fluxremote.core.ServerManager
import com.ct106.fluxremote.model.ServerSettings
import com.ct106.fluxremote.model.FeatureToggles
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay

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
    var errorMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    fun loadSettings() {
        scope.launch {
            isLoading = true
            errorMessage = null
            try {
                val api = apiClient.getApi()
                if (api == null) {
                    errorMessage = "API Client not initialized"
                    isLoading = false
                    return@launch
                }
                val response = api.getSettings()
                if (response.isSuccessful) {
                    settings = response.body()?.data
                } else {
                    errorMessage = "Server error: ${response.code()}"
                }
            } catch (e: Exception) {
                errorMessage = e.message ?: "Unknown error"
                e.printStackTrace()
            }
            isLoading = false
        }
    }

    LaunchedEffect(Unit) {
        loadSettings()
    }

    var saveJob by remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }
    
    fun updateFeature(newFeatures: FeatureToggles) {
        settings = settings?.copy(features = newFeatures)
        
        saveJob?.cancel()
        saveJob = scope.launch {
            kotlinx.coroutines.delay(1000)
            try {
                val api = apiClient.getApi()
                val response = api?.updateSettings(settings!!)
                if (response?.isSuccessful == true) {
                    apiClient.features = settings!!.features!!
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
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
        } else if (errorMessage != null && settings == null) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = androidx.compose.ui.Alignment.Center) {
                Column(horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally) {
                    Text(errorMessage!!, color = MaterialTheme.colorScheme.error)
                    Button(onClick = { loadSettings() }) { Text(stringResource(R.string.refresh)) }
                }
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
                    SettingsRow(stringResource(R.string.version), settings?.version ?: stringResource(R.string.none))
                }
                
                item {
                    SettingsHeader(stringResource(R.string.language))
                }
                item {
                    val currentLang = serverManager.language.collectAsState().value
                    val langText = when(currentLang) {
                        "zh" -> stringResource(R.string.language_zh)
                        "en" -> stringResource(R.string.language_en)
                        else -> stringResource(R.string.language_auto)
                    }
                    var showLangDialog by remember { mutableStateOf(false) }
                    
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.language)) },
                        trailingContent = { Text(langText, color = MaterialTheme.colorScheme.primary) },
                        modifier = Modifier.clickable { showLangDialog = true }
                    )
                    
                    if (showLangDialog) {
                        AlertDialog(
                            onDismissRequest = { showLangDialog = false },
                            title = { Text(stringResource(R.string.language)) },
                            text = {
                                Column {
                                    listOf("auto", "zh", "en").forEach { lang ->
                                        Row(
                                            Modifier.fillMaxWidth().clickable {
                                                scope.launch {
                                                    serverManager.setLanguage(lang)
                                                    showLangDialog = false
                                                }
                                            }.padding(16.dp),
                                            verticalAlignment = androidx.compose.ui.Alignment.CenterVertically
                                        ) {
                                            RadioButton(selected = currentLang == lang, onClick = null)
                                            Spacer(Modifier.width(8.dp))
                                            Text(when(lang) {
                                                "zh" -> stringResource(R.string.language_zh)
                                                "en" -> stringResource(R.string.language_en)
                                                else -> stringResource(R.string.language_auto)
                                            })
                                        }
                                    }
                                }
                            },
                            confirmButton = {
                                TextButton(onClick = { showLangDialog = false }) {
                                    Text(stringResource(R.string.common_ok))
                                }
                            }
                        )
                    }
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
                        modifier = Modifier.clickable { showingLogoutAlert = true }
                    )
                }

                item {
                    SettingsHeader(stringResource(R.string.feature_control))
                }
                
                val features = settings?.features
                if (features != null) {
                    item { FeatureToggle(stringResource(R.string.process_mgmt), features.processes ?: true) { newValue -> updateFeature(features.copy(processes = newValue)) } }
                    item { FeatureToggle(stringResource(R.string.logs_mgmt), features.logs ?: true) { newValue -> updateFeature(features.copy(logs = newValue)) } }
                    item { FeatureToggle(stringResource(R.string.configs_mgmt), features.configs ?: true) { newValue -> updateFeature(features.copy(configs = newValue)) } }
                    item { FeatureToggle(stringResource(R.string.launchagents_mgmt), features.launchagent ?: true) { newValue -> updateFeature(features.copy(launchagent = newValue)) } }
                    item { FeatureToggle(stringResource(R.string.docker_mgmt), features.docker ?: true) { newValue -> updateFeature(features.copy(docker = newValue)) } }
                    item { FeatureToggle(stringResource(R.string.nginx_mgmt), features.nginx ?: true) { newValue -> updateFeature(features.copy(nginx = newValue)) } }
                } else {
                    item {
                        Text(
                            text = stringResource(R.string.none),
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.padding(16.dp)
                        )
                    }
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
fun FeatureToggle(label: String, enabled: Boolean, onCheckedChange: (Boolean) -> Unit) {
    ListItem(
        headlineContent = { Text(label) },
        trailingContent = {
            Switch(checked = enabled, onCheckedChange = onCheckedChange)
        }
    )
}
