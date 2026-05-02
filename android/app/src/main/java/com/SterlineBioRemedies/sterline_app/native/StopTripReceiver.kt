package com.FieldServiceBioRemedies.FieldService_app.native

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class StopTripReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == NotificationHelper.ACTION_STOP) {
            // Send stop action to service via startForegroundService
            val serviceIntent = Intent(context, TripForegroundService::class.java).apply {
                action = NotificationHelper.ACTION_STOP
            }
            context.startForegroundService(serviceIntent)
        }
    }
}

