// lib/Screens/cart_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/Screens/orders_screen.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

class CartScreen extends StatefulWidget {
  final String customerId;
  final String type;

  const CartScreen({super.key, required this.customerId, required this.type});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  static const Color _brandGreen = Color(0xFF2E7D32);
  static const Color _accentGreen = Color(0xFF1AB69C);

  bool _isLoading = false;
  bool _isPlacingOrder = false;
  String? _error;
  Map<String, dynamic>? _serverCart;
  String? _employeeId;
  String? _tripId;
  bool? tripCompleted;
  final Set<String> _pendingProductOps = <String>{};
  final _remarksCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  @override
  void dispose() {
    _remarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _hydrate() async {
    final meta = await _loadSessionMeta();
    await _fetchCart(employeeId: meta['employeeId'], tripId: meta['tripId']);
  }

  Future<Map<String, String>> _loadSessionMeta() async {
    debugPrint('🔄 [TripWithOrder] Loading session metadata...');

    final prefs = await SharedPreferences.getInstance();

    final employeeId = prefs.getString('userId') ?? '';
    final currentTripId = prefs.getString('currentTripId') ?? '';
    tripCompleted = prefs.getBool('tripCompleted') ?? false;
    final effectiveTripId = tripCompleted == true ? currentTripId : '';

    debugPrint(
      '📦 [TripWithOrder] Raw Data → '
      'employeeId: $employeeId, '
      'currentTripId: $currentTripId, '
      'tripCompleted: $tripCompleted',
    );

    setState(() {
      _employeeId = employeeId;
      _tripId = effectiveTripId;

      if (tripCompleted == true) {
        debugPrint('✅ [TripWithOrder] Trip is ACTIVE → Using tripId: $_tripId');
      } else {
        debugPrint('⚠️ [TripWithOrder] Trip NOT active → Clearing tripId');
      }
    });

    debugPrint(
      '🎯 [TripWithOrder] Final State → '
      'employeeId: $_employeeId, tripId: $_tripId',
    );

    return {'employeeId': employeeId, 'tripId': effectiveTripId};
  }

  Future<Map<String, String>> _buildHeaders({bool json = false}) async {
    final token = await SecureStorageService.getToken();
    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic>? _cartFromResponse(dynamic body) {
    if (body is Map<String, dynamic>) {
      if (body['cart'] is Map<String, dynamic>) {
        return Map<String, dynamic>.from(body['cart'] as Map<String, dynamic>);
      }
      if (body['data'] is Map<String, dynamic>) {
        return Map<String, dynamic>.from(body['data'] as Map<String, dynamic>);
      }
      if (body.containsKey('_id') && body.containsKey('items')) {
        return Map<String, dynamic>.from(body);
      }
    }
    return null;
  }

  Uri _cartUri(String employeeId) {
    return AppConfig.u(
      AppConfig.fill(AppConfig.getCart, {'employeeid': employeeId}),
    );
  }

  Future<void> _fetchCart({String? employeeId, String? tripId}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final effectiveEmployeeId = (employeeId ?? _employeeId ?? '').trim();

      if (effectiveEmployeeId.isEmpty) {
        setState(() {
          _error = 'Missing employee id for cart.';
        });
        return;
      }

      final headers = await _buildHeaders();
      final uri = _cartUri(effectiveEmployeeId);

      final resp = await http
          .get(uri, headers: headers)
          .timeout(AppConfig.httpTimeout);

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        final cart = _cartFromResponse(body);
        if (cart != null) {
          setState(() => _serverCart = cart);
        } else {
          setState(() => _error = 'Unexpected cart response');
        }
      } else if (resp.statusCode == 401) {
        setState(() => _error = 'Session expired. Please log in again.');
      } else if (resp.statusCode == 404) {
        setState(() {
          _serverCart = {'_id': '', 'items': []};
        });
      } else {
        setState(() => _error = 'Server error (${resp.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No internet');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _itemsFromServer() {
    final items = <Map<String, dynamic>>[];
    try {
      final rawItems = _serverCart?['items'] as List<dynamic>?;
      if (rawItems != null) {
        for (final it in rawItems) {
          if (it is Map<String, dynamic>) {
            items.add(it);
          } else if (it is Map) {
            items.add(Map<String, dynamic>.from(it));
          }
        }
      }
    } catch (_) {}
    return items;
  }

  int get _totalItems {
    final list = _itemsFromServer();
    var s = 0;
    for (final it in list) {
      final q = it['quantity'];
      if (q is num) {
        s += q.toInt();
      } else if (q is String) {
        s += int.tryParse(q) ?? 0;
      }
    }
    return s;
  }

  double get _totalAmount {
    final list = _itemsFromServer();
    double tot = 0.0;
    for (final it in list) {
      final q = it['quantity'];
      final price = it['price'];
      final qn = (q is num)
          ? q.toDouble()
          : (q is String ? double.tryParse(q) ?? 0 : 0);
      final pn = (price is num)
          ? price.toDouble()
          : (price is String ? double.tryParse(price) ?? 0 : 0);
      tot += qn * pn;
    }
    return tot;
  }

  String? _productIdOf(Map<String, dynamic> item) {
    final productId = item['productId'];
    if (productId == null) return null;
    if (productId is String) return productId;
    if (productId is Map && productId['_id'] != null) {
      return productId['_id'].toString();
    }
    return productId.toString();
  }

  Future<void> _updateCartQuantity(String productId, String action) async {
    if (action != 'increase' && action != 'decrease') return;
    setState(() => _pendingProductOps.add(productId));

    debugPrint(widget.customerId);
    debugPrint(_employeeId);
    debugPrint(_tripId);
    debugPrint(productId);

    try {
      final headers = await _buildHeaders(json: true);

      final body = <String, dynamic>{
        'customerId': widget.customerId,
        'type': widget.type,
        'employeeId': _employeeId ?? '',
        'tripId': _tripId ?? '',
        'productId': productId,
        'action': action,
      };

      final resp = await http
          .put(
            AppConfig.u(AppConfig.updateCart),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(AppConfig.httpTimeout);

      debugPrint(resp.body);

      final parsed = jsonDecode(resp.body);
      if (resp.statusCode == 200) {
        if ((body['message'] == 'Cart not found' || body['status'] == 404)) {
          setState(() {
            _serverCart = {'_id': '', 'items': []};
          });
          return;
        }

        final cart = _cartFromResponse(parsed);
        if (cart != null) {
          setState(() => _serverCart = cart);
        }
        await _fetchCart();
      } else {
        final message =
            parsed['message']?.toString() ??
            'Failed to update cart (${resp.statusCode})';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), duration: Durations.extralong1),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network error: try again'),
            duration: Durations.extralong1,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _pendingProductOps.remove(productId));
      }
    }
  }

  // ── NEW: bulk update — sends absolute quantity directly ──────────────────
  //
  // Called only from _showQuantityOptions. Sends the final computed quantity
  // to the same update-cart endpoint using a 'setQuantity' action (or whatever
  // your backend supports). Adjust the body fields to match your API contract.
  Future<void> _updateCartQuantityBulk(String productId, int newQty) async {
    if (newQty < 1) return;
    setState(() => _pendingProductOps.add(productId));

    try {
      final headers = await _buildHeaders(json: true);

      final body = <String, dynamic>{
        'customerId': widget.customerId,
        'type': widget.type,
        'employeeId': _employeeId ?? '',
        'tripId': _tripId ?? '',
        'productId': productId,
        'action': 'setQuantity', // ← adjust to your API's field/value
        'quantity': newQty, // ← the absolute new quantity
      };

      final resp = await http
          .put(
            AppConfig.u(AppConfig.updateCart),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(AppConfig.httpTimeout);

      debugPrint('Bulk update response: ${resp.body}');

      final parsed = jsonDecode(resp.body);
      if (resp.statusCode == 200) {
        final cart = _cartFromResponse(parsed);
        if (cart != null) setState(() => _serverCart = cart);
        await _fetchCart();
      } else {
        final message =
            parsed['message']?.toString() ??
            'Failed to update quantity (${resp.statusCode})';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), duration: Durations.extralong1),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Network error: try again'),
            duration: Durations.extralong1,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingProductOps.remove(productId));
    }
  }

