package com.ct106.flux_remote

import android.app.Application
import com.aptabase.Aptabase

class FluxRemoteApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        
        // Initialize Aptabase Analytics
        val appKey = BuildConfig.APTABASE_APP_KEY
        if (appKey.isNotEmpty()) {
            Aptabase.instance.initialize(this, appKey)
            Aptabase.instance.trackEvent("app_started")
        }
    }
}
