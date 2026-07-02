package com.ct106.flux_remote.ui.screens

import android.content.res.Configuration
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ct106.flux_remote.R
import com.ct106.flux_remote.core.AnalyticsTracker
import com.ct106.flux_remote.core.RemoteAPIClient
import com.ct106.flux_remote.core.ServerManager
import com.ct106.flux_remote.model.*
import com.ct106.flux_remote.ui.components.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    serverManager: ServerManager,
    apiClient: RemoteAPIClient,
    onBack: () -> Unit,
    onLogout: () -> Unit
) {
    val context = LocalContext.current
    val server = serverManager.getSelectedServer()
    var settings by remember { mutableStateOf<ServerSettings?>(null) }
    var isLoading by remember { mutableStateOf(false) }
    var showingLogoutAlert by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }

    fun loadSettings() {
        scope.launch {
            isLoading = true
            errorMessage = null
            try {
                val api = apiClient.getApi() ?: return@launch
                val response = api.getSettings()
                if (response.isSuccessful) {
                    settings = response.body()?.data
                    settings?.ai?.let { apiClient.aiConfig = it }
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
    
    fun saveSettings(newSettings: ServerSettings) {
        settings = newSettings
        saveJob?.cancel()
        saveJob = scope.launch {
            delay(1000)
            try {
                val api = apiClient.getApi() ?: return@launch
                val response = api.updateSettings(newSettings)
                if (response.isSuccessful) {
                    newSettings.features?.let { apiClient.features = it }
                    newSettings.ai?.let { apiClient.aiConfig = it }
                    AnalyticsTracker.track(context, "settings_modified")
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.settings)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                }
            )
        }
    ) { padding ->
        if (isLoading && settings == null) {
            LoadingView(Modifier.padding(padding))
        } else if (errorMessage != null && settings == null) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(errorMessage!!, color = MaterialTheme.colorScheme.error)
                    Button(onClick = { loadSettings() }) { Text(stringResource(R.string.refresh)) }
                }
            }
        } else {
            LazyColumn(Modifier.padding(padding).fillMaxSize()) {
                // Connection Section
                item { SettingsHeader(stringResource(R.string.connection)) }
                item { SettingsRow(stringResource(R.string.server), server?.name ?: "") }
                item { SettingsRow(stringResource(R.string.version), settings?.version ?: stringResource(R.string.none)) }
                
                // AI Section
                item { SettingsHeader(stringResource(R.string.ai_config)) }
                settings?.ai?.let { ai ->
                    item {
                        FeatureToggle(stringResource(R.string.ai_enabled), ai.enabled ?: false) { enabled ->
                            saveSettings(settings!!.copy(ai = ai.copy(enabled = enabled)))
                        }
                    }
                    if (ai.enabled == true) {
                        item {
                            FeatureToggle(stringResource(R.string.ai_use_public), ai.usePublicService ?: true) { usePublic ->
                                saveSettings(settings!!.copy(ai = ai.copy(usePublicService = usePublic)))
                            }
                        }
                        if (ai.usePublicService == false) {
                            item {
                                TextFieldRow(stringResource(R.string.ai_url), ai.url ?: "") { url ->
                                    saveSettings(settings!!.copy(ai = ai.copy(url = url)))
                                }
                            }
                            item {
                                TextFieldRow(stringResource(R.string.ai_key), ai.key ?: "", isPassword = true) { key ->
                                    saveSettings(settings!!.copy(ai = ai.copy(key = key)))
                                }
                            }
                            item {
                                TextFieldRow(stringResource(R.string.ai_model), ai.model ?: "") { model ->
                                    saveSettings(settings!!.copy(ai = ai.copy(model = model)))
                                }
                            }
                        }
                        item {
                            FeatureToggle(stringResource(R.string.ai_stream), ai.stream ?: true) { stream ->
                                saveSettings(settings!!.copy(ai = ai.copy(stream = stream)))
                            }
                        }
                    }
                }

                // Feature Control Section
                item { SettingsHeader(stringResource(R.string.feature_control)) }
                settings?.features?.let { features ->
                    item { FeatureToggle(stringResource(R.string.dashboard), features.monitor ?: true) { v -> saveSettings(settings!!.copy(features = features.copy(monitor = v))) } }
                    item { FeatureToggle(stringResource(R.string.process_mgmt), features.processes ?: true) { v -> saveSettings(settings!!.copy(features = features.copy(processes = v))) } }
                    item { FeatureToggle(stringResource(R.string.ports_mgmt), features.ports ?: true) { v -> saveSettings(settings!!.copy(features = features.copy(ports = v))) } }
                    item { FeatureToggle(stringResource(R.string.logs_mgmt), features.logs ?: true) { v -> saveSettings(settings!!.copy(features = features.copy(logs = v))) } }
                    item { FeatureToggle(stringResource(R.string.configs_mgmt), features.configs ?: true) { v -> saveSettings(settings!!.copy(features = features.copy(configs = v))) } }
                    item { FeatureToggle(stringResource(R.string.launchagents_mgmt), features.launchagent ?: true) { v -> saveSettings(settings!!.copy(features = features.copy(launchagent = v))) } }
                    item { FeatureToggle(stringResource(R.string.docker_mgmt), features.docker ?: true) { v -> saveSettings(settings!!.copy(features = features.copy(docker = v))) } }
                    item { FeatureToggle(stringResource(R.string.nginx_mgmt), features.nginx ?: true) { v -> saveSettings(settings!!.copy(features = features.copy(nginx = v))) } }
                }

                // Language Section
                item { SettingsHeader(systemStringResource(R.string.language)) }
                item {
                    val currentLang = serverManager.language.collectAsState().value
                    val systemLanguage = systemStringResource(R.string.language)
                    val systemLanguageAuto = systemStringResource(R.string.language_auto)
                    val langText = when(currentLang) {
                        "zh" -> stringResource(R.string.language_zh)
                        "zh-Hant" -> stringResource(R.string.language_zh_hant)
                        "en" -> stringResource(R.string.language_en)
                        "ja" -> stringResource(R.string.language_ja)
                        "ko" -> stringResource(R.string.language_ko)
                        "es" -> stringResource(R.string.language_es)
                        "de" -> stringResource(R.string.language_de)
                        "fr" -> stringResource(R.string.language_fr)
                        "it" -> stringResource(R.string.language_it)
                        else -> systemLanguageAuto
                    }
                    var showLangDialog by remember { mutableStateOf(false) }
                    
                    ListItem(
                        headlineContent = { Text(systemLanguage) },
                        trailingContent = { Text(langText, color = MaterialTheme.colorScheme.primary) },
                        modifier = Modifier.clickable { showLangDialog = true }
                    )
                    
                    if (showLangDialog) {
                        LanguageDialog(
                            currentLang = currentLang,
                            onSelect = { lang ->
                                scope.launch {
                                    serverManager.setLanguage(lang)
                                    showLangDialog = false
                                }
                            },
                            onDismiss = { showLangDialog = false }
                        )
                    }
                }

                // Account Section
                item { SettingsHeader(stringResource(R.string.account)) }
                item { SettingsRow(stringResource(R.string.username), server?.username ?: "") }
                item {
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.logout), color = MaterialTheme.colorScheme.error) },
                        modifier = Modifier.clickable { showingLogoutAlert = true }
                    )
                }
                item { Spacer(Modifier.height(32.dp)) }
            }
        }
    }

    if (showingLogoutAlert) {
        ConfirmationDialog(
            title = stringResource(R.string.logout),
            message = stringResource(R.string.logout_confirm),
            onConfirm = {
                scope.launch {
                    server?.let { serverManager.setAuthenticated(it.id, false) }
                    onLogout()
                }
            },
            onDismiss = { showingLogoutAlert = false },
            isDestructive = true
        )
    }
}

