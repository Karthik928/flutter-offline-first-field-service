// lib/main.dart
import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:FieldService_app/Screens/splash_screen.dart';
import 'package:FieldService_app/Screens/sync_center.dart';
import 'package:FieldService_app/offline/cart_local_store.dart';
import 'package:FieldService_app/provider/auth_provider.dart';
import 'package:FieldService_app/services/local_store.dart';
import 'package:FieldService_app/services/push_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:FieldService_app/services/trip_manager.dart';
import 'package:workmanager/workmanager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'offline/queue_store.dart';
import 'offline/api_client.dart';
import 'offline/sync_service.dart';
import 'offline/failed_record_store.dart'; // ← NEW
import 'screens/failed_records_screen.dart'; // ← NEW
import 'services/connectivity_service.dart';

import 'firebase_options.dart';

// Screens
import 'package:FieldService_app/Screens/homescreen.dart';
import 'package:FieldService_app/Screens/login_screen.dart';
import 'package:FieldService_app/Screens/main_page.dart';
import 'package:FieldService_app/Screens/trip_screen.dart';

import 'offline/cache_store.dart';
import 'widgets/shared_bottom_nav.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Globals
// ─────────────────────────────────────────────────────────────────────────────

late QueueStore queueStore;
late ApiClient apiClient;
late SyncService syncService;
late CacheStore cacheStore;
late FailedRecordStore failedRecordStore; // ← NEW

MenuState _initialMenuForMain = MenuState.homedashboard;
bool _initialIsZonalManager = false;

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Tiny global toast helper — green by default, red when [error] is true.
void showGlobalToast(String text, {bool error = false, Duration? duration}) {
  final messenger = scaffoldMessengerKey.currentState;
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(text),
      backgroundColor: error ? Colors.redAccent : const Color(0xFF2E7D32),
      behavior: SnackBarBehavior.floating,
      duration: duration ?? const Duration(seconds: 2),
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Background sync (Android Workmanager)
// ─────────────────────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await Hive.initFlutter();

    final qs = QueueStore();
    await qs.init();

    final frs = FailedRecordStore(); // ← NEW

    // All 3 positional arguments are now provided
    final sync = SyncService(qs, http.Client(), frs, maxAttempts: 5);
    await sync.flush();

    return true;
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// main()
// ─────────────────────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("✅ Firebase initialized. Apps: ${Firebase.apps.length}");

  // FCM
  await PushService.init();
  await PushService.requestPermissionsIfNeeded();
  await PushService.configureNotificationClicks();

  // Desktop DB setup
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Hive + offline stores
  await Hive.initFlutter();

  cacheStore = CacheStore();
  await cacheStore.init();

  queueStore = QueueStore();
  await queueStore.init();

  final cartLocalStore = CartLocalStore();
  await cartLocalStore.init();

  // Local SQL
  try {
    await LocalStore.init();
    debugPrint('✅ LocalStore (sqflite) initialized.');
  } catch (e) {
    debugPrint('⚠️ LocalStore.init failed (non-fatal): $e');
  }

  // Failed record store — no async init needed (SharedPreferences-backed)
  failedRecordStore = FailedRecordStore(); // ← NEW

  final client = http.Client();
  apiClient = ApiClient(client, queueStore, cache: cacheStore);

  // ✅ 3 positional arguments — both errors in main.dart are now fixed
  syncService = SyncService(
    queueStore,
    client,
    failedRecordStore, // ← NEW (3rd positional arg)
    maxAttempts: 5,
  );

  // Foreground periodic sync
  syncService.start();

  // Connectivity listener → force flush on reconnect
  Connectivity().onConnectivityChanged.listen((status) async {
    debugPrint('🌐 [Net] status changed: $status');
    if (status.contains(ConnectivityResult.none)) return;
    final ok = await ConnectivityService.canReachApi();
    debugPrint('🌐 [Net] API reachable? $ok');
    if (ok) {
      debugPrint('🌐 [Net] Forcing queue flush on reconnect');
      await syncService.flush(force: true);
    }
  });

  // Background auto-sync (Android only)
  try {
    if (Platform.isAndroid) {
      await Workmanager().initialize(callbackDispatcher);
      await Workmanager().registerPeriodicTask(
        "syncQueue",
        "syncQueueTask",
        frequency: const Duration(minutes: 15),
      );
    }
  } catch (e) {
    debugPrint('⚠️ Workmanager init skipped: $e');
  }

  // Read terminated-state notification BEFORE runApp()
  final RemoteMessage? initialMsg = await FirebaseMessaging.instance
      .getInitialMessage();

  runApp(ProviderScope(child: MyApp(openFromNotification: initialMsg != null)));
}

