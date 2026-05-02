package com.FieldServiceBioRemedies.FieldService_app.native

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.util.concurrent.TimeUnit

/**
 * AlarmHelper provides utilities to schedule exact alarms for critical locations checks.
 *
 * This is used sparingly as an additional fallback for Doze/idle modes when:
 * 1. WorkManager may be delayed or throttled.
 * 2. An active trip is ongoing.
 * 3. Device might enter deep sleep.
 *
 * The alarm wakes the device (with setAndAllowWhileIdle) and triggers a WakeReceiver,
 * which quickly checks if the service is still running and performs a lightweight restart if needed.
 *
 * WARNING: Excessive use of exact alarms drains battery. This helper only enables alarms
 * when an active trip is present and disables them immediately after trip stops.
 *
 * @author FieldServiceBioRemedies Team
 */
class AlarmHelper(private val context: Context) {

    companion object {
        private const val TAG = "AlarmHelper"
        private const val REQUEST_CODE_WAKE = 1001
        private const val ALARM_INTERVAL_MILLIS = 5 * 60 * 1000L // 5 minutes (tune as needed)

        fun getInstance(context: Context) = AlarmHelper(context)
    }

    private val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager

    /**
     * Schedule an exact alarm that fires every [ALARM_INTERVAL_MILLIS].
     * Used to kick the device awake while in Doze and trigger a quick service health check.
     *
     * Call this when starting an active trip.
     */
    fun scheduleWakeAlarm() {
        if (alarmManager == null) {
            Log.w(TAG, "scheduleWakeAlarm: AlarmManager not available")
            return
        }

        try {
            val intent = Intent(context, WakeReceiver::class.java).apply {
                action = "com.FieldServiceBioRemedies.FieldService_app.WAKE_FOREGROUND_SERVICE"
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                REQUEST_CODE_WAKE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val triggerTime = System.currentTimeMillis() + ALARM_INTERVAL_MILLIS

            // Use setAndAllowWhileIdle to allow waking from Doze (Android 6+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // Android 12+: use setAndAllowWhileIdle (preferred over setExactAndAllowWhileIdle due to permissions)
                alarmManager?.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerTime,
                    pendingIntent
                )
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                // Android 6-11: setExactAndAllowWhileIdle (requires SCHEDULE_EXACT_ALARM)
                try {
                    alarmManager?.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerTime,
                        pendingIntent
                    )
                } catch (e: SecurityException) {
                    Log.w(TAG, "scheduleWakeAlarm: SCHEDULE_EXACT_ALARM permission denied, falling back to setAndAllowWhileIdle")
                    alarmManager?.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerTime,
                        pendingIntent
                    )
                }
            } else {
                // Android < 6: use setRepeating (not ideal, but fallback)
                alarmManager?.setRepeating(
                    AlarmManager.RTC_WAKEUP,
                    triggerTime,
                    ALARM_INTERVAL_MILLIS,
                    pendingIntent
                )
            }

            Log.d(TAG, "scheduleWakeAlarm: Scheduled to fire in ${ALARM_INTERVAL_MILLIS / 1000}s")
        } catch (e: Exception) {
            Log.e(TAG, "scheduleWakeAlarm: Error scheduling alarm", e)
        }
    }

    /**
     * Cancel the wake alarm immediately.
     * Call this when stopping an active trip to avoid unnecessary battery drain.
     */
    fun cancelWakeAlarm() {
        if (alarmManager == null) {
            Log.w(TAG, "cancelWakeAlarm: AlarmManager not available")
            return
        }

        try {
            val intent = Intent(context, WakeReceiver::class.java).apply {
                action = "com.FieldServiceBioRemedies.FieldService_app.WAKE_FOREGROUND_SERVICE"
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                REQUEST_CODE_WAKE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager?.cancel(pendingIntent)
            Log.d(TAG, "cancelWakeAlarm: Alarm canceled")
        } catch (e: Exception) {
            Log.e(TAG, "cancelWakeAlarm: Error canceling alarm", e)
        }
    }
}

/**
 * WakeReceiver is triggered by the alarm set by AlarmHelper.
 * It wakes the device and performs a lightweight check to ensure TripForegroundService
 * is still alive. If not, it queues a worker to restart the service.
 *
 * This receiver is only active when an active trip is running.
 */
class WakeReceiver : android.content.BroadcastReceiver() {
    companion object {
        private const val TAG = "WakeReceiver"
        private const val PREFS_NAME = "trip_prefs"
        private const val PREF_ACTIVE_ID = "activeTripId"
        private const val PREF_START_UTC = "tripStartUtc"
        private const val PREF_DISTANCE = "distanceMeters"
        private const val PREF_SERVICE_RUNNING = "serviceRunning"
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "onReceive: Alarm triggered, checking service health")

        if (intent.action != "com.FieldServiceBioRemedies.FieldService_app.WAKE_FOREGROUND_SERVICE") {
            return
        }

        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val activeTripId = prefs.getString(PREF_ACTIVE_ID, null)
            val tripStartUtc = prefs.getString(PREF_START_UTC, null)
            val distanceMeters = prefs.getFloat(PREF_DISTANCE, 0.0f).toDouble()
            val serviceRunning = prefs.getBoolean(PREF_SERVICE_RUNNING, false)

            if (activeTripId == null) {
                Log.d(TAG, "onReceive: No active trip, alarm is stale")
                return
            }

            if (serviceRunning) {
                Log.d(TAG, "onReceive: Service is running, health check passed")
                // Reschedule the alarm for next interval
                AlarmHelper.getInstance(context).scheduleWakeAlarm()
                return
            }

            // Service is NOT running but trip is ACTIVE = restart immediately
            Log.w(TAG, "onReceive: Service dead, trip active! Attempting restart")

            if (tripStartUtc != null) {
                val restartIntent = Intent(context, TripForegroundService::class.java).apply {
                    action = "RESTORE_TRIP_ALARM_WAKE"
                    putExtra("tripId", activeTripId)
                    putExtra("tripStartUtc", tripStartUtc)
                    putExtra("distanceMeters", distanceMeters)
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(restartIntent)
                } else {
                    context.startService(restartIntent)
                }

                Log.d(TAG, "onReceive: Restart command sent")
            }

            // Reschedule the alarm for next interval
            AlarmHelper.getInstance(context).scheduleWakeAlarm()

        } catch (e: Exception) {
            Log.e(TAG, "onReceive: Error in health check", e)
        }
    }
}
