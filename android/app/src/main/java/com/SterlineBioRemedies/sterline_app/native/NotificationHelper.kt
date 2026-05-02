package com.FieldServiceBioRemedies.FieldService_app.native

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.FieldServiceBioRemedies.FieldService_app.MainActivity

class NotificationHelper(private val context: Context) {
    private val notificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    companion object {
        const val CHANNEL_ID = "trip_channel_id"
        const val NOTIFICATION_ID = 1002
        const val ACTION_STOP = "com.FieldServiceBioRemedies.FieldService_app.STOP_TRIP"
    }

    init {
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Trip Tracking",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows trip progress and elapsed time"
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    fun buildNotification(
        tripId: String,
        elapsedSeconds: Long,
        distanceMeters: Double
    ): Notification {
        val elapsedTime = formatElapsedTime(elapsedSeconds)
        val distanceText = formatDistance(distanceMeters)
        val contentText = "$elapsedTime • $distanceText"

        // Deep link intent — tapping notification opens the trip screen
        val deepLinkIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            putExtra("route", "/trip?tripId=$tripId")
        }
        val contentPendingIntent = PendingIntent.getActivity(
            context,
            0,
            deepLinkIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // FIX Minor: Stop action — uses getService so onStartCommand handles ACTION_STOP.
        // Previously used getBroadcast with no registered receiver, so the action was
        // built but never delivered. Now routes to onStartCommand which already handles it.
        val stopServiceIntent = Intent(context, TripForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            context,
            1,
            stopServiceIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("Trip Running")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(contentPendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun formatElapsedTime(seconds: Long): String {
        val hours = seconds / 3600
        val minutes = (seconds % 3600) / 60
        val secs = seconds % 60
        return String.format("%dh %02dm %02ds", hours, minutes, secs)
    }

    private fun formatDistance(meters: Double): String {
        return if (meters < 1000) {
            String.format("%.0fm", meters)
        } else {
            String.format("%.2fkm", meters / 1000.0)
        }
    }

    fun updateNotification(
        tripId: String,
        elapsedSeconds: Long,
        distanceMeters: Double
    ) {
        val notification = buildNotification(tripId, elapsedSeconds, distanceMeters)
        Log.d("NotificationHelper", "updateNotification: NOTIFICATION_ID=$NOTIFICATION_ID elapsedSeconds=$elapsedSeconds distanceMeters=$distanceMeters")
        removeDuplicateTripNotifications(NOTIFICATION_ID)
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    fun cancelNotification() {
        notificationManager.cancel(NOTIFICATION_ID)
    }

    /**
     * Cancel other trip notifications on the same channel with a different id.
     * Prevents duplicate notifications when an external plugin posts on the same channel.
     */
    fun removeDuplicateTripNotifications(preserveId: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val active = notificationManager.activeNotifications
                for (sbn in active) {
                    val nid = sbn.id
                    val channel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        sbn.notification.channelId
                    } else null
                    if (channel == CHANNEL_ID && nid != preserveId) {
                        Log.d("NotificationHelper", "removeDuplicateTripNotifications: cancelling id=$nid")
                        notificationManager.cancel(nid)
                    }
                }
            } catch (e: Exception) {
                Log.e("NotificationHelper", "removeDuplicateTripNotifications failed", e)
            }
        }
    }
}