@Composable
fun SettingsHeader(title: String) {
    Text(
        text = title.uppercase(),
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.primary,
        fontWeight = FontWeight.Bold,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
    )
}

@Composable
fun SettingsRow(label: String, value: String) {
    ListItem(
        headlineContent = { Text(label, style = MaterialTheme.typography.bodyMedium) },
        trailingContent = { Text(value, style = MaterialTheme.typography.bodyMedium, color = Color.Gray) }
    )
}

@Composable
fun FeatureToggle(label: String, enabled: Boolean, onCheckedChange: (Boolean) -> Unit) {
    ListItem(
        headlineContent = { Text(label, style = MaterialTheme.typography.bodyMedium) },
        trailingContent = {
            Switch(checked = enabled, onCheckedChange = onCheckedChange)
        }
    )
}

@Composable
fun TextFieldRow(label: String, value: String, isPassword: Boolean = false, onValueChange: (String) -> Unit) {
    var text by remember { mutableStateOf(value) }
    ListItem(
        headlineContent = {
            TextField(
                value = text,
                onValueChange = { text = it; onValueChange(it) },
                label = { Text(label) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                visualTransformation = if (isPassword) PasswordVisualTransformation() else VisualTransformation.None,
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = Color.Transparent,
                    unfocusedContainerColor = Color.Transparent
                )
            )
        }
    )
}

@Composable
fun LanguageDialog(currentLang: String, onSelect: (String) -> Unit, onDismiss: () -> Unit) {
    val systemLanguage = systemStringResource(R.string.language)
    val systemLanguageAuto = systemStringResource(R.string.language_auto)

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(systemLanguage) },
        text = {
            Column {
                listOf("auto", "zh", "zh-Hant", "en", "ja", "ko", "es", "de", "fr", "it").forEach { lang ->
                    Row(
                        Modifier.fillMaxWidth().clickable { onSelect(lang) }.padding(vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        RadioButton(selected = currentLang == lang, onClick = null)
                        Spacer(Modifier.width(12.dp))
                        Text(when(lang) {
                            "zh" -> stringResource(R.string.language_zh)
                            "zh-Hant" -> stringResource(R.string.language_zh_hant)
                            "en" -> stringResource(R.string.language_en)
                            "ja" -> stringResource(R.string.language_ja)
                            "ko" -> stringResource(R.string.language_ko)
                            "es" -> stringResource(R.string.language_es)
                            "de" -> stringResource(R.string.language_de)
                            "fr" -> stringResource(R.string.language_fr)
                            "it" -> stringResource(R.string.language_it)
                            else -> systemLanguageAuto
                        })
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_ok)) }
        }
    )
}

@Composable
private fun systemStringResource(id: Int): String {
    val context = LocalContext.current.applicationContext
    val systemLocale = Locale.getDefault()
    return remember(context, systemLocale, id) {
        val config = Configuration(context.resources.configuration)
        config.setLocale(systemLocale)
        context.createConfigurationContext(config).getString(id)
    }
}
