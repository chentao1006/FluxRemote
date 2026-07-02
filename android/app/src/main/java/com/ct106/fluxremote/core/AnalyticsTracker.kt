package com.ct106.flux_remote.core

import android.content.Context
import android.util.Log
import com.aptabase.Aptabase
import com.ct106.flux_remote.BuildConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

object AnalyticsTracker {
    private const val TAG = "AnalyticsTracker"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @Volatile private var initialized = false
    @Volatile private var disabled = false

    fun track(context: Context, eventName: String) {
        if (disabled) return

        val appContext = context.applicationContext
        scope.launch {
            try {
                if (!ensureInitialized(appContext)) return@launch
                Aptabase.instance.trackEvent(eventName)
            } catch (t: Throwable) {
                disabled = true
                Log.w(TAG, "Analytics disabled after track failure", t)
            }
        }
    }

    private fun ensureInitialized(context: Context): Boolean {
        if (disabled) return false
        if (initialized) return true

        val appKey = BuildConfig.APTABASE_APP_KEY
        if (appKey.isEmpty()) {
            disabled = true
            return false
        }

        return synchronized(this) {
            if (disabled) return@synchronized false
            if (!initialized) {
                try {
                    Aptabase.instance.initialize(context.applicationContext, appKey)
                    initialized = true
                } catch (t: Throwable) {
                    disabled = true
                    Log.w(TAG, "Analytics disabled after init failure", t)
                }
            }
            initialized
        }
    }
}
