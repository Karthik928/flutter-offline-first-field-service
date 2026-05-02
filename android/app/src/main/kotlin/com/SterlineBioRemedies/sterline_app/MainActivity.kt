package com.FieldServiceBioRemedies.FieldService_app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.FieldServiceBioRemedies.FieldService_app.native.TripForegroundService
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.locks.ReentrantLock

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.myapp.trip/native_service"
    private val EVENT_CHANNEL = "com.myapp.trip/native_service/events"

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    // Thread-safe service access
    private val serviceLock = ReentrantLock()
    private var service: TripForegroundService? = null
    private var serviceBound = false

    // Use AtomicBoolean for thread-safe binding guard
    private val bindingMutex = AtomicBoolean(false)

    // Pending request tracking (checked in onServiceConnected)
    private var pendingStartResult: MethodChannel.Result? = null
    private var pendingStartArgs: Triple<String, String, Double?>? = null
    private var pendingStartAuthToken: String? = null
    private var pendingStartApiBaseUrl: String? = null
    private var pendingStartTime: Long = 0L

    private var pendingPunchTrackingResult: MethodChannel.Result? = null
    private var pendingPunchTrackingTime: Long = 0L
    private var pendingPunchTrackingAuthToken: String? = null

    private var pendingEventChannelBind: Boolean = false

    companion object {
        private const val PENDING_REQUEST_TIMEOUT_MS = 30_000L
    }

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            val localBinder = binder as? TripForegroundService.LocalBinder
            if (localBinder == null) {
                android.util.Log.e("MainActivity", "Invalid binder type in serviceConnection")
                completeFailedBinding("Invalid binder type")
                return
            }

            try {
                serviceLock.lock()
                service = localBinder.getService()
                serviceBound = true
            } finally {
                serviceLock.unlock()
            }

            android.util.Log.d("MainActivity", "TripForegroundService bound")
            bindingMutex.set(false)

            // Apply pending punch-tracking auth token
            if (pendingPunchTrackingAuthToken != null) {
                try {
                    serviceLock.lock()
                    service?.setAuthToken(pendingPunchTrackingAuthToken)
                } finally {
                    serviceLock.unlock()
                }
                android.util.Log.d("MainActivity", "Applied pending punch-tracking auth token to service")
                pendingPunchTrackingAuthToken = null
            }

            // Apply pending startTrip auth token
            if (pendingStartAuthToken != null) {
                try {
                    serviceLock.lock()
                    service?.setAuthToken(pendingStartAuthToken)
                } finally {
                    serviceLock.unlock()
                }
                android.util.Log.d("MainActivity", "Applied pending startTrip auth token to service")
                pendingStartAuthToken = null
            }

            // Set EventChannel callback
            try {
                serviceLock.lock()
                service?.setEventChannelCallback { snapshot ->
                    runOnUiThread { eventSink?.success(snapshot) }
                }
            } finally {
                serviceLock.unlock()
            }

            // Execute pending startTrip if present
            if (pendingStartResult != null && pendingStartArgs != null) {
                if (System.currentTimeMillis() - pendingStartTime > PENDING_REQUEST_TIMEOUT_MS) {
                    android.util.Log.w("MainActivity", "Pending startTrip timed out after 30s")
                    pendingStartResult?.error("TIMEOUT", "Service binding took > 30s", null)
                    pendingStartResult = null
                    pendingStartArgs = null
                    pendingStartApiBaseUrl = null
                } else {
                    android.util.Log.d("MainActivity", "Executing pending startTrip")
                    try {
                        val (pTripId, pTripStartUtc, pInitialDistance) = pendingStartArgs!!
                        // Apply URL and token from the pending fields (local vars are out of scope here)
                        if (!pendingStartApiBaseUrl.isNullOrBlank()) {
                            service?.setTrackingApiBaseUrl(pendingStartApiBaseUrl)
                        }
                        // pendingStartAuthToken was already applied above; no need to re-apply
                        val success = service!!.startTrip(pTripId, pTripStartUtc, pInitialDistance)
                        pendingStartApiBaseUrl = null
                        pendingStartResult?.success(mapOf("ok" to success))
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "Error completing pending startTrip", e)
                        pendingStartResult?.error("SERVICE_ERROR", "Failed to start trip: ${e.message}", null)
                    } finally {
                        pendingStartResult = null
                        pendingStartArgs = null
                    }
                }
            }

            // Execute pending startPunchTracking if present
            if (pendingPunchTrackingResult != null) {
                if (System.currentTimeMillis() - pendingPunchTrackingTime > PENDING_REQUEST_TIMEOUT_MS) {
                    android.util.Log.w("MainActivity", "Pending startPunchTracking timed out after 30s")
                    pendingPunchTrackingResult?.error("TIMEOUT", "Service binding took > 30s", null)
                    pendingPunchTrackingResult = null
                } else {
                    android.util.Log.d("MainActivity", "Executing pending startPunchTracking")
                    try {
                        service!!.startPunchTracking()
                        pendingPunchTrackingResult?.success(mapOf("ok" to true))
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "Error completing pending startPunchTracking", e)
                        pendingPunchTrackingResult?.error("SERVICE_ERROR", "Failed to start punch tracking: ${e.message}", null)
                    } finally {
                        pendingPunchTrackingResult = null
                    }
                }
            }

            // Fulfill pending EventChannel bind if waiting
            if (pendingEventChannelBind && eventSink != null && service != null) {
                android.util.Log.d("MainActivity", "EventChannel pending bind fulfilled")
                pendingEventChannelBind = false
                try {
                    serviceLock.lock()
                    service?.setEventChannelCallback { snapshot ->
                        runOnUiThread { eventSink?.success(snapshot) }
                    }
                } finally {
                    serviceLock.unlock()
                }
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            android.util.Log.d("MainActivity", "Service disconnected")
            try {
                serviceLock.lock()
                service = null
                serviceBound = false
            } finally {
                serviceLock.unlock()
            }
        }
    }

    private fun completeFailedBinding(reason: String) {
        android.util.Log.e("MainActivity", "Binding failed: $reason")
        bindingMutex.set(false)

        if (pendingStartResult != null) {
            pendingStartResult?.error("SERVICE_ERROR", reason, null)
            pendingStartResult = null
            pendingStartArgs = null
            pendingStartApiBaseUrl = null
        }

        if (pendingPunchTrackingResult != null) {
            pendingPunchTrackingResult?.error("SERVICE_ERROR", reason, null)
            pendingPunchTrackingResult = null
        }
    }

    private fun ensureServiceBound(reason: String): Boolean {
        try {
            serviceLock.lock()
            if (serviceBound && service != null) {
                android.util.Log.d("MainActivity", "Service already bound ($reason)")
                return true
            }
        } finally {
            serviceLock.unlock()
        }

        if (!bindingMutex.compareAndSet(false, true)) {
            android.util.Log.d("MainActivity", "Another thread is binding, skipping ($reason)")
            return false
        }

        val bindIntent = Intent(this, TripForegroundService::class.java)
        val bindResult = bindService(bindIntent, serviceConnection, Context.BIND_AUTO_CREATE)

        if (!bindResult) {
            android.util.Log.e("MainActivity", "Failed to bind service ($reason)")
            bindingMutex.set(false)
            return false
        }

        android.util.Log.d("MainActivity", "Service binding initiated ($reason)")
        return true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {

                "startTrip" -> {
                    try {
                        val tripId = call.argument<String>("tripId")
                        val tripStartUtc = call.argument<String>("tripStartUtc")
                        val initialDistanceMeters = call.argument<Double>("initialDistanceMeters")
                        val authToken = call.argument<String>("authToken")
                        val apiBaseUrl = call.argument<String>("apiBaseUrl")

                        if (tripId == null || tripStartUtc == null) {
                            result.error("INVALID_ARGUMENT", "tripId and tripStartUtc are required", null)
                            return@setMethodCallHandler
                        }

                        // Start the foreground service first so Android 14 foreground requirement is met
                        val serviceIntent = Intent(this, TripForegroundService::class.java)
                        if (!authToken.isNullOrBlank()) {
                            serviceIntent.putExtra("authToken", authToken)
                        }
                        try {
                            startForegroundService(serviceIntent)
                            android.util.Log.d("MainActivity", "startForegroundService requested")
                        } catch (e: IllegalStateException) {
                            startService(serviceIntent)
                            android.util.Log.d("MainActivity", "startService requested (fallback)")
                        }

                        var alreadyBound = false
                        try {
                            serviceLock.lock()
                            alreadyBound = serviceBound && service != null
                        } finally {
                            serviceLock.unlock()
                        }

                        if (!alreadyBound) {
                            // Guard against duplicate pending starts
                            if (pendingStartResult != null) {
                                if (pendingStartArgs?.first == tripId) {
                                    result.success(mapOf("ok" to true))
                                    return@setMethodCallHandler
                                } else {
                                    result.error("SERVICE_ERROR", "Start trip already pending", null)
                                    return@setMethodCallHandler
                                }
                            }

                            // Store pending request and initiate binding
                            pendingStartResult = result
                            pendingStartArgs = Triple(tripId, tripStartUtc, initialDistanceMeters)
                            pendingStartAuthToken = authToken
                            pendingStartApiBaseUrl = apiBaseUrl
                            pendingStartTime = System.currentTimeMillis()

                            if (!ensureServiceBound("startTrip")) {
                                completeFailedBinding("bindService failed")
                            }
                        } else {
                            // Service already bound — call directly
                            try {
                                val success = try {
                                    serviceLock.lock()
                                    if (!apiBaseUrl.isNullOrBlank()) {
                                        service?.setTrackingApiBaseUrl(apiBaseUrl)
                                    }
                                    if (!authToken.isNullOrBlank()) {
                                        service?.setAuthToken(authToken)
                                    }
                                    service!!.startTrip(tripId, tripStartUtc, initialDistanceMeters)
                                } finally {
                                    serviceLock.unlock()
                                }
                                result.success(mapOf("ok" to success))
                            } catch (e: Exception) {
                                android.util.Log.e("MainActivity", "Error starting trip", e)
                                result.error("SERVICE_ERROR", "Failed to start trip: ${e.message}", null)
                            }
                        }
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "Error in startTrip", e)
                        result.error("SERVICE_ERROR", "Unexpected error: ${e.message}", null)
                    }
                }

                "stopTrip" -> {
                    try {
                        var toUnbind = false
                        try {
                            serviceLock.lock()
                            toUnbind = serviceBound && service != null
                        } finally {
                            serviceLock.unlock()
                        }

                        if (toUnbind) {
                            try {
                                try {
                                    serviceLock.lock()
                                    service!!.stopTrip()
                                } finally {
                                    serviceLock.unlock()
                                }
                            } catch (e: Exception) {
                                android.util.Log.e("MainActivity", "Error requesting service stop", e)
                            }

                            try {
                                unbindService(serviceConnection)
                                try {
                                    serviceLock.lock()
                                    serviceBound = false
                                    service = null
                                    android.util.Log.d("MainActivity", "unbindService successful")
                                } finally {
                                    serviceLock.unlock()
                                }
                            } catch (e: IllegalArgumentException) {
                                android.util.Log.w("MainActivity", "unbindService ignored: ${e.message}")
                            } catch (e: Exception) {
                                android.util.Log.e("MainActivity", "Error unbinding service", e)
                            }
                        }

                        result.success(mapOf("ok" to true))
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "Error in stopTrip", e)
                        result.success(mapOf("ok" to true))
                    }
                }

                "getActiveTripSnapshot" -> {
                    var isBound = false
                    try {
                        serviceLock.lock()
                        isBound = serviceBound && service != null
                    } finally {
                        serviceLock.unlock()
                    }

                    if (isBound) {
                        try {
                            serviceLock.lock()
                            val snapshot = service!!.getActiveTripSnapshot()
                            result.success(snapshot)
                        } finally {
                            serviceLock.unlock()
                        }
                    } else {
                        val bindIntent = Intent(this, TripForegroundService::class.java)
                        val tempConnection = object : ServiceConnection {
                            override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                                try {
                                    val localBinder = binder as TripForegroundService.LocalBinder
                                    result.success(localBinder.getService().getActiveTripSnapshot())
                                } finally {
                                    try { unbindService(this) } catch (_: Exception) {}
                                }
                            }
                            override fun onServiceDisconnected(name: ComponentName?) {
                                result.success(null)
                            }
                        }
                        if (!bindService(bindIntent, tempConnection, Context.BIND_AUTO_CREATE)) {
                            result.success(null)
                        }
                    }
                }

                "isServiceRunning" -> {
                    var isBound = false
                    try {
                        serviceLock.lock()
                        isBound = serviceBound && service != null
                    } finally {
                        serviceLock.unlock()
                    }

                    if (isBound) {
                        try {
                            serviceLock.lock()
                            result.success(mapOf("running" to service!!.isServiceRunning()))
                        } finally {
                            serviceLock.unlock()
                        }
                    } else {
                        val bindIntent = Intent(this, TripForegroundService::class.java)
                        val tempConnection = object : ServiceConnection {
                            override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                                try {
                                    val localBinder = binder as TripForegroundService.LocalBinder
                                    result.success(mapOf("running" to localBinder.getService().isServiceRunning()))
                                } finally {
                                    try { unbindService(this) } catch (_: Exception) {}
                                }
                            }
                            override fun onServiceDisconnected(name: ComponentName?) {
                                result.success(mapOf("running" to false))
                            }
                        }
                        if (!bindService(bindIntent, tempConnection, Context.BIND_AUTO_CREATE)) {
                            result.success(mapOf("running" to false))
                        }
                    }
                }

                "debugGuards" -> {
                    try {
                        var isBound = false
                        try {
                            serviceLock.lock()
                            isBound = serviceBound && service != null
                        } finally {
                            serviceLock.unlock()
                        }

                        if (isBound) {
                            try {
                                serviceLock.lock()
                                service?.logGuardState()
                                result.success(mapOf("ok" to true))
                            } finally {
                                serviceLock.unlock()
                            }
                        } else {
                            val bindIntent = Intent(this, TripForegroundService::class.java)
                            val tempConnection = object : ServiceConnection {
                                override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                                    try {
                                        val localBinder = binder as TripForegroundService.LocalBinder
                                        localBinder.getService().logGuardState()
                                        result.success(mapOf("ok" to true))
                                    } finally {
                                        try { unbindService(this) } catch (_: Exception) {}
                                    }
                                }
                                override fun onServiceDisconnected(name: ComponentName?) {
                                    result.success(mapOf("ok" to false))
                                }
                            }
                            if (!bindService(bindIntent, tempConnection, Context.BIND_AUTO_CREATE)) {
                                result.success(mapOf("ok" to false))
                            }
                        }
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "debugGuards: error", e)
                        result.success(mapOf("ok" to false, "error" to e.message))
                    }
                }

                "startPunchTracking" -> {
                    val authToken = call.argument<String>("authToken")
                    android.util.Log.d("MainActivity", "startPunchTracking requested (tokenPresent=${!authToken.isNullOrBlank()})")

                    var isBound = false
                    try {
                        serviceLock.lock()
                        isBound = serviceBound && service != null
                    } finally {
                        serviceLock.unlock()
                    }

                    if (isBound) {
                        try {
                            try {
                                serviceLock.lock()
                                service?.setAuthToken(authToken)
                                service?.startPunchTracking()
                            } finally {
                                serviceLock.unlock()
                            }
                            android.util.Log.d("MainActivity", "startPunchTracking: called successfully")
                            result.success(mapOf("ok" to true))
                        } catch (e: Exception) {
                            android.util.Log.e("MainActivity", "startPunchTracking: error", e)
                            result.error("SERVICE_ERROR", e.message, null)
                        }
                        return@setMethodCallHandler
                    }

                    try {
                        val intent = Intent(this, TripForegroundService::class.java)
                        startForegroundService(intent)
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "startPunchTracking: startForegroundService failed", e)
                        result.error("SERVICE_ERROR", "Failed to start service: ${e.message}", null)
                        return@setMethodCallHandler
                    }

                    pendingPunchTrackingResult = result
                    pendingPunchTrackingTime = System.currentTimeMillis()
                    pendingPunchTrackingAuthToken = authToken

                    if (!ensureServiceBound("startPunchTracking")) {
                        completeFailedBinding("bindService failed")
                    }
                }

                "stopPunchTracking" -> {
                    try {
                        var hasService = false
                        try {
                            serviceLock.lock()
                            hasService = serviceBound && service != null
                        } finally {
                            serviceLock.unlock()
                        }

                        if (hasService) {
                            try {
                                serviceLock.lock()
                                service?.stopPunchTracking()
                            } finally {
                                serviceLock.unlock()
                            }
                        }
                        result.success(mapOf("ok" to true))
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "stopPunchTracking error", e)
                        result.success(mapOf("ok" to true))
                    }
                }

                "tripStarted" -> {
                    try {
                        try {
                            serviceLock.lock()
                            service?.startTripMode()
                        } finally {
                            serviceLock.unlock()
                        }
                        result.success(mapOf("ok" to true))
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "tripStarted error", e)
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }

                "tripStopped" -> {
                    try {
                        try {
                            serviceLock.lock()
                            service?.stopTripMode()
                        } finally {
                            serviceLock.unlock()
                        }
                        result.success(mapOf("ok" to true))
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "tripStopped error", e)
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }

                // Inside the when(call.method) block, add:
