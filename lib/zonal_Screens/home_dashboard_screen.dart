import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/Screens/app_drawer.dart';
import 'package:FieldService_app/Screens/assigned_tasks_screen.dart';
import 'package:FieldService_app/Screens/dashboard_kpi_page.dart';
import 'package:FieldService_app/Screens/login_screen.dart';
import 'package:FieldService_app/Screens/trips.dart';
import 'package:FieldService_app/Screens/upload_expense_page.dart';
import 'package:FieldService_app/services/attendance_service.dart';
import 'package:FieldService_app/services/employee_task_service.dart';
import 'package:FieldService_app/zonal_Screens/dealer_list_screen.dart';
import 'package:FieldService_app/zonal_Screens/farmer_list_screen.dart';
import 'package:FieldService_app/zonal_Screens/field_support_screen.dart';
import 'package:FieldService_app/zonal_Screens/field_team_screen.dart';
import 'package:FieldService_app/zonal_Screens/orders_management_screen.dart';
import 'package:FieldService_app/zonal_Screens/task_manager_screen.dart';
import 'package:FieldService_app/zonal_Screens/zonal_dealer_visits_screen.dart';
import 'package:FieldService_app/zonal_Screens/zonal_farmer_visits_screen.dart';
import 'package:FieldService_app/zonal_services/zonal_dashboard_service.dart';
import 'package:FieldService_app/zonal_services/zonal_kpi_service.dart';
import 'package:top_snackbar_flutter/custom_snack_bar.dart';
import 'package:top_snackbar_flutter/top_snack_bar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SHIMMER UTILITY
// A lightweight shimmer that requires zero external packages.
// ─────────────────────────────────────────────────────────────────────────────

