package com.sportpadi.watch

import android.app.Application

class WatchApp : Application() {
    override fun onCreate() {
        super.onCreate()
        ContextStore.init(this)
        ApiClient.init(this)
        ActionQueue.init(this)
        UsageTracker.init(this)
    }
}
