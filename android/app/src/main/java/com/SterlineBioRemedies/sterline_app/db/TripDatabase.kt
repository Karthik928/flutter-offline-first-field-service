package com.FieldServiceBioRemedies.FieldService_app.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import com.FieldServiceBioRemedies.FieldService_app.db.dao.TripDao
import com.FieldServiceBioRemedies.FieldService_app.db.entity.Trip
import com.FieldServiceBioRemedies.FieldService_app.db.entity.LocationSample

@Database(
    entities = [Trip::class, LocationSample::class],
    version = 1,
    exportSchema = false
)
abstract class TripDatabase : RoomDatabase() {
    abstract fun tripDao(): TripDao

    companion object {
        @Volatile
        private var INSTANCE: TripDatabase? = null

        fun getDatabase(context: Context): TripDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    TripDatabase::class.java,
                    "trip_database"
                ).build()
                INSTANCE = instance
                instance
            }
        }
    }
}

