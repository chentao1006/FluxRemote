package com.ct106.fluxremote.core

import android.content.Context
import com.ct106.fluxremote.model.AIConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.security.MessageDigest
import java.util.*
import java.util.concurrent.TimeUnit

@Serializable
data class ChatMessage(val role: String, val content: String)

@Serializable
data class ChatRequest(val model: String, val messages: List<ChatMessage>, val stream: Boolean?)

@Serializable
data class ChatResponse(val choices: List<Choice>) {
    @Serializable
    data class Choice(val message: ChatMessage)
}

@Serializable
data class ChatStreamResponse(val choices: List<Choice>) {
    @Serializable
    data class Choice(val delta: Delta) {
        @Serializable
        data class Delta(val content: String? = null)
    }
}

class LLMClient(private val context: Context) {
    private val client = OkHttpClient.Builder()
        .connectTimeout(60, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()

    private val json = Json { ignoreUnknownKeys = true }
    private val serviceSecret = "k9F3xP2vZ8mQ7sR4tY6uW1aC5dE0bHnL"
    private val publicServiceURL = "openai.ct106.com/v1"

    private fun getDeviceId(): String {
        val prefs = context.getSharedPreferences("ai_prefs", Context.MODE_PRIVATE)
        var id = prefs.getString("deviceId", null)
        if (id == null) {
            id = UUID.randomUUID().toString()
            prefs.edit().putString("deviceId", id).apply()
        }
        return id!!
    }

    private fun generateToken(deviceId: String): String {
        val hour = System.currentTimeMillis() / 1000 / 3600
        val input = "$serviceSecret$deviceId$hour"
        val md = MessageDigest.getInstance("MD5")
        val digest = md.digest(input.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }

    fun sendRequestStream(systemPrompt: String, userPrompt: String, customConfig: AIConfig?): Flow<String> = flow {
        val isPublic = customConfig?.usePublicService ?: true
        val urlStr: String
        val apiKey: String
        val model: String

        if (isPublic) {
            urlStr = "https://$publicServiceURL/chat/completions"
            apiKey = ""
            model = "gpt-4o-mini"
        } else {
            val customURL = customConfig?.url ?: ""
            val base = customURL.trim().removeSuffix("/")
            urlStr = "$base/chat/completions"
            apiKey = customConfig?.key ?: ""
            model = customConfig?.model ?: "gpt-4o"
        }

        val chatRequest = ChatRequest(
            model = model,
            messages = listOf(
                ChatMessage("system", systemPrompt),
                ChatMessage("user", userPrompt)
            ),
            stream = true
        )

        val requestBody = json.encodeToString(chatRequest).toRequestBody("application/json".toMediaType())
        val requestBuilder = Request.Builder()
            .url(urlStr)
            .post(requestBody)
            .addHeader("Accept", "text/event-stream")
            .addHeader("Cache-Control", "no-cache")

        if (isPublic) {
            val deviceId = getDeviceId()
            val token = generateToken(deviceId)
            requestBuilder.addHeader("X-Device-Id", deviceId)
            requestBuilder.addHeader("X-Token", token)
        } else if (apiKey.isNotEmpty()) {
            requestBuilder.addHeader("Authorization", "Bearer $apiKey")
        }

        val request = requestBuilder.build()
        
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                val errorBody = response.body?.string() ?: ""
                throw IOException("API Error (${response.code}): $errorBody")
            }
            val reader = response.body?.source()?.inputStream()?.bufferedReader() ?: throw IOException("No body")
            var line: String? = reader.readLine()
            while (line != null) {
                if (line!!.startsWith("data:")) {
                    val dataStr = line!!.substring(5).trim()
                    if (dataStr == "[DONE]") break
                    try {
                        val chunk = json.decodeFromString<ChatStreamResponse>(dataStr)
                        chunk.choices.firstOrNull()?.delta?.content?.let {
                            emit(it)
                        }
                    } catch (e: Exception) {
                        // Ignore partial JSON or errors
                    }
                }
                line = reader.readLine()
            }
        }
    }.flowOn(Dispatchers.IO)
}

class AIService(context: Context) {
    private val client = LLMClient(context)

    fun analyzeStream(prompt: String, systemPrompt: String, apiClient: RemoteAPIClient): Flow<String> {
        val config = apiClient.aiConfig
        if (config?.enabled != true) {
            return flow { throw IllegalStateException("AI_CONFIG_MISSING") }
        }
        return client.sendRequestStream(prompt, systemPrompt, config)
    }

    companion object {
        private var instance: AIService? = null
        fun getInstance(context: Context): AIService {
            return instance ?: synchronized(this) {
                instance ?: AIService(context.applicationContext).also { instance = it }
            }
        }
    }
}
