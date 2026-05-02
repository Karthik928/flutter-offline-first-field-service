package com.FieldServiceBioRemedies.FieldService_app.db.entity

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "trips")
data class Trip(
    @PrimaryKey
    val tripId: String,
    val tripStartUtc: String, // ISO8601 UTC
    val distanceM: Double,
    val lastLat: Double,
    val lastLng: Double,
    val lastFixTs: String // ISO8601 UTC
)