"openOppoBatterySettings" -> {
    try {
        // Oppo/Realme specific: AutoStart Manager
        val intent = Intent().apply {
            component = android.content.ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.permission.startup.StartupAppListActivity"
            )
        }
        startActivity(intent)
        result.success(null)
    } catch (_: Exception) {
        try {
            // Realme fallback
            val intent = Intent().apply {
                component = android.content.ComponentName(
                    "com.realme.safecenter",
                    "com.realme.safecenter.permission.startup.StartupAppListActivity"
                )
            }
            startActivity(intent)
            result.success(null)
        } catch (e2: Exception) {
            // Neither worked — caller falls back to openAppSettings()
            result.error("NOT_FOUND", "Oppo battery settings not found", null)
        }
    }
}

                else -> result.notImplemented()
            }
        }

        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
        eventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                android.util.Log.d("MainActivity", "EventChannel.onListen called")
                eventSink = events

                var isBound = false
                try {
                    serviceLock.lock()
                    isBound = serviceBound && service != null
                } finally {
                    serviceLock.unlock()
                }

                if (isBound) {
                    try {
                        serviceLock.lock()
                        service?.setEventChannelCallback { snapshot ->
                            runOnUiThread { eventSink?.success(snapshot) }
                        }
                    } finally {
                        serviceLock.unlock()
                    }
                } else {
                    pendingEventChannelBind = true
                    ensureServiceBound("EventChannel.onListen")
                }
            }

            override fun onCancel(arguments: Any?) {
                android.util.Log.d("MainActivity", "EventChannel.onCancel called")
                eventSink = null
                pendingEventChannelBind = false
            }
        })
    }

    override fun onDestroy() {
        super.onDestroy()
        android.util.Log.d("MainActivity", "onDestroy: cleaning up")

        pendingStartResult = null
        pendingStartArgs = null
        pendingStartApiBaseUrl = null
        pendingPunchTrackingResult = null

        if (serviceBound) {
            try {
                unbindService(serviceConnection)
                android.util.Log.d("MainActivity", "onDestroy: unbindService successful")
            } catch (e: IllegalArgumentException) {
                android.util.Log.d("MainActivity", "onDestroy: unbind already cleared")
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "onDestroy: unbind error", e)
            } finally {
                try {
                    serviceLock.lock()
                    serviceBound = false
                    service = null
                } finally {
                    serviceLock.unlock()
                }
                bindingMutex.set(false)
            }
        }
    }
}
