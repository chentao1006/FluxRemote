package com.ct106.flux_remote.core

import com.ct106.flux_remote.model.*
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import okhttp3.OkHttpClient
import okhttp3.RequestBody
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.http.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody
import com.jakewharton.retrofit2.converter.kotlinx.serialization.asConverterFactory
import java.util.concurrent.TimeUnit

interface FluxRemoteApi {
    @POST("api/auth/login")
    suspend fun login(@Body credentials: Map<String, String>): Response<ActionResponse>

    @GET("api/settings")
    suspend fun getSettings(): Response<ServerSettingsResponse>

    @GET("api/system/stats")
    suspend fun getStats(): Response<RemoteStatsResponse>

    @Streaming
    @POST("api/system/command")
    suspend fun executeCommand(@Body body: Map<String, String>): Response<ResponseBody>

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
    @GET("api/nginx/sites")
    suspend fun getNginxSites(): Response<NginxResponse>

    @POST("api/nginx/action")
    suspend fun nginxAction(@Body body: Map<String, String>): Response<ActionResponse>

    @POST("api/nginx/site/action")
    suspend fun nginxSiteAction(@Body body: Map<String, String>): Response<ActionResponse>

    // Processes
    @GET("api/system/processes")
    suspend fun getProcesses(@Query("sort") sort: String = "cpu"): Response<ProcessResponse>

    @GET("api/system/processes")
    suspend fun getProcessDetail(@Query("pid") pid: String): Response<DetailedProcessResponse>

    @POST("api/system/processes")
    suspend fun processAction(@Body body: Map<String, String>): Response<ActionResponse>

    // Ports
    @GET("api/system/ports")
    suspend fun getPorts(): Response<PortsResponse>

    @POST("api/system/ports")
    suspend fun portAction(@Body body: Map<String, String>): Response<ActionResponse>

    // Logs
    @GET("api/logs")
    suspend fun getLogs(): Response<LogResponse>

    @GET("api/logs")
    suspend fun getLogContent(@Query("file") path: String): Response<LogResponse>

    // Configs
    @GET("api/configs")
    suspend fun getConfigs(): Response<ConfigResponse>

    @POST("api/configs")
    suspend fun configAction(@Body body: Map<String, String>): Response<ConfigResponse>

    // Launch Agent
    @GET("api/launchagent/list")
    suspend fun getLaunchAgents(@Query("type") type: String = "agent"): Response<LaunchAgentResponse>
    
    @POST("api/launchagent/action")
    suspend fun launchAgentAction(@Body body: Map<String, String>): Response<ActionResponse>

    @POST("api/settings")
    suspend fun updateSettings(@Body settings: ServerSettings): Response<ActionResponse>

    @GET("api/system/screenshot")
    suspend fun getScreenshot(): Response<ScreenshotResponse>
}

class RemoteAPIClient(val serverManager: ServerManager) {
    private var currentRetrofit: Retrofit? = null
    private var currentApi: FluxRemoteApi? = null
    
    // Feature toggles and config state
    var features by mutableStateOf(FeatureToggles())
    var aiConfig by mutableStateOf<AIConfig?>(null)
    var dashboardStats by mutableStateOf<RemoteSystemStats?>(null)
    var dashboardHistory = mutableListOf<MetricPoint>()
    
    // Caches
    var processItems by mutableStateOf<List<RemoteProcess>>(emptyList())
    var portGroups by mutableStateOf<List<PortProcessGroup>>(emptyList())
    var portSummary by mutableStateOf(PortSummary())
    var logItems by mutableStateOf<List<LogItem>>(emptyList())
    var configItems by mutableStateOf<List<ConfigItem>>(emptyList())
    var agentItems by mutableStateOf<List<LaunchAgentItem>>(emptyList())
    var dockerContainers by mutableStateOf<List<DockerContainer>>(emptyList())
    var dockerImages by mutableStateOf<List<DockerImage>>(emptyList())
    var nginxSites by mutableStateOf<List<NginxSite>>(emptyList())
    var isNginxRunning by mutableStateOf<Boolean?>(null)
    var nginxPids by mutableStateOf<List<String>>(emptyList())
    var nginxBinPath by mutableStateOf("")

    val baseURL: String?
        get() = serverManager.getSelectedServer()?.baseURL

    companion object {
        private val cookieStore = mutableMapOf<String, List<okhttp3.Cookie>>()
    }
    
    private val okHttpClient = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .cookieJar(object : okhttp3.CookieJar {
            override fun saveFromResponse(url: okhttp3.HttpUrl, cookies: List<okhttp3.Cookie>) {
                cookieStore[url.host] = cookies
            }
            override fun loadForRequest(url: okhttp3.HttpUrl): List<okhttp3.Cookie> {
                return cookieStore[url.host] ?: listOf()
            }
        })
        .addInterceptor { chain ->
            val request = chain.request().newBuilder()
                .header("User-Agent", "FluxRemote/1.0 (Android)")
                .header("Accept", "application/json")
                .build()
            chain.proceed(request)
        }
        .build()

    fun getApi(forServer: ServerConfig? = null): FluxRemoteApi? {
        val server = forServer ?: serverManager.getSelectedServer() ?: return null
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
        val contentType = "application/json".toMediaType()
        return json.asConverterFactory(contentType)
    }

    suspend fun login(credentials: Map<String, String>, server: ServerConfig): Boolean {
        try {
            val api = getApi(server) ?: return false
            val response = api.login(credentials)
            if (response.isSuccessful && response.body()?.success == true) {
                serverManager.setAuthenticated(server.id, true)
                if (server.rememberPassword) {
                    serverManager.setPassword(server.id, credentials["password"])
                }
                
                // Fetch features and AI config after login
                val settingsResponse = api.getSettings()
                if (settingsResponse.isSuccessful) {
                    settingsResponse.body()?.data?.let { settings ->
                        features = settings.features ?: FeatureToggles()
                        aiConfig = settings.ai
                    }
                }
                
                return true
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
    }
}
