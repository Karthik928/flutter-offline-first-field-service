import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/Screens/cart_screen.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';
import 'package:FieldService_app/models/product.dart';

class ProductDescriptionScreen extends StatefulWidget {
  final Product product;
  final double price;
  final String imageBase;
  final Color brandGreen;
  final void Function(Product, {int qty}) onAddToCart;
  final Map<String, CartItem> cart;
  final double Function(Product) priceFor;

  // Optional callbacks so parent can react to cart changes (avoids relying only on direct map mutation)
  final void Function(String id, int qty)? onUpdateCart;
  final void Function(String id)? onRemoveFromCart;
  final VoidCallback? onClearCart;

  final String? customerId;
  final String type;
  //final bool condition;
  final String? unit;
  final int? unitValue;

  const ProductDescriptionScreen({
    super.key,
    required this.product,
    required this.price,
    required this.imageBase,
    required this.brandGreen,
    required this.onAddToCart,
    required this.cart,
    required this.priceFor,
    this.customerId,
    required this.type,
    //required this.condition,
    this.unit,
    this.unitValue,
    this.onUpdateCart,
    this.onRemoveFromCart,
    this.onClearCart,
  });

  @override
  State<ProductDescriptionScreen> createState() =>
      _ProductDescriptionScreenState();
}

class _ProductDescriptionScreenState extends State<ProductDescriptionScreen> {
  int qty = 1;

  Map<String, CartItem> _localCart = {};
  bool _isAddingToCart = false;

  late Future<Box> _imageBoxFuture;

  @override
  void initState() {
    super.initState();
    _localCart = Map<String, CartItem>.from(widget.cart);
    _imageBoxFuture = Hive.openBox('image_cache');
  }

  Uint8List? _getCachedImageBytes(Box box, String imageName) {
    final v = box.get(imageName);
    if (v is Uint8List) return v;
    if (v is List<int>) return Uint8List.fromList(v);
    return null;
  }

