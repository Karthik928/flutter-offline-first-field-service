// lib/Screens/trips.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/Screens/trip_details_screen.dart';

import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/offline/cache_store.dart';
import 'package:FieldService_app/main.dart' show apiClient;
import 'package:FieldService_app/services/secure_storage_service.dart'; // use the global client you created

class Trips extends StatefulWidget {
  /// 'All' | 'Today' | 'Yesterday' | 'Last 7 days' | 'This Month' | 'Last Month'
  final String initialFilter;

  const Trips({super.key, this.initialFilter = 'Last 7 days'});

  @override
  State<Trips> createState() => _TripsState();
}

class _TripsState extends State<Trips> with TickerProviderStateMixin {
  // ---------- UI ----------
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;

  // Filters
  static const String fAll = 'All';
  static const String fToday = 'Today';
  static const String fYesterday = 'Yesterday';
  static const String fLast7 = 'Last 7 days';
  static const String fThisMonth = 'This Month';
  static const String fLastMonth = 'Last Month';

  late String _selectedFilter;
  String _searchQuery = '';

  // Colors
  final Color appGreen = const Color(0xFF2E7D32);
  final Color backgroundColor = const Color.fromARGB(255, 255, 255, 255);

  // Network helper client (for rare GET-with-body calls)
  final http.Client _client = http.Client();

  // Per-filter cache & state (we'll populate these from the single all-trips fetch)
  final Map<String, List<TripItem>> _data = {
    fAll: [],
    fToday: [],
    fYesterday: [],
    fLast7: [],
    fThisMonth: [],
    fLastMonth: [],
  };

  final Map<String, bool> _loaded = {
    fAll: false,
    fToday: false,
    fYesterday: false,
    fLast7: false,
    fThisMonth: false,
    fLastMonth: false,
  };

  final Map<String, bool> _loading = {
    fAll: false,
    fToday: false,
    fYesterday: false,
    fLast7: false,
    fThisMonth: false,
    fLastMonth: false,
  };

  final Map<String, String?> _error = {
    fAll: null,
    fToday: null,
    fYesterday: null,
    fLast7: null,
    fThisMonth: null,
    fLastMonth: null,
  };

  final Map<String, int> _fetchId = {
    fAll: 0,
    fToday: 0,
    fYesterday: 0,
    fLast7: 0,
    fThisMonth: 0,
    fLastMonth: 0,
  };
  final Map<String, DateTime?> _lastFetchAt = {
    fAll: null,
    fToday: null,
    fYesterday: null,
    fLast7: null,
    fThisMonth: null,
    fLastMonth: null,
  };

  // Incentives per filter (null = unknown)
  final Map<String, double?> _incentives = {
    fAll: null,
    fToday: null,
    fYesterday: null,
    fLast7: null,
    fThisMonth: null,
    fLastMonth: null,
  };

  bool _incentivesLoading = false;
  String? _incentivesError;

  final GlobalKey<RefreshIndicatorState> _refreshKey =
      GlobalKey<RefreshIndicatorState>();

  void _log(String msg) => debugPrint('🛰️ Trips> $msg');

  // ---------- Helpers ----------
  String _titleForFilter(String filter) => 'Trip Logs';

  String _cacheKeyForEmployeeAll(String employeeId) {
    // cache key for the "all trips" endpoint per employee
    return 'trips:employee:$employeeId:all';
  }

  String _formatIncentiveValue(double? v) {
    if (v == null) return '--';
    try {
      return v.toStringAsFixed(2);
    } catch (_) {
      return v.toString();
    }
  }

  String _incentiveTextForSelectedFilter() {
    final val = _incentives[_selectedFilter];
    return _formatIncentiveValue(val);
  }

  // ---------- Lifecycle ----------
  @override
  void initState() {
    super.initState();
    _selectedFilter = widget.initialFilter;

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    // Initial fetch (will use cache if available)
    _fetchIfNeeded(_selectedFilter, force: true);
  }

