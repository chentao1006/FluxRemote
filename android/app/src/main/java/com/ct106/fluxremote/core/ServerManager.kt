package com.ct106.fluxremote.core

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.ct106.fluxremote.model.AIConfig
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
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
    var isLauncher: Boolean = false,
    var lastUpdatedAt: Long = System.currentTimeMillis(),
    var rememberPassword: Boolean = true,
    var autoLogin: Boolean = true
) {
    val baseURL: String
        get() = if (url.endsWith("/")) url else "$url/"
}

private val Context.dataStore by preferencesDataStore(name = "flux_remote_settings")

class ServerManager(private val context: Context) {
    private val json = Json { ignoreUnknownKeys = true }
    
    private val _servers = MutableStateFlow<List<ServerConfig>>(emptyList())
    val servers: StateFlow<List<ServerConfig>> = _servers
    
    private val _selectedServerId = MutableStateFlow<String?>(null)
    val selectedServerId: StateFlow<String?> = _selectedServerId
    
    private val _reachabilityStatuses = MutableStateFlow<Map<String, Boolean?>>(emptyMap())
    val reachabilityStatuses: StateFlow<Map<String, Boolean?>> = _reachabilityStatuses
    
    private val _authenticatedServerIds = MutableStateFlow<Set<String>>(emptySet())
    val authenticatedServerIds: StateFlow<Set<String>> = _authenticatedServerIds
    
    private val _passwords = MutableStateFlow<Map<String, String>>(emptyMap())

    private val _isInitializing = MutableStateFlow(true)
    val isInitializing: StateFlow<Boolean> = _isInitializing

    private val SERVERS_KEY = stringPreferencesKey("flux_remote_servers_v2")
    private val SELECTED_SERVER_ID_KEY = stringPreferencesKey("selected_server_id_v2")
    private val PASSWORDS_KEY = stringPreferencesKey("flux_remote_passwords_v1")
    private val AI_CONFIG_KEY = stringPreferencesKey("flux_remote_shared_ai_config")

    suspend fun loadInitialData() {
        context.dataStore.data.map { preferences ->
            val serversJson = preferences[SERVERS_KEY] ?: "[]"
            val servers = json.decodeFromString<List<ServerConfig>>(serversJson)
            _servers.value = servers.sortedBy { it.name }
            
            _selectedServerId.value = preferences[SELECTED_SERVER_ID_KEY]
            
            val passwordsJson = preferences[PASSWORDS_KEY] ?: "{}"
            _passwords.value = json.decodeFromString<Map<String, String>>(passwordsJson)
            _isInitializing.value = false
        }.collect {}
    }

    suspend fun addServer(server: ServerConfig) {
        val current = _servers.value.toMutableList()
        current.add(server)
        updateServers(current)
        if (_selectedServerId.value == null) {
            selectServer(server)
        }
    }

    suspend fun updateServer(server: ServerConfig) {
        val current = _servers.value.map {
            if (it.id == server.id) server.copy(lastUpdatedAt = System.currentTimeMillis()) else it
        }
        updateServers(current)
    }

    suspend fun removeServer(server: ServerConfig) {
        val current = _servers.value.filter { it.id != server.id }
        updateServers(current)
        if (_selectedServerId.value == server.id) {
            _selectedServerId.value = current.firstOrNull()?.id
            saveSelectedServerId(_selectedServerId.value)
        }
        removePassword(server.id)
        setAuthenticated(server.id, false)
    }

    private suspend fun updateServers(newList: List<ServerConfig>) {
        _servers.value = newList.sortedBy { it.name }
        context.dataStore.edit { preferences ->
            preferences[SERVERS_KEY] = json.encodeToString(_servers.value)
        }
    }

    suspend fun selectServer(server: ServerConfig) {
        _selectedServerId.value = server.id
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
        _passwords.value = current
        context.dataStore.edit { preferences ->
            preferences[PASSWORDS_KEY] = json.encodeToString(current)
        }
    }

    fun getPassword(serverId: String): String? {
        return _passwords.value[serverId]
    }

    private suspend fun removePassword(serverId: String) {
        setPassword(serverId, null)
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
}