class _Shimmer extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const _Shimmer({required this.width, required this.height, this.radius = 8});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = Tween<double>(
      begin: -1.5,
      end: 1.5,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(_anim.value - 1, 0),
              end: Alignment(_anim.value, 0),
              colors: const [
                Color(0xFFEEEEEE),
                Color(0xFFF8F8F8),
                Color(0xFFEEEEEE),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // ── Palette ─────────────────────────────────────────────────────────────────
  static const _gradientStart = Color(0xFF52D494);
  static const _gradientEnd = Color(0xFF1AB69C);
  static const _accentGreen = Color(0xFF1AB69C);

  // ── Attendance ──────────────────────────────────────────────────────────────
  late final AttendanceService _attendanceService;
  bool _isOnDuty = false;
  bool _isDutyLoading = false;

  late AnimationController _dutyAnimationController;
  late Animation<double> _dutyScaleAnimation;

  // ── User ────────────────────────────────────────────────────────────────────
  String _firstName = '';
  String _lastName = '';

  // ── Team dashboard ──────────────────────────────────────────────────────────
  late final ZonalDashboardService _dashboardService;
  Map<String, dynamic>? _dashboardData;

  // ── Personal KPI ────────────────────────────────────────────────────────────
  late final ZonalKpiService _kpiService;
  ZonalKpiResult _kpiData = ZonalKpiResult.empty;

  // ── Tasks ───────────────────────────────────────────────────────────────────
  late final AllTasksService _tasksService;
  List<TaskItem> _pendingTasks = [];

  // ── Loading flags (granular — each section shimmer independently) ────────────
  bool _isDashboardLoading = true;
  bool _isKpiLoading = true;
  bool _isTasksLoading = true;

  // ─────────────────────────────────────────────────────────────────────────────
  // Convenience getters
  // ─────────────────────────────────────────────────────────────────────────────

  String get _fullName {
    final n = '$_firstName $_lastName'.trim();
    return n.isEmpty ? 'User' : n;
  }

  Map<String, dynamic> get _teamActivity =>
      _dashboardData?['teamActivity'] ?? {};
  Map<String, dynamic> get _teamPerformance =>
      _dashboardData?['teamPerformance'] ?? {};

  // ── ADD: Synchronous in-flight guard to prevent race-condition double-tap (Bug 1)
  bool _dutyOperationInFlight = false;

  // ─────────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attendanceService = AttendanceService();
    _dashboardService = ZonalDashboardService();
    _kpiService = ZonalKpiService();
    _tasksService = AllTasksService();

    _dutyAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _dutyScaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(
        parent: _dutyAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    // ── Fire all data fetches IN PARALLEL ────────────────────────────────────
    // Using Future.wait at the top-level ensures none of them block each other.
    // Attendance is independent and light so it runs concurrently too.
    _bootstrapAll();
  }

  /// Kicks off every data source concurrently.
  /// Each source updates its own loading flag independently so the UI
  /// progressively reveals sections as data arrives.
  Future<void> _bootstrapAll() async {
    await Future.wait([
      _safe(_loadUserData),
      _safe(_loadDashboard),
      _safe(_loadKpi),
      _safe(_loadPendingTasks),
      _safe(_initAttendance),
    ]);

    // All done — dismiss any remaining full-page shimmer.
    //if (mounted) setState(() => _isPageLoading = false);
  }

  Future<void> _safe(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ bootstrap error: $e');
    }
  }

  // ── ADD lifecycle resync ──────────────────────────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _reloadAttendance();
    }
  }

  @override
  void dispose() {
    _dutyAnimationController.dispose();
    _attendanceService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _kpiService.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // DATA LOADING  — every method has a timeout + graceful fallback
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 5),
      );
      if (!mounted) return;
      setState(() {
        _firstName = prefs.getString('firstName') ?? '';
        _lastName = prefs.getString('lastName') ?? '';
      });
    } catch (_) {
      // SharedPreferences failure is non-fatal — user just sees 'User'
    }
  }

  Future<void> _loadDashboard() async {
    try {
      final result = await _dashboardService.fetchDashboard().timeout(
        const Duration(seconds: 15),
      );
      if (!mounted) return;

      if (result.error == 'UNAUTHORIZED') {
        await _forceLogout();
        return;
      }

      if (!result.success) {
        // Non-fatal: section stays in shimmer / empty state
        debugPrint('[Dashboard] fetch failed: ${result.error}');
      } else {
        setState(() => _dashboardData = result.data);
      }
    } on Exception catch (e) {
      debugPrint('[Dashboard] timeout or error: $e');
      // No rethrow — other sections must not be blocked.
    } finally {
      if (mounted) setState(() => _isDashboardLoading = false);
    }
  }

  Future<void> _loadKpi() async {
    try {
      final result = await _kpiService.fetchKpi().timeout(
        const Duration(seconds: 15),
      );
      if (!mounted) return;

      if (result.forceLogout) {
        await _forceLogout();
        return;
      }

      setState(() => _kpiData = result);
    } on Exception catch (e) {
      debugPrint('[KPI] timeout or error: $e');
    } finally {
      if (mounted) setState(() => _isKpiLoading = false);
    }
  }

  Future<void> _loadPendingTasks() async {
    try {
      final result = await _tasksService.fetchAllTasks().timeout(
        const Duration(seconds: 15),
      );
      if (!mounted) return;

      if (result.error == 'UNAUTHORIZED') {
        await _forceLogout();
        return;
      }

      if (result.success) {
        final pending = result.tasks.where((t) => t.isPending).toList()
          ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
        setState(() => _pendingTasks = pending);
      }
    } on Exception catch (e) {
      debugPrint('[Tasks] timeout or error: $e');
    } finally {
      if (mounted) setState(() => _isTasksLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // ATTENDANCE
  // ─────────────────────────────────────────────────────────────────────────────

  /// Boot-time: Load today's status from API and mirror it in UI.
  /// Step 1: Show cached local state instantly (fast UI)
  /// Step 2: Fetch from server to get authoritative state
  /// Step 3: Update UI with server truth
  Future<void> _initAttendance() async {
    try {
      debugPrint(
        '[HomeDashboardScreen] _initAttendance: loading local cache + server state...',
      );

      final prefs = await SharedPreferences.getInstance();
      final flagDate = prefs.getString('dutyStateDate');
      final today = _todayIso();
      final local = (flagDate == today)
          ? (prefs.getBool('isOnDuty') ?? false)
          : false;

      if (local) {
        debugPrint(
          '[HomeDashboardScreen] _initAttendance: showing local cache ($local) as placeholder',
        );
      }
      _applyDutyState(local);

      debugPrint(
        '[HomeDashboardScreen] _initAttendance: syncing from server...',
      );
      final result = await _attendanceService.loadTodayAttendance();
      if (!mounted) return;
      if (result.forceLogout) {
        await _forceLogout();
        return;
      }
      debugPrint(
        '[HomeDashboardScreen] _initAttendance: server returned isOnDuty=${result.isOnDuty}',
      );
      _applyDutyState(result.isOnDuty);
    } on Exception catch (e) {
      debugPrint('[HomeDashboardScreen] _initAttendance error: $e');
    }
  }

  /// App resume: Re-sync with server (user may have checked in/out on another device).
  Future<void> _reloadAttendance() async {
    try {
      debugPrint(
        '[HomeDashboardScreen] _reloadAttendance: syncing from server...',
      );
      final result = await _attendanceService.loadTodayAttendance().timeout(
        const Duration(seconds: 15),
      );
      if (!mounted) return;
      if (result.forceLogout) {
        await _forceLogout();
        return;
      }
      debugPrint(
        '[HomeDashboardScreen] _reloadAttendance: server returned isOnDuty=${result.isOnDuty}',
      );
      _applyDutyState(result.isOnDuty);
    } on Exception catch (e) {
      debugPrint('[HomeDashboardScreen] _reloadAttendance error: $e');
    }
  }

  void _applyDutyState(bool isOnDuty) {
    if (!mounted) return;
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

  // ── REPLACE _updateDutyStatusOn ───────────────────────────────────────────────
  /// Check-in handler. Guards against:
  /// - Race-condition double-tap    (Bug 1: _dutyOperationInFlight)
  /// - Double network call on success (Bug 4: use result.isOnDuty directly)
  Future<void> _updateDutyStatusOn() async {
    // Bug 1: Synchronous flag checked BEFORE any async gap.
    if (_dutyOperationInFlight || _isOnDuty || _isDutyLoading) return;
    _dutyOperationInFlight = true;

    setState(() {
      _isDutyLoading = true;
      _isOnDuty = true; // Optimistic UI
    });
    _dutyAnimationController.forward();

    AttendanceResult? result;
    try {
      debugPrint(
        '[HomeDashboardScreen] _updateDutyStatusOn: calling checkIn...',
      );
      result = await _attendanceService
          .checkIn(currentDutyState: false)
          .timeout(const Duration(seconds: 20));
    } on Exception catch (e) {
      debugPrint('[HomeDashboardScreen] checkIn threw: $e');
      result = const AttendanceResult(
        isOnDuty: false,
        errorMessage: 'Check-in failed. Please try again.',
      );
    } finally {
      // Bug 1: Always release the flag before returning.
      _dutyOperationInFlight = false;
      if (mounted) setState(() => _isDutyLoading = false);
    }

    if (!mounted) return;

    if (result.forceLogout) {
      await _forceLogout();
      return;
    }

    if (result.errorMessage == '__NO_INTERNET__') {
      _applyDutyState(false); // rollback optimistic
      // Bug 5: await so the caller pauses until the user dismisses the dialog.
      await _showNoInternetDialog();
      return;
    }

    if (result.errorMessage != null) {
      _applyDutyState(false); // rollback optimistic
      _showAttendanceError(result.errorMessage!);
      return;
    }

    if (result.wasQueued) {
      _applyDutyState(true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Checked in offline — will sync automatically'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      // Bug 4: Server already confirmed state in the response body.
      // No need to fire a second GET request — use result directly.
      _applyDutyState(result.isOnDuty);
    }
  }

  /// Check-out handler. Guards against:
  /// - Race-condition double-tap    (Bug 1: _dutyOperationInFlight)
  /// - Double network call on success (Bug 4: use result.isOnDuty directly)
  Future<void> _updateDutyStatusOff() async {
    debugPrint(
      '[HomeDashboardScreen] _updateDutyStatusOff: entry '
      '_isOnDuty=$_isOnDuty _isDutyLoading=$_isDutyLoading',
    );

    // Bug 1: Synchronous flag checked BEFORE any async gap.
    if (_dutyOperationInFlight || !_isOnDuty || _isDutyLoading) return;
    _dutyOperationInFlight = true;

    setState(() {
      _isDutyLoading = true;
      _isOnDuty = false; // Optimistic UI
    });
    _dutyAnimationController.reverse();

    AttendanceResult? result;
    try {
      debugPrint(
        '[HomeDashboardScreen] _updateDutyStatusOff: calling checkOut...',
      );
      result = await _attendanceService
          .checkOut(currentDutyState: true)
          .timeout(const Duration(seconds: 20));
      debugPrint(
        '[HomeDashboardScreen] checkOut returned: '
        'isOnDuty=${result.isOnDuty} '
        'forceLogout=${result.forceLogout} '
        'wasQueued=${result.wasQueued} '
        'error=${result.errorMessage}',
      );
    } on Exception catch (e) {
      debugPrint('[HomeDashboardScreen] checkOut threw: $e');
      result = const AttendanceResult(
        isOnDuty: true,
        errorMessage: 'Check-out failed. Please try again.',
      );
    } finally {
      // Bug 1: Always release the flag before returning.
      _dutyOperationInFlight = false;
      if (mounted) setState(() => _isDutyLoading = false);
    }

    if (!mounted) return;

    if (result.forceLogout) {
      await _forceLogout();
      return;
    }

    if (result.errorMessage == '__NO_INTERNET__') {
      _applyDutyState(true); // rollback optimistic
      // Bug 5: await so the caller pauses until the user dismisses the dialog.
      await _showNoInternetDialog();
      return;
    }

    if (result.errorMessage != null) {
      _applyDutyState(true); // rollback optimistic
      _showAttendanceError(result.errorMessage!);
      return;
    }

    if (result.wasQueued) {
      _applyDutyState(false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Checked out offline — will sync automatically'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      // Bug 4: Use server-confirmed state directly. No second GET.
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
  // AUTH
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _forceLogout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}

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
  // DIALOGS
  // ─────────────────────────────────────────────────────────────────────────────

  void _showOffDutyConfirmationDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
                'Go Off Duty?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Are you sure you want to go off duty? '
                'That will be the End of Today.',
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
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        backgroundColor: Colors.grey.shade200,
                      ),
                      child: const Text(
                        'Cancel',
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
                        Navigator.of(ctx).pop();
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
                        'Go Off Duty',
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
      ),
    );
  }

  /// Bug 5: Returns Future<void> and uses `await showDialog` internally
  /// so callers that `await _showNoInternetDialog()` correctly pause
  /// until the user taps OK — not just until the dialog is shown.
  Future<void> _showNoInternetDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.signal_cellular_connected_no_internet_4_bar,
                size: 50,
                color: Color(0xFF1AB69C),
              ),
              const SizedBox(height: 16),
              const Text(
                'No Internet Connection',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1AB69C),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'You are offline. Please enable mobile data '
                'or Wi-Fi to continue.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF6B7280),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    backgroundColor: const Color(0xFFF7F9FA),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF0BA5EC),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F3),
      drawer: const AppDrawer(),
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        onRefresh: refreshAllData,
        color: _accentGreen,
        backgroundColor: Colors.white,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGreetingSection(),
                const SizedBox(height: 20),
                _buildSectionTitle('Team Activity'),
                const SizedBox(height: 8),
                _buildTeamGrid(),
                const SizedBox(height: 20),
                _buildSectionTitle('Quick Actions'),
                const SizedBox(height: 10),
                _buildQuickActions(),
                const SizedBox(height: 24),
                _buildSectionTitle('Operations'),
                const SizedBox(height: 8),
                _buildQuickActionsSection(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
      // ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // APP BAR
  // ─────────────────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_gradientStart, _gradientEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
          ),
          leading: Builder(
            builder: (ctx) => Container(
              margin: const EdgeInsets.all(10),
              child: Center(
                child: IconButton(
                  onPressed: () {
                    FocusScope.of(ctx).unfocus();
                    FocusManager.instance.primaryFocus?.unfocus();
                    Scaffold.of(ctx).openDrawer();
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
            padding: const EdgeInsets.only(left: 8),
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
                  'FieldService',
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
    );
  }

  /// Duty toggle widget.
  /// UX 3: HapticFeedback.mediumImpact() on every tap.
  /// UX 4: ConstrainedBox enforces 44×44pt minimum touch target per
  ///        Material/HIG guidelines — prevents missed taps on small fingers.
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
                onTap: _isDutyLoading
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
                          child: _isDutyLoading
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
  // GREETING SECTION
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildGreetingSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hello, $_fullName',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Zonal Manager',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 16),

          // ── Team Performance ─────────────────────────────────────────────
          _isDashboardLoading
              ? _buildCardShimmer(height: 130)
              : _buildStatCard(
                  label: 'TEAM PERFORMANCE',
                  value:
                      '₹${_teamPerformance['achieved'] ?? 0} / '
                      '₹${_teamPerformance['target'] ?? 0}',
                  progress: ((_teamPerformance['percentage'] ?? 0) / 100)
                      .toDouble()
                      .clamp(0.0, 1.0),
                  secondaryLabel: '${_teamPerformance['percentage'] ?? 0}%',
                  accent: _accentGreen,
                ),

          const SizedBox(height: 12),

          // ── Personal KPI ─────────────────────────────────────────────────
          _isKpiLoading
              ? _buildCardShimmer(height: 130)
              : _buildPersonalKpiCard(),

          const SizedBox(height: 12),

          // ── Assigned Tasks ───────────────────────────────────────────────
          _isTasksLoading
              ? _buildCardShimmer(height: 130)
              : _buildAssignedTasksCard(),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // SHIMMER HELPERS
  // ─────────────────────────────────────────────────────────────────────────────

  /// Full-card shimmer used while a section is loading.
  Widget _buildCardShimmer({required double height}) {
    return Container(
      width: double.infinity,
      height: height,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Shimmer(width: 32, height: 32, radius: 10),
              const SizedBox(width: 10),
              _Shimmer(width: 110, height: 12, radius: 6),
              const Spacer(),
              _Shimmer(width: 48, height: 12, radius: 6),
            ],
          ),
          const SizedBox(height: 14),
          _Shimmer(width: 160, height: 18, radius: 6),
          const SizedBox(height: 10),
          _Shimmer(width: double.infinity, height: 6, radius: 6),
          const SizedBox(height: 8),
          _Shimmer(width: 100, height: 11, radius: 4),
        ],
      ),
    );
  }

  /// Grid shimmer for the Team Activity section.
  Widget _buildGridShimmer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          mainAxisExtent: 120,
        ),
        itemBuilder: (_, _) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
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
              _Shimmer(width: 36, height: 36, radius: 10),
              const SizedBox(height: 10),
              _Shimmer(width: 60, height: 18, radius: 6),
              const SizedBox(height: 6),
              _Shimmer(width: 80, height: 11, radius: 4),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // PERSONAL KPI CARD
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildPersonalKpiCard() {
    final pct = _kpiData.achievedPercentage;
    final target = _kpiData.yearlyTarget;
    final achieved = _kpiData.achievedRevenue;

    final bool isOnOrOverTarget = pct >= 100;
    final Color accent = isOnOrOverTarget
        ? _accentGreen
        : (pct >= 60 ? Colors.orange : Colors.deepOrange);

    String fmt(double v) {
      if (v >= 1e7) return '₹${(v / 1e7).toStringAsFixed(2)}Cr';
      if (v >= 1e5) return '₹${(v / 1e5).toStringAsFixed(2)}L';
      if (v >= 1e3) return '₹${(v / 1e3).toStringAsFixed(1)}K';
      return '₹${v.toStringAsFixed(0)}';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.show_chart, size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              Text(
                'PERSONAL TARGET',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DashboardKpiPage()),
                ),
                child: const Text(
                  'View all',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _accentGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                fmt(achieved),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '/ ${fmt(target)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[500],
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${pct.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _kpiData.progressFraction,
              minHeight: 6,
              backgroundColor: Colors.grey.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          if (_kpiData.salesAmount > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 13,
                  color: Colors.grey[500],
                ),
                const SizedBox(width: 4),
                Text(
                  'Sales billed: ${fmt(_kpiData.salesAmount)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // ASSIGNED TASKS CARD
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildAssignedTasksCard() {
    return Container(
      width: double.infinity,
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
          // Header
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
              if (_pendingTasks.isNotEmpty)
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
                    '${_pendingTasks.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AssignedTasksScreen(),
                  ),
                ),
                child: const Text(
                  'View all',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _accentGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Body
          if (_pendingTasks.isEmpty)
            Text(
              'No pending tasks',
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            )
          else
            _CompactTaskTile(task: _pendingTasks.first),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // STAT CARD (Team Performance)
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildStatCard({
    required String label,
    required String value,
    required double progress,
    required String secondaryLabel,
    required Color accent,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.show_chart, size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              Text(
                secondaryLabel,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.grey.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // SECTION TITLE
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: Color(0xFF1A1A1A),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // TEAM ACTIVITY GRID
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildTeamGrid() {
    if (_isDashboardLoading) return _buildGridShimmer();

    final items = [
      _ActivityCardData(
        icon: Icons.person_outline,
        title: 'Employees',
        value: '${_teamActivity['totalEmployees'] ?? 0}',
        color: Colors.blue,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FieldTeamScreen()),
        ),
      ),
      _ActivityCardData(
        icon: Icons.store,
        title: 'Dealer Visits',
        value: '${_teamActivity['dealerVisitsToday'] ?? 0}',
        color: Colors.blue,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ZonalDealerVisitsScreen()),
        ),
      ),
      _ActivityCardData(
        icon: Icons.agriculture,
        title: 'Farmer Visits',
        value: '${_teamActivity['farmerVisitsToday'] ?? 0}',
        color: Colors.teal,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ZonalFarmerVisitsScreen()),
        ),
      ),
      _ActivityCardData(
        icon: Icons.shopping_cart_outlined,
        title: 'Orders Placed',
        value: '${_teamActivity['ordersPlaced'] ?? 0}',
        color: Colors.orange,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const OrdersManagementScreen()),
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          mainAxisExtent: 120,
        ),
        itemBuilder: (_, i) {
          final d = items[i];
          return GestureDetector(
            onTap: d.onTap,
            child: _ActivityCard(
              icon: d.icon,
              title: d.title,
              value: d.value,
              color: d.color,
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // QUICK ACTIONS
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _ActionButton(
            icon: Icons.add_shopping_cart,
            label: 'Manage\nQueries',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FieldSupportScreen()),
            ),
          ),
          const SizedBox(width: 8),
          _ActionButton(
            icon: Icons.task_alt_outlined,
            label: 'Manage\nTasks',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TaskManagerScreen()),
            ),
          ),
          const SizedBox(width: 8),
          _ActionButton(
            icon: Icons.person_add_alt_1,
            label: 'Dealers\nOnboard',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DealerListScreen()),
            ),
          ),
          const SizedBox(width: 8),
          _ActionButton(
            icon: Icons.agriculture_rounded,
            label: 'Farmer\nOnboard',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FarmerListScreen()),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // OPERATIONS SECTION
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildQuickActionsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 120,
        children: [
          _buildFeatureCard(
            icon: Icons.location_pin,
            title: 'Trip Log',
            caption: 'Track trips',
            color: const Color(0xFF50C6B4),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const Trips(initialFilter: 'Today'),
              ),
            ),
          ),
          _buildFeatureCard(
            icon: Icons.receipt_long_outlined,
            title: 'Upload Bill',
            caption: 'Upload expense',
            color: const Color(0xFF50C6B4),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UploadExpensePage()),
            ),
          ),
        ],
      ),
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
    final titleSize = (w < 360 ? 16.0 : 18.0) / (ts > 1.2 ? 1.05 : 1.0);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: color.withValues(alpha: 0.08),
        highlightColor: color.withValues(alpha: 0.04),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF1AB69C).withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
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
                      color: Colors.black,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// SUPPORTING WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _ActivityCardData {
  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final VoidCallback onTap;

  const _ActivityCardData({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    required this.onTap,
  });
}

class _ActivityCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const _ActivityCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFF1AB69C), size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AssignedTasksScreen()),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _priorityColor(),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
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

// ─────────────────────────────────────────────────────────────────────────────
// EXTENSION: Refresh method for _HomeDashboardScreenState
// ─────────────────────────────────────────────────────────────────────────────

extension _HomeDashboardScreenRefresh on _HomeDashboardScreenState {
  Future<void> refreshAllData() async {
    try {
      await Future.wait([
        _reloadAttendance(),
        _loadDashboard(),
        _loadKpi(),
        _loadPendingTasks(),
      ]);
    } catch (e) {
      debugPrint('[refreshAllData] Error: $e');
      // Issue 4: User must know the refresh failed — silence is not acceptable.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Refresh failed. Please check your network and try again.',
            ),
            backgroundColor: const Color(0xFF1AB69C),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