  Future<Uint8List?> _fetchAndCacheImage(Box box, String imageName) async {
    try {
      final uri = Uri.parse(AppConfig.imageUrl(imageName));
      debugPrint("🖼 IMAGE URL = $uri");

      final res = await http.get(uri).timeout(AppConfig.httpTimeout);
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        await box.put(imageName, res.bodyBytes);
        debugPrint("✅ Image cached: $imageName");
        return res.bodyBytes;
      } else {
        debugPrint("❌ Image fetch failed (${res.statusCode}): $imageName");
      }
    } catch (e) {
      debugPrint("❌ Image fetch error: $e");
    }
    return null;
  }

  Future<Uint8List?> _loadImageBytes(Box box, String imageName) async {
    final cached = _getCachedImageBytes(box, imageName);
    if (cached != null && cached.isNotEmpty) return cached;
    return await _fetchAndCacheImage(box, imageName);
  }

  Widget _buildUnifiedProductImage(Product p) {
    final String? imagePath = p.imagePath;
    if (imagePath == null || imagePath.isEmpty || imagePath == 'null') {
      return _imagePlaceholder();
    }

    return FutureBuilder<Box>(
      future: _imageBoxFuture,
      builder: (context, boxSnap) {
        if (!boxSnap.hasData) {
          return _loadingImage();
        }

        final box = boxSnap.data!;

        return FutureBuilder<Uint8List?>(
          future: _loadImageBytes(box, imagePath),
          builder: (context, snap) {
            // Image loaded successfully
            if (snap.hasData && snap.data != null) {
              return Image.memory(
                snap.data!,
                width: 220,
                height: 300,
                fit: BoxFit.cover,
              );
            }

            // Connection complete but no data = failed to load
            if (snap.connectionState == ConnectionState.done) {
              debugPrint("⚠️ Image load completed but no data for: $imagePath");
              return _imagePlaceholder();
            }

            // Still loading
            return _loadingImage();
          },
        );
      },
    );
  }

  Widget _loadingImage() {
    return Container(
      width: 220,
      height: 300,
      color: Colors.grey[200],
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  void _openCartScreen() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => CartScreen(
              customerId: widget.customerId ?? '',
              type: widget.type,
              //condition: widget.condition,
            ),
          ),
        )
        .then((_) {
          // Re-sync cart from server so the bottom bar reflects correct qty & totals
          _refreshCartFromServer();
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            gradient: LinearGradient(
              colors: [
                Color(0xFF52D494), // top
                Color(0xFF1AB69C), // bottom
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_sharp, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              widget.product.productName ?? 'Product Details',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 20,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),

      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 🖼️ Image
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Center(
                        // 👈 centers the image inside
                        child:
                            (widget.product.imagePath != null &&
                                widget.product.imagePath!.isNotEmpty &&
                                widget.product.imagePath != 'null')
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Center(
                                  child: _buildUnifiedProductImage(
                                    widget.product,
                                  ),
                                ),
                              )
                            : _imagePlaceholder(),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title
                    Text(
                      widget.product.productName ?? "Unnamed Product",
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                        color: Color(0xFF1AB69C),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Category + Price
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Chip(
                          label: Text(
                            widget.product.category ?? 'General',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          backgroundColor: Colors.white,
                          labelStyle: TextStyle(color: widget.brandGreen),
                        ),

                        const Spacer(),

                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₹${widget.priceFor(widget.product).toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: Color(0xFF1AB69C),
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),

                            // ✅ UNIT DISPLAY
                            if (widget.unit != null || widget.unitValue != null)
                              Text(
                                '${widget.unitValue ?? ''} ${widget.unit ?? ''}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // Replace the existing Row(...) that contains the quantity selector + Add button
                    Row(
                      children: [
                        // const Text(
                        //   "Quantity",
                        //   style: TextStyle(fontWeight: FontWeight.w600),
                        // ),
                        const SizedBox(width: 20),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove),
                                onPressed: () =>
                                    setState(() => qty = qty > 1 ? qty - 1 : 1),
                              ),
                              Text(
                                qty.toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add),
                                onPressed: () => setState(() => qty++),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),

                        // ---------- Conditional button: Add to Cart OR Go to Cart ----------
                        Builder(
                          builder: (ctx) {
                            final id = widget.product.id;
                            final inCart =
                                id != null && _localCart.containsKey(id);

                            if (id == null) {
                              return ElevatedButton(
                                onPressed: null,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                ),
                                child: const Text('Unavailable'),
                              );
                            }

                            if (!inCart) {
                              return ElevatedButton.icon(
                                onPressed: _isAddingToCart
                                    ? null
                                    : () async {
                                        if ((widget.customerId ?? '').isEmpty) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).clearSnackBars();

                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                "Select a Dealer/Farmer. ",
                                              ),
                                              backgroundColor: Colors.red,
                                              duration: Duration(seconds: 2),
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                          return;
                                        }

                                        setState(() => _isAddingToCart = true);

                                        await _addToCartApi(
                                          widget.product,
                                          qty,
                                        );

                                        if (mounted) {
                                          setState(
                                            () => _isAddingToCart = false,
                                          );
                                        }
                                      },
                                icon: _isAddingToCart
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.add_shopping_cart_outlined,
                                      ),
                                label: Text(
                                  _isAddingToCart ? "Adding..." : "Add to Cart",
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color(0xFF1AB69C),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                ),
                              );
                            }

                            // Go to Cart button when item is already in cart
                            return ElevatedButton.icon(
                              onPressed: () {
                                if ((widget.customerId ?? '').isEmpty) {
                                  ScaffoldMessenger.of(
                                    context,
                                  ).clearSnackBars();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Select Dealer/Farmer."),
                                      backgroundColor: Colors.red,
                                      duration: Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                  return;
                                }

                                _openCartScreen();
                              },
                              icon: const Icon(Icons.shopping_cart),
                              label: const Text('Go to Cart'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orangeAccent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 25),

                    // Description
                    Text(
                      "Description:",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: Colors.grey[900],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Html(
                      data:
                          (widget.product.longDescription?.isNotEmpty ?? false)
                          ? widget.product.longDescription!
                          : (widget.product.shortDescription?.isNotEmpty ??
                                false)
                          ? widget.product.shortDescription!
                          : "No description available for this product.",
                      style: {
                        "body": Style(
                          //textAlign: TextAlign.left,
                          fontSize: FontSize(14),
                          color: Colors.grey[800],
                          lineHeight: LineHeight(1.5),
                        ),
                        "p": Style(margin: Margins.only(bottom: 8)),
                      },
                    ),
                    // Quantity + Add Button
                    //const SizedBox(height: 50),
                  ],
                ),
              ),
            ),

            //✅ Bottom Cart Bar
            // if (_localCart.isNotEmpty)
            //   SafeArea(
            //     child: Container(
            //       margin: const EdgeInsets.all(12),
            //       padding: const EdgeInsets.symmetric(
            //         horizontal: 14,
            //         vertical: 12,
            //       ),
            //       decoration: BoxDecoration(
            //         color: Colors.white,
            //         borderRadius: BorderRadius.circular(12),
            //         boxShadow: [
            //           BoxShadow(
            //             color: Colors.black.withValues(alpha: 0.06),
            //             blurRadius: 12,
            //             offset: const Offset(0, 6),
            //           ),
            //         ],
            //       ),
            //       child: Row(
            //         children: [
            //           const Icon(Icons.shopping_cart, size: 28),
            //           const SizedBox(width: 12),
            //           Expanded(
            //             child: Text(
            //               '$_cartCount items • ₹${_cartTotal.toStringAsFixed(0)}',
            //               style: const TextStyle(fontWeight: FontWeight.w700),
            //             ),
            //           ),
            //           ElevatedButton(
            //             onPressed: _openCartScreen,
            //             style: ElevatedButton.styleFrom(
            //               backgroundColor: widget.brandGreen,
            //               foregroundColor: Colors.white,
            //             ),
            //             child: const Text('View Cart'),
            //           ),
            //         ],
            //       ),
            //     ),
            //   ),
          ],
        ),
      ),
    );
  }

  Future<void> _addToCartApi(Product p, int qty) async {
    if (p.id == null) return;

    debugPrint("➡️ ADD TO CART: ${p.productName} x $qty");

    final prefs = await SharedPreferences.getInstance();
    final employeeId = prefs.getString('userId') ?? '';
    final tripId = prefs.getString('currentTripId');
    //final token = prefs.getString('token');
    final token = await SecureStorageService.getToken();
    final Map<String, dynamic> body = {
      "customerId": {"id": widget.customerId, "type": widget.type},
      "employeeId": employeeId,
      "productId": p.id!,
      "quantity": qty,
      "price": widget.priceFor(p).toInt(),
      "productName": p.productName ?? "",
      "image": p.imagePath ?? "",
    };

    // Only add tripId if valid
    if (tripId != null && tripId.isNotEmpty) {
      body["tripId"] = tripId;
    }

    debugPrint("📤 ADD CART BODY: ${jsonEncode(body)}");

    final headers = {
      "Accept": "application/json",
      "Content-Type": "application/json",
      if (token != null && token.isNotEmpty) "Authorization": "Bearer $token",
    };

    final uri = AppConfig.u(AppConfig.addToCart);
    debugPrint("📡 POST → $uri");

    try {
      final resp = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(AppConfig.httpTimeout);

      debugPrint("📥 ADD RESPONSE CODE: ${resp.statusCode}");
      debugPrint("📥 ADD RESPONSE BODY: ${resp.body}");

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        //await _refreshCartFromServer();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('product Added successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );

        final addedCart = jsonDecode(resp.body)['cart'];
        if (addedCart != null) {
          _applyServerCart(addedCart);
        }

        setState(() {});
      } else {
        debugPrint("❌ Add failed ${resp.statusCode}");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('failed to add to cart'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint("🔥 AddToCart Exception: $e");
    }
  }

  void _applyServerCart(Map<String, dynamic> cart) {
    debugPrint("🔄 APPLY ADD RESPONSE CART");

    final items = cart['items'] as List<dynamic>? ?? [];

    setState(() {
      _localCart.clear();

      for (final it in items) {
        if (it is! Map) continue;
        final m = Map<String, dynamic>.from(it);

        String? id;
        final productField = m['productId'];

        if (productField is String) {
          id = productField;
        } else if (productField is Map) {
          id = productField['_id']?.toString();
        }

        if (id == null) continue;

        _localCart[id] = CartItem(
          product: Product(
            id: id,
            productName: productField['productName'] ?? "",
            shortDescription: productField['shortDescription'] ?? "",
            productImage: productField['productImage'] ?? "",
            category: "",
            longDescription: "",
            productPrice:
                double.tryParse(
                  (productField['productPrice'] ?? '0').toString(),
                ) ??
                0.0,
            isActive: null,
          ),
          qty: int.tryParse(m['quantity'].toString()) ?? 1,
        );
      }
    });
  }

  Future<void> _refreshCartFromServer() async {
    debugPrint("🔄 Refreshing Cart From Server...");

    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getString('userId') ?? '';
      //final token = prefs.getString('token');
      final token = await SecureStorageService.getToken();
      final uri = AppConfig.u(
        AppConfig.fill(AppConfig.getCart, {'employeeid': employeeId}),
      );

      debugPrint("📡 GET CART → $uri");

      final resp = await http.get(
        uri,
        headers: {
          "Accept": "application/json",
          if (token != null && token.isNotEmpty)
            "Authorization": "Bearer $token",
        },
      );

      debugPrint("📥 CART RESPONSE CODE: ${resp.statusCode}");
      debugPrint("📥 CART RESPONSE BODY RAW: ${resp.body}");

      if (resp.statusCode != 200) return;

      final raw = jsonDecode(resp.body);
      debugPrint("📥 CART DECODED: $raw");

      Map<String, dynamic> cart;
      if (raw['cart'] is Map) {
        cart = Map<String, dynamic>.from(raw['cart']);
      } else if (raw['data'] is Map) {
        cart = Map<String, dynamic>.from(raw['data']);
      } else {
        cart = Map<String, dynamic>.from(raw);
      }

      debugPrint("👜 CART ITEMS: ${cart['items']}");

      final items = cart['items'] as List<dynamic>? ?? [];

      setState(() {
        _localCart.clear();
        for (final it in items) {
          debugPrint("📦 ITEM: $it");

          final map = Map<String, dynamic>.from(it);
          String? id;

          if (map['productId'] is String) {
            id = map['productId'];
          } else if (map['productId'] is Map) {
            final meta = Map<String, dynamic>.from(map['productId']);
            id = meta['_id']?.toString();
          }

          if (id == null) continue;

          final prod = Product(
            id: id,
            productName: map['productName'] ?? '',
            shortDescription: '',
            longDescription: '',
            category: '',
            productImage: map['image'] ?? '',
            isActive: null,
            productPrice: double.tryParse(map['price'].toString()) ?? 0,
          );

          _localCart[id] = CartItem(
            product: prod,
            qty: int.tryParse(map['quantity'].toString()) ?? 1,
          );
        }
      });

      debugPrint("✅ LOCAL CART UPDATED: $_localCart");
    } catch (e) {
      debugPrint("🔥 Cart refresh error: $e");
    }
  }

  Widget _imagePlaceholder() {
    return Container(
      width: double.infinity,
      height: 260,
      color: Colors.grey[200],
      child: Center(
        child: Icon(
          Icons.image_not_supported,
          size: 60,
          color: Colors.grey[400],
        ),
      ),
    );
  }
}
