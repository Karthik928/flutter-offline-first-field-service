import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // for SystemNavigator.pop()
import 'package:FieldService_app/Screens/homescreen.dart';
import 'package:FieldService_app/Screens/notification_screeen.dart';
import 'package:FieldService_app/Screens/products_screen.dart';
import 'package:FieldService_app/services/notifications_service.dart';
import 'package:FieldService_app/Screens/trip_screen.dart';
import 'package:FieldService_app/widgets/shared_bottom_nav.dart';
import 'package:FieldService_app/zonal_Screens/home_dashboard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MainPage extends StatefulWidget {
  final MenuState initialMenu;
  final bool isZonalManager;
  final String? initialTripSearchQuery;

  const MainPage({
    super.key,
    this.initialMenu = MenuState.homedashboard,
    this.isZonalManager = false,
    this.initialTripSearchQuery,
  });

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  late MenuState _selectedMenu;

  bool _isZonalManager = false;

  // Keep other tabs as stable instances so they don't reload.
  late final Widget _tripScreen;
  final Widget _notificationPage = const NotificationPage();
  final Widget _productsScreen = const ProductsScreen(
    type: "Other",
    condition: false,
  );

  int _unreadCount = 0;
  late VoidCallback _unreadListener;

  @override
  void initState() {
    super.initState();
    _selectedMenu = widget.initialMenu;
    _isZonalManager = widget.isZonalManager;
    _tripScreen = TripScreen(initialSearchQuery: widget.initialTripSearchQuery);
    _loadUnread();
    if (!widget.isZonalManager) {
      _loadPrefs();
    }

    // Listen to external unread updates
    _unreadListener = () {
      if (!mounted) return;
      setState(() {
        _unreadCount = NotificationsService.unreadNotifier.value;
      });
    };
    NotificationsService.unreadNotifier.addListener(_unreadListener);
  }

  Future<void> _loadUnread() async {
    try {
      final list = await NotificationsService.fetchAll();
      final lastSeen = await NotificationsService.getLastSeen();
      final unread = list
          .where((n) => n.sent && n.createdAt.toUtc().isAfter(lastSeen.toUtc()))
          .length;
      if (!mounted) return;
      setState(() {
        _unreadCount = unread;
      });
      // publish to notifier as well
      try {
        NotificationsService.unreadNotifier.value = unread;
      } catch (_) {}
    } catch (_) {
      // ignore
    }
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final storedZonal = prefs.getBool('isZonalManager') ?? false;
    if (!mounted) return;
    if (storedZonal != _isZonalManager) {
      setState(() => _isZonalManager = storedZonal);
    }
  }

  @override
  void dispose() {
    try {
      NotificationsService.unreadNotifier.removeListener(_unreadListener);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // we control back behavior manually
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final shouldPop = await _handleBackPress();

        if (!mounted) return;

        if (shouldPop) {
          navigator.maybePop();
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _getScreenIndex(_selectedMenu),
          children: <Widget>[
            _isZonalManager ? const HomeDashboardScreen() : const HomeDashboard(),
            _tripScreen,
            _notificationPage,
            _productsScreen,
          ],
        ),
        bottomNavigationBar: BottomNavbar(
          selectedMenu: _selectedMenu,
          unreadCount: _unreadCount,
          onItemSelected: (menu) async {
            if (menu == _selectedMenu) return;

            FocusScope.of(context).unfocus();
            FocusManager.instance.primaryFocus?.unfocus();

            if (menu == MenuState.notification) {
              NotificationsService.setLastSeen(DateTime.now().toUtc());
              setState(() {
                _unreadCount = 0;
              });
            }

            setState(() {
              _selectedMenu = menu;

              });

            if (menu != MenuState.notification) {
              _loadUnread();
            }
          },
        ),
      ),
    );
  }

  /// Intercept device back button:
  /// - If not on Home: switch to Home (don’t exit)
  /// - If on Home: show confirm-exit dialog
  Future<bool> _handleBackPress() async {
    // ✅ FIX: If MainPage was pushed onto an existing stack (e.g. from AssignedTasksScreen),
    // just pop back normally — don't treat it like the app root.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return false;
    }

    // If any overlay route can pop (dialogs, etc.), let it.
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      return true;
    }

    if (_selectedMenu != MenuState.homedashboard) {
      setState(() {
        _selectedMenu = MenuState.homedashboard;
      });
      return false;
    }

    // Already on Home → ask to exit
    final shouldExit = await _showExitConfirmDialog();
    if (shouldExit == true) {
      SystemNavigator.pop();
      return false;
    }
    return false;
  }

  Future<bool?> _showExitConfirmDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      //barrierColor: Colors.white,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF1AB69C), width: 0.5),
          ),
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 24,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.exit_to_app_rounded,
                  size: 48,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Exit App?',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Do you really want to exit?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(
                              color: Color(0xFF1AB69C),
                              width: 1,
                            ),
                          ),
                        ),
                        child: const Text(
                          'No',
                          style: TextStyle(
                            color: Color(0xFF1AB69C),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: const Color(0xFF1AB69C),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(
                              color: Color(0xFF1AB69C),
                              width: 1.6,
                            ),
                          ),
                        ),
                        child: const Text(
                          'Yes',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
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

  int _getScreenIndex(MenuState menu) {
    switch (menu) {
      case MenuState.homedashboard:
        return 0;
      case MenuState.map: // "New Trip"
        return 1;
      case MenuState.notification: // "Alerts"
        return 2;
      case MenuState.productsScreen: // "Products"
        return 3;
      default:
        return 0;
    }
  }
}
