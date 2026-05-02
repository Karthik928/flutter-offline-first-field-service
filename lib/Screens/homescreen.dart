import 'dart:async';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/Screens/assigned_tasks_screen.dart';
import 'package:FieldService_app/Screens/login_screen.dart';
import 'package:FieldService_app/Screens/clients.dart';
import 'package:FieldService_app/Screens/dashboard_kpi_page.dart';
import 'package:FieldService_app/Screens/orders_screen.dart';
import 'package:FieldService_app/Screens/projection.dart';
import 'package:FieldService_app/Screens/tickets.dart';
import 'package:FieldService_app/Screens/upload_expense_page.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/attendance_service.dart'; // ← NEW
import 'package:FieldService_app/services/employee_task_service.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';
import 'package:FieldService_app/services/unified_location_manager.dart';
import 'package:top_snackbar_flutter/custom_snack_bar.dart';
import 'package:top_snackbar_flutter/top_snack_bar.dart';

import 'trips.dart';
import 'app_drawer.dart';

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final Color appGreen = const Color(0xFF2E7D32);
  final Color lightGreen = const Color(0xFF4CAF50);
  final Color backgroundColor = const Color(0xFFF5F5F5);
  final Color cardBackground = Colors.white;

  // ── Attendance ──────────────────────────────────────────────────────────────
  // All business logic lives in AttendanceService.
  // This widget only holds presentation state (_isOnDuty, _isLoading)
  // and calls the service, then reacts to AttendanceResult.
  late final AttendanceService _attendanceService;

  bool _isOnDuty = false;
  bool _isLoading = false;
  bool _dutyOperationInFlight =
      false; // Synchronous flag to prevent race condition
  late AnimationController _dutyAnimationController;
  late Animation<double> _dutyScaleAnimation;

  // ── General ─────────────────────────────────────────────────────────────────
  bool _isNavigating = false;
  String? _userId;
  final http.Client _statsClient = http.Client();
  //final http.Client _attendanceClient = http.Client();

  String? _firstName;
  String? _lastName;
  String? _username;

  final Color primary = const Color(0xFF1EB89C);
  final Color accent = const Color(0xFF0BA5EC);
  final Color tileBg = const Color(0xFFF7F9FA);

  // ── Incentives / Performance ─────────────────────────────────────────────────
  bool _isIncentivesLoading = false;
  Map<String, double>? _incentivesData;
  String? _focusedLabel;
  double? _focusedValue;
  double _targetValue = 10000;
  double _salesValue = 0;
  double _revenueValue = 0;
  final bool _showSpeedometerInfo = true;

  static const double _overTargetThresholdLow = 1.0;
  static const double _overTargetThresholdHigh = 1.20;
  static const Duration _gaugeAnimDuration = Duration(milliseconds: 600);

  late final AllTasksService _tasksService;
  List<TaskItem> _pendingTasks = [];
  bool _isTasksLoading = true;

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Map<String, dynamic>? _overTargetStatusFor(double value, double target) {
    if (target <= 0) return null;
    final ratio = value / target;
    if (ratio < _overTargetThresholdLow) return null;
    final overPct = (ratio - 1.0) * 100;
    final label = ratio >= _overTargetThresholdHigh
        ? 'Over Target'
        : 'Target Achieved';
    return {'label': label, 'overPercent': overPct, 'ratio': ratio};
  }

  Map<String, dynamic>? overTargetStatus(double value, double target) {
    if (target <= 0 || value <= target) return null;
    final overPercent = ((value - target) / target) * 100;
    return {
      'percent': overPercent,
      'display': '+${overPercent.toStringAsFixed(0)}%',
      'arrow': Icons.arrow_upward,
    };
  }

  double normalizeTarget(double? rawTarget) =>
      (rawTarget == null || rawTarget <= 0) ? 100000 : rawTarget;

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  String get _displayName {
    final f = (_firstName ?? '').trim();
    if (f.isNotEmpty) return f;
    final u = (_username ?? '').trim();
    return u.isNotEmpty ? u : 'User';
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tasksService = AllTasksService();
    _loadPendingTasks();

    _attendanceService = AttendanceService();

    _dutyAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _dutyScaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(
        parent: _dutyAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _loadUserId();
    _loadUserIdAndName();
    _fetchIncentives();
    _initAttendance();
  }

  Future<void> _loadPendingTasks() async {
    final result = await _tasksService.fetchAllTasks();

    if (!mounted) return;

    if (result.error == 'UNAUTHORIZED') {
      await _forceLogout();
      return;
    }

    if (!result.success) {
      _showSnackBar(result.error ?? 'Failed to load tasks');
      setState(() => _isTasksLoading = false);
      return;
    }

    final pending = result.tasks.where((t) => t.isPending).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    // Either store it if you need completed tasks later:
    //final completed = result.tasks.where((t) => !t.isPending).toList();
    // OR just remove the dead line entirely.

    setState(() {
      _pendingTasks = pending;
      // ✅ FIXED
      _isTasksLoading = false;
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: appGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _dutyAnimationController.stop();
    _dutyAnimationController.dispose();
    _attendanceService.dispose();
    _statsClient.close();
    WidgetsBinding.instance.removeObserver(this);
    UnifiedLocationManager().dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      if (kDebugMode) {
        debugPrint(
          '[HomeDashboard] App resumed → syncing attendance from server',
        );
      }
      _reloadAttendance();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // ATTENDANCE — thin UI wrappers around AttendanceService
  // ─────────────────────────────────────────────────────────────────────────────

  /// Boot-time: Load today's status from API and mirror it in UI.
  /// Step 1: Show cached local state instantly (fast UI)
  /// Step 2: Fetch from server to get authoritative state
  /// Step 3: Update UI with server truth
  Future<void> _initAttendance() async {
    if (kDebugMode) {
      debugPrint(
        '[HomeDashboard] _initAttendance: loading local cache + server state...',
      );
    }

    // Step 1: instant local load (today-validated only)
    final prefs = await SharedPreferences.getInstance();
    final flagDate = prefs.getString('dutyStateDate');
    final today = _todayIso();
    final localBool = (flagDate == today)
        ? (prefs.getBool('isOnDuty') ?? false)
        : false;

    if (localBool) {
      if (kDebugMode) {
        debugPrint(
          '[HomeDashboard] _initAttendance: showing local cache ($localBool) as placeholder',
        );
      }
    }
    _applyDutyState(localBool);

    // Step 2: authoritative API sync
    if (kDebugMode) {
      debugPrint('[HomeDashboard] _initAttendance: syncing from server...');
    }
    final result = await _attendanceService.loadTodayAttendance();
    if (!mounted) return;
    if (result.forceLogout) {
      await _forceLogout();
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[HomeDashboard] _initAttendance: server returned isOnDuty=${result.isOnDuty}',
      );
    }
    _applyDutyState(result.isOnDuty);
  }

  /// App resume: Re-sync with server (user may have checked in/out on another device).
  Future<void> _reloadAttendance() async {
    if (kDebugMode) {
      debugPrint('[HomeDashboard] _reloadAttendance: syncing from server...');
    }
    final result = await _attendanceService.loadTodayAttendance();
    if (!mounted) return;
    if (result.forceLogout) {
      await _forceLogout();
      return;
    }
    if (kDebugMode) {
      debugPrint(
        '[HomeDashboard] _reloadAttendance: server returned isOnDuty=${result.isOnDuty}',
      );
    }
    _applyDutyState(result.isOnDuty);
  }

  /// Updates the animation + state flag in one place.
  void _applyDutyState(bool isOnDuty) {
    if (!mounted) return;
    // Stop any in-progress animation before applying new direction
    _dutyAnimationController.stop();
    setState(() => _isOnDuty = isOnDuty);
    isOnDuty
        ? _dutyAnimationController.forward()
        : _dutyAnimationController.reverse();
  }

  void _showAttendanceError(String message) {
    if (!mounted) return;
    final overlay = Overlay.of(context);
    try {
      showTopSnackBar(
        overlay,
        CustomSnackBar.error(message: message),
        displayDuration: const Duration(seconds: 3),
      );
    } catch (_) {
      // Top snack bar failed — log but don't show fallback
      debugPrint('[Attendance] Error display failed');
    }
  }

  Future<void> _updateDutyStatusOn() async {
    if (_dutyOperationInFlight || _isOnDuty || _isLoading) return;
    _dutyOperationInFlight = true;

    setState(() {
      _isLoading = true;
      _isOnDuty = true;
    });
    _dutyAnimationController.forward();

    AttendanceResult? result;
    try {
      if (kDebugMode) {
        debugPrint('[HomeDashboard] _updateDutyStatusOn: calling checkIn...');
      }
      result = await _attendanceService.checkIn(currentDutyState: false);
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('[HomeDashboard] checkIn threw: $e');
      result = const AttendanceResult(
        isOnDuty: false,
        errorMessage: 'Check-in failed. Please try again.',
      );
    } finally {
      _dutyOperationInFlight = false;
      if (mounted) setState(() => _isLoading = false);
    }

    if (!mounted) return;

    if (result.forceLogout) {
      await _forceLogout();
      return;
    }

    if (result.errorMessage == '__NO_INTERNET__') {
      _applyDutyState(false);
      await _showNoInternetDialog();
      return;
    }

    if (result.errorMessage != null) {
      _applyDutyState(false);
      _showAttendanceError(result.errorMessage!);
      return;
    }

    // Success (online or queued-offline)
    if (result.wasQueued) {
      _applyDutyState(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Checked in offline — will sync automatically'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      // Online success — use server response directly, no need to reload
      _applyDutyState(result.isOnDuty);
    }
  }

  Future<void> _updateDutyStatusOff() async {
    if (_dutyOperationInFlight || !_isOnDuty || _isLoading) return;
    _dutyOperationInFlight = true;

    setState(() {
      _isLoading = true;
      _isOnDuty = false;
    });
    _dutyAnimationController.reverse();

    AttendanceResult? result;
    try {
      if (kDebugMode) {
        debugPrint('[HomeDashboard] _updateDutyStatusOff: calling checkOut...');
      }
      result = await _attendanceService.checkOut(currentDutyState: true);
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('[HomeDashboard] checkOut threw: $e');
      result = const AttendanceResult(
        isOnDuty: true,
        errorMessage: 'Check-out failed. Please try again.',
      );
    } finally {
      _dutyOperationInFlight = false;
      if (mounted) setState(() => _isLoading = false);
    }

    if (!mounted) return;

    if (result.forceLogout) {
      await _forceLogout();
      return;
    }

    if (result.errorMessage == '__NO_INTERNET__') {
      _applyDutyState(true);
      await _showNoInternetDialog();
      return;
    }

    if (result.errorMessage != null) {
      _applyDutyState(true);
      _showAttendanceError(result.errorMessage!);
      return;
    }

    if (result.wasQueued) {
      _applyDutyState(false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Checked out offline — will sync automatically'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      // Online success — use server response directly, no need to reload
      _applyDutyState(result.isOnDuty);
    }
  }

  // ── ADD helper ────────────────────────────────────────────────────────────────
  String _todayIso() {
    final now = DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // USER DATA
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _loadUserIdAndName() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _safeSetState(() {
      _userId = prefs.getString('userId');
      _firstName = prefs.getString('firstName');
      _lastName = prefs.getString('lastName');
    });
    if (kDebugMode) {
      debugPrint("🔑 Loaded userId: $_userId, Name: $_firstName $_lastName");
    }
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _safeSetState(() {
      _userId = prefs.getString('userId');
    });
    if (kDebugMode) debugPrint("🔑 Loaded userId: $_userId");
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // FORCE LOGOUT
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _forceLogout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      if (kDebugMode) debugPrint('Error clearing prefs on logout: $e');
    }

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
      showTopSnackBar(
        Overlay.of(context),
        const CustomSnackBar.error(
          message: 'Session expired. Please log in again.',
        ),
        displayDuration: const Duration(seconds: 3),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // DIALOGS  (pure UI — stays here)
  // ─────────────────────────────────────────────────────────────────────────────

  void _showOffDutyConfirmationDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 24,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color.fromARGB(255, 73, 214, 191),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.logout,
                    size: 30,
                    color: Color.fromARGB(255, 238, 235, 235),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Go Off Duty?",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Are you sure you want to go off duty? That will be the End of Today.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          backgroundColor: Colors.grey.shade200,
                        ),
                        child: const Text(
                          "Cancel",
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _updateDutyStatusOff();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          backgroundColor: Colors.red.shade600,
                        ),
                        child: const Text(
                          "Go Off Duty",
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showNoInternetDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 24,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.signal_cellular_connected_no_internet_4_bar,
                  size: 50,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 16),
                const Text(
                  "No Internet Connection",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "You are offline. Please enable mobile data or Wi-Fi to continue.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          backgroundColor: Colors.grey.shade200,
                        ),
                        child: const Text(
                          "OK",
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // NAVIGATION
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _navigateWithInternetCheck(Widget destination) async {
    if (_isNavigating) return;
    _isNavigating = true;
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => destination),
      );
    } finally {
      _isNavigating = false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // INCENTIVES / DASHBOARD STATS  (unchanged)
  // ─────────────────────────────────────────────────────────────────────────────

  bool get _hasCategorySales {
    if (_incentivesData == null) return false;
    return _incentivesData!.values.any((v) => v > 0);
  }

  double _parseNum(dynamic v, {double fallback = 0.0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    if (v is String) {
      final cleaned = v.replaceAll(',', '').trim();
      return double.tryParse(cleaned) ?? fallback;
    }
    return fallback;
  }

  Future<void> _fetchIncentives() async {
    if (_isIncentivesLoading) return;
    setState(() => _isIncentivesLoading = true);

    const String cacheKey = 'dashboard:incentives';

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = await SecureStorageService.getToken();

      if (token == null || token.isEmpty) {
        final cached = prefs.getString(cacheKey);
        if (cached != null && cached.isNotEmpty) {
          final decoded = jsonDecode(cached) as Map<String, dynamic>? ?? {};
          final data = decoded['data'] as Map<String, dynamic>?;
          if (data != null && mounted) _parseDashboardData(data);
        }
        return;
      }

      final uri = AppConfig.u(AppConfig.reportsByToken);
      if (!mounted) return;
      final response = await _statsClient.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 401) {
        if (kDebugMode) {
          debugPrint('❌ 401 Token expired/invalid - Force logout');
        }
        await _forceLogout();
        return;
      }

      if (response.statusCode != 200 && response.statusCode != 201) {
        final cached = prefs.getString(cacheKey);
        if (cached != null && cached.isNotEmpty) {
          final decoded = jsonDecode(cached) as Map<String, dynamic>? ?? {};
          final data = decoded['data'] as Map<String, dynamic>?;
          if (data != null && mounted) _parseDashboardData(data);
        }
        return;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
      final data = decoded['data'] as Map<String, dynamic>?;
      if (data == null) return;

      await prefs.setString(cacheKey, response.body);
      if (mounted) _parseDashboardData(data);
    } catch (e, st) {
      if (kDebugMode) debugPrint('[_fetchIncentives] network error: $e');
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached) as Map<String, dynamic>? ?? {};
        final data = decoded['data'] as Map<String, dynamic>?;
        if (data != null && mounted) {
          _parseDashboardData(data);
          return;
        }
      }
      if (kDebugMode) debugPrint('[_fetchIncentives] error: $e\n$st');
    } finally {
      if (mounted) setState(() => _isIncentivesLoading = false);
    }
  }

  void _parseDashboardData(Map<String, dynamic> data) {
    final salesObj = data['sales'] as Map<String, dynamic>?;
    final revenueObj = data['revenue'] as Map<String, dynamic>?;
    final targetObj = data['target'] as Map<String, dynamic>?;

    final parsedSales = _parseNum(salesObj?['salesAmount']);
    final parsedRevenue = _parseNum(revenueObj?['receivedAmount']);
    final parsedTarget = _parseNum(targetObj?['yearlyTarget']);

    final List<dynamic>? catList = data['categoryWiseSales'] as List<dynamic>?;
    final Map<String, double> categories = {};

    if (catList != null && catList.isNotEmpty) {
      for (final item in catList) {
        if (item is Map<String, dynamic>) {
          final label =
              (item['category'] ??
                      item['name'] ??
                      item['label'] ??
                      item['title'])
                  ?.toString() ??
              'Unknown';
          final value = _parseNum(
            item['amount'] ?? item['value'] ?? item['sales'] ?? 0,
          );
          categories[label] = (categories[label] ?? 0) + value;
        }
      }
    }

    if (mounted) {
      setState(() {
        _incentivesData = categories.isNotEmpty
            ? categories
            : <String, double>{};
        _salesValue = parsedSales;
        _revenueValue = parsedRevenue;
        _targetValue = normalizeTarget(parsedTarget);
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: Colors.white,
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
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            leading: Builder(
              builder: (context) => Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: IconButton(
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      FocusManager.instance.primaryFocus?.unfocus();
                      Scaffold.of(context).openDrawer();
                    },
                    icon: const Icon(
                      Icons.menu_open,
                      color: Colors.white,
                      size: 25,
                    ),
                  ),
                ),
              ),
            ),
            title: Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/FieldServiceLogo.png',
                    width: 28,
                    height: 28,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    "FieldService",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          blurRadius: 17,
                          offset: Offset(3, 9),
                          color: Color(0x22000000),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [_buildDutyToggle()],
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        color: appGreen,
        backgroundColor: Colors.white,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWelcomeSection(),
              const SizedBox(height: 16),
              _buildAssignedTasksSection(),
              const SizedBox(height: 20),
              _buildPerformanceTile(
                compact: w < 360,
                showPie: true,
                showSpeedometer: true,
              ),
              const SizedBox(height: 24),
              _buildStatsGrid(),
              const SizedBox(height: 24),
              _buildQuickActionsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDutyToggle() {
    return AnimatedBuilder(
      animation: _dutyAnimationController,
      builder: (_, _) => Container(
        margin: const EdgeInsets.only(right: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isOnDuty ? 'ON DUTY' : 'OFF DUTY',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            ScaleTransition(
              scale: _dutyScaleAnimation,
              child: GestureDetector(
                // UX 4: Transparent hit-test region fills the ConstrainedBox.
                behavior: HitTestBehavior.translucent,
                onTap: _isLoading
                    ? null
                    : () {
                        // UX 3: Tactile confirmation on critical action.
                        HapticFeedback.mediumImpact();
                        if (_isOnDuty) {
                          _showOffDutyConfirmationDialog();
                        } else {
                          _updateDutyStatusOn();
                        }
                      },
                // UX 4: Minimum 44×44pt touch target.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  child: Center(
                    child: Container(
                      width: 50,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color:
                                (_isOnDuty
                                        ? const Color(0xFF4CAF50)
                                        : Colors.red)
                                    .withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        alignment: _isOnDuty
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: _isOnDuty
                                ? const Color(0xFF1AB69C)
                                : Colors.grey[400],
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: _isLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Icon(
                                  _isOnDuty ? Icons.check : Icons.close,
                                  color: Colors.white,
                                  size: 14,
                                ),
                        ),
                      ),
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

  // ─────────────────────────────────────────────────────────────────────────────
  // UI HELPERS  (all unchanged from original)
  // ─────────────────────────────────────────────────────────────────────────────

  String _formatShortDateIST(DateTime nowUtc) {
    const wdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final ist = nowUtc.toUtc().add(const Duration(hours: 5, minutes: 30));
    return '${wdays[ist.weekday - 1]} ${months[ist.month - 1]} ${ist.day}';
  }

  String _getGreeting() {
    final now = DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
    if (now.hour < 12) return "Good Morning";
    if (now.hour < 17) return "Good Afternoon";
    return "Good Evening";
  }

  Widget _buildWelcomeSection() {
    final nowUtc = DateTime.now().toUtc();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, primary.withValues(alpha: 0.85), primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: appGreen.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 5.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hello $_displayName',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.only(left: 1.0, right: 5.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_getGreeting()}..!',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    _formatShortDateIST(nowUtc),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignedTasksSection() {
    final pending = _pendingTasks;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// HEADER
            Row(
              children: [
                const Text(
                  'Assigned Tasks',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),

                const SizedBox(width: 8),

                /// 🔥 Pending Count Badge (CLEAN)
                if (pending.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      pending.length.toString(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                  ),

                const Spacer(),

                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AssignedTasksScreen(),
                      ),
                    );
                  },
                  child: const Text(
                    'View all',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1AB69C),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            /// LOADING
            if (_isTasksLoading)
              const Center(child: CircularProgressIndicator())
            /// EMPTY
            else if (pending.isEmpty)
              Text(
                'No pending tasks',
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              )
            /// ✅ SINGLE TASK ONLY (BEST UX)
            else
              _CompactTaskTile(task: pending.first),
          ],
        ),
      ),
    );
  }

  Widget _buildIncentivesPieCard({bool compact = false}) {
    if (_isIncentivesLoading) return _buildPieSkeleton();
    if (_incentivesData == null ||
        _incentivesData!.values.every((v) => v == 0)) {
      return _buildEmptyPieCard();
    }

    final colors = [
      const Color(0xFF1E88E5),
      const Color(0xFFFFC107),
      const Color(0xFF43A047),
      const Color(0xFF64B5F6),
      const Color(0xFFE91E63),
    ];

    final entries = _incentivesData!.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0.0, (p, e) => p + e.value);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: SizedBox(
                width: compact ? 115 : 140,
                height: compact ? 115 : 140,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: PieChart(
                        PieChartData(
                          centerSpaceRadius: 0,
                          sectionsSpace: 2,
                          startDegreeOffset: -90,
                          pieTouchData: PieTouchData(
                            touchCallback: (event, response) {
                              if (!event.isInterestedForInteractions ||
                                  response == null ||
                                  response.touchedSection == null) {
                                setState(() {
                                  _focusedLabel = null;
                                  _focusedValue = null;
                                });
                                return;
                              }
                              final int index =
                                  response.touchedSection!.touchedSectionIndex;
                              if (index < 0 || index >= entries.length) {
                                setState(() {
                                  _focusedLabel = null;
                                  _focusedValue = null;
                                });
                                return;
                              }
                              final entry = entries[index];
                              setState(() {
                                _focusedLabel = entry.key;
                                _focusedValue = entry.value;
                              });
                            },
                          ),
                          sections: List.generate(entries.length, (i) {
                            final value = entries[i].value;
                            final percent = total > 0
                                ? (value / total * 100)
                                : 0.0;
                            return PieChartSectionData(
                              value: value,
                              color: colors[i % colors.length],
                              radius: compact ? 60 : 70,
                              title: '${percent.toStringAsFixed(0)}%',
                              titleStyle: TextStyle(
                                fontSize: compact ? 11 : 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                              titlePositionPercentageOffset: 0.60,
                            );
                          }),
                        ),
                      ),
                    ),
                    if (_focusedLabel != null && _focusedValue != null)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.96),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _focusedLabel!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _focusedValue!.toStringAsFixed(0),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                              Text(
                                "(${((_focusedValue! / total) * 100).toStringAsFixed(0)}%)",
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildPieSkeleton() {
    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  Widget _buildEmptyPieCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1AB69C), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1AB69C).withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Center(
        child: Text(
          "No incentive activity available",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // _buildVehicleSpeedometer — chosen is now a LOCAL variable, never a field.
  // This eliminates the "side-effectful build" anti-pattern.
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildVehicleSpeedometer({
    required double salesValue,
    required double revenueValue,
    required double maxValue,
    bool compact = false,
  }) {
    final double actualSalesPercent = maxValue == 0
        ? 0.0
        : (salesValue / maxValue);
    final double actualRevenuePercent = maxValue == 0
        ? 0.0
        : (revenueValue / maxValue);

    final salesStatus = _overTargetStatusFor(salesValue, maxValue);
    final revenueStatus = _overTargetStatusFor(revenueValue, maxValue);
    final salesOver = overTargetStatus(salesValue, maxValue);
    final revenueOver = overTargetStatus(revenueValue, maxValue);

    // ── Determine badge data as pure local computation ────────────────────────
    Map<String, dynamic>? chosenStatus;
    if (salesStatus != null && revenueStatus != null) {
      chosenStatus = (salesStatus['ratio'] >= revenueStatus['ratio'])
          ? salesStatus
          : revenueStatus;
    } else {
      chosenStatus = salesStatus ?? revenueStatus;
    }

    // ── Over-target display badge (also local) ────────────────────────────────
    Map<String, dynamic>? chosenOverTarget;
    if (salesOver != null && revenueOver != null) {
      chosenOverTarget = salesOver['percent'] >= revenueOver['percent']
          ? salesOver
          : revenueOver;
    } else {
      chosenOverTarget = salesOver ?? revenueOver;
    }

    final bool isOver = chosenStatus != null;

    final double clampedSales = salesValue.clamp(0.0, maxValue);
    final double clampedRevenue = revenueValue.clamp(0.0, maxValue);
    final double salesProgress = maxValue == 0
        ? 0.0
        : (clampedSales / maxValue).clamp(0.0, 1.0);
    final double revenueProgress = maxValue == 0
        ? 0.0
        : (clampedRevenue / maxValue).clamp(0.0, 1.0);

    final double padding = compact ? 8.0 : 12.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 420),
      padding: EdgeInsets.only(
        left: padding + 5,
        right: padding + 5,
        top: padding,
        bottom: padding + 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1AB69C), width: 1.0),
        boxShadow: isOver
            ? [
                BoxShadow(
                  color: const Color(0xFF1AB69C).withValues(alpha: 0.16),
                  blurRadius: 22,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _legendDot(
                      label: 'Sales',
                      color: const Color.fromARGB(221, 197, 4, 4),
                    ),
                    _legendDot(
                      label: 'Revenue',
                      color: const Color(0xFF1AB69C),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: compact ? 140 : 160,
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: 24,
                    left: 6.0,
                    right: 6.0,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      return RepaintBoundary(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: size,
                              painter: _SpeedometerArcPainter(
                                maxValue: maxValue,
                              ),
                            ),
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: salesProgress),
                              duration: _gaugeAnimDuration,
                              curve: Curves.easeOutCubic,
                              builder: (context, animSales, _) {
                                return CustomPaint(
                                  size: size,
                                  painter: _SpeedometerNeedlePainter(
                                    animSales,
                                    color: const Color.fromARGB(221, 197, 4, 4),
                                    thicknessFactor: 0.28,
                                  ),
                                );
                              },
                            ),
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: revenueProgress),
                              duration: _gaugeAnimDuration,
                              curve: Curves.easeOutCubic,
                              builder: (context, animRevenue, _) {
                                return CustomPaint(
                                  size: size,
                                  painter: _SpeedometerNeedlePainter(
                                    animRevenue,
                                    color: const Color(0xFF1AB69C),
                                    thicknessFactor: 0.50,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: !_showSpeedometerInfo
                    ? const SizedBox.shrink()
                    : Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _speedInfoBlock(
                              label: 'Sales',
                              value: salesValue,
                              percent: actualSalesPercent,
                              color: Colors.black87,
                            ),
                            _speedInfoBlock(
                              label: 'Revenue',
                              value: revenueValue,
                              percent: actualRevenuePercent,
                              color: const Color(0xFF1AB69C),
                            ),
                            _speedInfoBlock(
                              label: 'Target',
                              value: maxValue,
                              percent: null,
                              color: Colors.black54,
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
          // ── Badge: only shown when over target ──────────────────────────────
          if (isOver && chosenStatus != null)
            Positioned(
              right: -8,
              top: -10,
              child: _buildTargetBadge(
                label: chosenStatus['label'] as String,
                overPercent: chosenStatus['overPercent'] as double,
                // Pass the computed local value — no more class-level mutation.
                chosenOverTarget: chosenOverTarget,
              ),
            ),
        ],
      ),
    );
  }

  // ── _buildTargetBadge now accepts chosenOverTarget as a parameter ─────────────
  Widget _buildTargetBadge({
    required String label,
    required double overPercent,
    required Map<String, dynamic>? chosenOverTarget,
  }) {
    final display = chosenOverTarget?['display'] as String? ?? '';
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1AB69C),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_upward, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              display,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _speedInfoBlock({
    required String label,
    required double value,
    required double? percent,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        if (percent != null)
          Text(
            percent <= 1
                ? "${(percent * 100).toStringAsFixed(0)}%"
                : "+${((percent - 1) * 100).toStringAsFixed(0)}%",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: percent > 1 ? const Color(0xFF1AB69C) : Colors.black45,
            ),
          ),
      ],
    );
  }

  Widget _legendDot({required String label, required Color color}) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceTile({
    bool compact = false,
    bool showPie = true,
    bool showSpeedometer = true,
  }) {
    final bool effectiveShowPie = showPie && _hasCategorySales;
    final titleRow = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Performance',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF50C6B4),
          ),
        ),
        TextButton(
          onPressed: () {
            if (mounted) {
              _navigateWithInternetCheck(const DashboardKpiPage());
            }
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            backgroundColor: Colors.transparent,
          ),
          child: const Text(
            "View all",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1AB69C),
            ),
          ),
        ),
      ],
    );

    final w = MediaQuery.of(context).size.width;
    final isCompact = compact || w < 360;
    const double visualHeight = 240;

    final List<Widget> children = [];

    if (effectiveShowPie) {
      children.add(
        SizedBox(
          height: visualHeight,
          child: _buildIncentivesPieCard(compact: isCompact),
        ),
      );
    }

    if (showSpeedometer) {
      children.add(
        _buildVehicleSpeedometer(
          salesValue: _salesValue,
          revenueValue: _revenueValue,
          maxValue: _targetValue,
          compact: isCompact,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [titleRow, const SizedBox(height: 12), ...children],
    );
  }

  Widget _buildStatsGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Overview',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF50C6B4),
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: _gridAspectRatio(context),
          children: [
            _buildFeatureCard(
              icon: Icons.people_outline,
              title: "Clients",
              caption: "View Clients",
              color: const Color(0xFF50C6B4),
              onTap: () => _navigateWithInternetCheck(const ClientsPage()),
            ),
            _buildFeatureCard(
              icon: Icons.people_outline,
              title: "Projections",
              caption: "Payments",
              color: const Color(0xFF50C6B4),
              onTap: () => _navigateWithInternetCheck(const ProjectionPage()),
            ),
            _buildFeatureCard(
              icon: Icons.production_quantity_limits_outlined,
              title: "Orders",
              caption: "Check Orders",
              color: const Color(0xFF50C6B4),
              onTap: () => _navigateWithInternetCheck(
                const OrdersScreen(condition: false),
              ),
            ),
            _buildFeatureCard(
              icon: Icons.cases_outlined,
              title: "Queries",
              caption: "Check Status",
              color: const Color(0xFF50C6B4),
              onTap: () => _navigateWithInternetCheck(
                const TicketsPage(condition: false),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String caption,
    required Color color,
    VoidCallback? onTap,
  }) {
    final w = MediaQuery.of(context).size.width;
    final ts = MediaQuery.textScalerOf(context).scale(1);
    final titleSize = (w < 360 ? 18.0 : 20.0) / (ts > 1.2 ? 1.05 : 1.0);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: color.withValues(alpha: 0.08),
        highlightColor: color.withValues(alpha: 0.04),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF1AB69C).withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color.fromARGB(
                  255,
                  0,
                  0,
                  0,
                ).withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          color.withValues(alpha: 0.20),
                          color.withValues(alpha: 0.10),
                        ],
                      ),
                      border: Border.all(color: color.withValues(alpha: 0.15)),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const Spacer(),
                  if (onTap != null)
                    const Icon(
                      Icons.chevron_right,
                      size: 25,
                      color: Color.fromARGB(255, 0, 0, 0),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                caption,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black.withValues(alpha: 0.40),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Operations',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF50C6B4),
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: _gridAspectRatio(context),
          children: [
            _buildFeatureCard(
              icon: Icons.location_pin,
              title: "Trip Log",
              caption: "Track Trips",
              color: const Color(0xFF50C6B4),
              onTap: () => _navigateWithInternetCheck(
                const Trips(initialFilter: 'Today'),
              ),
            ),
            _buildFeatureCard(
              icon: Icons.receipt_long_outlined,
              title: "Upload Bill",
              caption: "Expense bill",
              color: const Color(0xFF50C6B4),
              onTap: () =>
                  _navigateWithInternetCheck(const UploadExpensePage()),
            ),
          ],
        ),
      ],
    );
  }

  double _gridAspectRatio(BuildContext context) {
    final mq = MediaQuery.of(context);
    final ts = mq.textScaler.scale(1);
    final w = mq.size.width;
    double ratio = 1.25;
    if (w < 360) ratio = 1.12;
    ratio -= (ts - 1.0) * 0.1;
    return ratio.clamp(1.05, 1.5);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // PULL-TO-REFRESH
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _refreshAll() async {
    try {
      await Future.wait([
        _reloadAttendance(),
        _fetchIncentives(),
        _loadPendingTasks(),
      ]);
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          'Refresh failed. Please check your network and try again.',
        );
      }
      if (kDebugMode) debugPrint('[_refreshAll] Error: $e');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom Painters  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

class _SpeedometerArcPainter extends CustomPainter {
  final double maxValue;
  _SpeedometerArcPainter({required this.maxValue});

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = (size.width * 0.12).clamp(8.0, 20.0);
    final radius = (size.width / 2) - strokeWidth * 0.6;
    final center = Offset(size.width / 2, size.height * 0.95);
    const startAngle = pi;
    const sweepAngle = pi;
    final arcRect = Rect.fromCircle(center: center, radius: radius);

    final thresholds = [0.35, 0.6, 0.8, 1.0];
    final colors = const [
      Color(0xFFF44336),
      Color(0xFFFF9800),
      Color(0xFFFFEB3B),
      Color(0xFF4CAF50),
    ];

    const int segments = 42;
    for (int i = 0; i < segments; i++) {
      final fracStart = i / segments;
      final fracSweep = 1 / segments;
      Color segColor = colors.last;
      for (int t = 0; t < thresholds.length; t++) {
        if (fracStart <= thresholds[t]) {
          segColor = colors[t];
          break;
        }
      }
      final paint = Paint()
        ..color = segColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        arcRect,
        startAngle + sweepAngle * fracStart,
        sweepAngle * fracSweep,
        false,
        paint,
      );
    }

    final minorTickPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..strokeWidth = 1.0;
    final majorTickPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..strokeWidth = 2.6;

    const int majorDivisions = 10;
    for (int i = 0; i <= majorDivisions; i++) {
      final frac = i / majorDivisions;
      final angle = startAngle + sweepAngle * frac;
      final outer = Offset(
        center.dx + (radius + strokeWidth * 0.20) * cos(angle),
        center.dy + (radius + strokeWidth * 0.20) * sin(angle),
      );
      final inner = Offset(
        center.dx + (radius - strokeWidth * 0.45) * cos(angle),
        center.dy + (radius - strokeWidth * 0.45) * sin(angle),
      );
      canvas.drawLine(inner, outer, majorTickPaint);
      if (i < majorDivisions) {
        for (int m = 1; m <= 3; m++) {
          final subFrac = (i + m / 4) / majorDivisions;
          final subAngle = startAngle + sweepAngle * subFrac;
          final so = Offset(
            center.dx + (radius + strokeWidth * 0.16) * cos(subAngle),
            center.dy + (radius + strokeWidth * 0.16) * sin(subAngle),
          );
          final si = Offset(
            center.dx + (radius - strokeWidth * 0.30) * cos(subAngle),
            center.dy + (radius - strokeWidth * 0.30) * sin(subAngle),
          );
          canvas.drawLine(si, so, minorTickPaint);
        }
      }
    }

    final labelStyle = TextStyle(
      color: Colors.black54,
      fontSize: (size.width * 0.025).clamp(8.0, 12.0),
      fontWeight: FontWeight.w600,
    );
    final stepValue = maxValue / majorDivisions;
    String fmt(double v) {
      if (v >= 1e7) return '${(v / 1e7).toStringAsFixed(1)}Cr';
      if (v >= 1e5) return '${(v / 1e5).toStringAsFixed(1)}L';
      if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
      return v.toInt().toString();
    }

    final normalOffset = strokeWidth * 0.9;
    final edgeExtra = strokeWidth * 0.15;
    final edgeDrop = strokeWidth * 0.45;

    for (int i = 0; i <= majorDivisions; i++) {
      final frac = i / majorDivisions;
      final angle = startAngle + sweepAngle * frac;
      final bool isStart = i == 0;
      final bool isEnd = i == majorDivisions;
      final tp = TextPainter(
        text: TextSpan(text: fmt(stepValue * i), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final arcPoint = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
      final normal = Offset(cos(angle), sin(angle));
      final tangent = Offset(-sin(angle), cos(angle));
      final double extraOffset = isStart
          ? edgeExtra
          : isEnd
          ? edgeExtra + 7
          : 5;
      Offset labelCenter = arcPoint + normal * (normalOffset + extraOffset);
      if (isStart || isEnd) {
        labelCenter += tangent * (tp.width * (isStart ? 2 : -0.45));
        labelCenter = labelCenter.translate(0, edgeDrop);
      }
      final dx = isStart
          ? labelCenter.dx
          : isEnd
          ? labelCenter.dx - tp.width
          : labelCenter.dx - tp.width / 2;
      final dy = labelCenter.dy - tp.height / 2;
      tp.paint(canvas, Offset(dx, dy));
    }

    final outerRingPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius + strokeWidth * 0.55),
      startAngle,
      sweepAngle,
      false,
      outerRingPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SpeedometerArcPainter old) =>
      old.maxValue != maxValue;
}