  // ── NEW: bottom sheet with ±1 / ±10 / ±15 / custom ──────────────────────
  //
  // Shown when the user taps the quantity number badge.
  void _showQuantityOptions(
    BuildContext context,
    String productId,
    int currentQty,
  ) {
    final customCtrl = TextEditingController();

    // Preset delta options: positive = add, negative = subtract
    //const presets = <int>[-15, -10, -1, 1, 10, 15];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── header ──
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Update Quantity',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // current qty badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _accentGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _accentGreen, width: 1),
                    ),
                    child: Text(
                      'Current: $currentQty',
                      style: const TextStyle(
                        color: _accentGreen,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // ── custom input ──
              const Text(
                'Set exact quantity',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: customCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'e.g. 25',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: Colors.grey.withValues(alpha: 0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: _accentGreen,
                            width: 1.2,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: _accentGreen,
                            width: 1.2,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: _accentGreen,
                            width: 1.8,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      final parsed = int.tryParse(customCtrl.text.trim());
                      if (parsed == null || parsed < 1) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Enter a valid quantity (≥ 1)'),
                          ),
                        );
                        return;
                      }
                      Navigator.of(ctx).pop();
                      _updateCartQuantityBulk(productId, parsed);
                    },
                    child: const Text('Set'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
  // ── END NEW CODE ──────────────────────────────────────────────────────────

  Future<void> _deleteCartItem(Map<String, dynamic> item) async {
    final productId = _productIdOf(item);
    if (productId == null) return;
    setState(() => _pendingProductOps.add(productId));

    final cartId = _serverCart?['_id']?.toString();
    if (cartId == null || cartId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to delete: missing cartId')),
        );
      }
      setState(() => _pendingProductOps.remove(productId));
      return;
    }

