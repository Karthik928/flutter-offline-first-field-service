// lib/offline/failed_record_store.dart
//
// Persistent store for failed sync records.
// Uses SharedPreferences (same dependency already in the project).
// Max 200 records are kept; oldest are pruned automatically.
//
// Thread-safety: all public methods are async and serialised via a simple
// lock flag.  For higher throughput consider Hive or sqflite, but
// SharedPreferences is sufficient for a "view-only" failure log.

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'failed_record_model.dart';

class FailedRecordStore {
  static const String _key = 'failed_records_v1';
  static const int _maxRecords = 200;

  // Simple async mutex
  bool _busy = false;
  final _queue = <Completer<void>>[];

  Future<T> _withLock<T>(Future<T> Function() fn) async {
    if (_busy) {
      final c = Completer<void>();
      _queue.add(c);
      await c.future;
    }
    _busy = true;
    try {
      return await fn();
    } finally {
      _busy = false;
      if (_queue.isNotEmpty) {
        final next = _queue.removeAt(0);
        next.complete();
      }
    }
  }

  // ─── Read ─────────────────────────────────────────────────────────────────

  Future<List<FailedRecord>> all() async {
    return _withLock(() async {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        return list
            .map(
              (e) => FailedRecord.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
      } catch (_) {
        return [];
      }
    });
  }

  Future<FailedRecord?> getById(String id) async {
    final records = await all();
    try {
      return records.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  // ─── Write ────────────────────────────────────────────────────────────────

  /// Append a new failed record.  Automatically prunes oldest beyond [_maxRecords].
  Future<void> add(FailedRecord record) async {
    return _withLock(() async {
      final prefs = await SharedPreferences.getInstance();
      final existing = await _loadRaw(prefs);

      // Deduplicate by envelopeId (replace if already present)
      existing.removeWhere((r) => r.envelopeId == record.envelopeId);
      existing.add(record);

      // Prune: keep most recent [_maxRecords] sorted by failedAt desc
      existing.sort((a, b) => b.failedAt.compareTo(a.failedAt));
      final pruned = existing.take(_maxRecords).toList();

      await _saveRaw(prefs, pruned);
    });
  }

  /// Remove a single record by id (for future "dismiss" feature).
  Future<void> remove(String id) async {
    return _withLock(() async {
      final prefs = await SharedPreferences.getInstance();
      final existing = await _loadRaw(prefs);
      existing.removeWhere((r) => r.id == id);
      await _saveRaw(prefs, existing);
    });
  }

  /// Clear all failed records.
  Future<void> clear() async {
    return _withLock(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    });
  }

  // ─── Stats ────────────────────────────────────────────────────────────────

  Future<int> count() async {
    final records = await all();
    return records.length;
  }

  Future<Map<FailedRecordType, int>> countByType() async {
    final records = await all();
    final map = <FailedRecordType, int>{};
    for (final r in records) {
      map[r.recordType] = (map[r.recordType] ?? 0) + 1;
    }
    return map;
  }

  // ─── Internal ─────────────────────────────────────────────────────────────

  Future<List<FailedRecord>> _loadRaw(SharedPreferences prefs) async {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map(
            (e) => FailedRecord.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveRaw(
    SharedPreferences prefs,
    List<FailedRecord> records,
  ) async {
    final encoded = jsonEncode(records.map((r) => r.toJson()).toList());
    await prefs.setString(_key, encoded);
  }
}