class _SpeedometerNeedlePainter extends CustomPainter {
  final double progress;
  final Color color;
  final double thicknessFactor;

  _SpeedometerNeedlePainter(
    this.progress, {
    required this.color,
    required this.thicknessFactor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final baseStroke = (size.width * 0.12).clamp(8.0, 20.0);
    final radius = (size.width / 2) - baseStroke * 0.6;
    final center = Offset(size.width / 2, size.height * 0.95);
    final p = progress.clamp(0.0, 1.0);
    final angle = pi + (pi * p);
    final stroke = (baseStroke * thicknessFactor).clamp(1.8, 10.0);
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final end = Offset(
      center.dx + radius * 0.90 * cos(angle),
      center.dy + radius * 0.90 * sin(angle),
    );
    canvas.drawLine(center, end, paint);
    final outerRadius = (baseStroke * 0.22).clamp(6.0, 12.0);
    canvas.drawCircle(
      center,
      outerRadius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );
    final innerRadius = outerRadius * 0.55;
    canvas.drawCircle(
      center,
      innerRadius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(center, innerRadius * 0.35, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SpeedometerNeedlePainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.thicknessFactor != thicknessFactor;
}

class _CompactTaskTile extends StatelessWidget {
  final TaskItem task;

  const _CompactTaskTile({required this.task});

  Color _priorityColor() {
    switch (task.priority.toLowerCase()) {
      case 'high':
        return const Color(0xFFEF4444);
      case 'medium':
        return const Color(0xFFF59E0B);
      case 'low':
        return const Color(0xFF1AB69C);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AssignedTasksScreen()),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            /// PRIORITY DOT
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _priorityColor(),
                shape: BoxShape.circle,
              ),
            ),

            const SizedBox(width: 10),

            /// TEXT
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${task.dueDateLabel} • ${task.priority}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),

            const Icon(Icons.chevron_right, size: 18, color: Colors.black38),
          ],
        ),
      ),
    );
  }
}
