package com.FieldServiceBioRemedies.FieldService_app.db.entity

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "location_samples")
data class LocationSample(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val tripId: String,
    val ts: String, // ISO8601 UTC
    val lat: Double,
    val lng: Double,
    val accuracyM: Double?,
    val speedMps: Double?
)

