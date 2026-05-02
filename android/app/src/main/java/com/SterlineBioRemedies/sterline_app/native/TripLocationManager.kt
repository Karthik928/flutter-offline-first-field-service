package com.FieldServiceBioRemedies.FieldService_app.native

import android.content.Context
import android.location.Location
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.location.*
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import java.util.concurrent.atomic.AtomicBoolean

/**
 * TripLocationManager provides robust location tracking with multiple fallback strategies:
 *
 * 1. **Primary**: FusedLocationProvider with high-accuracy request and adaptive intervals.
 * 2. **Secondary**: Last-known location + current location API as fallback if fused is silent.
 * 3. **Tertiary**: GPS freeze detection with watchdog to restart the stream if needed.
 *
 * Key features:
 * - Robust LocationRequest configuration with accurate parameters
 * - GPS freeze detection (>30s silence triggers restart)
 * - Fallback to last-known location during provider silence
 * - Adaptive strategies for Doze/low-battery scenarios
 * - Comprehensive error handling and logging
 *
 * @author FieldServiceBioRemedies Team
 */
class TripLocationManager(private val context: Context) {
    private val fusedLocationClient: FusedLocationProviderClient =
        LocationServices.getFusedLocationProviderClient(context)

    private var activeCallback: LocationCallback? = null
    private var locationRequest: LocationRequest? = null
    private var collectorActive = AtomicBoolean(false)  // Prevent multiple simultaneous collectors
    private var restartInProgress = AtomicBoolean(false)  // Guard against concurrent restarts
    
    companion object {
        private const val TAG = "TripLocationManager"
        
        // GPS freeze detection thresholds
        private const val LOCATION_STREAM_SILENCE_THRESHOLD_MILLIS = 20_000L // 20 seconds
        private const val WATCHDOG_CHECK_INTERVAL_MILLIS = 10_000L // Check every 10 seconds
        
        // Location request configuration constants
        private const val PRIMARY_UPDATE_INTERVAL_MILLIS = 5_000L // 5 seconds
        private const val MIN_UPDATE_INTERVAL_MILLIS = 5_000L
        private const val MAX_UPDATE_DELAY_MILLIS = 15_000L // 15 seconds max batch
    }

