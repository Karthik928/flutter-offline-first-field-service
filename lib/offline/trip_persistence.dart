// lib/offline/trip_persistence.dart
import 'package:hive/hive.dart';

class TripPersistence {
  static const _currentBox = 'current_trip';
  static const _updatesBox = 'trip_updates';

  /// Save/overwrite current trip summary
  static Future<void> saveCurrentTrip(Map<String, dynamic> summary) async {
    final box = await Hive.openBox(_currentBox);
    await box.put('active', summary);
  }

  /// Read active trip summary (or null)
  static Future<Map<String, dynamic>?> readCurrentTrip() async {
    final box = await Hive.openBox(_currentBox);
    final raw = box.get('active');
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw as Map);
  }

  /// Delete active trip summary
  static Future<void> clearCurrentTrip() async {
    final box = await Hive.openBox(_currentBox);
    await box.delete('active');
  }

  /// Create empty updates list for localTripId
  static Future<void> createUpdatesList(String localTripId) async {
    final box = await Hive.openBox(_updatesBox);
    await box.put(localTripId, <Map<String, dynamic>>[]);
  }

  /// Append a location/update entry
  static Future<void> appendUpdate(String localTripId, Map<String, dynamic> entry) async {
    final box = await Hive.openBox(_updatesBox);
    final List raw = box.get(localTripId) ?? <Map<String, dynamic>>[];
    final updates = List<Map<String, dynamic>>.from(raw);
    updates.add(entry);
    await box.put(localTripId, updates);
  }

  /// Read updates for a trip
  static Future<List<Map<String, dynamic>>> readUpdates(String localTripId) async {
    final box = await Hive.openBox(_updatesBox);
    final raw = box.get(localTripId) ?? <Map<String, dynamic>>[];
    return List<Map<String, dynamic>>.from(raw);
  }

  /// Optionally move updates to archive (not implemented here)
  static Future<void> deleteUpdates(String localTripId) async {
    final box = await Hive.openBox(_updatesBox);
    await box.delete(localTripId);
  }
}
