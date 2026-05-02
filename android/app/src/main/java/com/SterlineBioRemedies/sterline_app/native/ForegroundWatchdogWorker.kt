package com.FieldServiceBioRemedies.FieldService_app.native

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.work.*
import java.util.concurrent.TimeUnit

/**
 * ForegroundWatchdogWorker is a periodic WorkManager task (runs every 15 minutes) that:
 * 1. Checks if TripForegroundService is still running for an active trip.
 * 2. If the service has died but a trip is active (persisted in prefs), attempts to restart it safely.
 * 3. Also monitors if device is in Doze mode and reschedules if needed.
 *
 * This provides an extra layer of resilience against:
 * - System killing the service in background
 * - App/service crashes
 * - OEM aggressive background restrictions
 *
 * The watchdog respects user force-stop: if the user has force-stopped the app,
 * the receiver/worker will NOT run at all (Android OS level blocking).
 *
 * @author FieldServiceBioRemedies Team
 */
class ForegroundWatchdogWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    companion object {
        private const val TAG = "ForegroundWatchdogWorker"
        private const val PREFS_NAME = "trip_prefs"
        private const val PREF_ACTIVE_ID = "activeTripId"
        private const val PREF_START_UTC = "tripStartUtc"
        private const val PREF_DISTANCE = "distanceMeters"
        private const val PREF_SERVICE_RUNNING = "serviceRunning"

        // Watchdog configuration (tunable)
        private const val WATCHDOG_INTERVAL_MINUTES = 15L
        private const val WATCHDOG_RESTART_DELAY_MILLIS = 1000L

        private const val PREF_LAST_HEARTBEAT = "serviceHeartbeatTs"
private const val HEARTBEAT_EXPIRY_MS = 3 * 60_000L  // 3 minutes — covers 2 missed beats

        /**
         * Schedule a periodic watchdog worker that runs every [WATCHDOG_INTERVAL_MINUTES] minutes.
         * Uses ExistingPeriodicWorkPolicy.KEEP to avoid duplicate scheduling.
         */
        fun schedulePeriodicWatchdog(context: Context) {
            try {
                val watchdogRequest = PeriodicWorkRequestBuilder<ForegroundWatchdogWorker>(
                    WATCHDOG_INTERVAL_MINUTES,
                    TimeUnit.MINUTES
                ).apply {
                    // Run even in low-battery/Doze mode where possible
                    setBackoffCriteria(
                        BackoffPolicy.EXPONENTIAL,
                        WorkRequest.MIN_BACKOFF_MILLIS,
                        TimeUnit.MILLISECONDS
                    )
                    // Note: setExpedited and OutOfQuotaPolicy may not be available in all worker library versions
                    // For maximum compatibility, we rely on WorkManager's default scheduling and backoff strategy
                    addTag("trip_foreground_watchdog")
                }.build()

                WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                    "trip_foreground_watchdog",
                    ExistingPeriodicWorkPolicy.KEEP, // Don't reschedule if already scheduled
                    watchdogRequest
                )

                Log.d(TAG, "schedulePeriodicWatchdog: Watchdog scheduled to run every $WATCHDOG_INTERVAL_MINUTES minutes")
            } catch (e: Exception) {
                Log.e(TAG, "schedulePeriodicWatchdog: Failed to schedule", e)
            }
        }

        /**
         * Check if the service is currently running by examining a persisted flag.
         * This is a lightweight check that doesn't require introspection of the ActivityManager.
         */
        fun isServiceRunning(context: Context): Boolean {
            return try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.getBoolean(PREF_SERVICE_RUNNING, false)
            } catch (e: Exception) {
                Log.e(TAG, "isServiceRunning: Error checking service state", e)
                false
            }
        }

        /**
         * Mark that the service is running (called by TripForegroundService on startTrip).
         */
        fun markServiceRunning(context: Context, running: Boolean) {
            try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit().putBoolean(PREF_SERVICE_RUNNING, running).apply()
                Log.d(TAG, "markServiceRunning: service=$running")
            } catch (e: Exception) {
                Log.e(TAG, "markServiceRunning: Error", e)
            }
        }
    }

    override suspend fun doWork(): Result {
        Log.d(TAG, "doWork: Watchdog periodic check running")

        return try {
            val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val activeTripId = prefs.getString(PREF_ACTIVE_ID, null)
            val tripStartUtc = prefs.getString(PREF_START_UTC, null)
            val distanceMeters = prefs.getFloat(PREF_DISTANCE, 0.0f).toDouble()

            Log.d(TAG, "doWork: Checking trip state: activeTripId=$activeTripId")

            if (activeTripId == null) {
                // No active trip, nothing to do
                Log.d(TAG, "doWork: No active trip, watchdog idle")
                return Result.success()
            }

            // AFTER — heartbeat timestamp replaces the unreliable bool
val lastHeartbeat = prefs.getLong(PREF_LAST_HEARTBEAT, 0L)
val now = System.currentTimeMillis()
val heartbeatExpired = lastHeartbeat == 0L || (now - lastHeartbeat > HEARTBEAT_EXPIRY_MS)

Log.d(TAG, "doWork: lastHeartbeat=$lastHeartbeat ageMs=${now - lastHeartbeat} expired=$heartbeatExpired")

if (heartbeatExpired && tripStartUtc != null) {
    // No heartbeat for 3+ minutes but trip is active → service crashed or was killed
    Log.w(TAG, "doWork: Heartbeat expired for trip=$activeTripId (age=${now - lastHeartbeat}ms). Restarting service.")

    val intent = Intent(applicationContext, TripForegroundService::class.java).apply {
        action = "RESTORE_TRIP_WATCHDOG"
        putExtra("tripId", activeTripId)
        putExtra("tripStartUtc", tripStartUtc)
        putExtra("distanceMeters", distanceMeters)
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        applicationContext.startForegroundService(intent)
    } else {
        applicationContext.startService(intent)
    }

    Log.d(TAG, "doWork: Restart command sent to TripForegroundService")

    try { Thread.sleep(WATCHDOG_RESTART_DELAY_MILLIS) } catch (e: InterruptedException) { }

    Result.success()
} else if (!heartbeatExpired) {
    Log.d(TAG, "doWork: Heartbeat fresh for trip=$activeTripId, watchdog satisfied")
    Result.success()
} else {
    Log.d(TAG, "doWork: No active trip, watchdog idle")
    Result.success()
}
        } catch (e: Exception) {
            Log.e(TAG, "doWork: Error in watchdog check", e)
            // Retry on next scheduled interval
            Result.retry()
        }
    }
}
