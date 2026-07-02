package com.ct106.flux_remote.core

import android.content.Context
import android.net.Uri
import android.util.Base64
import android.util.Log
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import java.nio.ByteBuffer
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import okhttp3.*
import okio.ByteString.Companion.toByteString

/**
 * MQTT Remote Sync for Android (Flux Remote)
 *
 * Subscribes to an encrypted MQTT topic published by the Mac's Flux Monitor app to automatically
 * discover the latest public URL when direct connection fails.
 *
 * Protocol: MQTT 3.1.1 over WebSocket Encryption: AES-256-GCM (nonce + ciphertext + tag combined,
 * Base64 encoded)
 */
class MQTTRemoteSync private constructor(private val context: Context) {

    companion object {
        private const val TAG = "MQTTRemoteSync"

        @Volatile private var instance: MQTTRemoteSync? = null

        fun getInstance(context: Context): MQTTRemoteSync {
            return instance
                    ?: synchronized(this) {
                        instance
                                ?: MQTTRemoteSync(context.applicationContext).also { instance = it }
                    }
        }

        data class PairingData(
                val topic: String,
                val key: String,
                val user: String?,
                val pass: String?
        )

        // Parse a flux://connect?topic=xxx&key=xxx or https://flux.ct106.com/connect.html?topic=...
        // URI
        fun parsePairingURI(uri: String): PairingData? {
            return try {
                val parsed = Uri.parse(uri)
                val isCustomScheme = parsed.scheme == "flux" && parsed.host == "connect"
                val isUniversalLink =
                        (parsed.scheme == "https" || parsed.scheme == "http") &&
                                parsed.host?.equals("flux.ct106.com", ignoreCase = true) == true &&
                                parsed.path?.contains("connect", ignoreCase = true) == true

                if (!isCustomScheme && !isUniversalLink) return null

                val topic = parsed.getQueryParameter("topic") ?: return null
                val rawKey = parsed.getQueryParameter("key") ?: return null
                val key = rawKey.replace(" ", "+")
                val user = parsed.getQueryParameter("u")
                val pass = parsed.getQueryParameter("p")
                if (topic.isEmpty() || key.isEmpty()) return null
                PairingData(topic, key, user, pass)
            } catch (e: Exception) {
                null
            }
        }
    }

    // --- Persistence ---
    private val Context.mqttDataStore by preferencesDataStore(name = "mqtt_remote_sync")
    private val TOPIC_KEY = stringPreferencesKey("mqtt_topic")
    private val AES_KEY = stringPreferencesKey("mqtt_aes_key")

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // --- State ---
    private val _isPaired = MutableStateFlow(false)
    val isPaired: StateFlow<Boolean> = _isPaired

    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected

    private val _latestURL = MutableStateFlow<String?>(null)
    val latestURL: StateFlow<String?> = _latestURL

    private val _latestUser = MutableStateFlow<String?>(null)
    private val _latestPass = MutableStateFlow<String?>(null)
    private val _latestHostname = MutableStateFlow<String?>(null)

    private var savedTopic: String? = null
    private var savedAESKey: String? = null

    // --- MQTT Broker Failover ---
    private data class MQTTBroker(
            val host: String,
            val port: Int,
            val path: String,
            val useTLS: Boolean
    ) {
        val url: String
            get() = "${if (useTLS) "wss" else "ws"}://$host:$port$path"
    }

    private val brokers =
            listOf(
                    MQTTBroker("broker.emqx.io", 8084, "/mqtt", true),
                    MQTTBroker("broker.hivemq.com", 8884, "/mqtt", true),
            )

    private var currentBrokerIndex = 0
    private var webSocket: WebSocket? = null
    private var isConnecting = false
    private var keepAliveJob: Job? = null
    private val okHttpClient =
            OkHttpClient.Builder()
                    .connectTimeout(5, java.util.concurrent.TimeUnit.SECONDS)
                    .readTimeout(
                            0,
                            java.util.concurrent.TimeUnit.MILLISECONDS
                    ) // Keep WebSocket open
                    .build()