// ─────────────────────────────────────────────────────────────────────────────
// App root
// ─────────────────────────────────────────────────────────────────────────────

class MyApp extends ConsumerStatefulWidget {
  final bool openFromNotification;
  const MyApp({super.key, required this.openFromNotification});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  bool _isLoading = true;
  StreamSubscription<SyncEvent>? _syncSub;

  @override
  void initState() {
    super.initState();
    _bootstrap();

    _syncSub = syncService.events.listen((e) {
      debugPrint(
        '📣 [SyncEvent@global] id=${e.id} success=${e.success} '
        'code=${e.statusCode} ${e.method} ${e.path} err=${e.error}',
      );

      if (e.success) {
        showGlobalToast('Data Synced ✔');
      } else if (e.error == 'max-attempts-reached') {
        showGlobalToast(
          'Sync failed after ${syncService.maxAttempts} tries. '
          'Check Failed Records for details.',
          error: true,
          duration: const Duration(seconds: 4),
        );
      } else if (e.statusCode == 401) {
        showGlobalToast('Session expired. Please log in again.', error: true);
      }
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final tripBox = await Hive.openBox('current_trip');
    final active = tripBox.get('active');

    try {
      await TripManager.restore();
      debugPrint('✅ TripManager.restore() completed.');
    } catch (e) {
      debugPrint('⚠️ TripManager.restore() failed (non-fatal): $e');
    }

    final prefs = await SharedPreferences.getInstance();
    _initialIsZonalManager = prefs.getBool('isZonalManager') ?? false;

    if (widget.openFromNotification) {
      _initialMenuForMain = MenuState.notification;
    } else if (active != null && active['status'] == 'started') {
      _initialMenuForMain = MenuState.map;
    } else {
      _initialMenuForMain = MenuState.homedashboard;
    }

    debugPrint('🏠 [MyApp] bootstrap complete: isZonalManager=$_initialIsZonalManager, initialMenu=$_initialMenuForMain');

    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    if (_isLoading) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Poppins'),
        home: const SplashScreen(),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: ThemeData(fontFamily: 'Poppins'),
      home: authState.isLoggedIn
          ? MainPage(
              initialMenu: _initialMenuForMain,
              isZonalManager: _initialIsZonalManager,
            )
          : const LoginScreen(),
      routes: {
        '/punch': (_) => const HomeDashboard(),
        '/main': (_) => const MainPage(),
        '/trip': (_) => const TripScreen(),
        '/sync': (_) =>
            SyncCenterPage(queueStore: queueStore, syncService: syncService),
        // ── Failed Records screen ──────────────────────────────────────────
        // Navigate with:  Navigator.pushNamed(context, '/failed-records')
        // or:             AppNavigator.goToFailedRecords(context)
        '/failed-records': (_) => FailedRecordsScreen(store: failedRecordStore),
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Convenience navigator helper — call from anywhere in the app
// ─────────────────────────────────────────────────────────────────────────────

/// Static helpers so any widget / service can open the Failed Records screen
/// without needing a BuildContext.
class AppNavigator {
  AppNavigator._();

  /// Open Failed Records screen (requires a live BuildContext).
  static void goToFailedRecords(BuildContext context) {
    Navigator.pushNamed(context, '/failed-records');
  }

  /// Open Failed Records screen from anywhere — uses the global navigator key.
  /// Safe to call from a SyncEvent listener, a background callback, etc.
  static void goToFailedRecordsGlobal() {
    appNavigatorKey.currentState?.pushNamed('/failed-records');
  }
}
