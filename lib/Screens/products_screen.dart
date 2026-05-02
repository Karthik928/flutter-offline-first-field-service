// lib/Screens/products_screen_improved.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:FieldService_app/Screens/cart_screen.dart';

import 'package:FieldService_app/Screens/product_description_screen.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/offline/cache_store.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';
import 'package:FieldService_app/models/product.dart';
import 'package:FieldService_app/zonal_services/zonal_customer_service.dart';

const Color _brandGreen = Color(0xFF1AB69C);
const Color _brandGreenDark = Color(0xFF0D9A84);
const Color _brandGreenLight = Color(0xFFE6FAF7);
const Color _surfaceColor = Color(0xFFF6F8FA);

// ─────────────────────────────────────────────────────────────────
// SharedPreferences cache keys
// ─────────────────────────────────────────────────────────────────
const _kCacheDealers = 'cache_dealers_list';
const _kCacheFarmers = 'cache_farmers_list';
const _kCacheZonalCustomers = 'cache_zonal_customers_list';

// ─────────────────────────────────────────────────────────────────
// Customer Model
// ─────────────────────────────────────────────────────────────────

class CustomerItem {
  final String id;
  final String name;
  final String subName;
  final String mobile;
  final String type; // 'dealer' or 'farmer'
  final String? image;
  final String? customerId;

  /// Only populated for zonal-manager flow — the employee's name
  final String? employeeName;

  const CustomerItem({
    required this.id,
    required this.name,
    required this.subName,
    required this.mobile,
    required this.type,
    this.image,
    this.customerId,
    this.employeeName,
  });

  // ── Regular employee flow ────────────────────────────────────────

  factory CustomerItem.fromDealerJson(Map<String, dynamic> json) {
    return CustomerItem(
      id: json['_id']?.toString() ?? '',
      name: json['dealerName']?.toString() ?? 'Unknown Dealer',
      subName: json['shopName']?.toString() ?? '',
      mobile: json['mobileNumber']?.toString() ?? '',
      type: 'dealer',
      image: json['dealerImage']?.toString(),
      customerId: json['dealerId']?.toString(),
    );
  }

  factory CustomerItem.fromFarmerJson(Map<String, dynamic> json) {
    return CustomerItem(
      id: json['_id']?.toString() ?? '',
      name:
          json['farmerName']?.toString() ??
          json['name']?.toString() ??
          'Unknown Farmer',
      subName:
          json['farmName']?.toString() ??
          json['villageName']?.toString() ??
          json['farmAddress']?.toString() ??
          '',
      mobile: json['mobileNumber']?.toString() ?? '',
      type: 'farmer',
      image: json['farmerImage']?.toString() ?? json['image']?.toString(),
      customerId: json['farmerId']?.toString() ?? json['_id']?.toString(),
    );
  }

  // ── Zonal manager flow — from ZonalCustomer ──────────────────────

  factory CustomerItem.fromZonalCustomer(ZonalCustomer z) {
    return CustomerItem(
      id: z.id,
      name: z.name,
      subName: z.type == 'dealer'
          ? (z.shopName ?? z.address ?? '')
          : (z.address ?? ''),
      mobile: z.phone,
      type: z.type,
      customerId: z.id,
      employeeName: z.employeeName, // ✅ ADD THIS
    );
  }