    init {
        // Load saved credentials
        scope.launch {
            context.mqttDataStore.data.first().let { prefs ->
                savedTopic = prefs[TOPIC_KEY]
                savedAESKey = prefs[AES_KEY]
                _isPaired.value = savedTopic != null && savedAESKey != null
            }
        }
    }

    // MARK: - Public API

    /**
     * Save pairing credentials from a QR code scan. Returns true if successfully parsed and saved.
     */
    suspend fun savePairing(topic: String, aesKey: String): Boolean {
        return try {
            // Validate the AES key is valid Base64 of correct length
            val decoded = Base64.decode(aesKey, Base64.DEFAULT)
            if (decoded.size != 32) { // AES-256 = 32 bytes
                Log.w(TAG, "Invalid AES key length: ${decoded.size}")
                return false
            }

            context.mqttDataStore.edit { prefs ->
                prefs[TOPIC_KEY] = topic
                prefs[AES_KEY] = aesKey
            }
            savedTopic = topic
            savedAESKey = aesKey
            _isPaired.value = true
            Log.i(TAG, "Pairing saved for topic: flux_remote/$topic")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save pairing", e)
            false
        }
    }

    data class FetchResult(
            val url: String,
            val user: String?,
            val pass: String?,
            val hostname: String?
    )

    /**
     * Try to fetch the latest URL and credentials via MQTT. This is called when direct connection
     * fails or right after pairing.
     *
     * @param timeoutMs Maximum time to wait for an MQTT message
     * @param onDataReceived Callback with the decrypted data, or null if timeout
     */
    fun fetchLatestData(timeoutMs: Long = 15000, onDataReceived: (FetchResult?) -> Unit) {
        val topic = savedTopic
        val key = savedAESKey
        if (topic == null || key == null) {
            Log.w(TAG, "Cannot fetch data: not paired")
            onDataReceived(null)
            return
        }

        scope.launch {
            val wasConnected = _isConnected.value

            // Force reconnect to ensure we pull the fresh retained message from the broker
            disconnect()
            _latestURL.value = null

            // Connect and subscribe, then wait for the retained message
            connectAndSubscribe()

            // Wait for the URL with timeout
            val result = withTimeoutOrNull(timeoutMs) { _latestURL.filterNotNull().first() }
            if (result != null) {
                onDataReceived(
                        FetchResult(
                                result,
                                _latestUser.value,
                                _latestPass.value,
                                _latestHostname.value
                        )
                )
            } else {
                onDataReceived(null)
            }
        }
    }

    /** Connect to MQTT and subscribe. Used in background for continuous monitoring. */
    fun connectAndSubscribe() {
        if (isConnecting || _isConnected.value) return
        if (savedTopic == null || savedAESKey == null) return

        currentBrokerIndex = 0
        connectToNextBroker()
    }

    /** Disconnect from MQTT broker. */
    fun disconnect() {
        keepAliveJob?.cancel()
        keepAliveJob = null
        webSocket?.close(1000, "Client disconnect")
        webSocket = null
        isConnecting = false
        _isConnected.value = false
    }

    /** Clear all pairing data. */
    suspend fun clearPairing() {
        disconnect()
        context.mqttDataStore.edit { prefs ->
            prefs.remove(TOPIC_KEY)
            prefs.remove(AES_KEY)
        }
        savedTopic = null
        savedAESKey = null
        _isPaired.value = false
        _latestURL.value = null
        _latestHostname.value = null
    }

    // MARK: - MQTT Connection

