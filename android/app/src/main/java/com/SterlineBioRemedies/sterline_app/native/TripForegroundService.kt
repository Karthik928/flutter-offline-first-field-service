package com.FieldServiceBioRemedies.FieldService_app.native

import android.app.Service
import android.content.Intent
import android.location.Location
import android.os.Binder
import android.os.IBinder
import android.util.Log
import androidx.lifecycle.LifecycleService
import com.FieldServiceBioRemedies.FieldService_app.db.TripDatabase
import com.FieldServiceBioRemedies.FieldService_app.db.entity.LocationSample
import com.FieldServiceBioRemedies.FieldService_app.db.entity.Trip
import kotlinx.coroutines.*
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.max
import android.content.Context
import android.os.Handler
import android.os.Looper
import java.util.concurrent.atomic.AtomicBoolean
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit
import android.os.Build
import androidx.work.WorkManager

/**
 * TripForegroundService is the core location-tracking service for the app.
 *
 * Key responsibilities:
 * 1. Start/stop trip tracking with location updates from TripLocationManager.
 * 2. Persist trip state and telemetry to TripDatabase and SharedPreferences.
 * 3. Emit location snapshots via EventChannel to Flutter.
 * 4. Handle service restoration after process restart, reboot, or system kill.
 * 5. Integrate with WorkManager watchdog and AlarmHelper for resilience.
 *
 * Starting a trip:
 * - Calls startTrip() which persists the trip in SharedPreferences and DB.
 * - Calls startForeground() exactly once to publish the foreground notification.
 * - Starts location updates via TripLocationManager.
 * - Schedules WorkManager watchdog and AlarmHelper for recovery.
 *
 * Stopping a trip:
 * - Calls stopTrip() which persists final state and cancels foreground.
 * - Cleans up resources and stops self.
 *
 * Restoration:
 * - BootReceiver detects boot and checks SharedPreferences for active trip.
 * - If found, schedules TripRestoreWorker to restart the service.
 * - ForegroundWatchdogWorker periodically checks if service is alive.
 * - AlarmHelper + WakeReceiver provides Doze-aware wake-up.
 * - Service respects user force-stop (app-level, OS prevents intents).
 */
class TripForegroundService : LifecycleService() {
    private val binder = LocalBinder()
    private var serviceJob: Job? = null
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private lateinit var locationManager: TripLocationManager
    private lateinit var notificationHelper: NotificationHelper
    private lateinit var database: TripDatabase

    private var activeTripId: String? = null
    private var tripStartUtc: String? = null
    private var lastLat: Double? = null
    private var lastLng: Double? = null
    private var lastFixTs: String? = null
    private var lastLocationTimestamp: Long = 0L
    private var distanceMeters: Double = 0.0
    private var lastNotificationUpdate: Long = 0
    private var lastNotificationDistance: Double = 0.0
    private var locationRestartInProgress = AtomicBoolean(false)

    private val maxPlausibleSpeedMps = 60.0 // ~216 km/h
    private val maxAccuracyM = 40.0

    private var eventChannelCallback: ((Map<String, Any?>) -> Unit)? = null

    // Buffer the last emitted snapshot so late EventChannel subscribers get immediate state
    // (fixes Minor: EventChannel replay for cold-start restore)
    private var lastSnapshot: Map<String, Any?>? = null

    private lateinit var prefs: android.content.SharedPreferences

    private val stopping = AtomicBoolean(false)
    private val foregroundStarted = AtomicBoolean(false)
    private val tripStarting = AtomicBoolean(false)

    private val LOCAL_NOTIFICATION_ID = NotificationHelper.NOTIFICATION_ID

    private val mainHandler = Handler(Looper.getMainLooper())

    private var trackingEnabled = false
    private var tripActive = false
    private var lastTrackingApiCall: Long = 0
    private var lastSkippedEmitTs: Long = 0

    private var authToken: String? = null
    private var trackingApiBaseUrl: String? = null

    private val TRACKING_API_INTERVAL_MS = 60_000L

    private var trackingTickerJob: Job? = null
    private var heartbeatJob: Job? = null

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .writeTimeout(10, TimeUnit.SECONDS)
        .build()