  // ── JSON serialization for offline caching ───────────────────────

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'subName': subName,
    'mobile': mobile,
    'type': type,
    'image': image,
    'customerId': customerId,
    'employeeName': employeeName,
  };

  factory CustomerItem.fromCacheJson(Map<String, dynamic> json) {
    return CustomerItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      subName: json['subName']?.toString() ?? '',
      mobile: json['mobile']?.toString() ?? '',
      type: json['type']?.toString() ?? 'dealer',
      image: json['image']?.toString(),
      customerId: json['customerId']?.toString(),
      employeeName: json['employeeName']?.toString(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Offline cache helper (SharedPreferences-based for customer lists)
// ─────────────────────────────────────────────────────────────────

class _CustomerCache {
  static Future<void> saveList(String key, List<CustomerItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
      await prefs.setString(key, encoded);
    } catch (_) {}
  }

  static Future<List<CustomerItem>?> loadList(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(CustomerItem.fromCacheJson)
          .toList();
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────────────

class ProductsScreen extends StatefulWidget {
  final String? customerId;
  final String type;
  final bool condition;

  const ProductsScreen({
    super.key,
    this.customerId,
    required this.type,
    required this.condition,
  });

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen>
    with SingleTickerProviderStateMixin {
  // ─── Core State ───────────────────────────────────────────────
  final ValueNotifier<bool> _isLoadingNotifier = ValueNotifier(false);
  final ValueNotifier<String?> _errorNotifier = ValueNotifier(null);
  final ValueNotifier<List<Product>> _productsNotifier = ValueNotifier([]);
  final ValueNotifier<String> _searchNotifier = ValueNotifier('');
  final Map<String, CartItem> _cart = {};
  late final AnimationController _animController;
  final CacheStore _cache = CacheStore();
  late Box _imageBox;

  // ─── Filter State ─────────────────────────────────────────────
  String? _selectedCategoryId;
  String? _selectedSubCategoryId;
  String? _selectedChildCategoryId;
  List<ProductCategory> _categories = [];
  bool _categoriesLoading = false;
  String? _categoriesError;
  List<ProductCategory> _subcategories = [];
  bool _subcategoriesLoading = false;
  String? _subcategoriesError;
  List<ProductCategory> _childCategories = [];
  bool _childCategoriesLoading = false;
  String? _childCategoriesError;

  // ─── Customer State ───────────────────────────────────────────
  CustomerItem? _selectedCustomer;
  List<CustomerItem> _dealers = [];
  List<CustomerItem> _farmers = [];
  bool _dealersLoading = false;
  bool _farmersLoading = false;
  String? _dealersError;
  String? _farmersError;

  // ─── Zonal Manager Flag ───────────────────────────────────────
  bool _isZonalManager = false;

  final TextEditingController _searchController = TextEditingController();
  List<Product> get _products => _productsNotifier.value;

  String get _effectiveCustomerId =>
      _selectedCustomer?.id ?? widget.customerId ?? '';

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _init();
  }

  Future<void> _init() async {
    await Hive.initFlutter();
    await _cache.init();
    _imageBox = await Hive.openBox('image_cache');

    // Load zonal flag FIRST — other fetches depend on it
    await _loadPrefs();

    await Future.wait([
      _fetchCategories(),
      _fetchProducts(),
      _fetchCustomers(),
    ]);
    await _syncCartFromServer();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isZonalManager = prefs.getBool('isZonalManager') ?? false;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animController.dispose();
    _productsNotifier.dispose();
    _searchNotifier.dispose();
    _isLoadingNotifier.dispose();
    _errorNotifier.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _buildHeaders() async {
    final token = await SecureStorageService.getToken();
    return {
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  String get _effectiveType {
    if (widget.type == "Other") {
      if (_selectedCustomer?.type == 'dealer') return "Dealer";
      if (_selectedCustomer?.type == 'farmer') return "Farmer";
      return "Other";
    }
    return widget.type;
  }

  // ─────────────────────────────────────────────────────────────────
  // Customer Fetching — routes based on _isZonalManager
  // ─────────────────────────────────────────────────────────────────

  Future<void> _fetchCustomers() async {
    if (_isZonalManager) {
      await _fetchZonalCustomers();
    } else {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getString('userId') ?? '';
      if (employeeId.isEmpty) return;
      await Future.wait([_fetchDealers(employeeId), _fetchFarmers(employeeId)]);
    }
  }

  // ── Zonal: single endpoint, split by type ──────────────────────

  Future<void> _fetchZonalCustomers() async {
    if (!mounted) return;
    setState(() {
      _dealersLoading = true;
      _farmersLoading = true;
      _dealersError = null;
      _farmersError = null;
    });

    // Try to pre-populate from cache for instant UI
    final cachedZonal = await _CustomerCache.loadList(_kCacheZonalCustomers);
    if (cachedZonal != null && mounted) {
      _applyZonalSplit(cachedZonal);
    }

    try {
      final service = ZonalCustomerService();
      final result = await service.fetchCustomers().timeout(
        const Duration(seconds: 15),
      );

      if (!mounted) return;

      if (!result.success) {
        final err = result.error ?? 'Failed to load customers';
        // If cache already populated, don't flash an error
        if (cachedZonal == null || cachedZonal.isEmpty) {
          setState(() {
            _dealersError = err;
            _farmersError = err;
          });
        }
        return;
      }

      final items = result.customers
          .map(CustomerItem.fromZonalCustomer)
          .toList();

      // Persist to cache
      await _CustomerCache.saveList(_kCacheZonalCustomers, items);

      if (mounted) _applyZonalSplit(items);
    } on Exception catch (e) {
      debugPrint('[ZonalCustomers] error: $e');
      if (!mounted) return;
      // Only show error if we have nothing to show
      if (_dealers.isEmpty && _farmers.isEmpty) {
        final errMsg = 'Network error — showing cached data if available';
        setState(() {
          _dealersError = errMsg;
          _farmersError = errMsg;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _dealersLoading = false;
          _farmersLoading = false;
        });
      }
    }
  }

  void _applyZonalSplit(List<CustomerItem> items) {
    if (!mounted) return;
    setState(() {
      _dealers = items.where((c) => c.type == 'dealer').toList();
      _farmers = items.where((c) => c.type == 'farmer').toList();
    });
  }

  // ── Regular employee: separate dealer / farmer endpoints ─────────

  Future<void> _fetchDealers(String employeeId) async {
    if (!mounted) return;
    setState(() {
      _dealersLoading = true;
      _dealersError = null;
    });

    // Pre-populate from cache
    final cached = await _CustomerCache.loadList(_kCacheDealers);
    if (cached != null && mounted) {
      setState(() => _dealers = cached);
    }

    try {
      final headers = await _buildHeaders();
      final uri = AppConfig.u('/api/dealers/employee/$employeeId');
      final resp = await http
          .get(uri, headers: headers)
          .timeout(AppConfig.httpTimeout);

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        if (body is Map && body['dealers'] is List) {
          final dealers = (body['dealers'] as List)
              .map(
                (e) =>
                    CustomerItem.fromDealerJson(Map<String, dynamic>.from(e)),
              )
              .toList();
          await _CustomerCache.saveList(_kCacheDealers, dealers);
          if (mounted) setState(() => _dealers = dealers);
        }
      } else {
        // Keep cached data visible; only show error if nothing cached
        if (_dealers.isEmpty) {
          setState(
            () => _dealersError = 'Failed to load dealers (${resp.statusCode})',
          );
        }
      }
    } on Exception catch (e) {
      debugPrint('[Dealers] error: $e');
      if (mounted && _dealers.isEmpty) {
        setState(
          () => _dealersError = 'Network error — no cached data available',
        );
      }
    } finally {
      if (mounted) setState(() => _dealersLoading = false);
    }
  }

  Future<void> _fetchFarmers(String employeeId) async {
    if (!mounted) return;
    setState(() {
      _farmersLoading = true;
      _farmersError = null;
    });

    // Pre-populate from cache
    final cached = await _CustomerCache.loadList(_kCacheFarmers);
    if (cached != null && mounted) {
      setState(() => _farmers = cached);
    }

    try {
      final headers = await _buildHeaders();
      final uri = AppConfig.u('/api/farmers/employee/$employeeId');
      final resp = await http
          .get(uri, headers: headers)
          .timeout(AppConfig.httpTimeout);

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        if (body is Map && body['farmers'] is List) {
          final farmers = (body['farmers'] as List)
              .map(
                (e) =>
                    CustomerItem.fromFarmerJson(Map<String, dynamic>.from(e)),
              )
              .toList();
          await _CustomerCache.saveList(_kCacheFarmers, farmers);
          if (mounted) setState(() => _farmers = farmers);
        }
      } else {
        if (_farmers.isEmpty) {
          setState(
            () => _farmersError = 'Failed to load farmers (${resp.statusCode})',
          );
        }
      }
    } on Exception catch (e) {
      debugPrint('[Farmers] error: $e');
      if (mounted && _farmers.isEmpty) {
        setState(
          () => _farmersError = 'Network error — no cached data available',
        );
      }
    } finally {
      if (mounted) setState(() => _farmersLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Category / Product Fetching (unchanged logic)
  // ─────────────────────────────────────────────────────────────────

  Future<void> _fetchCategories() async {
    if (!mounted) return;
    setState(() {
      _categoriesLoading = true;
      _categoriesError = null;
    });
    const cacheKey = 'categories';
    final uri = AppConfig.u(AppConfig.apiCategories);
    try {
      final headers = await _buildHeaders();
      final resp = await http
          .get(uri, headers: headers)
          .timeout(AppConfig.httpTimeout);
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        if (body is Map<String, dynamic> && body['data'] is List) {
          final dataList = body['data'] as List;
          _categories = dataList.map((e) {
            if (e is Map<String, dynamic>) return ProductCategory.fromJson(e);
            return ProductCategory.fromJson(
              Map<String, dynamic>.from(e as Map),
            );
          }).toList();
          await _cache.put(
            cacheKey,
            CacheEntry(
              body: jsonEncode(body['data']),
              storedAtMillis: DateTime.now().millisecondsSinceEpoch,
              statusCode: resp.statusCode,
            ),
          );
          _categoriesError = null;
        } else {
          _categoriesError = 'Unexpected categories response.';
        }
      } else {
        _categoriesError = 'Server error (${resp.statusCode}).';
      }
    } catch (e) {
      final cached = _cache.get(cacheKey);
      if (cached != null && cached.body.isNotEmpty) {
        try {
          final data = jsonDecode(cached.body) as List;
          _categories = data
              .map(
                (e) => ProductCategory.fromJson(
                  e is Map ? Map<String, dynamic>.from(e) : e,
                ),
              )
              .toList();
          _categoriesError = null;
        } catch (_) {
          _categoriesError = 'Failed to parse cached categories.';
        }
      } else {
        _categoriesError = 'Network error: $e';
      }
    } finally {
      setState(() => _categoriesLoading = false);
    }
  }

  Future<void> _refreshProducts() async {
    await _fetchProducts(
      categoryId: _selectedCategoryId,
      subCategoryId: _selectedSubCategoryId,
      childCategoryId: _selectedChildCategoryId,
    );
  }

  Future<void> _onCategorySelected(String? categoryId) async {
    if (!mounted) return;
    setState(() {
      _selectedCategoryId = categoryId;
      _selectedSubCategoryId = null;
      _selectedChildCategoryId = null;
      _subcategories = [];
      _childCategories = [];
      _subcategoriesError = null;
      _childCategoriesError = null;
    });
    if (categoryId != null && categoryId.isNotEmpty) {
      await _fetchSubcategories(categoryId);
    }
    await _fetchProducts(categoryId: categoryId);
  }

  Future<void> _onSubCategorySelected(String? subCategoryId) async {
    if (!mounted) return;
    setState(() {
      _selectedSubCategoryId = subCategoryId;
      _selectedChildCategoryId = null;
      _childCategories = [];
      _childCategoriesError = null;
    });
    if (subCategoryId != null &&
        subCategoryId.isNotEmpty &&
        _selectedCategoryId != null) {
      await _fetchChildCategories(_selectedCategoryId!, subCategoryId);
    }
    await _fetchProducts(
      categoryId: _selectedCategoryId,
      subCategoryId: subCategoryId,
    );
  }

  Future<void> _onChildCategorySelected(String? childCategoryId) async {
    if (!mounted) return;
    setState(() => _selectedChildCategoryId = childCategoryId);
    await _fetchProducts(
      categoryId: _selectedCategoryId,
      subCategoryId: _selectedSubCategoryId,
      childCategoryId: childCategoryId,
    );
  }

  Future<void> _fetchProducts({
    String? categoryId,
    String? subCategoryId,
    String? childCategoryId,
  }) async {
    if (!mounted) return;
    _isLoadingNotifier.value = true;
    _errorNotifier.value = null;
    final isAll = categoryId == null || categoryId.isEmpty;
    final cacheKey = isAll
        ? 'products_all'
        : (childCategoryId != null && childCategoryId.isNotEmpty)
        ? 'products_cat_$categoryId*sub*$subCategoryId*child*$childCategoryId'
        : (subCategoryId != null && subCategoryId.isNotEmpty)
        ? 'products_cat_$categoryId*sub*$subCategoryId'
        : 'products_cat_$categoryId';
    final uri = isAll
        ? AppConfig.u(AppConfig.apiProducts)
        : (childCategoryId != null && childCategoryId.isNotEmpty)
        ? AppConfig.u(
            AppConfig.fill(AppConfig.productsByChildCategoriesId, {
              'id': categoryId,
              'subid': subCategoryId!,
              'childid': childCategoryId,
            }),
          )
        : (subCategoryId != null && subCategoryId.isNotEmpty)
        ? AppConfig.u(
            AppConfig.fill(AppConfig.productsBySubCategoriesId, {
              'id': categoryId,
              'subid': subCategoryId,
            }),
          )
        : AppConfig.u(
            AppConfig.fill(AppConfig.productsByCategoriesId, {
              'id': categoryId,
            }),
          );
    try {
      final headers = await _buildHeaders();
      final resp = await http
          .get(uri, headers: headers)
          .timeout(AppConfig.httpTimeout);
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        if (body is Map<String, dynamic> && body['data'] is List) {
          final products = (body['data'] as List)
              .map((e) => Product.fromJson(e))
              .toList();
          _productsNotifier.value = products;
          await _cache.put(
            cacheKey,
            CacheEntry(
              body: jsonEncode(body['data']),
              storedAtMillis: DateTime.now().millisecondsSinceEpoch,
              statusCode: resp.statusCode,
            ),
          );
          for (final p in products) {
            final image = p.imagePath;
            if (image != null && image.isNotEmpty && image != 'null') {
              _cacheImageIfAbsent(image);
            }
          }
          _errorNotifier.value = null;
        } else {
          _errorNotifier.value = 'Unexpected response format';
        }
      } else {
        _errorNotifier.value = 'Server error (${resp.statusCode})';
      }
    } catch (e) {
      final cached = _cache.get(cacheKey);
      if (cached != null && cached.body.isNotEmpty) {
        final data = jsonDecode(cached.body) as List;
        _productsNotifier.value = data
            .map((e) => Product.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _errorNotifier.value = null;
      } else {
        _errorNotifier.value = 'No internet & no cached data';
      }
    } finally {
      _isLoadingNotifier.value = false;
      _animController.forward(from: 0);
    }
  }

  Future<void> _fetchSubcategories(String categoryId) async {
    if (!mounted) return;
    setState(() {
      _subcategoriesLoading = true;
      _subcategoriesError = null;
    });
    final cacheKey = 'subcategories_$categoryId';
    final uri = AppConfig.u(
      AppConfig.fill(AppConfig.apiSubCategories, {'id': categoryId}),
    );
    try {
      final headers = await _buildHeaders();
      final resp = await http
          .get(uri, headers: headers)
          .timeout(AppConfig.httpTimeout);
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        if (body is Map<String, dynamic> && body['data'] is List) {
          _subcategories = (body['data'] as List).map((e) {
            if (e is Map<String, dynamic>) return ProductCategory.fromJson(e);
            return ProductCategory.fromJson(
              Map<String, dynamic>.from(e as Map),
            );
          }).toList();
          await _cache.put(
            cacheKey,
            CacheEntry(
              body: jsonEncode(body['data']),
              storedAtMillis: DateTime.now().millisecondsSinceEpoch,
              statusCode: resp.statusCode,
            ),
          );
          _subcategoriesError = null;
        }
      }
    } catch (e) {
      final cached = _cache.get(cacheKey);
      if (cached != null && cached.body.isNotEmpty) {
        try {
          final data = jsonDecode(cached.body) as List;
          _subcategories = data
              .map(
                (e) => ProductCategory.fromJson(
                  e is Map ? Map<String, dynamic>.from(e) : e,
                ),
              )
              .toList();
          _subcategoriesError = null;
        } catch (_) {
          _subcategoriesError = 'Failed to parse cached subcategories.';
        }
      } else {
        _subcategoriesError = 'Network error';
      }
    } finally {
      setState(() => _subcategoriesLoading = false);
    }
  }

  Future<void> _fetchChildCategories(
    String categoryId,
    String subCategoryId,
  ) async {
    if (!mounted) return;
    setState(() {
      _childCategoriesLoading = true;
      _childCategoriesError = null;
    });
    final cacheKey = 'childcategories_${categoryId}_$subCategoryId';
    final uri = AppConfig.u(
      AppConfig.fill(AppConfig.apiChildCategories, {
        'id': categoryId,
        'subid': subCategoryId,
      }),
    );
    try {
      final headers = await _buildHeaders();
      final resp = await http
          .get(uri, headers: headers)
          .timeout(AppConfig.httpTimeout);
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        if (body is Map<String, dynamic> && body['data'] is List) {
          _childCategories = (body['data'] as List).map((e) {
            if (e is Map<String, dynamic>) return ProductCategory.fromJson(e);
            return ProductCategory.fromJson(
              Map<String, dynamic>.from(e as Map),
            );
          }).toList();
          await _cache.put(
            cacheKey,
            CacheEntry(
              body: jsonEncode(body['data']),
              storedAtMillis: DateTime.now().millisecondsSinceEpoch,
              statusCode: resp.statusCode,
            ),
          );
          _childCategoriesError = null;
        }
      }
    } catch (e) {
      final cached = _cache.get(cacheKey);
      if (cached != null && cached.body.isNotEmpty) {
        try {
          final data = jsonDecode(cached.body) as List;
          _childCategories = data
              .map(
                (e) => ProductCategory.fromJson(
                  e is Map ? Map<String, dynamic>.from(e) : e,
                ),
              )
              .toList();
          _childCategoriesError = null;
        } catch (_) {
          _childCategoriesError = 'Failed to parse cached child categories.';
        }
      } else {
        _childCategoriesError = 'Network error';
      }
    } finally {
      setState(() => _childCategoriesLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Image Helpers
  // ─────────────────────────────────────────────────────────────────

  Uint8List? _getCachedImageBytes(String imageName) {
    try {
      final v = _imageBox.get(imageName);
      if (v is Uint8List) return v;
      if (v is List<int>) return Uint8List.fromList(v);
    } catch (_) {}
    return null;
  }

  Future<Uint8List?> _fetchAndCacheImage(String imageName) async {
    try {
      final uri = AppConfig.u(AppConfig.imageUrl(imageName));
      final res = await http.get(uri).timeout(AppConfig.httpTimeout);
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        await _imageBox.put(imageName, res.bodyBytes);
        return res.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _cacheImageIfAbsent(String imageName) async {
    if (_getCachedImageBytes(imageName) != null) return;
    await _fetchAndCacheImage(imageName);
  }

  // ─────────────────────────────────────────────────────────────────
  // Cart Logic (unchanged)
  // ─────────────────────────────────────────────────────────────────

  Map<String, dynamic>? _extractCartPayload(dynamic body) {
    if (body is Map<String, dynamic>) {
      if (body['cart'] is Map<String, dynamic>) {
        return Map<String, dynamic>.from(body['cart']);
      }
      if (body['data'] is Map<String, dynamic>) {
        return Map<String, dynamic>.from(body['data']);
      }
      if (body.containsKey('_id') && body.containsKey('items')) {
        return Map<String, dynamic>.from(body);
      }
    }
    return null;
  }

  void _applyServerCart(Map<String, dynamic>? cart) {
    if (!mounted || cart == null) return;
    final items = cart['items'] as List<dynamic>?;
    if (items == null) return;
    final Map<String, CartItem> newMap = {};
    for (final raw in items) {
      if (raw is! Map) continue;
      final it = Map<String, dynamic>.from(raw);
      final productField =
          it['productId'] ?? it['product_id'] ?? it['productid'];
      String? prodId;
      Map<String, dynamic>? productMeta;
      if (productField is String) {
        prodId = productField;
      } else if (productField is Map) {
        productMeta = Map<String, dynamic>.from(productField);
        prodId =
            (productMeta['_id'] ??
                    productMeta['id'] ??
                    productMeta['productId'])
                ?.toString();
      } else if (productField != null) {
        prodId = productField.toString();
      }
      if (prodId == null) continue;
      final prod = Product(
        id: prodId,
        productName:
            (it['productName'] ?? productMeta?['productName'] ?? it['name'])
                ?.toString(),
        productImage: (it['image'] ?? productMeta?['productImage'])?.toString(),
        shortDescription: null,
        longDescription: null,
        category: null,
        isActive: null,
        productPrice: (() {
          final v =
              it['price'] ??
              productMeta?['productPrice'] ??
              productMeta?['price'];
          if (v is num) return v.toDouble();
          if (v is String) return double.tryParse(v);
          return null;
        })(),
      );
      final qty = (it['quantity'] is num)
          ? (it['quantity'] as num).toInt()
          : (it['quantity'] is String ? int.tryParse(it['quantity']) ?? 1 : 1);
      newMap[prodId] = CartItem(product: prod, qty: qty);
    }
    setState(() {
      _cart
        ..clear()
        ..addAll(newMap);
    });
  }

  Future<void> _syncCartFromServer() async {
    try {
      final headers = await _buildHeaders();
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getString('userId') ?? '';
      final uri = AppConfig.u(
        AppConfig.fill(AppConfig.getCart, {'employeeid': employeeId}),
      );
      final resp = await http
          .get(uri, headers: headers)
          .timeout(AppConfig.httpTimeout);
      if (resp.statusCode == 200) {
        final parsed = jsonDecode(resp.body);
        final cart = _extractCartPayload(parsed);
        if (cart != null) {
          final items = cart['items'] as List<dynamic>?;
          if (items != null && items.isEmpty && _cart.isNotEmpty) return;
          _applyServerCart(cart);
        }
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────
  // Product Image Widget
  // ─────────────────────────────────────────────────────────────────

  Widget _buildProductImage(Product p) {
    const double imgSize = 160;
    final String? imagePath = p.imagePath;
    if (imagePath == null || imagePath.isEmpty || imagePath == 'null') {
      return _imagePlaceholder(null, size: imgSize);
    }
    return FutureBuilder<Uint8List?>(
      future: _loadImageBytes(imagePath),
      builder: (context, snap) {
        if (snap.hasData && snap.data != null) {
          return Image.memory(
            snap.data!,
            width: imgSize,
            height: imgSize,
            fit: BoxFit.contain,
          );
        }
        if (snap.connectionState == ConnectionState.done) {
          return _imagePlaceholder(p.productName, size: imgSize);
        }
        return SizedBox(
          width: imgSize,
          height: imgSize,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: const Color.fromRGBO(26, 182, 156, 0.5),
            ),
          ),
        );
      },
    );
  }

  Future<Uint8List?> _loadImageBytes(String imageName) async {
    final cached = _getCachedImageBytes(imageName);
    if (cached != null && cached.isNotEmpty) return cached;
    return _fetchAndCacheImage(imageName);
  }

  double _priceFor(Product p) {
    if (p.productPrice != null) return p.productPrice!;
    return 109 + (p.productName?.length ?? 5) * 3.5 + (p.category?.length ?? 2);
  }

  void _addToCart(Product p, {int qty = 1}) {
    if (p.id == null) return;
    _addToCartAsync(p, qty: qty);
  }

  Future<void> _addToCartAsync(Product p, {int qty = 1}) async {
    if (p.id == null) return;
    final id = p.id!;
    final previousCart = Map<String, CartItem>.from(_cart);
    setState(() {
      final existing = _cart[id];
      if (existing != null) {
        _cart[id] = existing.copyWith(qty: existing.qty + qty);
      } else {
        _cart[id] = CartItem(product: p, qty: qty);
      }
    });

    final customerId = _effectiveCustomerId;
    if (customerId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.person_off, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Please select a customer first'),
              ],
            ),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
      setState(
        () => _cart
          ..clear()
          ..addAll(previousCart),
      );
      return;
    }

    String employeeId = '';
    String tripId = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      employeeId = prefs.getString('userId') ?? '';
      tripId = prefs.getString('currentTripId') ?? '';
    } catch (_) {}

    final body = {
      'customerId': {'id': customerId, 'type': _effectiveType},
      'employeeId': employeeId,
      'productId': id,
      'quantity': qty,
      'price': _priceFor(p).toInt(),
      'productName': p.productName ?? '',
      'image': p.imagePath ?? '',
    };

    if (tripId.isNotEmpty) {
      body['tripId'] = tripId;
    }

    try {
      final headers = await _buildHeaders();
      headers['Content-Type'] = 'application/json';
      final uri = AppConfig.u(AppConfig.addToCart);
      final resp = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(AppConfig.httpTimeout);

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        try {
          final parsed = jsonDecode(resp.body);
          final cart = _extractCartPayload(parsed);
          if (cart != null) _applyServerCart(cart);
        } catch (_) {}
        await _syncCartFromServer();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text('${p.productName} × $qty added'),
                ],
              ),
              backgroundColor: _brandGreen,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              duration: const Duration(milliseconds: 1200),
            ),
          );
        }
      } else {
        final message = (() {
          try {
            final parsed = jsonDecode(resp.body);
            if (parsed is Map && parsed['message'] != null) {
              return parsed['message'].toString();
            }
          } catch (_) {}
          return 'Failed to add to cart (${resp.statusCode})';
        })();
        setState(
          () => _cart
            ..clear()
            ..addAll(previousCart),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.red.shade600,
            ),
          );
        }
      }
    } catch (e) {
      setState(
        () => _cart
          ..clear()
          ..addAll(previousCart),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Network error: $e')));
      }
    }
  }

  int get _cartCount => _cart.length;

  int get _activeFilterCount {
    int count = 0;
    if (_selectedCategoryId != null) count++;
    if (_selectedSubCategoryId != null) count++;
    if (_selectedChildCategoryId != null) count++;
    return count;
  }

  // ─────────────────────────────────────────────────────────────────
  // Product Card
  // ─────────────────────────────────────────────────────────────────

  Widget _productCard(Product p, int index) {
    final price = _priceFor(p);
    return _productCardBody(p, price);
  }

  Widget _productCardBody(Product p, double price) {
    final hasImage =
        p.imagePath != null && p.imagePath!.isNotEmpty && p.imagePath != 'null';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _brandGreen, width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color.fromRGBO(26, 182, 156, 0.10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => ProductDescriptionScreen(
                    product: p,
                    price: price,
                    imageBase: AppConfig.imageBase,
                    brandGreen: _brandGreen,
                    onAddToCart: _addToCart,
                    cart: _cart,
                    priceFor: _priceFor,
                    customerId: _effectiveCustomerId,
                    type: _effectiveType,
                    unit: p.unit ?? 'N/A',
                    unitValue: p.unitValue,
                    onUpdateCart: (id, qty) {
                      setState(() {
                        final prod = _products.firstWhere((e) => e.id == id);
                        _cart[id] = CartItem(product: prod, qty: qty);
                      });
                    },
                  ),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: SizedBox(
                  height: 148,
                  child: Center(
                    child: hasImage
                        ? _buildProductImage(p)
                        : _imagePlaceholder(p.productName),
                  ),
                ),
              ),
            ),
          ),
          Container(height: 1, color: const Color.fromRGBO(26, 182, 156, 0.25)),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF22C9AA), Color(0xFF1AB69C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.productName ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    p.shortDescription ?? '',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(40),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '₹${price.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Color(0xFF1AB69C),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 36,
                        child: (p.id != null && _cart.containsKey(p.id))
                            ? ElevatedButton.icon(
                                onPressed: () => _handleCartClick(),

                                icon: const Icon(Icons.shopping_cart, size: 16),
                                label: const Text(
                                  'Cart',
                                  style: TextStyle(fontSize: 12),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orangeAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  minimumSize: const Size(0, 36),
                                ),
                              )
                            : ElevatedButton.icon(
                                onPressed: p.id == null
                                    ? null
                                    : () => _addToCart(p, qty: 1),
                                icon: const Icon(
                                  Icons.add_shopping_cart,
                                  size: 16,
                                ),
                                label: const Text(
                                  'Add',
                                  style: TextStyle(fontSize: 12),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: _brandGreen,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  minimumSize: const Size(0, 36),
                                ),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surfaceColor,
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
            automaticallyImplyLeading: false,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            title: const Text(
              'Order Products',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontSize: 20,
              ),
            ),
            leading: widget.condition
                ? IconButton(
                    icon: const Icon(
                      Icons.arrow_back,
                      size: 26,
                      color: Colors.white,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                : null,
            actions: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.shopping_cart_outlined,
                      size: 28,
                      color: Colors.white,
                    ),
                    onPressed: _handleCartClick,
                  ),
                  if (_cartCount > 0 && widget.condition)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: CircleAvatar(
                        radius: 9,
                        backgroundColor: Colors.red,
                        child: Text(
                          _cartCount.toString(),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            CustomerSelectionBar(
              selectedCustomer: _selectedCustomer,
              isZonalManager: _isZonalManager,
              onTap: _openCustomerSheet,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: Row(
                children: [
                  Expanded(
                    child: _SearchBar(
                      controller: _searchController,
                      searchNotifier: _searchNotifier,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _FilterButton(
                    activeCount: _activeFilterCount,
                    onTap: _openFilterSheet,
                  ),
                ],
              ),
            ),
            if (_activeFilterCount > 0)
              _ActiveFiltersBreadcrumb(
                selectedCategoryId: _selectedCategoryId,
                selectedSubCategoryId: _selectedSubCategoryId,
                selectedChildCategoryId: _selectedChildCategoryId,
                categories: _categories,
                subcategories: _subcategories,
                childCategories: _childCategories,
                onClear: _clearAllFilters,
              ),
            Expanded(
              child: ProductGrid(
                productsList: _productsNotifier,
                searchQuery: _searchNotifier,
                isLoading: _isLoadingNotifier,
                error: _errorNotifier,
                onRefresh: _refreshProducts,
                productCardBuilder: _productCard,
                emptyView: _emptyView,
                errorView: _errorView,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleCartClick() {
    if (_selectedCustomer == null && _effectiveCustomerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.person_off, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Please select a customer first'),
            ],
          ),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => CartScreen(
              customerId: _effectiveCustomerId,
              type: _effectiveType,
            ),
          ),
        )
        .then((_) async => _syncCartFromServer());
  }

  void _clearAllFilters() {
    setState(() {
      _selectedCategoryId = null;
      _selectedSubCategoryId = null;
      _selectedChildCategoryId = null;
      _subcategories = [];
      _childCategories = [];
    });
    _fetchProducts();
  }

  // ─────────────────────────────────────────────────────────────────
  // CUSTOMER SELECTION SHEET
  // ─────────────────────────────────────────────────────────────────

  void _openCustomerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CustomerSelectionSheet(
        dealers: _dealers,
        farmers: _farmers,
        dealersLoading: _dealersLoading,
        farmersLoading: _farmersLoading,
        dealersError: _dealersError,
        farmersError: _farmersError,
        selectedCustomer: _selectedCustomer,
        isZonalManager: _isZonalManager,
        onSelect: (customer) {
          setState(() => _selectedCustomer = customer);
          Navigator.of(ctx).pop();
        },
        onRetryDealers: () async {
          Navigator.of(ctx).pop();
          if (_isZonalManager) {
            await _fetchZonalCustomers();
          } else {
            final prefs = await SharedPreferences.getInstance();
            await _fetchDealers(prefs.getString('userId') ?? '');
          }
          if (mounted) _openCustomerSheet();
        },
        onRetryFarmers: () async {
          Navigator.of(ctx).pop();
          if (_isZonalManager) {
            await _fetchZonalCustomers();
          } else {
            final prefs = await SharedPreferences.getInstance();
            await _fetchFarmers(prefs.getString('userId') ?? '');
          }
          if (mounted) _openCustomerSheet();
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // FILTER SHEET
  // ─────────────────────────────────────────────────────────────────

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return FilterBottomSheet(
          categories: _categories,
          subcategories: _subcategories,
          childCategories: _childCategories,
          selectedCategoryId: _selectedCategoryId,
          selectedSubCategoryId: _selectedSubCategoryId,
          selectedChildCategoryId: _selectedChildCategoryId,
          categoriesLoading: _categoriesLoading,
          subcategoriesLoading: _subcategoriesLoading,
          childCategoriesLoading: _childCategoriesLoading,
          categoriesError: _categoriesError,
          subcategoriesError: _subcategoriesError,
          childCategoriesError: _childCategoriesError,
          onCategorySelect: (id) async => _onCategorySelected(id),
          onSubCategorySelect: (id) async => _onSubCategorySelected(id),
          onChildCategorySelect: (id) async => _onChildCategorySelected(id),
          onClearAll: () {
            _clearAllFilters();
            Navigator.of(ctx).pop();
          },
          onApply: () => Navigator.of(ctx).pop(),
          onRetryCategories: _fetchCategories,
          onRetrySubcategories: () {
            if (_selectedCategoryId != null) {
              _fetchSubcategories(_selectedCategoryId!);
            }
          },
          onRetryChildCategories: () {
            if (_selectedCategoryId != null && _selectedSubCategoryId != null) {
              _fetchChildCategories(
                _selectedCategoryId!,
                _selectedSubCategoryId!,
              );
            }
          },
        );
      },
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
              _errorNotifier.value ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _refreshProducts,
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

  Widget _emptyView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            size: 72,
            color: Color(0xFF1AB69C),
          ),
          const SizedBox(height: 12),
          const Text(
            'No products found',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Try refreshing or check back later',
            style: TextStyle(color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  Widget _imagePlaceholder(Object? tag, {double size = 160}) {
    final String initials = tag?.toString().isNotEmpty == true
        ? tag!.toString().substring(0, 1).toUpperCase()
        : 'P';
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: _brandGreen.withValues(alpha: 0.12),
              child: Text(
                initials,
                style: TextStyle(
                  color: _brandGreen,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Image coming soon',
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// CUSTOMER SELECTION BAR
// ═════════════════════════════════════════════════════════════════════════════

class CustomerSelectionBar extends StatelessWidget {
  final CustomerItem? selectedCustomer;
  final bool isZonalManager;
  final VoidCallback onTap;

  const CustomerSelectionBar({
    super.key,
    required this.selectedCustomer,
    required this.isZonalManager,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasCustomer = selectedCustomer != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            color: hasCustomer ? _brandGreenLight : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasCustomer ? _brandGreen : const Color(0xFFDDE3EC),
              width: hasCustomer ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: hasCustomer
                    ? const Color.fromRGBO(26, 182, 156, 0.12)
                    : const Color.fromRGBO(0, 0, 0, 0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: hasCustomer
                      ? _brandGreen.withValues(alpha: 0.15)
                      : const Color(0xFFF0F0F0),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasCustomer
                      ? (selectedCustomer!.type == 'dealer'
                            ? Icons.store_rounded
                            : Icons.agriculture_rounded)
                      : Icons.person_add_alt_1_rounded,
                  color: hasCustomer ? _brandGreenDark : Colors.grey.shade500,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: hasCustomer
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _TypeBadge(type: selectedCustomer!.type),
                              const SizedBox(width: 6),
                              // if (selectedCustomer!.customerId != null &&
                              //     selectedCustomer!.customerId!.isNotEmpty)
                              //   Text(
                              //     selectedCustomer!.customerId!,
                              //     style: TextStyle(
                              //       fontSize: 11,
                              //       color: Colors.grey.shade600,
                              //       fontWeight: FontWeight.w500,
                              //     ),
                              //   ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            selectedCustomer!.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Color(0xFF1A1A2E),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (selectedCustomer!.subName.isNotEmpty)
                            Text(
                              selectedCustomer!.subName,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Select Customer',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                          Text(
                            isZonalManager
                                ? 'Tap to choose from all dealers & farmers'
                                : 'Tap to choose a dealer or farmer',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
              ),
              Icon(
                hasCustomer
                    ? Icons.swap_horiz_rounded
                    : Icons.chevron_right_rounded,
                color: hasCustomer ? _brandGreen : Colors.grey.shade400,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Reusable type badge (Dealer / Farmer) ───────────────────────

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final isDealer = type == 'dealer';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: isDealer ? _brandGreen : const Color(0xFF4CAF50),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDealer ? Icons.store_rounded : Icons.agriculture_rounded,
            size: 10,
            color: Colors.white,
          ),
          const SizedBox(width: 3),
          Text(
            isDealer ? 'Dealer' : 'Farmer',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// CUSTOMER SELECTION SHEET
// ═════════════════════════════════════════════════════════════════════════════

class CustomerSelectionSheet extends StatefulWidget {
  final List<CustomerItem> dealers;
  final List<CustomerItem> farmers;
  final bool dealersLoading;
  final bool farmersLoading;
  final String? dealersError;
  final String? farmersError;
  final CustomerItem? selectedCustomer;
  final bool isZonalManager;
  final ValueChanged<CustomerItem> onSelect;
  final VoidCallback onRetryDealers;
  final VoidCallback onRetryFarmers;

  const CustomerSelectionSheet({
    super.key,
    required this.dealers,
    required this.farmers,
    required this.dealersLoading,
    required this.farmersLoading,
    required this.dealersError,
    required this.farmersError,
    required this.selectedCustomer,
    required this.isZonalManager,
    required this.onSelect,
    required this.onRetryDealers,
    required this.onRetryFarmers,
  });

  @override
  State<CustomerSelectionSheet> createState() => _CustomerSelectionSheetState();
}

class _CustomerSelectionSheetState extends State<CustomerSelectionSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.selectedCustomer?.type == 'farmer') {
      _tabController.index = 1;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<CustomerItem> _filtered(List<CustomerItem> list) {
    if (_searchQuery.trim().isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              c.subName.toLowerCase().contains(q) ||
              c.mobile.contains(q) ||
              (c.customerId?.toLowerCase().contains(q) ?? false) ||
              (c.employeeName?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return Container(
      height: screenHeight * 0.82,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // ── Drag handle ──
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDE3EC),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Customer',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      if (widget.isZonalManager)
                        Text(
                          'All dealers & farmers across your zone',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF666680),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // ── Search ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Container(
              decoration: BoxDecoration(
                color: _surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE8EEF3)),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Color(0xFF9BA8B5),
                    size: 20,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear,
                            color: Color(0xFF9BA8B5),
                            size: 18,
                          ),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  hintText: widget.isZonalManager
                      ? 'Search name, shop, mobile, address...'
                      : 'Search by name, shop, or mobile...',
                  hintStyle: const TextStyle(
                    color: Color(0xFFB0BAC5),
                    fontSize: 13.5,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 13,
                  ),
                ),
              ),
            ),
          ),

          // ── Tabs ──
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: _surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8EEF3)),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF22C9AA), Color(0xFF1AB69C)],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color.fromRGBO(26, 182, 156, 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: const Color(0xFF8A96A8),
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              tabs: [
                _buildTab(
                  icon: Icons.store_rounded,
                  label: 'Dealers',
                  count: widget.dealers.length,
                ),
                _buildTab(
                  icon: Icons.agriculture_rounded,
                  label: 'Farmers',
                  count: widget.farmers.length,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── List ──
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _CustomerList(
                  items: _filtered(widget.dealers),
                  isLoading: widget.dealersLoading,
                  error: widget.dealersError,
                  selectedId: widget.selectedCustomer?.id,
                  emptyIcon: Icons.store_mall_directory_outlined,
                  emptyLabel: 'No dealers found',
                  isZonalManager: widget.isZonalManager,
                  onSelect: widget.onSelect,
                  onRetry: widget.onRetryDealers,
                ),
                _CustomerList(
                  items: _filtered(widget.farmers),
                  isLoading: widget.farmersLoading,
                  error: widget.farmersError,
                  selectedId: widget.selectedCustomer?.id,
                  emptyIcon: Icons.grass_outlined,
                  emptyLabel: 'No farmers found',
                  isZonalManager: widget.isZonalManager,
                  onSelect: widget.onSelect,
                  onRetry: widget.onRetryFarmers,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Tab _buildTab({
    required IconData icon,
    required String label,
    required int count,
  }) {
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 6),
          Text(label),
          if (count > 0)
            Container(
              margin: const EdgeInsets.only(left: 5),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('$count', style: const TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Customer List
// ─────────────────────────────────────────────────────────────────

class _CustomerList extends StatelessWidget {
  final List<CustomerItem> items;
  final bool isLoading;
  final String? error;
  final String? selectedId;
  final IconData emptyIcon;
  final String emptyLabel;
  final bool isZonalManager;
  final ValueChanged<CustomerItem> onSelect;
  final VoidCallback onRetry;

  const _CustomerList({
    required this.items,
    required this.isLoading,
    required this.error,
    required this.selectedId,
    required this.emptyIcon,
    required this.emptyLabel,
    required this.isZonalManager,
    required this.onSelect,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: _brandGreen));
    }

    if (error != null && items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _brandGreen,
                side: const BorderSide(color: _brandGreen),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(emptyIcon, size: 52, color: Colors.grey[300]),
            const SizedBox(height: 10),
            Text(
              emptyLabel,
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) => _CustomerTile(
        item: items[i],
        isSelected: items[i].id == selectedId,
        isZonalManager: isZonalManager,
        onTap: () => onSelect(items[i]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Customer Tile — zonal-aware
// ─────────────────────────────────────────────────────────────────

class _CustomerTile extends StatelessWidget {
  final CustomerItem item;
  final bool isSelected;
  final bool isZonalManager;
  final VoidCallback onTap;

  const _CustomerTile({
    required this.item,
    required this.isSelected,
    required this.isZonalManager,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initials = item.name
        .split(' ')
        .where((s) => s.isNotEmpty)
        .map((s) => s[0])
        .take(2)
        .join()
        .toUpperCase();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isSelected ? _brandGreenLight : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? _brandGreen : const Color(0xFFEEF2F6),
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: const Color.fromRGBO(26, 182, 156, 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // ── Avatar ────────────────────────────────────────────
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? const LinearGradient(
                          colors: [Color(0xFF22C9AA), Color(0xFF1AB69C)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: isSelected ? null : const Color(0xFFF0F4F8),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF8A96A8),
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // ── Info ──────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name + ID row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: isSelected
                                  ? _brandGreenDark
                                  : const Color(0xFF1A1A2E),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // if (item.customerId != null &&
                        //     item.customerId!.isNotEmpty)
                        //   Text(
                        //     item.customerId!,
                        //     style: TextStyle(
                        //       fontSize: 11,
                        //       color: isSelected
                        //           ? _brandGreen
                        //           : Colors.grey.shade500,
                        //       fontWeight: FontWeight.w600,
                        //     ),
                        //   ),
                      ],
                    ),

                    // Shop / address line (subName)
                    if (item.subName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            Icon(
                              item.type == 'dealer'
                                  ? Icons.store_outlined
                                  : Icons.location_on_outlined,
                              size: 11,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                item.subName,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 3),

                    // Phone row
                    Row(
                      children: [
                        Icon(
                          Icons.phone_outlined,
                          size: 12,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          item.mobile,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade600,
                          ),
                        ),

                        // Employee name badge (zonal manager sees this)
                      ],
                    ),

                    SizedBox(height: 3),
                    if (isZonalManager &&
                        item.employeeName != null &&
                        item.employeeName!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F9FF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFBAE6FD)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.person_outline,
                              size: 9,
                              color: Color(0xFF0369A1),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              item.employeeName!,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF0369A1),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // ── Check circle ──────────────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: isSelected
                    ? Container(
                        key: const ValueKey('check'),
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF22C9AA), Color(0xFF1AB69C)],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      )
                    : Container(
                        key: const ValueKey('circle'),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFFDDE3EC),
                            width: 1.5,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// FILTER BUTTON  (unchanged)
// ═════════════════════════════════════════════════════════════════════════════

class _FilterButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTap;

  const _FilterButton({required this.activeCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isActive = activeCount > 0;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(
                  colors: [Color(0xFF22C9AA), Color(0xFF1AB69C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isActive ? null : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? Colors.transparent : const Color(0xFFDDE3EC),
          ),
          boxShadow: [
            BoxShadow(
              color: isActive
                  ? const Color.fromRGBO(26, 182, 156, 0.3)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Icon(
                Icons.tune_rounded,
                color: isActive ? Colors.white : const Color(0xFF6B7280),
                size: 22,
              ),
            ),
            if (isActive)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF4757),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$activeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ACTIVE FILTERS BREADCRUMB  (unchanged)
// ═════════════════════════════════════════════════════════════════════════════

class _ActiveFiltersBreadcrumb extends StatelessWidget {
  final String? selectedCategoryId;
  final String? selectedSubCategoryId;
  final String? selectedChildCategoryId;
  final List<ProductCategory> categories;
  final List<ProductCategory> subcategories;
  final List<ProductCategory> childCategories;
  final VoidCallback onClear;

  const _ActiveFiltersBreadcrumb({
    required this.selectedCategoryId,
    required this.selectedSubCategoryId,
    required this.selectedChildCategoryId,
    required this.categories,
    required this.subcategories,
    required this.childCategories,
    required this.onClear,
  });

  String _nameFor(List<ProductCategory> list, String? id) {
    if (id == null) return '';
    for (final c in list) {
      if (c.id == id) return c.name ?? 'Unknown';
    }
    return 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (selectedCategoryId != null) {
      chips.add(
        _FilterCrumb(
          label: _nameFor(categories, selectedCategoryId),
          icon: Icons.category_outlined,
        ),
      );
    }
    if (selectedSubCategoryId != null) {
      chips.add(
        const Icon(Icons.chevron_right, size: 14, color: Color(0xFF9BA8B5)),
      );
      chips.add(
        _FilterCrumb(
          label: _nameFor(subcategories, selectedSubCategoryId),
          icon: Icons.subdirectory_arrow_right_outlined,
        ),
      );
    }
    if (selectedChildCategoryId != null) {
      chips.add(
        const Icon(Icons.chevron_right, size: 14, color: Color(0xFF9BA8B5)),
      );
      chips.add(
        _FilterCrumb(
          label: _nameFor(childCategories, selectedChildCategoryId),
          icon: Icons.label_outline_rounded,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      child: Row(
        children: [
          const Icon(Icons.filter_list_rounded, size: 15, color: _brandGreen),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: chips),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onClear,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.close_rounded,
                    size: 12,
                    color: Colors.red.shade400,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'Clear',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.red.shade500,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterCrumb extends StatelessWidget {
  final String label;
  final IconData icon;
  const _FilterCrumb({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _brandGreenLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _brandGreen.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: _brandGreenDark),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: _brandGreenDark,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// FILTER BOTTOM SHEET  (unchanged)
// ═════════════════════════════════════════════════════════════════════════════

class FilterBottomSheet extends StatefulWidget {
  final List<ProductCategory> categories;
  final List<ProductCategory> subcategories;
  final List<ProductCategory> childCategories;
  final String? selectedCategoryId;
  final String? selectedSubCategoryId;
  final String? selectedChildCategoryId;
  final bool categoriesLoading;
  final bool subcategoriesLoading;
  final bool childCategoriesLoading;
  final String? categoriesError;
  final String? subcategoriesError;
  final String? childCategoriesError;
  final ValueChanged<String?> onCategorySelect;
  final ValueChanged<String?> onSubCategorySelect;
  final ValueChanged<String?> onChildCategorySelect;
  final VoidCallback onClearAll;
  final VoidCallback onApply;
  final VoidCallback onRetryCategories;
  final VoidCallback onRetrySubcategories;
  final VoidCallback onRetryChildCategories;

  const FilterBottomSheet({
    super.key,
    required this.categories,
    required this.subcategories,
    required this.childCategories,
    required this.selectedCategoryId,
    required this.selectedSubCategoryId,
    required this.selectedChildCategoryId,
    required this.categoriesLoading,
    required this.subcategoriesLoading,
    required this.childCategoriesLoading,
    required this.categoriesError,
    required this.subcategoriesError,
    required this.childCategoriesError,
    required this.onCategorySelect,
    required this.onSubCategorySelect,
    required this.onChildCategorySelect,
    required this.onClearAll,
    required this.onApply,
    required this.onRetryCategories,
    required this.onRetrySubcategories,
    required this.onRetryChildCategories,
  });

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  String? _catId;
  String? _subId;
  String? _childId;

  @override
  void initState() {
    super.initState();
    _catId = widget.selectedCategoryId;
    _subId = widget.selectedSubCategoryId;
    _childId = widget.selectedChildCategoryId;
  }

  int get _activeCount {
    int c = 0;
    if (_catId != null) c++;
    if (_subId != null) c++;
    if (_childId != null) c++;
    return c;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDE3EC),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 16),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF22C9AA), Color(0xFF1AB69C)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Filter Products',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      Text(
                        _activeCount == 0
                            ? 'No filters applied'
                            : '$_activeCount filter${_activeCount > 1 ? 's' : ''} active',
                        style: TextStyle(
                          fontSize: 12,
                          color: _activeCount > 0
                              ? _brandGreen
                              : Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_activeCount > 0)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _catId = null;
                        _subId = null;
                        _childId = null;
                      });
                      widget.onClearAll();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade400,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text(
                      'Clear All',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF9BA8B5),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF0F4F8)),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.55,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FilterSection(
                    title: 'Category',
                    icon: Icons.category_rounded,
                    isLoading: widget.categoriesLoading,
                    error: widget.categoriesError,
                    onRetry: widget.onRetryCategories,
                    child: _buildChipWrap(
                      items: widget.categories,
                      selectedId: _catId,
                      allLabel: 'All Categories',
                      onSelect: (id) {
                        setState(() {
                          _catId = id;
                          _subId = null;
                          _childId = null;
                        });
                        widget.onCategorySelect(id);
                      },
                    ),
                  ),
                  if (_catId != null) ...[
                    const SizedBox(height: 4),
                    _FilterSection(
                      title: 'Sub-Category',
                      icon: Icons.account_tree_outlined,
                      isLoading: widget.subcategoriesLoading,
                      error: widget.subcategoriesError,
                      onRetry: widget.onRetrySubcategories,
                      child: _buildChipWrap(
                        items: widget.subcategories,
                        selectedId: _subId,
                        allLabel: 'All Sub-Categories',
                        onSelect: (id) {
                          setState(() {
                            _subId = id;
                            _childId = null;
                          });
                          widget.onSubCategorySelect(id);
                        },
                      ),
                    ),
                  ],
                  if (_catId != null && _subId != null) ...[
                    const SizedBox(height: 4),
                    _FilterSection(
                      title: 'Product Type',
                      icon: Icons.label_rounded,
                      isLoading: widget.childCategoriesLoading,
                      error: widget.childCategoriesError,
                      onRetry: widget.onRetryChildCategories,
                      child: _buildChipWrap(
                        items: widget.childCategories,
                        selectedId: _childId,
                        allLabel: 'All Types',
                        onSelect: (id) {
                          setState(() => _childId = id);
                          widget.onChildCategorySelect(id);
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF0F4F8)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: _surfaceColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE8EEF3)),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.filter_list_rounded,
                              color: _activeCount > 0
                                  ? _brandGreen
                                  : Colors.grey.shade400,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _activeCount == 0
                                  ? 'No Filters'
                                  : '$_activeCount Applied',
                              style: TextStyle(
                                color: _activeCount > 0
                                    ? _brandGreenDark
                                    : Colors.grey.shade500,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: widget.onApply,
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF22C9AA), Color(0xFF1AB69C)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: const [
                            BoxShadow(
                              color: Color.fromRGBO(26, 182, 156, 0.35),
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Show Results',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChipWrap({
    required List<ProductCategory> items,
    required String? selectedId,
    required String allLabel,
    required ValueChanged<String?> onSelect,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _FilterChip(
          label: allLabel,
          isSelected: selectedId == null,
          onTap: () => onSelect(null),
        ),
        ...items.map(
          (cat) => _FilterChip(
            label: cat.name ?? 'Category',
            isSelected: selectedId == cat.id,
            onTap: () => onSelect(cat.id),
          ),
        ),
      ],
    );
  }
}

class _FilterSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isLoading;
  final String? error;
  final VoidCallback onRetry;
  final Widget child;

  const _FilterSection({
    required this.title,
    required this.icon,
    required this.isLoading,
    required this.error,
    required this.onRetry,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _brandGreenLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: _brandGreen, size: 15),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: Color(0xFF2D3748),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _brandGreen,
                  ),
                ),
              ),
            )
          else if (error != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    error!,
                    style: TextStyle(color: Colors.red.shade400, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: _brandGreen,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Retry', style: TextStyle(fontSize: 12)),
                ),
              ],
            )
          else
            child,
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFF22C9AA), Color(0xFF1AB69C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? Colors.transparent : const Color(0xFFDDE3EC),
            width: 1.2,
          ),
          boxShadow: isSelected
              ? const [
                  BoxShadow(
                    color: Color.fromRGBO(26, 182, 156, 0.3),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              const Icon(Icons.check_rounded, size: 13, color: Colors.white),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF4A5568),
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SEARCH BAR  (unchanged)
// ═════════════════════════════════════════════════════════════════════════════

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.searchNotifier});

  final TextEditingController controller;
  final ValueNotifier<String> searchNotifier;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDDE3EC)),
        ),
        child: ValueListenableBuilder<String>(
          valueListenable: searchNotifier,
          builder: (context, value, _) {
            return TextField(
              controller: controller,
              onChanged: (v) => searchNotifier.value = v,
              decoration: InputDecoration(
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF9BA8B5),
                  size: 20,
                ),
                suffixIcon: value.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear_rounded,
                          color: Color(0xFF9BA8B5),
                          size: 18,
                        ),
                        onPressed: () {
                          controller.clear();
                          searchNotifier.value = '';
                        },
                      )
                    : null,
                hintText: 'Search products...',
                hintStyle: const TextStyle(
                  color: Color(0xFFB0BAC5),
                  fontSize: 14,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PRODUCT GRID  (unchanged)
// ═════════════════════════════════════════════════════════════════════════════

typedef ProductCardBuilder = Widget Function(Product product, int index);

class ProductGrid extends StatefulWidget {
  const ProductGrid({
    super.key,
    required this.productsList,
    required this.searchQuery,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.productCardBuilder,
    required this.emptyView,
    required this.errorView,
  });

  final ValueListenable<List<Product>> productsList;
  final ValueListenable<String> searchQuery;
  final ValueListenable<bool> isLoading;
  final ValueListenable<String?> error;
  final Future<void> Function() onRefresh;
  final ProductCardBuilder productCardBuilder;
  final Widget Function() emptyView;
  final Widget Function() errorView;

  @override
  State<ProductGrid> createState() => _ProductGridState();
}

class _ProductGridState extends State<ProductGrid> {
  late List<Product> _products;
  late String _search;
  late bool _isLoading;
  String? _error;

  @override
  void initState() {
    super.initState();
    _products = widget.productsList.value;
    _search = widget.searchQuery.value;
    _isLoading = widget.isLoading.value;
    _error = widget.error.value;
    widget.productsList.addListener(_onProductsChanged);
    widget.searchQuery.addListener(_onSearchChanged);
    widget.isLoading.addListener(_onLoadingChanged);
    widget.error.addListener(_onErrorChanged);
  }

  @override
  void didUpdateWidget(covariant ProductGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productsList != widget.productsList) {
      oldWidget.productsList.removeListener(_onProductsChanged);
      widget.productsList.addListener(_onProductsChanged);
      _products = widget.productsList.value;
    }
    if (oldWidget.searchQuery != widget.searchQuery) {
      oldWidget.searchQuery.removeListener(_onSearchChanged);
      widget.searchQuery.addListener(_onSearchChanged);
      _search = widget.searchQuery.value;
    }
    if (oldWidget.isLoading != widget.isLoading) {
      oldWidget.isLoading.removeListener(_onLoadingChanged);
      widget.isLoading.addListener(_onLoadingChanged);
      _isLoading = widget.isLoading.value;
    }
    if (oldWidget.error != widget.error) {
      oldWidget.error.removeListener(_onErrorChanged);
      widget.error.addListener(_onErrorChanged);
      _error = widget.error.value;
    }
  }

  @override
  void dispose() {
    widget.productsList.removeListener(_onProductsChanged);
    widget.searchQuery.removeListener(_onSearchChanged);
    widget.isLoading.removeListener(_onLoadingChanged);
    widget.error.removeListener(_onErrorChanged);
    super.dispose();
  }

  void _onProductsChanged() {
    final newProducts = widget.productsList.value;
    if (!listEquals(newProducts, _products)) {
      setState(() => _products = newProducts);
    }
  }

  void _onSearchChanged() => setState(() => _search = widget.searchQuery.value);
  void _onLoadingChanged() =>
      setState(() => _isLoading = widget.isLoading.value);
  void _onErrorChanged() => setState(() => _error = widget.error.value);

  List<Product> _applySearch(List<Product> items, String query) {
    if (query.trim().isEmpty) return items;
    final q = query.toLowerCase();
    return items.where((p) {
      final text =
          '${p.productName ?? ''} ${p.category ?? ''} ${p.shortDescription ?? ''}';
      return text.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _brandGreen));
    }
    if (_error != null) return widget.errorView();
    final filtered = _applySearch(_products, _search);
    if (filtered.isEmpty) return widget.emptyView();

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      color: _brandGreen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 20, top: 10),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 10,
            childAspectRatio: 0.60,
          ),
          itemCount: filtered.length,
          itemBuilder: (ctx, i) => widget.productCardBuilder(filtered[i], i),
        ),
      ),
    );
  }
}
