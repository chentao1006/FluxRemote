package com.ct106.flux_remote.model

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.*

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
data class MetricPoint(
    val cpu: Double,
    val memory: Double,
    val netIn: Double,
    val netOut: Double
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

@Serializable(with = DockerContainerSerializer::class)
data class DockerContainer(
    val id: String,
    val names: List<String>,
    val image: String,
    val state: String,
    val status: String,
    val ports: String,
    val command: String? = null,
    val createdAt: String? = null
) {
    val name: String
        get() = names.firstOrNull()?.replace("/", "") ?: "unknown"
}

object DockerContainerSerializer : KSerializer<DockerContainer> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("DockerContainer")

    override fun deserialize(decoder: Decoder): DockerContainer {
        val jsonInput = decoder as? JsonDecoder ?: throw SerializationException("Expected JsonDecoder")
        val json = jsonInput.decodeJsonElement().jsonObject
        fun getString(vararg keys: String): String {
            for (key in keys) {
                val element = json[key]
                if (element is JsonPrimitive && element.isString) return element.content
            }
            return ""
        }

        val id = getString("ID", "id")
        val namesElement = json["Names"] ?: json["names"]
        val names = when (namesElement) {
            is JsonArray -> namesElement.map { it.jsonPrimitive.content }
            is JsonPrimitive -> if (namesElement.isString) listOf(namesElement.content) else emptyList()
            else -> emptyList()
        }

        return DockerContainer(
            id = id,
            names = names,
            image = getString("Image", "image"),
            state = getString("State", "state"),
            status = getString("Status", "status"),
            ports = getString("Ports", "ports"),
            command = getString("Command", "command").takeIf { it.isNotEmpty() },
            createdAt = getString("CreatedAt", "createdAt").takeIf { it.isNotEmpty() }
        )
    }

    override fun serialize(encoder: Encoder, value: DockerContainer) {
        val json = buildJsonObject {
            put("ID", value.id)
            put("Names", JsonArray(value.names.map { JsonPrimitive(it) }))
            put("Image", value.image)
            put("State", value.state)
            put("Status", value.status)
            put("Ports", value.ports)
            value.command?.let { put("Command", it) }
            value.createdAt?.let { put("CreatedAt", it) }
        }
        encoder.encodeSerializableValue(JsonObject.serializer(), json)
    }
}

@Serializable
data class DockerResponse(
    val success: Boolean,
    val data: List<DockerContainer>
)

@Serializable(with = DockerImageSerializer::class)
data class DockerImage(
    val id: String,
    val repository: String,
    val tag: String,
    val size: String,
    val createdAt: String,
    val inUse: Boolean? = null
)

object DockerImageSerializer : KSerializer<DockerImage> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("DockerImage")

    override fun deserialize(decoder: Decoder): DockerImage {
        val jsonInput = decoder as? JsonDecoder ?: throw SerializationException("Expected JsonDecoder")
        val json = jsonInput.decodeJsonElement().jsonObject
        fun getString(vararg keys: String): String {
            for (key in keys) {
                val element = json[key]
                if (element is JsonPrimitive && element.isString) return element.content
            }
            return ""
        }

        return DockerImage(
            id = getString("ID", "id"),
            repository = getString("Repository", "repository"),
            tag = getString("Tag", "tag"),
            size = getString("Size", "size"),
            createdAt = getString("CreatedAt", "createdAt"),
            inUse = json["InUse"]?.jsonPrimitive?.booleanOrNull ?: json["inUse"]?.jsonPrimitive?.booleanOrNull
        )
    }

    override fun serialize(encoder: Encoder, value: DockerImage) {
        val json = buildJsonObject {
            put("ID", value.id)
            put("Repository", value.repository)
            put("Tag", value.tag)
            put("Size", value.size)
            put("CreatedAt", value.createdAt)
            value.inUse?.let { put("InUse", it) }
        }
        encoder.encodeSerializableValue(JsonObject.serializer(), json)
    }
}

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
data class PortEntry(
    val protocol: String,
    val port: Int,
    val address: String,
    val endpoint: String,
    val endpoints: List<String>? = null,
    val connectionCount: Int? = null,
    val state: String = ""
)

@Serializable
data class PortProcessGroup(
    val pid: String,
    val command: String,
    val user: String,
    val cpu: String,
    val mem: String,
    val ppid: String = "",
    val start: String = "",
    val fullCommand: String = "",
    val ports: List<PortEntry>
)

@Serializable
data class PortSummary(
    val processes: Int = 0,
    val ports: Int = 0,
    val listening: Int = 0
)

@Serializable
data class PortsResponse(
    val success: Boolean,
    val data: List<PortProcessGroup> = emptyList(),
    val summary: PortSummary = PortSummary(),
    val error: String? = null,
    val details: String? = null
)

@Serializable
data class DetailedProcess(
    val pid: String,
    val ppid: String,
    val ppidName: String,
    val cpu: String,
    val mem: String,
    val state: String,
    val start: String,
    val time: String,
    val user: String,
    val command: String,
    val fullCommand: String,
    val openFiles: List<String>
)

@Serializable
data class DetailedProcessResponse(
    val success: Boolean,
    val data: DetailedProcess
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
    var ports: Boolean? = null,
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
@SerialName("AIResponse")
data class AIResponse(
    val success: Boolean,
    val data: String
)

@Serializable
data class GenericLogResponse(
    val success: Boolean,
    val logs: String
)

@Serializable
data class ScreenshotResponse(
    val success: Boolean,
    val data: String? = null,
    val error: String? = null
)