  @override
  void dispose() {
    _client.close();
    _animationController.dispose();
    super.dispose();
  }

  // ---------- Fetch orchestration (with cache) ----------
  Future<void> _fetchIfNeeded(String filter, {bool force = false}) async {
    if (_loading[filter]! && !force) return;
    if (_loaded[filter]! && !force) return;
    await _fetchAllAndFilter(force: force);
  }

  String _cacheKeyForIncentives(String employeeId) {
    return 'incentives:employee:$employeeId';
  }

  Future<void> _fetchIncentives(String employeeId, String token) async {
    final cacheKey = _cacheKeyForIncentives(employeeId);

    try {
      _incentivesLoading = true;
      _incentivesError = null;
      if (mounted) setState(() {});

      // ---------- STEP 1: Serve cache immediately ----------
      final cached = apiClient.cache?.get(cacheKey);
      bool hadCache = false;

      if (cached != null && cached.body.isNotEmpty) {
        try {
          final decoded = jsonDecode(cached.body);
          if (decoded is Map && decoded['data'] is Map) {
            _applyIncentiveData(Map<String, dynamic>.from(decoded['data']));
            hadCache = true;
            if (mounted) setState(() {});
          }
        } catch (_) {}
      }

      // ---------- STEP 2: Network refresh ----------
      final path = AppConfig.incentivesById.replaceFirst(
        '{employeeid}',
        employeeId,
      );
      final uri = AppConfig.u(path);

      final resp = await _client
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              if (token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
          )
          .timeout(AppConfig.httpTimeout);

      if (resp.statusCode != 200) {
        if (!hadCache) {
          _incentivesError = 'Error ${resp.statusCode}';
          if (mounted) setState(() {});
        }
        return;
      }

      // Save to cache
      await apiClient.cache?.put(
        cacheKey,
        CacheEntry(
          body: resp.body,
          statusCode: resp.statusCode,
          storedAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      final decoded = jsonDecode(resp.body);
      if (decoded is Map && decoded['data'] is Map) {
        _applyIncentiveData(Map<String, dynamic>.from(decoded['data']));
        if (mounted) setState(() {});
      }
    } on TimeoutException {
      if (_incentivesError == null) {
        _incentivesError = 'Request timed out';
        if (mounted) setState(() {});
      }
    } catch (e) {
      if (_incentivesError == null) {
        _incentivesError = 'Error: $e';
        if (mounted) setState(() {});
      }
    } finally {
      _incentivesLoading = false;
      if (mounted) setState(() {});
    }
  }

  void _applyIncentiveData(Map<String, dynamic> data) {
    double? d(String k) {
      final v = data[k];
      if (v == null) return 0.0;
      return double.tryParse(v.toString());
    }

    _incentives[fToday] = d('today');
    _incentives[fYesterday] = d('yesterday');
    _incentives[fLast7] = d('last7Days');
    _incentives[fThisMonth] = d('thisMonth');
    _incentives[fLastMonth] = d('lastMonth');
    _incentives[fAll] = d('totalIncentive') ?? _incentives[fAll];
  }

  /// Fetch all trips for the employee (single network call), then populate
  /// per-filter lists locally (Today / Yesterday / Last 7 days / This Month / Last Month / All).
  ///
  /// This version first checks `apiClient.cache` for a cached server response
  /// (keyed by employeeId). If cached response exists it is displayed immediately,
  /// while a background network refresh is started that updates cache and UI if newer.
  Future<void> _fetchAllAndFilter({bool force = false}) async {
    final now = DateTime.now();
    // small debounce: avoid repeated requests within 600ms
    if (!force) {
      final last = _lastFetchAt[fAll];
      if (last != null &&
          now.difference(last) < const Duration(milliseconds: 600)) {
        return;
      }
    }
    _lastFetchAt[fAll] = now;

    // Mark all filters loading so UI shows loader consistently
    for (final k in _loading.keys) {
      _loading[k] = true;
    }
    _error[fAll] = null;
    _fetchId[fAll] = (_fetchId[fAll]! + 1);
    final myId = _fetchId[fAll]!;
    if (mounted) setState(() {});

    Timer? watchdog;
    watchdog = Timer(const Duration(seconds: 22), () {
      if (!mounted) return;
      if (_loading[fAll] == true && myId == _fetchId[fAll]) {
        for (final k in _loading.keys) {
          _loading[k] = false;
        }
        _error[fAll] = 'Request took too long';
        setState(() {});
      }
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getString('userId') ?? '';
      if (employeeId.isEmpty) {
        _log('No userId in prefs; cannot fetch trips');
        _error[fAll] = 'User not found';
        return;
      }

      // Accept token from either 'token' or 'authToken'
      // final token =
      //     prefs.getString('token') ??
      //     prefs.getString('authToken') ??
      //     prefs.getString('accessToken') ??
      //     '';
      final token = await SecureStorageService.getToken();

      final headers = <String, String>{
        'Accept': 'application/json',
        if (token!.isNotEmpty) 'Authorization': 'Bearer $token',
        'Connection': 'close',
      };

      // --- fetch incentives (background) ---
      // Do this regardless of trips cache; incentives are independent.
      unawaited(_fetchIncentives(employeeId, token));

      final uri = AppConfig.u('/api/trips/employee/$employeeId');
      _log('GET $uri');

      List listJson = const [];

      // ---- CACHE: try reading cache first (non-blocking UI) ----
      final cacheKey = _cacheKeyForEmployeeAll(employeeId);
      final cached = apiClient.cache?.get(cacheKey);

      // track whether we had a usable cache so network failures don't overwrite cached UI
      bool hadCache = false;

      if (cached != null && cached.body.isNotEmpty) {
        try {
          final decoded = jsonDecode(cached.body);
          if (decoded is List) {
            listJson = decoded;
          } else if (decoded is Map) {
            if (decoded['data'] is List) {
              listJson = decoded['data'] as List;
            } else if (decoded['trips'] is List) {
              listJson = decoded['trips'] as List;
            } else if (decoded['todayTrips'] is List) {
              listJson = decoded['todayTrips'] as List;
            } else if (decoded['result'] is List) {
              listJson = decoded['result'] as List;
            } else {
              final maybeTripKeys = {'_id', 'tripDate', 'startTime'};
              if (decoded.keys.any((k) => maybeTripKeys.contains(k))) {
                listJson = [decoded];
              } else {
                listJson = const [];
              }
            }
          } else {
            listJson = const [];
          }
        } catch (e) {
          _log('cache parse error: $e');
          listJson = const [];
        }

        // Populate local data from cached payload immediately
        // defensive parsing of cached listJson -> parsedFromCache
        final parsedFromCache = <TripItem>[];
        for (final e in listJson) {
          if (e == null) {
            _log('skip cached null item');
            continue;
          }
          if (e is Map) {
            try {
              parsedFromCache.add(
                TripItem.fromJson(Map<String, dynamic>.from(e)),
              );
            } catch (err) {
              _log('skip cached invalid trip item (parse error): $err');
              _log(' item: $e');
            }
          } else {
            _log('skip cached non-map trip item: ${e.runtimeType} -> $e');
          }
        }

        // Optional: if cache had content but produced 0 valid items, delete corrupt cache so we don't repeatedly fail offline
        if (parsedFromCache.isEmpty && (cached.body.isNotEmpty)) {
          try {
            //await apiClient.cache?.delete(cacheKey);
            _log(
              'deleted corrupt cache for key=$cacheKey (was non-empty but parsed 0 items)',
            );
          } catch (err) {
            _log('failed to delete corrupt cache key=$cacheKey: $err');
          }
        }
        // mark that we have usable cache (non-empty parsed list)
        hadCache = parsedFromCache.isNotEmpty;

        _log(
          'cache[$cacheKey].body length=${cached.body.length} type: ${cached.body.runtimeType}',
        );
        _log(
          'cache preview: ${cached.body.length > 200 ? "${cached.body.substring(0, 200)}..." : cached.body}',
        );

        // set All immediately
        _data[fAll] = parsedFromCache;

        // local timezone-agnostic comparisons: compare Y/M/D in UTC to be consistent with server dates
        final nowUtc = DateTime.now().toUtc();
        final todayUtc = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
        final yesterdayUtc = todayUtc.subtract(const Duration(days: 1));
        final last7StartUtc = todayUtc.subtract(
          const Duration(days: 6),
        ); // last 7 days including today
        final startOfThisMonthUtc = DateTime.utc(nowUtc.year, nowUtc.month, 1);
        final startOfLastMonthUtc = DateTime.utc(
          nowUtc.month == 1 ? nowUtc.year - 1 : nowUtc.year,
          nowUtc.month == 1 ? 12 : nowUtc.month - 1,
          1,
        );
        final startOfNextMonthUtc = DateTime.utc(
          startOfThisMonthUtc.year,
          startOfThisMonthUtc.month + 1,
          1,
        );

        _data[fToday] = parsedFromCache.where((t) {
          final td = DateTime.utc(
            t.tripDate.year,
            t.tripDate.month,
            t.tripDate.day,
          );
          return td == todayUtc;
        }).toList();

        _data[fYesterday] = parsedFromCache.where((t) {
          final td = DateTime.utc(
            t.tripDate.year,
            t.tripDate.month,
            t.tripDate.day,
          );
          return td == yesterdayUtc;
        }).toList();

        _data[fLast7] = parsedFromCache.where((t) {
          final td = DateTime.utc(
            t.tripDate.year,
            t.tripDate.month,
            t.tripDate.day,
          );
          return !td.isBefore(last7StartUtc) && !td.isAfter(todayUtc);
        }).toList();

        _data[fThisMonth] = parsedFromCache.where((t) {
          final td = DateTime.utc(
            t.tripDate.year,
            t.tripDate.month,
            t.tripDate.day,
          );
          return !td.isBefore(startOfThisMonthUtc) &&
              td.isBefore(startOfNextMonthUtc);
        }).toList();

        // last month: >= startOfLastMonthUtc and < startOfThisMonthUtc
        _data[fLastMonth] = parsedFromCache.where((t) {
          final td = DateTime.utc(
            t.tripDate.year,
            t.tripDate.month,
            t.tripDate.day,
          );
          return !td.isBefore(startOfLastMonthUtc) &&
              td.isBefore(startOfThisMonthUtc);
        }).toList();

        _loaded[fAll] = true;
        _loaded[fToday] = true;
        _loaded[fYesterday] = true;
        _loaded[fLast7] = true;
        _loaded[fThisMonth] = true;
        _loaded[fLastMonth] = true;

        if (mounted) {
          _animationController.forward(from: 0);
          setState(() {});
        }

        _log(
          'served ${parsedFromCache.length} trips from cache (key=$cacheKey)',
        );
      }

      // ---- NETWORK: always attempt to refresh in background (or do network immediately if no cache) ----
      // If no cache, do network and await; if cache existed, do network in background and update cache/UI when done.
      Future<void> doNetworkFetch() async {
        try {
          final resp = await _client
              .get(uri, headers: headers)
              .timeout(AppConfig.httpTimeout);

          if (myId != _fetchId[fAll]) return; // stale

          if (resp.statusCode == 200) {
            _log('200 OK len=${resp.body.length}');
            // save to cache
            try {
              await apiClient.cache?.put(
                cacheKey,
                CacheEntry(
                  body: resp.body,
                  statusCode: resp.statusCode,
                  storedAtMillis: DateTime.now().millisecondsSinceEpoch,
                ),
              );
              _log('cache updated (key=$cacheKey)');
            } catch (e) {
              _log('cache put failed: $e');
            }

            // parse network response and update data
            List netJson = const [];
            final decoded = jsonDecode(resp.body);
            if (decoded is List) {
              netJson = decoded;
            } else if (decoded is Map) {
              if (decoded['data'] is List) {
                netJson = decoded['data'] as List;
              } else if (decoded['trips'] is List) {
                netJson = decoded['trips'] as List;
              } else if (decoded['todayTrips'] is List) {
                netJson = decoded['todayTrips'] as List;
              } else if (decoded['result'] is List) {
                netJson = decoded['result'] as List;
              } else {
                final maybeTripKeys = {'_id', 'tripDate', 'startTime'};
                if (decoded.keys.any((k) => maybeTripKeys.contains(k))) {
                  netJson = [decoded];
                } else {
                  netJson = const [];
                }
              }
            } else {
              netJson = const [];
            }

            // defensive parsing of network netJson -> parsed
            final parsed = <TripItem>[];
            for (final e in netJson) {
              if (e == null) continue;
              if (e is Map) {
                try {
                  parsed.add(TripItem.fromJson(Map<String, dynamic>.from(e)));
                } catch (err) {
                  _log('skip network trip item (parse error): $err');
                  _log(' item: $e');
                }
              } else {
                _log('skip network non-map trip item: ${e.runtimeType} -> $e');
              }
            }

            // Guard against stale result
            if (myId != _fetchId[fAll]) return;

            _data[fAll] = parsed;

            // derive today/yesterday/last7/thisMonth/lastMonth from parsed network data
            final nowUtc = DateTime.now().toUtc();
            final todayUtc = DateTime.utc(
              nowUtc.year,
              nowUtc.month,
              nowUtc.day,
            );
            final yesterdayUtc = todayUtc.subtract(const Duration(days: 1));
            final last7StartUtc = todayUtc.subtract(
              const Duration(days: 6),
            ); // last 7 days including today
            final startOfThisMonthUtc = DateTime.utc(
              nowUtc.year,
              nowUtc.month,
              1,
            );
            final startOfNextMonthUtc = DateTime.utc(
              startOfThisMonthUtc.year,
              startOfThisMonthUtc.month + 1,
              1,
            );
            final startOfLastMonthUtc = DateTime.utc(
              nowUtc.month == 1 ? nowUtc.year - 1 : nowUtc.year,
              nowUtc.month == 1 ? 12 : nowUtc.month - 1,
              1,
            );

            _data[fToday] = parsed.where((t) {
              final td = DateTime.utc(
                t.tripDate.year,
                t.tripDate.month,
                t.tripDate.day,
              );
              return td == todayUtc;
            }).toList();

            _data[fYesterday] = parsed.where((t) {
              final td = DateTime.utc(
                t.tripDate.year,
                t.tripDate.month,
                t.tripDate.day,
              );
              return td == yesterdayUtc;
            }).toList();

            _data[fLast7] = parsed.where((t) {
              final td = DateTime.utc(
                t.tripDate.year,
                t.tripDate.month,
                t.tripDate.day,
              );
              return !td.isBefore(last7StartUtc) && !td.isAfter(todayUtc);
            }).toList();

            _data[fThisMonth] = parsed.where((t) {
              final td = DateTime.utc(
                t.tripDate.year,
                t.tripDate.month,
                t.tripDate.day,
              );
              return !td.isBefore(startOfThisMonthUtc) &&
                  td.isBefore(startOfNextMonthUtc);
            }).toList();

            _data[fLastMonth] = parsed.where((t) {
              final td = DateTime.utc(
                t.tripDate.year,
                t.tripDate.month,
                t.tripDate.day,
              );
              return !td.isBefore(startOfLastMonthUtc) &&
                  td.isBefore(startOfThisMonthUtc);
            }).toList();

            _loaded[fAll] = true;
            _loaded[fToday] = true;
            _loaded[fYesterday] = true;
            _loaded[fLast7] = true;
            _loaded[fThisMonth] = true;
            _loaded[fLastMonth] = true;

            _log('✅ Stored ${parsed.length} trips locally (all) from network');

            if (mounted) {
              _animationController.forward(from: 0);
              setState(() {});
            }
          } else if (resp.statusCode == 404) {
            // Treat 404 as "no trips" for ALL filter
            _log('404 — no trips found');

            _data[fAll] = [];
            _data[fToday] = [];
            _data[fYesterday] = [];
            _data[fLast7] = [];
            _data[fThisMonth] = [];
            _data[fLastMonth] = [];

            _loaded[fAll] = true;
            _loaded[fToday] = true;
            _loaded[fYesterday] = true;
            _loaded[fLast7] = true;
            _loaded[fThisMonth] = true;
            _loaded[fLastMonth] = true;

            _error[fAll] = null; // IMPORTANT: clear error

            if (mounted) {
              _animationController.forward(from: 0);
              setState(() {});
            }
          } else {
            _log('HTTP ${resp.statusCode} ${resp.reasonPhrase}');
            if (!hadCache) {
              _error[fAll] = 'Error ${resp.statusCode}';
              if (mounted) setState(() {});
            }
          }
        } on TimeoutException {
          if (myId == _fetchId[fAll]) {
            if (!hadCache) {
              _error[fAll] = 'Request timed out';
              _log('⏳ Timeout while fetching all trips (no cache)');
              if (mounted) setState(() {});
            } else {
              _log(
                '⏳ Timeout while fetching all trips — cache present, ignoring for UI',
              );
            }
          }
        } catch (e) {
          if (myId == _fetchId[fAll]) {
            if (!hadCache) {
              _error[fAll] = 'Network/parse error: $e';
              _log('❌ Exception fetching trips (no cache): $e');
              if (mounted) setState(() {});
            } else {
              _log('❌ Exception fetching trips (ignored, cache present): $e');
            }
          }
        }
      }

      // If we had cache, refresh in background; otherwise await network (first-time load)
      if (cached != null && cached.body.isNotEmpty) {
        // fire-and-forget background refresh
        unawaited(doNetworkFetch());
      } else {
        // no cache: do network fetch inline (wait) so UI receives data
        await doNetworkFetch();
      }
    } on TimeoutException {
      if (myId == _fetchId[fAll]) {
        _error[fAll] = 'Request timed out';
        _log('⏳ Timeout while fetching all trips (outer try)');
      }
    } catch (e) {
      if (myId == _fetchId[fAll]) {
        _error[fAll] = 'Network/parse error: $e';
        _log('❌ Exception fetching trips (outer try): $e');
      }
    } finally {
      watchdog.cancel();
      if (myId == _fetchId[fAll]) {
        for (final k in _loading.keys) {
          _loading[k] = false;
        }
        if (mounted) setState(() {});
      }
    }
  }

  // ---------- UI Builders ----------
  @override
  Widget build(BuildContext context) {
    final list = _currentList();
    final isLoading = _isLoadingFor(_selectedFilter);
    final errMsg = _errorFor(_selectedFilter);

    return Scaffold(
      backgroundColor: backgroundColor,
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
              _titleForFilter(_selectedFilter),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 20,
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: _incentivesLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          const Icon(
                            Icons.account_balance_wallet_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "₹${_incentiveTextForSelectedFilter()}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),

      body: Column(
        children: [
          _buildFiltersRow(),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : (errMsg != null
                      ? _ErrorBlock(
                          message: errMsg,
                          onRetry: () =>
                              _fetchIfNeeded(_selectedFilter, force: true),
                        )
                      : list.isEmpty
                      ? const _EmptyBlock()
                      : RefreshIndicator(
                          key: _refreshKey,
                          onRefresh: () async {
                            await _fetchIfNeeded(_selectedFilter, force: true);
                          },
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: list.length,
                            itemBuilder: (context, index) {
                              final trip = list[index];
                              return FadeTransition(
                                opacity: _fadeAnimation,
                                child: _buildTripCard(trip),
                              );
                            },
                          ),
                        )),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersRow() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [fAll, fToday, fYesterday, fLast7, fThisMonth, fLastMonth]
              .map((filter) {
                final isSelected = _selectedFilter == filter;
                return Container(
                  margin: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () => _onFilterTap(filter),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF2EB9AC)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(
                          color: isSelected ? appGreen : Colors.grey[300]!,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        filter,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                );
              })
              .toList(),
        ),
      ),
    );
  }

  // ---------- Filter Helpers ----------
  void _onFilterTap(String filter) {
    if (_selectedFilter == filter) return;
    setState(() {
      _selectedFilter = filter;
      _searchQuery = '';
    });
    // If we already loaded all trips no network call required; otherwise ensure fetch
    if (!_loaded[fAll]!) {
      _fetchIfNeeded(filter);
    } else {
      // no-op: lists already populated locally
      _animationController.forward(from: 0);
    }
  }

  bool _isLoadingFor(String filter) => _loading[filter] ?? false;
  String? _errorFor(String filter) => _error[filter];

  List<TripItem> _currentList() {
    List<TripItem> base = _data[_selectedFilter] ?? [];

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      base = base.where((t) {
        final d = formatDate(t.tripDate).toLowerCase();
        final st = t.startTime != null
            ? formatTime12(t.startTime!).toLowerCase()
            : '';
        final et = t.endTime != null
            ? formatTime12(t.endTime!).toLowerCase()
            : '';
        return d.contains(q) || st.contains(q) || et.contains(q);
      }).toList();
    }

    base.sort((a, b) {
      final byDate = b.tripDate.compareTo(a.tripDate);
      if (byDate != 0) return byDate;
      final aStart = a.startTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bStart = b.startTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bStart.compareTo(aStart);
    });

    return base;
  }

  // ---------- Formatting ----------
  DateTime _toIST(DateTime utc) => utc.toUtc(); // adjust if you later need IST
  String formatDate(DateTime utc) {
    final dt = _toIST(utc);
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String formatTime12(DateTime utc) {
    final dt = _toIST(utc);
    final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final p = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $p';
  }

  String formatDurationFromSeconds(int? totalSeconds) {
    if (totalSeconds == null) return '--';
    final s = totalSeconds.abs();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final hStr = h > 0 ? '${h}h ' : '';
    final mStr = '${m}m ';
    final sStr = '${sec.toString().padLeft(2, '0')}s';
    return '$hStr$mStr$sStr';
  }

  // ---------- Trip Card ----------
  // NEW
  Widget _buildTripCard(TripItem trip) {
    final isCompleted = trip.endTime != null;

    // friendly distance display
    String distanceText() {
      final km = trip.totalKm ?? trip.distanceKm;
      if (km == null) return '--';
      return '${km.toStringAsFixed(km % 1 == 0 ? 0 : 2)} km';
    }

    void openTripDetails(BuildContext ctx) {
      // OPTION A — push the details screen widget directly (preferred if you have this widget)
      try {
        Navigator.of(ctx).push(
          MaterialPageRoute(builder: (_) => TripDetailsScreen(tripId: trip.id)),
        );
        return;
      } catch (_) {}

      // If neither works, log or show a snackbar
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Unable to open trip details')),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          if (trip.endTime == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "This trip is still ongoing. Details unavailable.",
                ),
                duration: Durations.extralong1,
              ),
            );
            return;
          }

          openTripDetails(context);
        },

        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: Color(0xFF1AB69C)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header section (Date + Status)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Color(0xFF1AB69C),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 18,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        formatDate(trip.tripDate),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? const Color.fromARGB(255, 255, 255, 255)
                            : const Color(0xFFF59E0B),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        isCompleted ? 'Completed' : 'Ongoing',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Trip timing row
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 18,
                      color: Colors.black,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${trip.startTime != null ? formatTime12(trip.startTime!) : "--"}'
                      '  →  '
                      '${trip.endTime != null ? formatTime12(trip.endTime!) : "--"}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Stats Row (Duration + Distance)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,

