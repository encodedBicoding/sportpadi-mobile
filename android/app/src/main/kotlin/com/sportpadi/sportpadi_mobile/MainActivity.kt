package com.sportpadi.sportpadi_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.app.ActivityManager
import android.content.Context
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
        createMessagingChannels()
    }

    /**
     * Officiant mode (lib/features/games/officiate_screen.dart) locks the
     * timekeeper into the app: screen pinning via lock task, so Home and
     * Recents can't pull them away mid-match, plus keep-screen-on. For an app
     * that isn't a device owner, startLockTask() is Android's "screen pinning"
     * — the system may ask the user to confirm once. Best effort throughout.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sportpadi/officiate")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "lockIn" -> {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        try {
                            if (!isLockTaskOn()) startLockTask()
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "release" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        try {
                            if (isLockTaskOn()) stopLockTask()
                        } catch (_: Exception) {
                        }
                        result.success(true)
                    }
                    "isLocked" -> result.success(isLockTaskOn())
                    else -> result.notImplemented()
                }
            }
    }

    private fun isLockTaskOn(): Boolean {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
        } else {
            @Suppress("DEPRECATION")
            am.isInLockTaskMode
        }
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

    /**
     * Messaging channels (docs/design/wards-and-messaging.md, B6): one per
     * kind of message, so each can be tuned in system settings and they look
     * and sound different. The server names them in
     * android.notification.channel_id; lib/core/push/push_service.dart uses
     * the same ids for foreground pushes. `sportpadi_high` above stays for
     * everything that doesn't name one of these.
     *
     *   announcements         group/team/event announcements — high
     *   announcements_urgent  urgent ones — high, sound + vibration; this is
     *                         what still gets through when a group is muted
     *   messages              conversations with staff (Messaging 2) — high
     *   activity              app notifications and SportPadi news — default
     *
     * Same caveat as above: importance and sound only apply at creation.
     */
    private fun createMessagingChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val audio = AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .build()

        val announcements = NotificationChannel(
            CHANNEL_ANNOUNCEMENTS,
            "Announcements",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "News from your groups, teams and event organisers."
            setShowBadge(true)
        }

        val urgent = NotificationChannel(
            CHANNEL_ANNOUNCEMENTS_URGENT,
            "Urgent announcements",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Time-critical news from your groups, with sound and a heads-up alert."
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 250, 150, 250)
            enableLights(true)
            setShowBadge(true)
            setSound(sound, audio)
        }

        val messages = NotificationChannel(
            CHANNEL_MESSAGES,
            "Messages",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Conversations with your coaches and group staff."
            setShowBadge(true)
        }

        val activity = NotificationChannel(
            CHANNEL_ACTIVITY,
            "Activity",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Check-ins, results, invites, payments and SportPadi news."
            setShowBadge(true)
        }

        manager.createNotificationChannels(listOf(announcements, urgent, messages, activity))
    }

    private companion object {
        const val CHANNEL_ID = "sportpadi_high"
        const val CHANNEL_ANNOUNCEMENTS = "announcements"
        const val CHANNEL_ANNOUNCEMENTS_URGENT = "announcements_urgent"
        const val CHANNEL_MESSAGES = "messages"
        const val CHANNEL_ACTIVITY = "activity"
    }
}
