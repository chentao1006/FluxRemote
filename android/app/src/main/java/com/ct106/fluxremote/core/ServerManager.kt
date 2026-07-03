package com.ct106.flux_remote.core

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.ct106.flux_remote.model.AIConfig
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.UUID

@Serializable
data class ServerConfig(
    val id: String = UUID.randomUUID().toString(),
    var name: String,
    var url: String,
    var username: String? = null,
    var password: String? = null,
    var isLauncher: Boolean = false,
    var lastUpdatedAt: Long = System.currentTimeMillis(),
    var rememberPassword: Boolean = true,
    var autoLogin: Boolean = true,
    var mqttTopic: String? = null,
    var mqttKey: String? = null
) {
    val baseURL: String
        get() = if (url.startsWith("http")) (if (url.endsWith("/")) url else "$url/") else "http://" + (if (url.endsWith("/")) url else "$url/")
}

private val Context.dataStore by preferencesDataStore(name = "flux_remote_settings")

class ServerManager(private val context: Context) {
    private val json = Json { ignoreUnknownKeys = true }
    private val scope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO + kotlinx.coroutines.SupervisorJob())

    private val _servers = MutableStateFlow<List<ServerConfig>>(emptyList())
    val servers: StateFlow<List<ServerConfig>> = _servers

    private val _selectedServerId = MutableStateFlow<String?>(null)
    val selectedServerId: StateFlow<String?> = _selectedServerId

    companion object {
        private val _authenticatedServerIds = MutableStateFlow<Set<String>>(emptySet())
        private val _reachabilityStatuses = MutableStateFlow<Map<String, Boolean?>>(emptyMap())
    }
    
    val authenticatedServerIds: StateFlow<Set<String>> = _authenticatedServerIds
    val reachabilityStatuses: StateFlow<Map<String, Boolean?>> = _reachabilityStatuses

    private val _isInitializing = MutableStateFlow(true)
    val isInitializing: StateFlow<Boolean> = _isInitializing

    private val SERVERS_KEY = stringPreferencesKey("flux_remote_servers_v2")
    private val SELECTED_SERVER_ID_KEY = stringPreferencesKey("selected_server_id_v2")
    private val LANGUAGE_KEY = stringPreferencesKey("app_language_v1")
    private val PASSWORDS_KEY = stringPreferencesKey("flux_remote_passwords_v1")

    private val _language = MutableStateFlow<String>("auto")
    val language: StateFlow<String> = _language
    private val _passwords = MutableStateFlow<Map<String, String>>(emptyMap())

    init {
        scope.launch {
            context.dataStore.data.collect { preferences ->
                val serversJson = preferences[SERVERS_KEY] ?: "[]"
                try {
                    val servers = json.decodeFromString<List<ServerConfig>>(serversJson)
                    _servers.value = servers.sortedBy { it.name }
                } catch (e: Exception) {
                    e.printStackTrace()
                }

                _selectedServerId.value = preferences[SELECTED_SERVER_ID_KEY]
                _language.value = preferences[LANGUAGE_KEY] ?: "auto"
                val passwordsJson = preferences[PASSWORDS_KEY] ?: "{}"
                try {
                    _passwords.value = json.decodeFromString<Map<String, String>>(passwordsJson)
                } catch (e: Exception) {
                    _passwords.value = emptyMap()
                }
                _isInitializing.value = false
            }
        }
    }

    suspend fun loadInitialData() {
        // Now handled in init, but keeping the method to avoid breaking MainActivity
        // We just wait until _isInitializing is false
        _isInitializing.first { !it }
    }

    suspend fun addServer(server: ServerConfig) {
        val current = _servers.value.toMutableList()
        if (current.none { it.id == server.id }) {
            current.add(server)
            saveServers(current)
        }
        if (_selectedServerId.value == null) {
            selectServer(server)
        }
    }

    suspend fun updateServer(server: ServerConfig) {
        val current = _servers.value.map {
            if (it.id == server.id) server.copy(lastUpdatedAt = System.currentTimeMillis()) else it
        }
        saveServers(current)
    }

    suspend fun removeServer(server: ServerConfig) {
        val current = _servers.value.filter { it.id != server.id }
        saveServers(current)
        if (_selectedServerId.value == server.id) {
            saveSelectedServerId(current.firstOrNull()?.id)
        }
        removePassword(server.id)
        setAuthenticated(server.id, false)
    }

    suspend fun removePassword(serverId: String) {
        val current = _passwords.value.toMutableMap()
        current.remove(serverId)
        _passwords.value = current
        context.dataStore.edit { preferences ->
            preferences[PASSWORDS_KEY] = json.encodeToString(current)
        }
    }

    private suspend fun saveServers(newList: List<ServerConfig>) {
        context.dataStore.edit { preferences ->
            preferences[SERVERS_KEY] = json.encodeToString(newList)
        }
    }

    suspend fun selectServer(server: ServerConfig) {
        saveSelectedServerId(server.id)
    }

    private suspend fun saveSelectedServerId(id: String?) {
        context.dataStore.edit { preferences ->
            if (id != null) {
                preferences[SELECTED_SERVER_ID_KEY] = id
            } else {
                preferences.remove(SELECTED_SERVER_ID_KEY)
            }
        }
    }

    suspend fun logout() {
        val server = getSelectedServer() ?: return
        setAuthenticated(server.id, false)
        removePassword(server.id)
    }

    fun setAuthenticated(serverId: String, authenticated: Boolean) {
        val current = _authenticatedServerIds.value.toMutableSet()
        if (authenticated) current.add(serverId) else current.remove(serverId)
        _authenticatedServerIds.value = current
    }

    fun isServerAuthenticated(serverId: String): Boolean {
        return _authenticatedServerIds.value.contains(serverId)
    }

    suspend fun setPassword(serverId: String, password: String?) {
        val current = _passwords.value.toMutableMap()
        if (password != null) {
            current[serverId] = password
        } else {
            current.remove(serverId)
        }
        context.dataStore.edit { preferences ->
            preferences[PASSWORDS_KEY] = json.encodeToString(current)
        }
    }

    fun getPassword(serverId: String): String? {
        return _passwords.value[serverId] ?: _servers.value.find { it.id == serverId }?.password
    }

    fun hasSavedPassword(serverId: String): Boolean {
        return getPassword(serverId) != null
    }

    fun updateReachability(serverId: String, isOffline: Boolean) {
        val current = _reachabilityStatuses.value.toMutableMap()
        current[serverId] = isOffline
        _reachabilityStatuses.value = current
    }

    fun getSelectedServer(): ServerConfig? {
        val id = _selectedServerId.value ?: return _servers.value.firstOrNull()
        return _servers.value.find { it.id == id }
    }

    suspend fun setLanguage(language: String) {
        context.dataStore.edit { it[LANGUAGE_KEY] = language }
    }
}