    try {
      final headers = await _buildHeaders(json: true);
      final body = {'cartId': cartId, 'productId': productId};

      final resp = await http
          .delete(
            AppConfig.u(AppConfig.deleteCart),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(AppConfig.httpTimeout);

      final parsed = jsonDecode(resp.body);
      if (resp.statusCode == 200) {
        final cart = _cartFromResponse(parsed);
        if (cart != null) {
          setState(() => _serverCart = cart);
        }
        if (mounted) {
          final message =
              parsed['message']?.toString() ?? 'Item removed from cart.';
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
          await _fetchCart();
        }
      } else {
        final message =
            parsed['message']?.toString() ??
            'Failed to remove item (${resp.statusCode})';
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network error: try again'),
            duration: Durations.extralong1,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _pendingProductOps.remove(productId));
      }
    }
  }

  Future<void> _createOrderFromCart() async {
    if (_itemsFromServer().isEmpty) return;

    setState(() => _isPlacingOrder = true);

    try {
      final headers = await _buildHeaders(json: true);

      final body = {
        "customerId": {"id": widget.customerId, "type": widget.type},
        if (_employeeId != null && _employeeId!.isNotEmpty)
          "employeeId": _employeeId,
        if (_tripId != null && _tripId!.isNotEmpty) "tripId": _tripId,
        "items": _itemsFromServer()
            .map(
              (e) => {
                "productId": _productIdOf(e),
                "quantity": e['quantity'],
                "price": e['price'],
              },
            )
            .toList(),
        "remarks": _remarksCtrl.text.trim(),
      };

      debugPrint('ORDER BODY => ${jsonEncode(body)}');

      final resp = await http.post(
        AppConfig.u(AppConfig.createOrder),
        headers: headers,
        body: jsonEncode(body),
      );

      final parsed = jsonDecode(resp.body);

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Order placed successfully')));

        await _fetchCart();
        if (!mounted) return;

        // Set tripCompleted to false on successful order
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('tripCompleted', false);

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => OrdersScreen(condition: true)),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(parsed['message'] ?? 'Order failed')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPlacingOrder = false);
    }
  }

  String? _resolveImage(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    return AppConfig.imageUrl(raw);
  }

  @override
  Widget build(BuildContext context) {
    final items = _itemsFromServer();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context);
        return;
      },

      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              gradient: LinearGradient(
                colors: [Color(0xFF52D494), Color(0xFF1AB69C)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(24),
                ),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_sharp, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text(
                'Cart',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
          ),
        ),

        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _errorView()
              : RefreshIndicator(
                  onRefresh: _fetchCart,
                  child: items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.2,
                            ),
                            const Icon(
                              Icons.shopping_cart_outlined,
                              size: 72,
                              color: Color(0xFF1AB69C),
                            ),
                            const SizedBox(height: 12),
                            const Center(child: Text('Your cart is empty')),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24.0,
                              ),
                              child: ElevatedButton(
                                onPressed: () => _fetchCart(),
                                child: const Text(
                                  'Reload',
                                  style: TextStyle(color: Color(0xFF1AB69C)),
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: items.length + 1,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (ctx, i) {
                            if (i == items.length) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      0,
                                      8,
                                      12,
                                    ),
                                    child: TextField(
                                      controller: _remarksCtrl,
                                      maxLines: 3,
                                      decoration: InputDecoration(
                                        labelText:
                                            'Description / Requirement (Optional)',
                                        alignLabelWithHint: true,
                                        filled: true,
                                        fillColor: Colors.grey.withValues(
                                          alpha: 0.06,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFF1AB69C),
                                            width: 1.2,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFF1AB69C),
                                            width: 1.2,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFF1AB69C),
                                            width: 1.8,
                                          ),
                                        ),
                                        errorBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: Color(0xFF1AB69C),
                                            width: 1.2,
                                          ),
                                        ),
                                        focusedErrorBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: Color(0xFF1AB69C),
                                            width: 1.8,
                                          ),
                                        ),
                                        labelStyle: const TextStyle(
                                          color: _accentGreen,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Card(
                                    elevation: 1,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: const BorderSide(
                                        color: Color(0xFF1AB69C),
                                        width: 1.2,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14.0),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '$_totalItems items',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  'Total: ₹${_totalAmount.toStringAsFixed(0)}',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFF1AB69C),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          ElevatedButton(
                                            onPressed: _isPlacingOrder
                                                ? null
                                                : _createOrderFromCart,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Color(
                                                0xFF1AB69C,
                                              ),
                                              foregroundColor: Colors.white,
                                            ),
                                            child: _isPlacingOrder
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.white,
                                                        ),
                                                  )
                                                : const Text('Place Order'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }

                            final it = items[i];
                            final productId = _productIdOf(it);
                            final busy =
                                productId != null &&
                                _pendingProductOps.contains(productId);
                            final Map<String, dynamic>? productMeta = () {
                              final raw = it['productId'];
                              if (raw is Map<String, dynamic>) return raw;
                              if (raw is Map) {
                                return Map<String, dynamic>.from(raw);
                              }
                              return null;
                            }();

                            final fallbackName = productMeta != null
                                ? productMeta['productName']
                                : null;
                            final productName =
                                (it['productName'] ??
                                        fallbackName ??
                                        'Unnamed product')
                                    .toString();

                            final fallbackImage = productMeta != null
                                ? (productMeta['productImages'] is List &&
                                          productMeta['productImages']
                                              .isNotEmpty
                                      ? productMeta['productImages'][0]
                                            .toString()
                                      : null)
                                : null;
                            final rawImage =
                                it['productImage'] ??
                                fallbackImage ??
                                (productMeta != null &&
                                        productMeta['productImages'] is List &&
                                        productMeta['productImages'].isNotEmpty
                                    ? productMeta['productImages'][0].toString()
                                    : null);

                            final qty = it['quantity'];

                            final rawPrice = it['price'];
                            final priceNum = (rawPrice is num)
                                ? rawPrice.toDouble()
                                : (rawPrice is String
                                      ? double.tryParse(rawPrice) ?? 0.0
                                      : 0.0);

                            final qtyNum = (qty is num)
                                ? qty.toInt()
                                : int.tryParse(qty.toString()) ?? 0;

                            final imageUrl = _resolveImage(rawImage);

                            return Card(
                              elevation: 1,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(
                                  color: _accentGreen,
                                  width: 1.2,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(10),
                                        image: imageUrl != null
                                            ? DecorationImage(
                                                image: NetworkImage(imageUrl),
                                                fit: BoxFit.cover,
                                              )
                                            : null,
                                      ),
                                      child: imageUrl == null
                                          ? const Icon(
                                              Icons.image_not_supported,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            productName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '₹${priceNum.toStringAsFixed(0)}',
                                            style: TextStyle(
                                              color: Colors.grey.shade800,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              // ── minus button (unchanged) ──
                                              IconButton(
                                                onPressed:
                                                    busy ||
                                                        productId == null ||
                                                        qtyNum <= 1
                                                    ? null
                                                    : () => _updateCartQuantity(
                                                        productId,
                                                        'decrease',
                                                      ),
                                                icon: const Icon(Icons.remove),
                                              ),

                                              // ── CHANGED: qty number is now
                                              //    tappable → opens bulk sheet ──
                                              GestureDetector(
                                                onTap: busy || productId == null
                                                    ? null
                                                    : () =>
                                                          _showQuantityOptions(
                                                            context,
                                                            productId,
                                                            qtyNum,
                                                          ),
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: _accentGreen
                                                        .withValues(
                                                          alpha: 0.08,
                                                        ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                    border: Border.all(
                                                      color: busy
                                                          ? Colors.transparent
                                                          : _accentGreen
                                                                .withValues(
                                                                  alpha: 0.4,
                                                                ),
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        '$qtyNum',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      // small pencil hint so
                                                      // user knows it's tappable
                                                      if (!busy) ...[
                                                        const SizedBox(
                                                          width: 3,
                                                        ),
                                                        Icon(
                                                          Icons.edit,
                                                          size: 11,
                                                          color: _accentGreen
                                                              .withValues(
                                                                alpha: 0.7,
                                                              ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              // ── END CHANGED ──

                                              // ── plus button (unchanged) ──
                                              IconButton(
                                                onPressed:
                                                    busy || productId == null
                                                    ? null
                                                    : () => _updateCartQuantity(
                                                        productId,
                                                        'increase',
                                                      ),
                                                icon: const Icon(Icons.add),
                                              ),
                                              if (busy)
                                                const Padding(
                                                  padding: EdgeInsets.only(
                                                    left: 8.0,
                                                  ),
                                                  child: SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  ),
                                                ),
                                              const Spacer(),
                                              TextButton.icon(
                                                onPressed:
                                                    busy || productId == null
                                                    ? null
                                                    : () => _deleteCartItem(it),
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 22,
                                                ),
                                                label: const Text(''),
                                                style: TextButton.styleFrom(
                                                  foregroundColor: Color(
                                                    0xFF1AB69C,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _fetchCart,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandGreen,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
