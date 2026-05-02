package com.FieldServiceBioRemedies.FieldService_app.db.dao

import androidx.room.*
import com.FieldServiceBioRemedies.FieldService_app.db.entity.Trip
import com.FieldServiceBioRemedies.FieldService_app.db.entity.LocationSample
import kotlinx.coroutines.flow.Flow

@Dao
interface TripDao {
    @Query("SELECT * FROM trips WHERE tripId = :tripId LIMIT 1")
    suspend fun getTrip(tripId: String): Trip?

    @Query("SELECT * FROM trips WHERE tripId = :tripId LIMIT 1")
    fun getTripFlow(tripId: String): Flow<Trip?>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertTrip(trip: Trip)

    @Insert
    suspend fun insertLocationSample(sample: LocationSample)

    @Query("SELECT * FROM location_samples WHERE tripId = :tripId ORDER BY ts ASC")
    suspend fun getLocationSamples(tripId: String): List<LocationSample>
}

