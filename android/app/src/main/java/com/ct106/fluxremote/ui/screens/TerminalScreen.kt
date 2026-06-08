package com.ct106.flux_remote.ui.screens

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.ct106.flux_remote.R
import com.ct106.flux_remote.core.AIService
import com.ct106.flux_remote.core.RemoteAPIClient
import com.ct106.flux_remote.ui.components.AIActionButton
import com.ct106.flux_remote.ui.components.AIAnalysisCard
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
private data class QuickCommand(
    val id: String = java.util.UUID.randomUUID().toString(),
    val name: String,
    val command: String
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TerminalScreen(
    apiClient: RemoteAPIClient,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }
    val listState = rememberLazyListState()
    val json = remember { Json { ignoreUnknownKeys = true } }

    var command by remember { mutableStateOf("") }
    var output by remember { mutableStateOf("") }
    var isExecuting by remember { mutableStateOf(false) }
    var commands by remember { mutableStateOf(loadQuickCommands(context, json)) }
    var showManageCommands by remember { mutableStateOf(false) }
    var commandToEdit by remember { mutableStateOf<QuickCommand?>(null) }
    var showAiDisabled by remember { mutableStateOf(false) }
    var isTranslating by remember { mutableStateOf(false) }
    var isAnalyzingOutput by remember { mutableStateOf(false) }
    var aiAnalysis by remember { mutableStateOf<String?>(null) }
    var terminalJob by remember { mutableStateOf<Job?>(null) }

    fun saveCommands() {
        context.getSharedPreferences("terminal_prefs", Context.MODE_PRIVATE)
            .edit()
            .putString("terminal_quick_commands_data", json.encodeToString(commands))
            .apply()
    }

    fun execute() {
        val commandToRun = command.trim()
        if (commandToRun.isEmpty() || isExecuting) return

        terminalJob?.cancel()
        terminalJob = scope.launch {
            isExecuting = true
            output = context.getString(R.string.terminal_executing, commandToRun) + "\n\n"
            aiAnalysis = null

            try {
                val api = apiClient.getApi() ?: throw IllegalStateException(context.getString(R.string.network_error))
                val response = api.executeCommand(mapOf("command" to commandToRun))
                if (!response.isSuccessful) {
                    val errorBody = response.errorBody()?.string().orEmpty()
                    throw IllegalStateException(errorBody.ifBlank { context.getString(R.string.server_error, response.code().toString()) })
                }

                val body = response.body() ?: throw IllegalStateException(context.getString(R.string.unknown_error))
                withContext(Dispatchers.IO) {
                    body.use { responseBody ->
                        val reader = responseBody.charStream().buffered()
                        reader.use {
                            var line = it.readLine()
                            while (line != null) {
                                val currentLine = line
                                withContext(Dispatchers.Main) {
                                    output += currentLine + "\n"
                                }
                                line = it.readLine()
                            }
                        }
                    }
                }
                output += "\n[${context.getString(R.string.terminal_finished)}]"
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                output += "\n[${context.getString(R.string.common_error)}: ${e.localizedMessage ?: context.getString(R.string.unknown_error)}]"
            } finally {
                isExecuting = false
            }
        }
    }

    fun stopExecution() {
        terminalJob?.cancel()
        terminalJob = null
        if (isExecuting) {
            output += "\n[${context.getString(R.string.terminal_stopped)}]"
        }
        isExecuting = false
    }

    fun translateCommand() {
        val userInput = command.trim()
        if (userInput.isEmpty()) {
            scope.launch { snackbarHostState.showSnackbar(context.getString(R.string.terminal_ai_hint)) }
            return
        }
        if (apiClient.aiConfig?.enabled != true) {
            showAiDisabled = true
            return
        }

        isTranslating = true
        command = ""
        val prompt = context.getString(R.string.terminal_generate_prompt, userInput)
        val systemPrompt = context.getString(R.string.terminal_generator_role)
        scope.launch {
            AIService.getInstance(context).analyzeStream(prompt, systemPrompt, apiClient)
                .catch { e ->
                    command = context.getString(R.string.error_prefix, e.localizedMessage ?: "")
                    isTranslating = false
                }
                .collect { chunk ->
                    command = (command + chunk).trim()
                    isTranslating = false
                }
        }
    }

    fun analyzeOutput() {
        if (output.isBlank()) return
        if (apiClient.aiConfig?.enabled != true) {
            showAiDisabled = true
            return
        }

        isAnalyzingOutput = true
        aiAnalysis = null
        val langName = context.getString(R.string.lang_name)
        val prompt = context.getString(R.string.terminal_analyze_prompt, langName, output)
        val systemPrompt = context.getString(R.string.terminal_output_analyzer_role)
        scope.launch {
            AIService.getInstance(context).analyzeStream(prompt, systemPrompt, apiClient)
                .catch { e ->
                    aiAnalysis = context.getString(R.string.error_prefix, e.localizedMessage ?: "")
                    isAnalyzingOutput = false
                }
                .collect { chunk ->
                    if (aiAnalysis == null) aiAnalysis = ""
                    aiAnalysis = aiAnalysis + chunk
                    isAnalyzingOutput = false
                }
        }
    }

    val outputLines = remember(output) { output.split('\n') }
    LaunchedEffect(outputLines.size) {
        if (outputLines.isNotEmpty()) {
            listState.animateScrollToItem(outputLines.lastIndex)
        }
    }

    DisposableEffect(Unit) {
        onDispose { terminalJob?.cancel() }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.terminal_title)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.Close, contentDescription = stringResource(R.string.common_cancel))
                    }
                },
                actions = {
                    IconButton(onClick = { output = ""; aiAnalysis = null }, enabled = !isExecuting) {
                        Icon(Icons.Default.DeleteSweep, contentDescription = stringResource(R.string.terminal_clear))
                    }
                }
            )
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f))
        ) {
            Column(Modifier.fillMaxSize()) {
                QuickCommandRow(
                    commands = commands,
                    onManage = { showManageCommands = true },
                    onSelect = { command = it.command },
                    context = context
                )

                TerminalInputBar(
                    command = command,
                    onCommandChange = { command = it },
                    isExecuting = isExecuting,
                    isTranslating = isTranslating,
                    onAiClick = { translateCommand() },
                    onRunClick = { execute() },
                    onStopClick = { stopExecution() },
                    modifier = Modifier
                        .padding(horizontal = 12.dp)
                        .widthIn(max = 720.dp)
                        .align(Alignment.CenterHorizontally)
                )

                if (aiAnalysis != null || isAnalyzingOutput) {
                    AIAnalysisCard(
                        analysis = aiAnalysis,
                        isAnalyzing = isAnalyzingOutput,
                        onDismiss = {
                            aiAnalysis = null
                            isAnalyzingOutput = false
                        },
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                }

                if (output.isBlank()) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            text = if (isTranslating) stringResource(R.string.terminal_ai_translating) else stringResource(R.string.terminal_waiting),
                            style = MaterialTheme.typography.bodySmall,
                            fontFamily = FontFamily.Monospace,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                } else {
                    LazyColumn(
                        state = listState,
                        modifier = Modifier.fillMaxSize()
                    ) {
                        itemsIndexed(outputLines) { index, line ->
                            Text(
                                text = line,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .background(
                                        if (index % 2 == 0) MaterialTheme.colorScheme.surface
                                        else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
                                    )
                                    .padding(horizontal = 16.dp, vertical = 2.dp),
                                style = MaterialTheme.typography.bodySmall,
                                fontFamily = FontFamily.Monospace
                            )
                        }
                        if (!isExecuting) {
                            item {
                                Box(
                                    Modifier
                                        .fillMaxWidth()
                                        .padding(16.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    AIActionButton(
                                        text = stringResource(R.string.ai_analyze),
                                        icon = Icons.Default.AutoAwesome,
                                        onClick = { analyzeOutput() },
                                        isLoading = isAnalyzingOutput
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (showAiDisabled) {
        AlertDialog(
            onDismissRequest = { showAiDisabled = false },
            confirmButton = {
                TextButton(onClick = { showAiDisabled = false }) {
                    Text(stringResource(R.string.common_ok))
                }
            },
            title = { Text(stringResource(R.string.ai_config_missing)) },
            text = { Text(stringResource(R.string.ai_config_missing_detail)) }
        )
    }

    if (showManageCommands) {
        QuickCommandManagerDialog(
            commands = commands,
            onDismiss = { showManageCommands = false },
            onEdit = { commandToEdit = it },
            onDelete = {
                commands = commands.filterNot { command -> command.id == it.id }
                saveCommands()
            },
            context = context
        )
    }

    commandToEdit?.let { item ->
        QuickCommandEditorDialog(
            command = item,
            onDismiss = { commandToEdit = null },
            onSave = { updated ->
                commands = if (commands.any { it.id == updated.id }) {
                    commands.map { if (it.id == updated.id) updated else it }
                } else {
                    commands + updated
                }
                saveCommands()
                commandToEdit = null
            }
        )
    }
}

@Composable
private fun TerminalInputBar(
    command: String,
    onCommandChange: (String) -> Unit,
    isExecuting: Boolean,
    isTranslating: Boolean,
    onAiClick: () -> Unit,
    onRunClick: () -> Unit,
    onStopClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        TextField(
            value = command,
            onValueChange = onCommandChange,
            modifier = Modifier.weight(1f),
            placeholder = { Text(stringResource(R.string.terminal_placeholder)) },
            minLines = 1,
            maxLines = 5,
            textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = Color.Transparent,
                unfocusedContainerColor = Color.Transparent,
                disabledContainerColor = Color.Transparent,
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
                disabledIndicatorColor = Color.Transparent
            )
        )
        IconButton(onClick = onAiClick, enabled = !isTranslating && !isExecuting) {
            if (isTranslating) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
            else Icon(Icons.Default.AutoAwesome, contentDescription = stringResource(R.string.ai_wand))
        }
        IconButton(
            onClick = if (isExecuting) onStopClick else onRunClick,
            enabled = isExecuting || command.isNotBlank()
        ) {
            Icon(
                imageVector = if (isExecuting) Icons.Default.StopCircle else Icons.Default.PlayCircle,
                contentDescription = if (isExecuting) stringResource(R.string.terminal_stop) else stringResource(R.string.terminal_run)
            )
        }
    }
}

@Composable
private fun QuickCommandRow(
    commands: List<QuickCommand>,
    onManage: () -> Unit,
    onSelect: (QuickCommand) -> Unit,
    context: Context
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        AssistChip(
            onClick = onManage,
            label = { Text(stringResource(R.string.edit)) },
            leadingIcon = { Icon(Icons.Default.Edit, contentDescription = null, modifier = Modifier.size(18.dp)) }
        )
        commands.forEach { item ->
            AssistChip(
                onClick = { onSelect(item) },
                label = {
                    Text(
                        text = resolveQuickCommandName(context, item.name),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            )
        }
    }
}

@Composable
private fun QuickCommandManagerDialog(
    commands: List<QuickCommand>,
    onDismiss: () -> Unit,
    onEdit: (QuickCommand) -> Unit,
    onDelete: (QuickCommand) -> Unit,
    context: Context
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = { onEdit(QuickCommand(name = "", command = "")) }) {
                Text(stringResource(R.string.add))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.common_ok))
            }
        },
        title = { Text(stringResource(R.string.terminal_common_commands)) },
        text = {
            LazyColumn(modifier = Modifier.heightIn(max = 420.dp)) {
                itemsIndexed(commands) { _, item ->
                    ListItem(
                        headlineContent = { Text(resolveQuickCommandName(context, item.name), fontWeight = FontWeight.Medium) },
                        supportingContent = { Text(item.command, fontFamily = FontFamily.Monospace, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                        trailingContent = {
                            Row {
                                IconButton(onClick = { onEdit(item) }) {
                                    Icon(Icons.Default.Edit, contentDescription = stringResource(R.string.edit))
                                }
                                IconButton(onClick = { onDelete(item) }) {
                                    Icon(Icons.Default.Delete, contentDescription = stringResource(R.string.delete))
                                }
                            }
                        }
                    )
                    HorizontalDivider()
                }
            }
        }
    )
}

@Composable
private fun QuickCommandEditorDialog(
    command: QuickCommand,
    onDismiss: () -> Unit,
    onSave: (QuickCommand) -> Unit
) {
    var name by remember(command.id) { mutableStateOf(command.name) }
    var value by remember(command.id) { mutableStateOf(command.command) }

    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(
                onClick = { onSave(command.copy(name = name, command = value)) },
                enabled = name.isNotBlank() && value.isNotBlank()
            ) {
                Text(stringResource(R.string.common_save))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.common_cancel))
            }
        },
        title = { Text(if (name.isBlank()) stringResource(R.string.terminal_add_command) else name) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text(stringResource(R.string.terminal_command_name)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = value,
                    onValueChange = { value = it },
                    label = { Text(stringResource(R.string.terminal_command_prompt)) },
                    minLines = 3,
                    maxLines = 6,
                    textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }
    )
}

private fun loadQuickCommands(context: Context, json: Json): List<QuickCommand> {
    val prefs = context.getSharedPreferences("terminal_prefs", Context.MODE_PRIVATE)
    val saved = prefs.getString("terminal_quick_commands_data", null)
    if (!saved.isNullOrBlank()) {
        runCatching { json.decodeFromString<List<QuickCommand>>(saved) }
            .getOrNull()
            ?.takeIf { it.isNotEmpty() }
            ?.let { return it }
    }
    return defaultQuickCommands()
}

private fun defaultQuickCommands(): List<QuickCommand> = listOf(
    QuickCommand(name = "monitor_quick_ls", command = "ls -FhG"),
    QuickCommand(name = "monitor_quick_df", command = "df -h"),
    QuickCommand(name = "monitor_quick_mem_sort", command = "ps -e -o pmem,comm | sort -rn | head -n 10"),
    QuickCommand(name = "monitor_quick_cpu_sort", command = "ps -e -o pcpu,comm | sort -rn | head -n 10"),
    QuickCommand(name = "monitor_quick_ip", command = "ifconfig | grep \"inet \" | grep -v 127.0.0.1"),
    QuickCommand(name = "monitor_quick_ports", command = "lsof -i -P | grep LISTEN"),
    QuickCommand(name = "monitor_quick_uptime", command = "uptime"),
    QuickCommand(name = "monitor_quick_brew", command = "brew list --versions"),
    QuickCommand(name = "monitor_quick_vers", command = "sw_vers"),
    QuickCommand(name = "monitor_quick_proc_count", command = "ps aux | wc -l"),
    QuickCommand(name = "monitor_quick_space", command = "du -sh ~/* | sort -rh | head -n 5"),
    QuickCommand(name = "monitor_quick_downloads", command = "ls -lt ~/Downloads | head -n 5"),
    QuickCommand(name = "monitor_quick_arch", command = "uname -m"),
    QuickCommand(name = "monitor_quick_who", command = "who"),
    QuickCommand(name = "monitor_quick_dns", command = "cat /etc/resolv.conf")
)

private fun resolveQuickCommandName(context: Context, name: String): String {
    val id = context.resources.getIdentifier(name, "string", context.packageName)
    return if (id != 0) context.getString(id) else name
}