                  children: [
                    _tripStatTile(
                      icon: Icons.timer_rounded,
                      title: 'Duration',
                      value: formatDurationFromSeconds(trip.durationSeconds),
                      styleType: 'filled',
                    ),

                    const SizedBox(width: 12),

                    _tripStatTile(
                      icon: Icons.route_rounded,
                      title: 'Distance',
                      value: distanceText(),
                      styleType: 'outlined',
                    ),
                  ],
                ),
              ),

              const SizedBox(
                height: 16,
              ), // keep spacing where action row used to be
            ],
          ),
        ),
      ),
    );
  }

  Widget _tripStatTile({
    required IconData icon,
    required String title,
    required String value,
    required String styleType, // "filled" or "outlined"
  }) {
    final Color green = const Color(0xFF1AB69C);

    final bool filled = styleType == "filled";

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: filled ? green : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: filled
              ? Border.all(color: Colors.white, width: 1.5)
              : Border.all(color: green, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 8,
              offset: const Offset(2, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: filled ? Colors.white : green, size: 20),
            const SizedBox(width: 5),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: filled ? Colors.white : green,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: filled ? Colors.white : green,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Models ----------
// ---------- Models ----------
class TripItem {
  final String id;
  final DateTime tripDate;
  final DateTime? startTime;
  final DateTime? endTime;
  final double? distanceKm; // legacy keys
  final double? totalKm; // prefer this from API (you requested)
  final double? durationMinutes;
  final int? durationSeconds; // parsed / derived seconds
  final int? ticketsCount;

  TripItem({
    required this.id,
    required this.tripDate,
    this.startTime,
    this.endTime,
    this.distanceKm,
    this.totalKm,
    this.durationMinutes,
    this.durationSeconds,
    this.ticketsCount,
  });

  factory TripItem.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null || v.toString().isEmpty) return null;
      try {
        return DateTime.parse(v.toString()).toUtc();
      } catch (_) {
        return null;
      }
    }

    final start = parseDate(json['startTime']);
    final end = parseDate(json['endTime']);

    // parse numeric values safely
    double? parseDouble(dynamic v) {
      if (v == null) return null;
      return double.tryParse(v.toString());
    }

    // prefer `totalKm` if provided; fallback to `distanceKm` or `distance`
    final totalKm =
        parseDouble(json['totalKm']) ??
        parseDouble(json['distanceKm']) ??
        parseDouble(json['distance']);

    // duration: prefer explicit seconds, else minutes, else compute from start/end
    int? durSeconds;
    if (json['durationSeconds'] != null) {
      durSeconds = int.tryParse(json['durationSeconds'].toString());
    } else if (json['durationMinutes'] != null) {
      final dm = (json['durationMinutes'] as num).toDouble();
      durSeconds = (dm * 60).round();
    } else if (start != null && end != null) {
      durSeconds = end.difference(start).inSeconds;
    }

    double? durMinutes;
    if (json['durationMinutes'] != null) {
      durMinutes = (json['durationMinutes'] as num).toDouble();
    } else if (durSeconds != null) {
      durMinutes = durSeconds / 60.0;
    }

    return TripItem(
      id: json['_id']?.toString() ?? '',
      tripDate:
          parseDate(json['tripDate']) ??
          (start != null
              ? DateTime.utc(start.year, start.month, start.day)
              : DateTime.now().toUtc()),
      startTime: start,
      endTime: end,
      distanceKm: parseDouble(json['distanceKm'] ?? json['distance']),
      totalKm: totalKm,
      durationMinutes: durMinutes,
      durationSeconds: durSeconds,
      ticketsCount: int.tryParse(json['ticketsCount']?.toString() ?? ''),
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock();

  @override
  Widget build(BuildContext context) => const Center(
    child: Text('No trips found.', style: TextStyle(color: Colors.black54)),
  );
}

class _ErrorBlock extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBlock({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 32),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}