    private val isoFormatter = SimpleDateFormat(
        "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
        Locale.US
    ).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

    private lateinit var alarmHelper: AlarmHelper

    inner class LocalBinder : Binder() {
        fun getService(): TripForegroundService = this@TripForegroundService
    }

    fun setAuthToken(token: String?) {
        authToken = token
        if (!token.isNullOrBlank()) {
            Log.d(TAG, "Tracking API auth token received")
        } else {
            Log.d(TAG, "Tracking API auth token cleared")
        }
    }

    fun setTrackingApiBaseUrl(url: String?) {
        trackingApiBaseUrl = url?.trimEnd('/')
        Log.d(TAG, "Tracking API base URL set: $trackingApiBaseUrl")
    }

    /**
     * Register the EventChannel callback.
     * Immediately replays the last known snapshot to the new subscriber so that
     * a Flutter widget subscribing after trip start (e.g. cold-start restore) gets
     * the current state without waiting for the next location update.
     * (Fixes Minor: EventChannel snapshot buffer for late subscribers)
     */
    fun setEventChannelCallback(callback: (Map<String, Any?>) -> Unit) {
        eventChannelCallback = callback
        // Replay last snapshot immediately for late-joining listeners
        val snapshot = lastSnapshot
        if (snapshot != null) {
            mainHandler.post { callback(snapshot) }
            Log.d(TAG, "setEventChannelCallback: replayed last snapshot to new subscriber")
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "TripForegroundService created")
        try {
            locationManager = TripLocationManager(this)
            notificationHelper = NotificationHelper(this)
            database = TripDatabase.getDatabase(this)
            alarmHelper = AlarmHelper(this)

            prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            trackingEnabled = prefs.getBoolean(PREF_TRACKING_ENABLED, false)
            Log.d(TAG, "Service onCreate - trackingEnabled restored=$trackingEnabled")
            if (trackingEnabled) {
                startTrackingTicker()
            }

            ForegroundWatchdogWorker.schedulePeriodicWatchdog(this)
        } catch (e: Exception) {
            Log.e(TAG, "Error in onCreate", e)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand: action=${intent?.action}")

        intent?.getStringExtra("authToken")?.let { token ->
            if (!token.isNullOrBlank()) {
                authToken = token
                Log.d(TAG, "onStartCommand: auth token received via intent")
            }
        }

        // AFTER — always re-confirm foreground on subsequent onStartCommand calls
if (foregroundStarted.compareAndSet(false, true)) {
    try {
        val notification = notificationHelper.buildNotification(
            activeTripId ?: "initializing",
            0,
            distanceMeters
        )
        startForeground(LOCAL_NOTIFICATION_ID, notification)
        Log.d(TAG, "startForeground: initial call")
    } catch (e: Exception) {
        Log.e(TAG, "Failed to start foreground service", e)
    }
} else {
    // Service already foreground — refresh notification to reassure OEM process managers
    try {
        notificationHelper.updateNotification(
            activeTripId ?: "active",
            0,
            distanceMeters
        )
        Log.d(TAG, "startForeground: already foreground — notification refreshed")
    } catch (e: Exception) {
        Log.e(TAG, "startForeground: notification refresh failed", e)
    }
}

        if (intent?.action == NotificationHelper.ACTION_STOP) {
            Log.d(TAG, "Notification STOP action received")
            stopTrip()
            return START_STICKY
        }

        val tripId = intent?.getStringExtra("tripId")
        val tripStartUtc = intent?.getStringExtra("tripStartUtc")
        val distanceMeters = intent?.getDoubleExtra("distanceMeters", 0.0) ?: 0.0

        val restoreActions = setOf(
            "RESTORE_TRIP_AFTER_BOOT",
            "RESTORE_TRIP_WATCHDOG",
            "RESTORE_TRIP_ALARM_WAKE"
        )

        if (tripId != null && tripStartUtc != null && intent?.action in restoreActions) {
            Log.d(TAG, "Restoring trip from ${intent?.action}: id=$tripId")
            serviceScope.launch {
                try {
                    startTrip(tripId, tripStartUtc, distanceMeters)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to restore trip", e)
                }
            }
            return START_STICKY
        }

        serviceScope.launch {
            try {
                val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val storedTripId = prefs.getString(PREF_ACTIVE_ID, null)
                if (storedTripId != null && activeTripId == null) {
                    val storedStartUtc = prefs.getString(PREF_START_UTC, null)
                    val storedDistance = prefs.getFloat(PREF_DISTANCE, 0.0f).toDouble()
                    if (storedStartUtc != null) {
                        Log.d(TAG, "Restoring active trip from prefs id=$storedTripId")
                        startTrip(storedTripId, storedStartUtc, storedDistance)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to restore persisted trip", e)
            }
        }

        return START_STICKY
    }

    /**
     * Called when the user swipes the app away from recents.
     *
     * FIX Major #4: If a trip is currently active, we keep the foreground service
     * alive so tracking continues uninterrupted. The watchdog and alarm are still
     * scheduled as a secondary recovery net.
     *
     * If no trip is active we clean up the idle service as before.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.d(TAG, "onTaskRemoved: activeTripId=$activeTripId")

        // Always persist latest telemetry regardless of trip state
        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit()
                .putFloat(PREF_DISTANCE, distanceMeters.toFloat())
                .putString(PREF_LAST_SAMPLE_TS, lastFixTs ?: "")
                .apply()
        } catch (e: Exception) {
            Log.e(TAG, "onTaskRemoved: Failed to save telemetry", e)
        }

        if (activeTripId != null) {
            // Active trip in progress — keep the foreground service alive so location
            // tracking continues. Watchdog + alarm provide a secondary recovery net.
            Log.d(TAG, "onTaskRemoved: Active trip in progress — keeping service alive (not stopping)")
            return
        }

        // No active trip — clean up the idle service
        Log.d(TAG, "onTaskRemoved: No active trip — stopping idle service")
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (e: Exception) {
            Log.e(TAG, "onTaskRemoved: stopForeground failed", e)
        }
        stopSelf()
    }

    override fun onBind(intent: Intent): IBinder {
        super.onBind(intent)
        return binder
    }

    fun startTrip(
        tripId: String,
        tripStartUtc: String,
        initialDistanceMeters: Double?
    ): Boolean {
        if (!tripStarting.compareAndSet(false, true)) {
            if (activeTripId == tripId) {
                Log.d(TAG, "startTrip: already starting/active for tripId=$tripId")
                return true
            }
            var waited = 0
            while (tripStarting.get() && waited < 2000) {
                try { Thread.sleep(50) } catch (_: InterruptedException) {}
                waited += 50
            }
            if (activeTripId == tripId) {
                Log.d(TAG, "startTrip: start completed by other thread for tripId=$tripId")
                return true
            }
        }

        try {
            if (activeTripId != null && activeTripId != tripId) {
                Log.w(TAG, "startTrip: different trip active ($activeTripId) — stopping before starting $tripId")
                try { stopTrip() } catch (e: Exception) {
                    Log.e(TAG, "startTrip: failed to stop existing trip", e)
                }
                var waited = 0
                while (activeTripId != null && waited < 2000) {
                    try { Thread.sleep(50) } catch (_: InterruptedException) {}
                    waited += 50
                }
            }

            if (activeTripId != null && activeTripId == tripId) {
                Log.d(TAG, "startTrip: already active for tripId=$tripId")
                return true
            }

            activeTripId = tripId
            this.tripStartUtc = tripStartUtc
            distanceMeters = initialDistanceMeters ?: 0.0
            tripActive = true       // FIX Critical #1a: enable location processing immediately
            trackingEnabled = true  // FIX Critical #1a: enable tracking API immediately
            lastNotificationUpdate = 0
            lastNotificationDistance = distanceMeters

            // Persist active marker
            try {
                val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit()
                    .putString(PREF_ACTIVE_ID, tripId)
                    .putString(PREF_START_UTC, tripStartUtc)
                    .putFloat(PREF_DISTANCE, distanceMeters.toFloat())
                    .putBoolean(PREF_SERVICE_RUNNING, true)
                    .apply()
                ForegroundWatchdogWorker.markServiceRunning(this, true)
                Log.d(TAG, "startTrip: Persisted active trip marker")
            } catch (e: Exception) {
                Log.e(TAG, "startTrip: Failed to persist active trip marker", e)
            }

            // Schedule alarm and start heartbeat
            try {
                alarmHelper.scheduleWakeAlarm()

                // Write first heartbeat immediately
                try {
                    val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    prefs.edit().putLong(PREF_LAST_HEARTBEAT, System.currentTimeMillis()).apply()
                } catch (e: Exception) {
                    Log.e(TAG, "startTrip: Failed to write initial heartbeat", e)
                }

                heartbeatJob?.cancel()
                heartbeatJob = serviceScope.launch(Dispatchers.IO) {
                    while (activeTripId != null) {
                        kotlinx.coroutines.delay(HEARTBEAT_INTERVAL_MS)
                        try {
                            if (activeTripId != null) {
                                val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                                prefs.edit().putLong(PREF_LAST_HEARTBEAT, System.currentTimeMillis()).apply()
                                Log.d(TAG, "Heartbeat written at ${System.currentTimeMillis()}")
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Heartbeat write failed", e)
                        }
                    }
                }

                Log.d(TAG, "startTrip: Wake alarm scheduled and heartbeat started")
            } catch (e: Exception) {
                Log.e(TAG, "startTrip: Failed to schedule alarm/heartbeat", e)
            }

            // Build notification and start foreground exactly once
            val notification = notificationHelper.buildNotification(tripId, 0, distanceMeters)
            if (foregroundStarted.compareAndSet(false, true)) {
                startForeground(LOCAL_NOTIFICATION_ID, notification)
                Log.d(TAG, "startTrip: startForeground called NOTIFICATION_ID=$LOCAL_NOTIFICATION_ID")
                notificationHelper.removeDuplicateTripNotifications(LOCAL_NOTIFICATION_ID)
            } else {
                if (activeTripId != null) {
                    notificationHelper.updateNotification(activeTripId!!, 0, distanceMeters)
                }
                Log.w(TAG, "startTrip: startForeground skipped — already started for tripId=$activeTripId")
            }

            // Persist initial snapshot and emit
            serviceScope.launch {
                withContext(Dispatchers.IO) { persistSnapshot() }
                emitSnapshot()
            }

            // Start location tracking
            serviceJob = serviceScope.launch {
                try {
                    locationManager.getLocationUpdates().collect { locations ->
                        try { processLocations(locations) } catch (e: Exception) {
                            Log.e(TAG, "Error processing locations", e)
                        }
                    }
                } catch (e: SecurityException) {
                    Log.e(TAG, "Location permission denied", e)
                    emitError("Location permission denied")
                } catch (e: Exception) {
                    Log.e(TAG, "Location updates error", e)
                    emitError("Location updates failed: ${e.message}")
                }
            }

            // Start location watchdog
            lastLocationTimestamp = System.currentTimeMillis()
            serviceScope.launch(Dispatchers.IO) {
                try {
                    while (activeTripId != null) {
                        kotlinx.coroutines.delay(30_000)
                        val now = System.currentTimeMillis()
                        val timeSinceLastLocation = now - lastLocationTimestamp
                        if (timeSinceLastLocation > 30_000) {
                            if (locationRestartInProgress.compareAndSet(false, true)) {
                                try {
                                    Log.w(TAG, "Location watchdog: stream stalled for ${timeSinceLastLocation}ms — restarting")
                                    locationManager.restartLocationUpdates()
                                } finally {
                                    locationRestartInProgress.set(false)
                                }
                            } else {
                                Log.d(TAG, "Location restart already in progress, skipping")
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Location watchdog error: ${e.message}")
                }
            }

            emitSnapshot()
            return true
        } finally {
            tripStarting.set(false)
        }
    }

    private suspend fun processLocations(locations: List<Location>) {
        Log.d(TAG, "Processing location batch: ${locations.size} locations")
        if (!trackingEnabled && !tripActive) return
        if (locations.isEmpty()) return

        // Process oldest-to-newest so distance is accumulated along the actual path.
        // Reverse ordering can backtrack across a batch and double-count movement.
        val sorted = locations.sortedBy { it.time }

        for (location in sorted) {
            val accuracy = location.accuracy
            val isMocked = if (Build.VERSION.SDK_INT >= 31) location.isMock else location.isFromMockProvider

            Log.d(TAG, "Location sample lat=${location.latitude} lng=${location.longitude} accuracy=${accuracy} mocked=${isMocked}")

            if (accuracy > maxAccuracyM) {
                Log.d(TAG, "Rejected: accuracy=${accuracy}m")
                continue
            }

            if (isMocked) {
                Log.w(TAG, "Mocked location detected (not advancing baseline)")
                continue
            }

            val lat = location.latitude
            val lng = location.longitude
            val timestamp = location.time

            // Speed plausibility check
            if (tripActive && lastLat != null && lastLng != null && lastFixTs != null) {
                val distance = FloatArray(1)
                Location.distanceBetween(lastLat!!, lastLng!!, lat, lng, distance)
                val deltaM = distance[0].toDouble()
                val timeDelta = try {
                    val lastTs = isoFormatter.parse(lastFixTs!!)?.time ?: 0L
                    max(1, timestamp - lastTs) / 1000.0
                } catch (e: Exception) { 1.0 }
                if (timeDelta > 0) {
                    val impliedSpeed = deltaM / timeDelta
                    if (impliedSpeed > maxPlausibleSpeedMps) {
                        Log.d(TAG, "Rejected: implied speed=${impliedSpeed}m/s")
                        continue
                    }
                }
            }

            Log.d(TAG, "Accepted location: lat=$lat lng=$lng accuracy=$accuracy")

            // Accumulate distance
            if (lastLat != null && lastLng != null) {
                val distance = FloatArray(1)
                Location.distanceBetween(lastLat!!, lastLng!!, lat, lng, distance)
                lastLocationTimestamp = System.currentTimeMillis()
                if (distance[0] > 0.2 && !distance[0].isNaN() && distance[0] >= 0) {
                    distanceMeters += distance[0]
                    Log.d(TAG, "Distance updated: +${distance[0]}m (total: ${distanceMeters}m)")
                }
            } else {
                lastLocationTimestamp = System.currentTimeMillis()
            }

            lastLat = lat
            lastLng = lng
            lastFixTs = isoFormatter.format(Date(timestamp))

            // Persist location sample
            serviceScope.launch(Dispatchers.IO) {
                try {
                    if (activeTripId != null) {
                        val sample = LocationSample(
                            tripId = activeTripId!!,
                            ts = lastFixTs!!,
                            lat = lat,
                            lng = lng,
                            accuracyM = accuracy.toDouble(),
                            speedMps = if (location.hasSpeed()) location.speed.toDouble() else null
                        )
                        database.tripDao().insertLocationSample(sample)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to persist location sample", e)
                }
            }

            withContext(Dispatchers.IO) { persistSnapshot() }

            val now = System.currentTimeMillis()

            // Tracking API
            if (trackingEnabled) {
                val elapsed = now - lastTrackingApiCall
                if (lastLat != null && lastLng != null) {
                    if (elapsed >= TRACKING_API_INTERVAL_MS) {
                        Log.d(TAG, "Tracking API trigger after ${elapsed}ms")
                        lastTrackingApiCall = now
                        lastSkippedEmitTs = 0
                        sendTrackingAPI(lastLat!!, lastLng!!)
                    } else {
                        if (lastSkippedEmitTs == 0L) {
                            lastSkippedEmitTs = now
                            emitApiStatus("skipped")
                        }
                    }
                } else {
                    if (lastSkippedEmitTs == 0L) {
                        lastSkippedEmitTs = now
                        emitApiStatus("skipped")
                    }
                }
            }

            // Update notification (throttled)
            val distanceDelta = distanceMeters - lastNotificationDistance
            val elapsedSinceUpdate = now - lastNotificationUpdate
            val shouldUpdate = (elapsedSinceUpdate >= 15000 && distanceDelta > 0.0) || distanceDelta >= 25.0
            if (shouldUpdate) {
                updateNotification()
                lastNotificationUpdate = now
                lastNotificationDistance = distanceMeters
            }

            // Persist quick telemetry
            try {
                val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit()
                    .putFloat(PREF_DISTANCE, distanceMeters.toFloat())
                    .putString(PREF_LAST_SAMPLE_TS, lastFixTs ?: "")
                    .apply()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to save telemetry prefs", e)
            }

            emitSnapshot()
        }
    }

    private fun sendTrackingAPI(lat: Double, lng: Double) {
        serviceScope.launch(Dispatchers.IO) {
            try {
                val token = authToken
                if (token.isNullOrBlank()) {
                    Log.w(TAG, "Tracking API skipped: missing auth token")
                    emitApiStatus("auth_missing")
                    return@launch
                }

                val base = trackingApiBaseUrl
                    ?.takeIf { it.isNotBlank() }
                    ?: run {
                        Log.w(TAG, "trackingApiBaseUrl not set — falling back to dev IP")
                        "YOUR_API_BASE_URL"
                    }
                val url = "$base/api/employee/update-location"

                val body = """{"latitude": $lat,"longitude": $lng}"""
                val request = okhttp3.Request.Builder()
                    .url(url)
                    .post(body.toRequestBody("application/json".toMediaType()))
                    .addHeader("Authorization", "Bearer $token")
                    .addHeader("Content-Type", "application/json")
                    .build()

                val response = httpClient.newCall(request).execute()
                if (response.isSuccessful) {
                    Log.d(TAG, "Tracking API success code=${response.code}")
                    emitApiStatus("success")
                } else {
                    Log.e(TAG, "Tracking API failed code=${response.code}")
                    emitApiStatus("failed")
                }
                response.close()
            } catch (e: Exception) {
                Log.e(TAG, "Tracking API exception", e)
                emitApiStatus("failed")
            }
        }
    }

    private fun getAuthToken(): String? {
        return try {
            val prefs = getSharedPreferences("FlutterSecureStorage", Context.MODE_PRIVATE)
            val token = prefs.getString("auth_token", null)
            if (token.isNullOrEmpty()) {
                Log.w(TAG, "Auth token not found in secure storage")
                null
            } else {
                Log.d(TAG, "Auth token retrieved successfully")
                token
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read auth token", e)
            null
        }
    }

    private fun emitApiStatus(status: String) {
        mainHandler.post {
            eventChannelCallback?.invoke(mapOf("type" to "tracking_api", "status" to status))
        }
    }

    private fun ensureLocationStreamRunning() {
        if (serviceJob?.isActive == true) {
            Log.d(TAG, "Location stream already running")
            return
        }
        Log.d(TAG, "Starting location stream")
        serviceJob = serviceScope.launch {
            try {
                locationManager.getLocationUpdates().collect { locations ->
                    processLocations(locations)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Location stream error", e)
            }
        }
    }

    fun startPunchTracking() {
        Log.d(TAG, "startPunchTracking: CALLED")
        trackingEnabled = true
        if (::prefs.isInitialized) {
            prefs.edit().putBoolean(PREF_TRACKING_ENABLED, true).apply()
        }
        ensureLocationStreamRunning()
        startTrackingTicker()
    }

    private fun startTrackingTicker() {
        trackingTickerJob?.cancel()
        trackingTickerJob = serviceScope.launch(Dispatchers.IO) {
            while (isActive) {
                delay(TRACKING_API_INTERVAL_MS)
                if (!trackingEnabled) continue
                val lat = lastLat
                val lng = lastLng
                if (lat != null && lng != null) {
                    val now = System.currentTimeMillis()
                    val elapsed = now - lastTrackingApiCall
                    if (elapsed >= TRACKING_API_INTERVAL_MS) {
                        Log.d(TAG, "Ticker firing tracking API")
                        lastTrackingApiCall = now
                        lastSkippedEmitTs = 0
                        sendTrackingAPI(lat, lng)
                    }
                }
            }
        }
    }

    fun stopPunchTracking() {
        Log.d(TAG, "stopPunchTracking: CALLED")
        trackingEnabled = false
        if (::prefs.isInitialized) {
            prefs.edit().putBoolean(PREF_TRACKING_ENABLED, false).apply()
        }
        trackingTickerJob?.cancel()
        trackingTickerJob = null
        if (!tripActive) {
            serviceJob?.cancel()
            serviceJob = null
        }
    }

    fun startTripMode() {
        Log.d(TAG, "startTripMode: trip mode activated")
        tripActive = true
        ensureLocationStreamRunning()
    }

    fun stopTripMode() {
        Log.d(TAG, "stopTripMode: trip mode deactivated")
        tripActive = false
    }

    private suspend fun persistSnapshot() {
        if (activeTripId == null || tripStartUtc == null) return
        try {
            val trip = Trip(
                tripId = activeTripId!!,
                tripStartUtc = tripStartUtc!!,
                distanceM = distanceMeters,
                lastLat = lastLat ?: 0.0,
                lastLng = lastLng ?: 0.0,
                lastFixTs = lastFixTs ?: tripStartUtc!!
            )
            database.tripDao().upsertTrip(trip)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to persist snapshot", e)
        }
    }

    private fun updateNotification() {
        if (activeTripId == null || tripStartUtc == null) return
        val elapsedSeconds = try {
            val start = isoFormatter.parse(tripStartUtc!!)?.time ?: 0L
            (System.currentTimeMillis() - start) / 1000
        } catch (e: Exception) { 0L }
        notificationHelper.updateNotification(activeTripId!!, elapsedSeconds, distanceMeters)
    }

    fun stopTrip(): Boolean {
        if (activeTripId == null) {
            Log.w(TAG, "No active trip to stop")
            return false
        }

        if (!stopping.compareAndSet(false, true)) {
            Log.w(TAG, "stopTrip: already in progress for tripId=$activeTripId")
            return false
        }

        Log.d(TAG, "stopTrip: Starting stop sequence for tripId=$activeTripId")

        serviceJob?.cancel()
        serviceJob = null

        // Clear restart markers immediately so an explicit user stop cannot be
        // resurrected by the watchdog/boot/alarm paths if cleanup is interrupted.
        clearPersistedActiveTripMarkers()

        // Cancel heartbeat and clear timestamp
        heartbeatJob?.cancel()
        heartbeatJob = null
        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().remove(PREF_LAST_HEARTBEAT).apply()
            Log.d(TAG, "stopTrip: heartbeat cleared")
        } catch (e: Exception) {
            Log.e(TAG, "stopTrip: Failed to clear heartbeat", e)
        }

        serviceScope.launch {
            try {
                withContext(Dispatchers.IO) { persistSnapshot() }

                val finalSnapshot = getActiveTripSnapshot()
                if (finalSnapshot != null) {
                    emitSnapshot()
                    Log.d(TAG, "stopTrip: Final snapshot emitted distanceMeters=${finalSnapshot["distanceMeters"]}")
                } else {
                    Log.w(TAG, "stopTrip: No final snapshot to emit")
                }

                // Clear state AFTER persisting and emitting
                activeTripId = null
                tripStartUtc = null
                lastLat = null
                lastLng = null
                lastFixTs = null
                distanceMeters = 0.0
                tripActive = false      // FIX Critical #1b
                trackingEnabled = false // FIX Critical #1b
                lastSnapshot = null     // clear replay buffer — trip is over

                // Clear persisted markers
                clearPersistedActiveTripMarkers()

                try {
                    alarmHelper.cancelWakeAlarm()
                    Log.d(TAG, "stopTrip: Wake alarm cancelled")
                } catch (e: Exception) {
                    Log.e(TAG, "stopTrip: Failed to cancel wake alarm", e)
                }

                try { notificationHelper.cancelNotification() } catch (e: Exception) {
                    Log.e(TAG, "stopTrip: Error canceling notification", e)
                }

                try { stopForeground(STOP_FOREGROUND_REMOVE) } catch (e: Exception) {
                    Log.e(TAG, "stopTrip: Error stopping foreground", e)
                }

                try {
                    foregroundStarted.set(false)
                    Log.d(TAG, "stopTrip: foregroundStarted reset to false")
                } catch (e: Exception) {
                    Log.e(TAG, "stopTrip: Error resetting foregroundStarted", e)
                }

                stopSelf()
                Log.d(TAG, "stopTrip: Service stopped successfully")
            } catch (e: Exception) {
                Log.e(TAG, "stopTrip: Error during stop sequence", e)
                try {
                    notificationHelper.cancelNotification()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    foregroundStarted.set(false)
                    stopSelf()
                } catch (e2: Exception) {
                    Log.e(TAG, "stopTrip: Error in cleanup", e2)
                }
            } finally {
                stopping.set(false)
            }
        }

        return true
    }

    fun getActiveTripSnapshot(): Map<String, Any?>? {
        if (activeTripId == null || tripStartUtc == null) return null
        return mapOf(
            "tripId" to activeTripId,
            "tripStartUtc" to tripStartUtc,
            "distanceMeters" to distanceMeters,
            "lastLat" to (lastLat ?: 0.0),
            "lastLng" to (lastLng ?: 0.0),
            "lastFixTs" to (lastFixTs ?: tripStartUtc)
        )
    }

    fun isServiceRunning(): Boolean = activeTripId != null

    /**
     * Emit snapshot via EventChannel and cache it for late subscribers.
     */
    private fun emitSnapshot() {
        val snapshot = getActiveTripSnapshot()
        if (snapshot != null) {
            lastSnapshot = snapshot // buffer for replay in setEventChannelCallback()
            mainHandler.post { eventChannelCallback?.invoke(snapshot) }
        }
    }

    private fun emitError(message: String) {
        eventChannelCallback?.invoke(mapOf("error" to message))
    }

    private fun clearPersistedActiveTripMarkers() {
        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit()
                .remove(PREF_ACTIVE_ID)
                .remove(PREF_START_UTC)
                .remove(PREF_DISTANCE)
                .putBoolean(PREF_SERVICE_RUNNING, false)
                .apply()
            ForegroundWatchdogWorker.markServiceRunning(this, false)
            Log.d(TAG, "clearPersistedActiveTripMarkers: active trip markers cleared")
        } catch (e: Exception) {
            Log.e(TAG, "clearPersistedActiveTripMarkers: Failed", e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "onDestroy: Service being destroyed")
        try {
            serviceJob?.cancel()
            serviceJob = null
            heartbeatJob?.cancel()
            heartbeatJob = null
            try { alarmHelper.cancelWakeAlarm() } catch (e: Exception) {
                Log.e(TAG, "onDestroy: Error canceling wake alarm", e)
            }
            try { ForegroundWatchdogWorker.markServiceRunning(this, false) } catch (e: Exception) {
                Log.e(TAG, "onDestroy: Error marking service as stopped", e)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in onDestroy", e)
        } finally {
            serviceScope.cancel()
            try { notificationHelper.cancelNotification() } catch (e: Exception) {
                Log.e(TAG, "Error canceling notification", e)
            }
            try { foregroundStarted.set(false) } catch (e: Exception) {
                Log.e(TAG, "onDestroy: Error resetting foregroundStarted", e)
            }
        }
    }

    companion object {
        private const val TAG = "TripForegroundService"

        private const val PREFS_NAME = "trip_prefs"
        private const val PREF_ACTIVE_ID = "activeTripId"
        private const val PREF_START_UTC = "tripStartUtc"
        private const val PREF_DISTANCE = "distanceMeters"
        private const val PREF_LAST_SAMPLE_TS = "lastSampleTs"
        private const val PREF_SERVICE_RUNNING = "serviceRunning"
        private const val PREF_TRACKING_ENABLED = "trackingEnabled"
        private const val PREF_LAST_HEARTBEAT = "serviceHeartbeatTs"
        private const val HEARTBEAT_INTERVAL_MS = 60_000L

        fun stopService(context: Context) {
            val intent = Intent(context, TripForegroundService::class.java)
            context.stopService(intent)
        }
    }

    fun logGuardState() {
        try {
            Log.d(TAG, "Guards: foregroundStarted=${foregroundStarted.get()} tripStarting=${tripStarting.get()} stopping=${stopping.get()} activeTripId=$activeTripId tripActive=$tripActive trackingEnabled=$trackingEnabled")
        } catch (e: Exception) {
            Log.e(TAG, "logGuardState: failed", e)
        }
    }
}
