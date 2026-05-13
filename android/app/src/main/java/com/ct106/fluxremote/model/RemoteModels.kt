package com.ct106.fluxremote.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive

@Serializable
data class RemoteStatsResponse(
    val success: Boolean,
    val data: RemoteSystemStats
)

@Serializable
data class RemoteSystemStats(
    val hostname: String,
    val osVersion: String,
    val uptime: String,
    val cpu: RemoteCPU? = null,
    val memory: RemoteMemory,
    val disk: RemoteDisk,
    val loadAvg: String,
    val arch: String,
    val cpuModel: String? = null,
    val kernel: String? = null,
    val swap: String? = null,
    val memPressure: String? = null,
    val battery: String? = null,
    val netBytes: RemoteNetBytes? = null
)

@Serializable
data class RemoteNetBytes(
    val `in`: Long,
    val out: Long
)

@Serializable
data class RemoteCPU(
    val user: Double,
    val sys: Double,
    val idle: Double
)

@Serializable
data class RemoteMemory(
    val usedMB: Int,
    val totalMB: Int,
    val freeMB: Int
)

@Serializable
data class RemoteDisk(
    val percent: String,
    val total: String,
    val used: String
)

@Serializable
data class DockerContainer(
    @SerialName("ID") val id: String,
    @SerialName("Names") val names: List<String>,
    @SerialName("Image") val image: String,
    @SerialName("State") val state: String,
    @SerialName("Status") val status: String,
    @SerialName("Ports") val ports: String,
    @SerialName("Command") val command: String? = null,
    @SerialName("CreatedAt") val createdAt: String? = null
) {
    val name: String
        get() = names.firstOrNull()?.replace("/", "") ?: "unknown"
}

@Serializable
data class DockerResponse(
    val success: Boolean,
    val data: List<DockerContainer>
)

@Serializable
data class DockerImage(
    @SerialName("ID") val id: String,
    @SerialName("Repository") val repository: String,
    @SerialName("Tag") val tag: String,
    @SerialName("Size") val size: String,
    @SerialName("CreatedAt") val createdAt: String,
    @SerialName("InUse") val inUse: Boolean? = null
)

@Serializable
data class DockerImageResponse(
    val success: Boolean,
    val data: List<DockerImage>
)

@Serializable
data class NginxSite(
    val name: String,
    val port: String,
    val serverName: String,
    val status: String
)

@Serializable
data class NginxResponse(
    val success: Boolean,
    val running: Boolean? = null,
    val pids: List<String>? = null,
    val binPath: String? = null,
    val data: List<NginxSite>? = null,
    val error: String? = null
)

@Serializable
data class RemoteProcess(
    val pid: String,
    val user: String,
    val cpu: String,
    val mem: String,
    val command: String
)

@Serializable
data class ProcessResponse(
    val success: Boolean,
    val data: List<RemoteProcess>
)

@Serializable
data class LogItem(
    val path: String,
    val name: String,
    val dir: String,
    val category: String,
    val size: Int,
    val mtime: Long,
    val isCustom: Boolean
)

@Serializable
data class LogResponse(
    val success: Boolean,
    val data: JsonElement? = null,
    val error: String? = null
)

@Serializable
data class ConfigItem(
    val id: String,
    val name: String,
    val path: String,
    val category: String,
    val size: Int? = null,
    val mtime: Double? = null
)

@Serializable
data class ConfigResponse(
    val success: Boolean,
    val data: List<ConfigItem>? = null,
    val content: String? = null
)

@Serializable
data class LaunchAgentItem(
    val name: String,
    val label: String? = null,
    val path: String,
    val isLoaded: Boolean,
    val size: Long,
    val mtime: Long
)

@Serializable
data class LaunchAgentResponse(
    val success: Boolean,
    val data: List<LaunchAgentItem>
)

@Serializable
data class ServerSettingsResponse(
    val success: Boolean,
    val data: ServerSettings
)

@Serializable
data class ServerSettings(
    var ai: AIConfig? = null,
    var features: FeatureToggles? = null,
    var version: String? = null
)

@Serializable
data class AIConfig(
    var enabled: Boolean? = null,
    var url: String? = null,
    var key: String? = null,
    var model: String? = null,
    var usePublicService: Boolean? = null,
    var stream: Boolean? = null
)

@Serializable
data class FeatureToggles(
    var monitor: Boolean? = null,
    var processes: Boolean? = null,
    var logs: Boolean? = null,
    var configs: Boolean? = null,
    var launchagent: Boolean? = null,
    var docker: Boolean? = null,
    var nginx: Boolean? = null
)

@Serializable
data class ActionResponse(
    val success: Boolean,
    val error: String? = null,
    val requiresPassword: Boolean? = null,
    val data: String? = null,
    val details: String? = null
)

@Serializable
data class GenericLogResponse(
    val success: Boolean,
    val logs: String
)
