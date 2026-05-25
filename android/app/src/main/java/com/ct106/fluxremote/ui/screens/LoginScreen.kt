package com.ct106.flux_remote.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ct106.flux_remote.R
import com.ct106.flux_remote.core.RemoteAPIClient
import com.ct106.flux_remote.core.ServerConfig
import com.ct106.flux_remote.core.ServerManager
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LoginScreen(
    serverManager: ServerManager,
    apiClient: RemoteAPIClient,
    initialServerId: String? = null,
    onLoginSuccess: () -> Unit,
    onBack: () -> Unit
) {
    var url by remember { mutableStateOf("") }
    var serverName by remember { mutableStateOf("") }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var autoLogin by remember { mutableStateOf(true) }
    var isLoading by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    
    val scope = rememberCoroutineScope()
    
    LaunchedEffect(initialServerId) {
        if (initialServerId != null) {
            val server = serverManager.servers.value.find { it.id == initialServerId }
            if (server != null) {
                url = server.url
                serverName = server.name
                username = server.username ?: ""
                autoLogin = server.autoLogin
                if (server.rememberPassword || server.autoLogin) {
                    password = serverManager.getPassword(server.id) ?: ""
                }
            }
        }
    }
    val focusManager = LocalFocusManager.current
    val loginFailedMsg = stringResource(R.string.login_failed)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.login_title)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = stringResource(R.string.login_title),
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(vertical = 16.dp)
            )

            // Server Info Section
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
            ) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    OutlinedTextField(
                        value = url,
                        onValueChange = { url = it },
                        label = { Text(stringResource(R.string.server_url)) },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("https://your-server.com") },
                        leadingIcon = { Icon(Icons.Default.Link, contentDescription = null) },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Uri,
                            imeAction = ImeAction.Next
                        ),
                        keyboardActions = KeyboardActions(
                            onNext = { focusManager.moveFocus(FocusDirection.Down) }
                        )
                    )
                    OutlinedTextField(
                        value = serverName,
                        onValueChange = { serverName = it },
                        label = { Text(stringResource(R.string.server_name)) },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text(stringResource(R.string.optional)) },
                        leadingIcon = { Icon(Icons.Default.Label, contentDescription = null) },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Text,
                            imeAction = ImeAction.Next
                        ),
                        keyboardActions = KeyboardActions(
                            onNext = { focusManager.moveFocus(FocusDirection.Down) }
                        )
                    )
                }
            }

            // Credentials Section
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
            ) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    OutlinedTextField(
                        value = username,
                        onValueChange = { username = it },
                        label = { Text(stringResource(R.string.username)) },
                        modifier = Modifier.fillMaxWidth(),
                        leadingIcon = { Icon(Icons.Default.Person, contentDescription = null) },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Text,
                            imeAction = ImeAction.Next
                        ),
                        keyboardActions = KeyboardActions(
                            onNext = { focusManager.moveFocus(FocusDirection.Down) }
                        )
                    )
                    OutlinedTextField(
                        value = password,
                        onValueChange = { password = it },
                        label = { Text(stringResource(R.string.password)) },
                        modifier = Modifier.fillMaxWidth(),
                        leadingIcon = { Icon(Icons.Default.Lock, contentDescription = null) },
                        visualTransformation = PasswordVisualTransformation(),
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Password,
                            imeAction = ImeAction.Done
                        ),
                        keyboardActions = KeyboardActions(
                            onDone = { focusManager.clearFocus() }
                        )
                    )
                }
            }

            // Auto Login Toggle
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Bolt, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                        Spacer(Modifier.width(12.dp))
                        Text(stringResource(R.string.auto_login))
                    }
                    Switch(
                        checked = autoLogin,
                        onCheckedChange = { autoLogin = it }
                    )
                }
            }

            if (errorMessage != null) {
                Text(errorMessage!!, color = MaterialTheme.colorScheme.error, fontSize = 12.sp)
            }

            Button(
                onClick = {
                    scope.launch {
                        isLoading = true
                        errorMessage = null
                        
                        var finalURL = url
                        if (!finalURL.lowercase().startsWith("http://") && !finalURL.lowercase().startsWith("https://")) {
                            finalURL = "https://$finalURL"
                        }
                        
                        val displayName = if (serverName.isBlank()) {
                            finalURL.replace("https://", "").replace("http://", "").removeSuffix("/")
                        } else serverName

                        val currentServer = if (initialServerId != null) {
                            serverManager.servers.value.find { it.id == initialServerId }
                        } else null

                        val tempServer = currentServer?.copy(
                            name = displayName,
                            url = finalURL,
                            username = username,
                            password = password,
                            autoLogin = autoLogin,
                            rememberPassword = true
                        ) ?: ServerConfig(
                            name = displayName,
                            url = finalURL,
                            username = username,
                            password = password,
                            autoLogin = autoLogin,
                            rememberPassword = true
                        )

                        if (initialServerId != null) {
                            serverManager.updateServer(tempServer)
                        } else {
                            serverManager.addServer(tempServer)
                        }
                        serverManager.selectServer(tempServer)
                        
                        val success = apiClient.login(
                            mapOf("username" to username, "password" to password),
                            tempServer
                        )
                        
                        if (success) {
                            onLoginSuccess()
                        } else {
                            errorMessage = loginFailedMsg
                        }
                        isLoading = false
                    }
                },
                modifier = Modifier.fillMaxWidth().height(50.dp),
                enabled = !isLoading && url.isNotBlank() && username.isNotBlank() && password.isNotBlank(),
                shape = MaterialTheme.shapes.medium
            ) {
                if (isLoading) {
                    CircularProgressIndicator(modifier = Modifier.size(24.dp), color = MaterialTheme.colorScheme.onPrimary)
                } else {
                    Text(stringResource(R.string.login_button), fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}
