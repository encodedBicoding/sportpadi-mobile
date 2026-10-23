package com.sportpadi.watch

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status

/**
 * While a match is live, an Ongoing Activity: the match sits on the watch
 * face and in the recents/ongoing slot, one tap back into officiant mode —
 * the Wear equivalent of the iOS workout session keeping the app frontmost.
 * Wear OS doesn't let an app pin itself on screen, so this plus ambient
 * mode (MainActivity) is the way back after the screen sleeps.
 */
object OngoingMatch {
    private const val CHANNEL = "officiating"
    private const val ID = 4101

    fun start(context: Context, g: Game) {
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Officiating", NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false) })
        val open = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java).putExtra("gameId", g.id).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(g.title)
            .setContentText(g.event?.title ?: "Officiating")
            .setContentIntent(open)
            .setOngoing(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
        val status = Status.Builder().addTemplate("Officiating · ${g.scoreline}").build()
        OngoingActivity.Builder(context, ID, builder)
            .setStaticIcon(android.R.drawable.ic_media_play)
            .setTouchIntent(open)
            .setStatus(status)
            .build()
            .apply(context)
        try { NotificationManagerCompat.from(context).notify(ID, builder.build()) } catch (_: SecurityException) { /* POST_NOTIFICATIONS declined */ }
    }

    fun stop(context: Context) {
        try { NotificationManagerCompat.from(context).cancel(ID) } catch (_: Exception) {}
    }
}
