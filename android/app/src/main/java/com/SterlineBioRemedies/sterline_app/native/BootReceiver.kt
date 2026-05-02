package com.FieldServiceBioRemedies.FieldService_app.native

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.FieldServiceBioRemedies.FieldService_app.db.TripDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * BootReceiver listens for BOOT_COMPLETED and LOCKED_BOOT_COMPLETED intents.
 *
 * When the device boots, it:
 * 1. Checks SharedPreferences for a persisted active trip (activeTripId, tripStartUtc, distanceMeters).
 * 2. If found, schedules a one-time WorkManager task to restore the trip after a brief delay,
 *    allowing the system to fully boot and services to be available.
 * 3. Also schedules the periodic ForegroundWatchdogWorker to monitor the service.
 *
 * IMPORTANT: User force-stop prevents automatic restart. Android will NOT deliver BOOT_COMPLETED
 * or any intents to an app that has been force-stopped. This is a fundamental Android limitation.
 * The app must be manually reopened by the user after a force-stop.
 *
 * @author FieldServiceBioRemedies Team
 */
class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootReceiver"
        private const val PREFS_NAME = "trip_prefs"
        private const val PREF_ACTIVE_ID = "activeTripId"
        private const val PREF_START_UTC = "tripStartUtc"
        private const val PREF_DISTANCE = "distanceMeters"
    }

    override fun onReceive(context: Context, intent: Intent) {
        // Handle BOOT_COMPLETED and LOCKED_BOOT_COMPLETED
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == "android.intent.action.LOCKED_BOOT_COMPLETED") {
            Log.d(TAG, "onReceive: ${intent.action}")

            // NOTE: At this point, the device may still be locked (if BOOT_COMPLETED fires early).
            // We use WorkManager to delay restoration and let the system stabilize.

            checkAndRestoreActiveTrip(context)
        } else {
            Log.w(TAG, "onReceive: unhandled action=${intent.action}")
        }
    }

    private fun checkAndRestoreActiveTrip(context: Context) {
        // Use a background scope to avoid blocking the receiver
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

        scope.launch {
            try {
                // Read persisted active trip marker
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val activeTripId = prefs.getString(PREF_ACTIVE_ID, null)
                val tripStartUtc = prefs.getString(PREF_START_UTC, null)
                val distanceMeters = prefs.getFloat(PREF_DISTANCE, 0.0f).toDouble()

                if (activeTripId != null && tripStartUtc != null) {
                    Log.d(TAG, "checkAndRestoreActiveTrip: Found active trip=$activeTripId. Scheduling one-time restore task...")

                    // Schedule a one-time WorkManager task to restore the trip after boot.
                    // This allows the system to fully stabilize before we attempt to start the service.
                    val restoreWorkRequest = OneTimeWorkRequestBuilder<TripRestoreWorker>()
                        .addTag("trip_restore_boot")
                        .setInitialDelay(10, java.util.concurrent.TimeUnit.SECONDS) // Wait 10s for system to stabilize
                        .build()

                    WorkManager.getInstance(context).enqueueUniqueWork(
                        "trip_restore_boot",
                        androidx.work.ExistingWorkPolicy.KEEP,
                        restoreWorkRequest
                    )

                    Log.d(TAG, "checkAndRestoreActiveTrip: One-time restore task scheduled.")
                } else {
                    Log.d(TAG, "checkAndRestoreActiveTrip: No active trip persisted. Boot complete, no action needed.")
                }

                // Also schedule the periodic foreground watchdog to ensure the service stays alive
                ForegroundWatchdogWorker.schedulePeriodicWatchdog(context)

            } catch (e: Exception) {
                Log.e(TAG, "checkAndRestoreActiveTrip: Error", e)
            }
        }
    }
}

/**
 * TripRestoreWorker is a one-time WorkManager task that runs after boot.
 * It checks if an active trip was persisted and restarts the TripForegroundService.
 *
 * This worker is enqueued by BootReceiver after the device boots.
 */
class TripRestoreWorker(
    context: android.content.Context,
    params: androidx.work.WorkerParameters
) : androidx.work.CoroutineWorker(context, params) {

    companion object {
        private const val TAG = "TripRestoreWorker"
        private const val PREFS_NAME = "trip_prefs"
        private const val PREF_ACTIVE_ID = "activeTripId"
        private const val PREF_START_UTC = "tripStartUtc"
        private const val PREF_DISTANCE = "distanceMeters"
    }

    override suspend fun doWork(): Result {
        Log.d(TAG, "doWork: TripRestoreWorker running after boot")

        return try {
            val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val activeTripId = prefs.getString(PREF_ACTIVE_ID, null)
            val tripStartUtc = prefs.getString(PREF_START_UTC, null)
            val distanceMeters = prefs.getFloat(PREF_DISTANCE, 0.0f).toDouble()

            if (activeTripId != null && tripStartUtc != null) {
                Log.d(TAG, "doWork: Restoring active trip=$activeTripId after boot")

                // Build intent to start the TripForegroundService with the persisted data
                val intent = Intent(applicationContext, TripForegroundService::class.java).apply {
                    action = "RESTORE_TRIP_AFTER_BOOT"
                    putExtra("tripId", activeTripId)
                    putExtra("tripStartUtc", tripStartUtc)
                    putExtra("distanceMeters", distanceMeters)
                }

                // Use startForegroundService() for Android 8+
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    applicationContext.startForegroundService(intent)
                } else {
                    applicationContext.startService(intent)
                }

                Log.d(TAG, "doWork: TripForegroundService started for trip restoration")
                Result.success()
            } else {
                Log.d(TAG, "doWork: No active trip to restore")
                Result.success()
            }
        } catch (e: Exception) {
            Log.e(TAG, "doWork: Error restoring trip", e)
            // Retry with exponential backoff
            Result.retry()
        }
    }
}
