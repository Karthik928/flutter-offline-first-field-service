import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';

class CacheEntry {
  final String body; // raw JSON text
  final int storedAtMillis; // epoch millis
  final int statusCode;

  CacheEntry({
    required this.body,
    required this.storedAtMillis,
    required this.statusCode,
  });

  Map<String, dynamic> toMap() => {
    'body': body,
    'storedAt': storedAtMillis,
    'statusCode': statusCode,
  };

  static CacheEntry? from(dynamic v) {
    if (v is Map) {
      return CacheEntry(
        body: (v['body'] ?? '').toString(),
        storedAtMillis: (v['storedAt'] ?? 0) as int,
        statusCode: (v['statusCode'] ?? 0) as int,
      );
    }
    return null;
  }
}

class CacheStore {
  static const _boxName = 'http_cache';
  late Box _box;

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  Future<void> put(String key, CacheEntry entry) async {
    await _box.put(key, entry.toMap());
    debugPrint('📦 [Cache] put "$key" (len=${entry.body.length})');
  }

  CacheEntry? get(String key) {
    final raw = _box.get(key);
    final parsed = CacheEntry.from(raw);
    if (parsed != null) {
      final age = DateTime.now().millisecondsSinceEpoch - parsed.storedAtMillis;
      debugPrint('📦 [Cache] hit "$key" age=${age}ms');
    } else {
      debugPrint('📦 [Cache] miss "$key"');
    }
    return parsed;
  }

  Future<void> invalidatePrefix(String prefix) async {
    final keys = _box.keys
        .where((k) => k.toString().startsWith(prefix))
        .toList();
    for (final k in keys) {
      await _box.delete(k);
    }
    debugPrint('🗑️ [Cache] invalidatePrefix "$prefix" (${keys.length} keys)');
  }
}
