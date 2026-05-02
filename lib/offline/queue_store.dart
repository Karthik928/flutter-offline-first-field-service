// lib/offline/queue_store.dart
import 'dart:convert';
import 'package:hive/hive.dart';
import 'request_envelope.dart';

class QueueStore {
  static const _boxName = 'request_queue';
  Box<String>? _box;

  Future<void> init() async {
    _box ??= await Hive.openBox<String>(_boxName);
  }

  Future<void> add(RequestEnvelope env) async {
    await _box!.put(env.id, jsonEncode(env.toJson()));
  }

  Future<void> remove(String id) async => _box!.delete(id);

  Future<List<RequestEnvelope>> all() async {
    final values = _box!.values;
    return values.map((s) => RequestEnvelope.fromJson(jsonDecode(s))).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<RequestEnvelope?> getById(String id) async {
    final raw = _box!.get(id);
    return raw == null ? null : RequestEnvelope.fromJson(jsonDecode(raw));
  }

  Future<void> update(RequestEnvelope env) async {
    await _box!.put(env.id, jsonEncode(env.toJson()));
  }
}