    private fun connectToNextBroker() {
        if (currentBrokerIndex >= brokers.size) {
            currentBrokerIndex = 0
            Log.w(TAG, "All MQTT brokers failed")
            isConnecting = false
            return
        }

        val broker = brokers[currentBrokerIndex]
        Log.i(TAG, "Connecting to MQTT broker: ${broker.host}")
        isConnecting = true

        val request =
                Request.Builder().url(broker.url).header("Sec-WebSocket-Protocol", "mqtt").build()

        webSocket =
                okHttpClient.newWebSocket(
                        request,
                        object : WebSocketListener() {
                            override fun onOpen(webSocket: WebSocket, response: Response) {
                                Log.i(TAG, "WebSocket opened to ${broker.host}")
                                sendMQTTConnect(webSocket)
                            }

                            override fun onMessage(webSocket: WebSocket, bytes: okio.ByteString) {
                                handleMQTTPacket(webSocket, bytes.toByteArray())
                            }

                            override fun onFailure(
                                    webSocket: WebSocket,
                                    t: Throwable,
                                    response: Response?
                            ) {
                                Log.e(TAG, "WebSocket failure: ${t.message}")
                                _isConnected.value = false
                                isConnecting = false
                                // Try next broker
                                currentBrokerIndex++
                                scope.launch {
                                    delay(1000)
                                    connectToNextBroker()
                                }
                            }

                            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                                Log.i(TAG, "WebSocket closed: $reason")
                                _isConnected.value = false
                                isConnecting = false
                            }
                        }
                )
    }

    // MARK: - MQTT Protocol (Minimal 3.1.1)

    private fun sendMQTTConnect(ws: WebSocket) {
        val topic = savedTopic ?: return
        val clientID = "fluxr_${topic.take(12)}"

        val variableHeader = ByteBuffer.allocate(10 + clientID.length + 2)
        // Protocol Name "MQTT"
        variableHeader.putShort(4)
        variableHeader.put("MQTT".toByteArray())
        // Protocol Level 4 (MQTT 3.1.1)
        variableHeader.put(4)
        // Connect Flags: Clean Session
        variableHeader.put(0x02)
        // Keep Alive: 60 seconds
        variableHeader.putShort(60)
        // Client ID
        variableHeader.putShort(clientID.length.toShort())
        variableHeader.put(clientID.toByteArray())

        val body = variableHeader.array().copyOf(variableHeader.position())
        val packet = buildMQTTPacket(0x10, body)
        ws.send(packet.toByteString())
    }

    private fun sendMQTTSubscribe(ws: WebSocket) {
        val topic = "flux_remote/${savedTopic ?: return}"
        val packetId: Short = 1

        val variableHeader = ByteBuffer.allocate(2 + 2 + topic.length + 1)
        // Packet Identifier
        variableHeader.putShort(packetId)
        // Topic Filter
        variableHeader.putShort(topic.length.toShort())
        variableHeader.put(topic.toByteArray())
        // QoS 0
        variableHeader.put(0)

        val body = variableHeader.array().copyOf(variableHeader.position())
        // SUBSCRIBE = 0x82 (with required flags)
        val packet = buildMQTTPacket(0x82.toByte().toInt(), body)
        ws.send(packet.toByteString())
        Log.i(TAG, "Subscribed to topic: $topic")
    }

    private fun sendPingReq(ws: WebSocket) {
        ws.send(byteArrayOf(0xC0.toByte(), 0x00).toByteString())
    }

    private fun buildMQTTPacket(packetType: Int, body: ByteArray): ByteArray {
        val remaining = encodeRemainingLength(body.size)
        val packet = ByteArray(1 + remaining.size + body.size)
        packet[0] = packetType.toByte()
        System.arraycopy(remaining, 0, packet, 1, remaining.size)
        System.arraycopy(body, 0, packet, 1 + remaining.size, body.size)
        return packet
    }

    private fun encodeRemainingLength(length: Int): ByteArray {
        val result = mutableListOf<Byte>()
        var value = length
        do {
            var byte = (value % 128).toByte()
            value /= 128
            if (value > 0) byte = (byte.toInt() or 0x80).toByte()
            result.add(byte)
        } while (value > 0)
        return result.toByteArray()
    }

    private fun handleMQTTPacket(ws: WebSocket, data: ByteArray) {
        if (data.isEmpty()) return
        val packetType = (data[0].toInt() and 0xFF) shr 4

        when (packetType) {
            2 -> { // CONNACK
                if (data.size >= 4 && data[3].toInt() == 0) {
                    Log.i(TAG, "MQTT CONNACK: Connection accepted")
                    isConnecting = false
                    _isConnected.value = true
                    sendMQTTSubscribe(ws)
                    startKeepAlive(ws)
                } else {
                    val rc = if (data.size >= 4) data[3].toInt() else -1
                    Log.w(TAG, "MQTT CONNACK rejected: return code $rc")
                    currentBrokerIndex++
                    connectToNextBroker()
                }
            }
            3 -> { // PUBLISH
                handlePublish(data)
            }
            9 -> { // SUBACK
                Log.i(TAG, "MQTT SUBACK received")
            }
            13 -> { // PINGRESP
                // Expected
            }
        }
    }

    private fun handlePublish(data: ByteArray) {
        try {
            // Parse PUBLISH packet to extract payload
            var offset = 1
            // Decode remaining length
            var multiplier = 1
            var remainingLength = 0
            do {
                val byte = data[offset].toInt() and 0xFF
                offset++
                remainingLength += (byte and 0x7F) * multiplier
                multiplier *= 128
            } while (byte and 0x80 != 0)

            // Topic length (2 bytes)
            val topicLen =
                    ((data[offset].toInt() and 0xFF) shl 8) or (data[offset + 1].toInt() and 0xFF)
            offset += 2 + topicLen // Skip topic

            // Check QoS - if QoS > 0, skip packet identifier
            val qos = (data[0].toInt() and 0x06) shr 1
            if (qos > 0) offset += 2

            // Remaining is payload
            val payloadEnd = 1 + encodeRemainingLength(remainingLength).size + remainingLength
            if (offset >= data.size) return
            val payload = data.copyOfRange(offset, minOf(payloadEnd, data.size))

            // Payload is Base64-encoded encrypted JSON string
            val base64String = String(payload, Charsets.UTF_8).trim()
            val decryptedString = decrypt(base64String)

            if (decryptedString != null) {
                Log.i(TAG, "Received and decrypted payload: $decryptedString")
                try {
                    val json = org.json.JSONObject(decryptedString)
                    val parsedUrl = json.optString("url")
                    val parsedUser = json.optString("u")
                    val parsedPass = json.optString("p")
                    val parsedHostname = json.optString("hostname")

                    if (parsedUrl.isNotEmpty()) {
                        _latestUser.value = parsedUser.takeIf { it.isNotEmpty() }
                        _latestPass.value = parsedPass.takeIf { it.isNotEmpty() }
                        _latestHostname.value = parsedHostname.takeIf { it.isNotEmpty() }
                        _latestURL.value = parsedUrl
                    }
                } catch (e: Exception) {
                    // Fallback to raw string (legacy Mac apps)
                    _latestURL.value = decryptedString
                }
            } else {
                Log.w(TAG, "Failed to decrypt MQTT payload")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing PUBLISH packet", e)
        }
    }

    private fun startKeepAlive(ws: WebSocket) {
        keepAliveJob?.cancel()
        keepAliveJob =
                scope.launch {
                    while (isActive) {
                        delay(55_000) // 55 seconds (keep alive is 60)
                        sendPingReq(ws)
                    }
                }
    }

    // MARK: - AES-GCM Decryption

    private fun decrypt(base64Combined: String): String? {
        val aesKeyBase64 = savedAESKey ?: return null
        return try {
            val keyBytes = Base64.decode(aesKeyBase64, Base64.DEFAULT)
            val combined = Base64.decode(base64Combined, Base64.DEFAULT)

            // CryptoKit's AES.GCM.seal combined format:
            // nonce (12 bytes) + ciphertext + tag (16 bytes)
            if (combined.size < 28) return null // 12 + 0 + 16 minimum

            val nonce = combined.copyOfRange(0, 12)
            val ciphertextAndTag = combined.copyOfRange(12, combined.size)

            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val keySpec = SecretKeySpec(keyBytes, "AES")
            val gcmSpec = GCMParameterSpec(128, nonce) // 128-bit tag
            cipher.init(Cipher.DECRYPT_MODE, keySpec, gcmSpec)

            val plaintext = cipher.doFinal(ciphertextAndTag)
            String(plaintext, Charsets.UTF_8)
        } catch (e: Exception) {
            Log.e(TAG, "AES-GCM decryption failed", e)
            null
        }
    }
}
