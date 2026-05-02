// lib/offline/cart_local_store.dart
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';

/// Simple Hive-backed cart store.
/// Stores a Map keyed by productId:
/// {
///   "{productId}": {
///     "product": { ...product metadata... },
///     "qty": 2
///   },
///   ...
/// }
class CartLocalStore {
  static const String _boxName = 'cart_box';
  static const String _cartKey = 'cart_map';

  Box<dynamic>? _box;

  Future<void> init() async {
    _box ??= await Hive.openBox<dynamic>(_boxName);
    if (kDebugMode) {
      debugPrint('✅ CartLocalStore.init -> opened $_boxName');
    }
  }

  Future<Map<String, Map<String, dynamic>>> getAll() async {
    await init();
    final raw = _box!.get(_cartKey);
    if (raw == null) return <String, Map<String, dynamic>>{};
    try {
      if (raw is Map) {
        // raw may be Map<dynamic, dynamic>
        final Map<String, Map<String, dynamic>> out = {};
        for (final e in (raw).entries) {
          final k = e.key.toString();
          final v = e.value;
          if (v is Map) {
            out[k] = Map<String, dynamic>.from(v);
          } else if (v is String) {
            // support stringified JSON
            out[k] = Map<String, dynamic>.from(jsonDecode(v) as Map);
          }
        }
        return out;
      } else if (raw is String) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        return decoded.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v)));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('CartLocalStore.getAll decode error: $e');
    }
    return <String, Map<String, dynamic>>{};
  }

  Future<void> saveAll(Map<String, Map<String, dynamic>> map) async {
    await init();
    try {
      await _box!.put(_cartKey, map);
      if (kDebugMode) {
        debugPrint('📥 CartLocalStore.saveAll (${map.length} entries)');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('CartLocalStore.saveAll error: $e');
      // fallback: store as JSON string
      await _box!.put(_cartKey, jsonEncode(map));
    }
  }

  Future<void> upsertItem(
    String productId,
    Map<String, dynamic> productMeta,
    int qty,
  ) async {
    final all = await getAll();
    all[productId] = {'product': productMeta, 'qty': qty};
    await saveAll(all);
  }

  Future<void> removeItem(String productId) async {
    final all = await getAll();
    if (all.containsKey(productId)) {
      all.remove(productId);
      await saveAll(all);
    }
  }

  Future<void> clear() async {
    await init();
    await _box!.delete(_cartKey);
  }

  Future<int> totalItems() async {
    final all = await getAll();
    var s = 0;
    for (final v in all.values) {
      final q = v['qty'];
      if (q is num) {
        s += q.toInt();
      } else if (q is String) {
        s += int.tryParse(q) ?? 0;
      }
    }
    return s;
  }

  Future<double> totalAmount() async {
    final all = await getAll();
    double tot = 0.0;
    for (final v in all.values) {
      final qty = v['qty'];
      final p = v['product'];
      double price = 0.0;
      if (p is Map) {
        final priceRaw = p['productPrice'] ?? p['price'] ?? p['productPrice'];
        if (priceRaw is num) {
          price = priceRaw.toDouble();
        } else if (priceRaw is String) {
          price = double.tryParse(priceRaw) ?? 0.0;
        }
      }
      final qn = (qty is num)
          ? qty.toDouble()
          : (qty is String ? double.tryParse(qty) ?? 0 : 0);
      tot += qn * price;
    }
    return tot;
  }
}