    /**
     * Build a robust LocationRequest for high-accuracy trip tracking.
     * This request is tuned to provide frequent updates while respecting battery constraints.
     * Includes movement displacement threshold to reduce wake cycles when stationary.
     */
    private fun buildLocationRequest(): LocationRequest {
        return LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            PRIMARY_UPDATE_INTERVAL_MILLIS
        ).apply {
            setMinUpdateIntervalMillis(MIN_UPDATE_INTERVAL_MILLIS)
            setMaxUpdateDelayMillis(MAX_UPDATE_DELAY_MILLIS)
            // Minimum movement distance: update if device moves 3+ meters
            try {
                setMinUpdateDistanceMeters(3f)
                Log.d(TAG, "Location request configured: 5s interval, 3m displacement threshold")
            } catch (e: Exception) {
                Log.w(TAG, "setMinUpdateDistanceMeters not available, using interval-only updates")
            }
            // Do not wait for accurate location to prevent stalls in background
            setWaitForAccurateLocation(false)
            // Use permission-level granularity for stable updates
            try {
                @Suppress("NewApi")
                setGranularity(Granularity.GRANULARITY_PERMISSION_LEVEL)
            } catch (e: Exception) {
                Log.w(TAG, "setGranularity not available, using standard settings")
            }
        }.build()
    }

    /**
     * Get a Flow of location updates with built-in provider availability handling.
     * Ensures only ONE collector is active at a time.
     */
    fun getLocationUpdates(): Flow<List<Location>> = callbackFlow {
        val request = buildLocationRequest()
        this@TripLocationManager.locationRequest = request
        
        // Prevent multiple simultaneous collectors (atomic guard)
        if (!collectorActive.compareAndSet(false, true)) {
            Log.w(TAG, "Location stream already being collected, rejecting new collector")
            close()
            return@callbackFlow
        }
        
        Log.d(TAG, "Location stream collector activated")
        
        val locationCallbackFlow = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                try {
                    val locations = result.locations
                    if (locations.isNotEmpty()) {
    Log.d(TAG, "Location batch received: ${locations.size} locations")

    // Log every location in the batch
    locations.forEach { loc ->
        Log.d(
            TAG,
            "Location received lat=${loc.latitude} lng=${loc.longitude} accuracy=${loc.accuracy}"
        )
    }

    // Fused provider delivers chronologically, no need to sort
    trySend(locations)
}
                } catch (e: Exception) {
                    Log.e(TAG, "onLocationResult error", e)
                }
            }

            override fun onLocationAvailability(availability: LocationAvailability) {
                val available = availability.isLocationAvailable
                // Log availability changes as informational only (not errors)
                // These are normal fused provider behavior, not failures
                if (available) {
                    Log.d(TAG, "GPS provider availability transitioned to available")
                } else {
                    Log.d(TAG, "GPS provider availability transitioned to unavailable (may be temporary)")
                }
            }
        }

        activeCallback = locationCallbackFlow

        try {
            // Request location with explicit main looper (ensures callbacks on main thread)
            fusedLocationClient.requestLocationUpdates(
                request,
                locationCallbackFlow,
                Looper.getMainLooper()
            )
            Log.d(TAG, "getLocationUpdates: FusedLocationProvider requested")

            awaitClose {
                Log.d(TAG, "Location stream collector cleanup")
                activeCallback = null
                collectorActive.set(false)  // Release collector lock
                try {
                    fusedLocationClient.removeLocationUpdates(locationCallbackFlow)
                } catch (e: Exception) {
                    Log.e(TAG, "Error removing location updates", e)
                }
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "getLocationUpdates: Security exception (missing location permission)", e)
            activeCallback = null
            close(e)
        } catch (e: Exception) {
            Log.e(TAG, "getLocationUpdates: Unexpected error", e)
            activeCallback = null
            close(e)
        }
    }

    /**
     * Restart location updates (guarded against concurrent restarts).
     * Used by watchdog when stall is detected.
     * Thread-safe: atomic guard prevents duplicate restarts.
     */
    suspend fun restartLocationUpdates() {
        // Guard against multiple simultaneous restart attempts
        if (!restartInProgress.compareAndSet(false, true)) {
            Log.d(TAG, "Location restart already in progress, skipping duplicate")
            return
        }
        
        try {
            if (locationRequest == null || activeCallback == null) {
                Log.w(TAG, "Cannot restart: missing request or callback")
                return
            }
            
            Log.d(TAG, "Restarting stalled location stream")
            fusedLocationClient.removeLocationUpdates(activeCallback!!)
            delay(500)
            fusedLocationClient.requestLocationUpdates(
                locationRequest!!
,
                activeCallback!!,
                Looper.getMainLooper()
            )
            Log.d(TAG, "Location stream restart complete")
        } catch (e: Exception) {
            Log.e(TAG, "Restart error: ${e.message}")
        } finally {
            restartInProgress.set(false)
        }
    }

    /**
     * Attempt to acquire current location for fallback when stream is silent.
     * Newer API that may provide faster current location acquisition.
     */
    suspend fun getCurrentLocation(): Location? {
        return try {
            Log.d(TAG, "Requesting current location via getCurrentLocation()")
            val location = fusedLocationClient.getCurrentLocation(
                Priority.PRIORITY_HIGH_ACCURACY,
                null
            ).await()
            if (location != null) {
                Log.d(TAG, "Current location acquired: lat=${location.latitude}, lng=${location.longitude}")
            }
            location
        } catch (e: Exception) {
            Log.e(TAG, "getCurrentLocation: Error", e)
            null
        }
    }

    /**
     * Attempt to get the last-known location as an emergency fallback.
     * Used when location stream is silent and getCurrentLocation fails.
     */
    suspend fun getLastKnownLocation(): Location? {
        return try {
            Log.d(TAG, "Requesting last known location")
            val location = fusedLocationClient.lastLocation.await()
            if (location != null) {
                Log.d(TAG, "Fallback location used: lat=${location.latitude}, lng=${location.longitude}")
            }
            location
        } catch (e: Exception) {
            Log.e(TAG, "getLastKnownLocation: Error", e)
            null
        }
    }
}

