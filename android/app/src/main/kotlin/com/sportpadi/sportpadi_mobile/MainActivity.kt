package com.sportpadi.sportpadi_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    /**
     * On Android 8+ a notification's importance — whether it peeks as a
     * heads-up banner, makes a sound, vibrates — is a property of its CHANNEL,
     * not of the message. FCM will happily deliver a push naming a channel that
     * doesn't exist; it just quietly drops it into its own fallback channel at
     * default importance, where it lands silently in the shade. That is what
     * makes a push feel second-class next to WhatsApp's.
     *
     * So the channel is created here, at IMPORTANCE_HIGH, on every launch
     * (creating an existing channel is a no-op). The id must stay in lockstep
     * with AndroidManifest.xml's default_notification_channel_id and the
     * server's android.notification.channel_id.
     *
     * NOTE: importance and sound are only honoured at CREATION. A user who
     * already has this channel keeps whatever settings it was created with —
     * changing them later needs a new channel id.
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Match & group alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description =
                "Kick-offs, call-ups, ticket and wallet updates, and news from your groups."
            enableVibration(true)
            enableLights(true)
            setShowBadge(true)
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .build(),
            )
        }
        manager.createNotificationChannel(channel)
    }

    private companion object {
        const val CHANNEL_ID = "sportpadi_high"
    }
}
