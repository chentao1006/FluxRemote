package com.ct106.fluxremote.core

import com.ct106.fluxremote.model.*
import okhttp3.OkHttpClient
import okhttp3.RequestBody
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.http.*
import java.util.concurrent.TimeUnit

interface FluxRemoteApi {
    @POST("api/auth/login")
    suspend fun login(@Body credentials: Map<String, String>): Response<ActionResponse>

    @GET("api/settings")
    suspend fun getSettings(): Response<ServerSettingsResponse>

    @GET("api/stats")
    suspend fun getStats(): Response<RemoteStatsResponse>

    // Docker
    @GET("api/docker/containers")
    suspend fun getDockerContainers(): Response<DockerResponse>

    @GET("api/docker/images")
    suspend fun getDockerImages(): Response<DockerImageResponse>

    @POST("api/docker/action")
    suspend fun dockerAction(@Body body: Map<String, String>): Response<ActionResponse>

    @GET("api/docker/logs")
    suspend fun getDockerLogs(@Query("id") id: String): Response<GenericLogResponse>

    // Nginx
    @GET("api/nginx")
    suspend fun getNginxSites(): Response<NginxResponse>

    @POST("api/nginx/action")
    suspend fun nginxAction(@Body body: Map<String, String>): Response<ActionResponse>

    // Processes
    @GET("api/process")
    suspend fun getProcesses(): Response<ProcessResponse>

    @POST("api/process/action")
    suspend fun processAction(@Body body: Map<String, String>): Response<ActionResponse>

    // Logs
    @GET("api/logs")
    suspend fun getLogs(): Response<LogResponse>

    @GET("api/logs/content")
    suspend fun getLogContent(@Query("path") path: String): Response<LogResponse>

    // Configs
    @GET("api/configs")
    suspend fun getConfigs(): Response<ConfigResponse>

    @GET("api/configs/content")
    suspend fun getConfigContent(@Query("path") path: String): Response<ConfigResponse>

    // Launch Agent
    @GET("api/launchagent")
    suspend fun getLaunchAgents(): Response<LaunchAgentResponse>

    @POST("api/launchagent/action")
    suspend fun launchAgentAction(@Body body: Map<String, String>): Response<ActionResponse>
}

class RemoteAPIClient(private val serverManager: ServerManager) {
    private var currentRetrofit: Retrofit? = null
    private var currentApi: FluxRemoteApi? = null
    
    private val okHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .addInterceptor { chain ->
            val request = chain.request().newBuilder()
                .header("User-Agent", "FluxRemote/1.0 (Android)")
                .header("Accept", "application/json")
                .build()
            chain.proceed(request)
        }
        .build()

    fun getApi(): FluxRemoteApi? {
        val server = serverManager.getSelectedServer() ?: return null
        val baseUrl = server.baseURL
        
        if (currentRetrofit?.baseUrl()?.toString() != baseUrl) {
            currentRetrofit = Retrofit.Builder()
                .baseUrl(baseUrl)
                .client(okHttpClient)
                .addConverterFactory(jsonConverter())
                .build()
            currentApi = currentRetrofit?.create(FluxRemoteApi::class.java)
        }
        return currentApi
    }

    private fun jsonConverter(): retrofit2.Converter.Factory {
        val json = kotlinx.serialization.json.Json { 
            ignoreUnknownKeys = true 
            coerceInputValues = true
        }
        val contentType = okhttp3.MediaType.get("application/json")
        return com.jakewharton.retrofit2.converter.kotlinxserialization.asConverterFactory(contentType, json)
    }

    suspend fun login(credentials: Map<String, String>, server: ServerConfig): Boolean {
        try {
            val api = getApi() ?: return false
            val response = api.login(credentials)
            if (response.isSuccessful && response.body()?.success == true) {
                serverManager.setAuthenticated(server.id, true)
                if (server.rememberPassword) {
                    serverManager.setPassword(server.id, credentials["password"])
                }
                return true
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
    }
}
