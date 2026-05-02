// lib/services/local_store.dart
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:FieldService_app/services/models.dart';

class LocalStore {
  static Database? _db;

  /// Ensures DB is available in THIS isolate.
  static Future<Database> _ensureDb() async {
    if (_db != null) return _db!;

    // Desktop/test environments
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = join(await getDatabasesPath(), 'field_tracker.db');

    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE locations(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            trip_id TEXT,
            ts TEXT,
            lat REAL,
            lng REAL,
            speed REAL,
            acc REAL
          )
        ''');

        await db.execute('''
          CREATE TABLE trips(
            id TEXT PRIMARY KEY,
            start_utc TEXT,
            end_utc TEXT,
            distance_m REAL,
            duration_sec INTEGER,
            origin_lat REAL,
            origin_lng REAL,
            dest_lat REAL,
            dest_lng REAL
          )
        ''');
      },
    );

    return _db!;
  }

  /// Optional explicit initialization.
  static Future<void> init() async {
    await _ensureDb();
  }

  // ---------------------------------------------------------------------------
  // ORIGINAL INTERNAL DB WRITE METHODS (SAFE)
  // ---------------------------------------------------------------------------

  /// Internal method: writes a location sample (used by wrapper appendLocationSample)
  static Future<void> addLocationSample(String tripId, LocationSample s) async {
    final db = await _ensureDb();

    await db.insert('locations', {
      'trip_id': tripId,
      'ts': s.ts.toIso8601String(),
      'lat': s.lat,
      'lng': s.lng,
      'speed': s.speed,
      'acc': s.accuracyM, // null allowed
    });
  }

  /// Internal method: writes/updates a Trip summary
  static Future<void> upsertTripSummary(TripSession t) async {
    final db = await _ensureDb();

    await db.insert('trips', {
      'id': t.id,
      'start_utc': t.startUtc.toIso8601String(),
      'end_utc': t.endUtc?.toIso8601String(),
      'distance_m': t.distanceM,
      'duration_sec': t.durationSec,
      'origin_lat': t.origin?.latitude,
      'origin_lng': t.origin?.longitude,
      'dest_lat': t.destination?.latitude,
      'dest_lng': t.destination?.longitude,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------------------------------------------------------------------------
  // COMPATIBILITY WRAPPERS — REQUIRED FOR TripManager (DO NOT REMOVE)
  // ---------------------------------------------------------------------------

  /// Required by TripManager.start(), TripManager.end(), TripManager.onLocation()
  static Future<void> upsertTrip(TripSession t) async {
    await upsertTripSummary(t);
  }

  /// Required by TripManager.onLocation()
  static Future<void> appendLocationSample(
    String tripId,
    LocationSample s,
  ) async {
    await addLocationSample(tripId, s);
  }

  // ---------------------------------------------------------------------------
  // (Optional) read APIs if needed in future steps
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>?> getTrip(String id) async {
    final db = await _ensureDb();
    final r = await db.query(
      'trips',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return r.isNotEmpty ? r.first : null;
  }

  static Future<List<Map<String, dynamic>>> getTripLocations(String id) async {
    final db = await _ensureDb();
    return db.query('locations', where: 'trip_id = ?', whereArgs: [id]);
  }
}
