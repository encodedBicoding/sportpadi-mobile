package com.sportpadi.watch

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.lifecycleScope
import androidx.wear.ambient.AmbientLifecycleObserver
import androidx.wear.compose.material.MaterialTheme
import kotlinx.coroutines.launch

/**
 * SportPadi Watch — officiant mode on a Wear OS wrist (docs/design/
 * watch-officiant.md). The watch takes the session from the paired phone
 * (ContextStore) and calls the same API the phone does.
 *
 * Ambient: while a match is live the activity stays on in ambient mode
 * (clock only, dimmed) instead of the watch face, and wrist-raise brings the
 * full face back — the Wear equivalent of the iOS workout session.
 */
class MainActivity : ComponentActivity() {
    /** True while the screen is in ambient (wrist down). */
    var ambient by mutableStateOf(false)
        private set
    /** A match a notification / deep link asked for. */
    var requestedGameId by mutableStateOf<String?>(null)
        private set

    private val ambientObserver by lazy {
        AmbientLifecycleObserver(this, object : AmbientLifecycleObserver.AmbientLifecycleCallback {
            override fun onEnterAmbient(ambientDetails: AmbientLifecycleObserver.AmbientDetails) { ambient = true }
            override fun onExitAmbient() { ambient = false }
            override fun onUpdateAmbient() {}
        })
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        lifecycle.addObserver(ambientObserver)
        handle(intent)
        lifecycleScope.launch { ContextStore.refreshFromPhone() }
        setContent {
            MaterialTheme { WatchNav(this) }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    override fun onResume() {
        super.onResume()
        lifecycleScope.launch { ContextStore.refreshFromPhone() }
        UsageTracker.foreground()   // owner console → Usage: watch sessions
    }

    override fun onPause() {
        UsageTracker.background()
        super.onPause()
    }

    /** sportpadi://sportpadi.com/watch/games/<id>, or an extra from our own notification. */
    private fun handle(intent: Intent?) {
        val fromExtra = intent?.getStringExtra("gameId")
        val fromUri = intent?.data?.pathSegments?.let { s -> if (s.size >= 3 && s[0] == "watch" && s[1] == "games") s[2] else null }
        (fromExtra ?: fromUri)?.let { requestedGameId = it }
    }

    fun consumeRequested() { requestedGameId = null }
}
