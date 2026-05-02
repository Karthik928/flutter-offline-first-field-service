// FILE: lib/Screens/farmer_purposes_screen.dart
//
// FarmerPurposesScreen — Expandable inline purpose cards.
// Similar to DealerPurposesScreen but for FARMERS:
// • Purposes: Other Visit (payment), Order, Query (in bottom sheet)
// • Farmer details instead of Dealer details
// • Farmer-specific APIs
// • Unified submit button at bottom
//
// ── Submit logic ──────────────────────────────────────────────────────────────
// The ONLY submit mechanism is the unified "Submit All Purposes" button at the
// bottom. Individual per-card save buttons have been removed.
//
// • Button is ENABLED when at least one started purpose is fully valid.
// • On tap, only the started+valid purposes have their APIs called.
// • Started-but-incomplete purposes are silently skipped.
// • A per-card status badge (✓ / ● / nothing) reflects fill state.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/Screens/main_page.dart';

import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/main.dart';
import 'package:FieldService_app/models/product.dart';
import 'package:FieldService_app/offline/cache_store.dart';
import 'package:FieldService_app/offline/request_envelope.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';
import 'package:FieldService_app/utils/mediaoptimizer.dart';
import 'package:FieldService_app/widgets/shared_bottom_nav.dart';

// ─── Shared constants ─────────────────────────────────────────────────────────

const Color _kGreen = Color(0xFF1AB69C);
const Color _kGreenLight = Color.fromARGB(255, 144, 252, 234);
const Color _surfaceColor = Color(0xFFF6F8FA);

// ─── Purpose type enum ────────────────────────────────────────────────────────

enum FarmerPurposeType { visit, order, query }

// ─── Order Product Data ────────────────────────────────────────────────────────

class OrderProductItem {
  final Product product;
  int quantity;

  OrderProductItem({required this.product, this.quantity = 1});

  double get totalPrice => (product.productPrice ?? 0) * quantity;

  OrderProductItem copyWith({int? quantity}) =>
      OrderProductItem(product: product, quantity: quantity ?? this.quantity);

  Map<String, dynamic> toJson() => {
    'productId': product.id,
    'quantity': quantity,
    'price': product.productPrice,
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
//  FarmerPurposesScreen
// ═══════════════════════════════════════════════════════════════════════════════

class FarmerPurposesScreen extends StatefulWidget {
  final String farmerId;
  final String farmerName;
  final String address;
  final String mobile;
  final double latitude;
  final double longitude;
  final double pendingAmount;
  final bool allowOtherVisit;
  final bool tripCompleted;
  final num totalCultureArea;

  const FarmerPurposesScreen({
    super.key,
    required this.farmerId,
    required this.farmerName,
    required this.address,
    required this.mobile,
    required this.latitude,
    required this.longitude,
    required this.pendingAmount,
    required this.allowOtherVisit,
    required this.tripCompleted,
    required this.totalCultureArea,
  });

  @override
  State<FarmerPurposesScreen> createState() => _FarmerPurposesScreenState();
}

class _FarmerPurposesScreenState extends State<FarmerPurposesScreen> {
  FarmerPurposeType? _expandedPurpose;
  late final _QueryDraft _queryDraft;

  // ── Purpose started flags ─────────────────────────────────────
  bool _visitStarted = true;
  bool _orderStarted = false;
  bool _queryStarted = false;

  // ── Purpose validity flags (reported by child cards) ──────────
  bool _visitValid = false;
  bool _orderValid = false;
  bool _queryValid = false;

  // ── Submit state ──────────────────────────────────────────────
  bool _isSubmitting = false;

  // ── Keys to access child card submit methods ───────────────────
  final GlobalKey<_LeadPurposeCardState> _visitKey =
      GlobalKey<_LeadPurposeCardState>();
  final GlobalKey<_OrderPurposeCardState> _orderKey =
      GlobalKey<_OrderPurposeCardState>();

  @override
  void initState() {
    super.initState();
    _queryDraft = _QueryDraft()
      ..seedFarmer(
        farmerId: widget.farmerId,
        farmerName: widget.farmerName,
        mobile: widget.mobile,
        address: widget.address,
      );
  }

  @override
  void dispose() {
    _queryDraft.dispose();
    super.dispose();
  }

  // ── Toggle / collapse ─────────────────────────────────────────
  void _toggle(FarmerPurposeType type) {
    setState(() {
      _expandedPurpose = _expandedPurpose == type ? null : type;
      if (_expandedPurpose == type) {
        if (type == FarmerPurposeType.visit) _visitStarted = true;
        if (type == FarmerPurposeType.order) _orderStarted = true;
      }
    });
  }

  void _collapseAll() {
    if (mounted) setState(() => _expandedPurpose = null);
  }

  // ── Validity callbacks from child cards ───────────────────────
  void _updateVisitValidity(bool v) {
    if (mounted) setState(() => _visitValid = v);
  }

  void _updateOrderValidity(bool v) {
    if (mounted) setState(() => _orderValid = v);
  }

  void _updateQueryValidity(bool v) {
    if (mounted) setState(() => _queryValid = v);
  }

  void _markQueryStarted() {
    if (mounted) setState(() => _queryStarted = true);
  }

  // ── Submit gate ───────────────────────────────────────────────
  /// Other Purpose is mandatory. Optional purpose APIs run only when valid.
  bool get _canSubmitAll => !_isSubmitting && _visitValid;

  bool get _atLeastOneStarted => true;

  String get _subtitle =>
      widget.mobile.trim().isNotEmpty ? widget.mobile.trim() : '';

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ── Gradient AppBar ──────────────────────────────────────────────────
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            gradient: LinearGradient(
              colors: [Color(0xFF52D494), _kGreen],
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
            title: const Text(
              'Purpose of Visit',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
        ),
      ),

      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Farmer header card ─────────────────────────────────────
                _FarmerHeaderCard(
                  farmerName: widget.farmerName,
                  subtitle: _subtitle,
                  address: widget.address,
                  latitude: widget.latitude,
                  longitude: widget.longitude,
                  pendingAmount: widget.pendingAmount,
                  totalCultureArea: widget.totalCultureArea,
                ),

                const SizedBox(height: 20),

                // ── Section label ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: _kGreenLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.task_alt_rounded,
                          color: _kGreen,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Select & Fill Purpose',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Hint strip (shown once any card is started) ────────────
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _HintStrip(
                    visitOk: _visitStarted && _visitValid,
                    orderOk: _orderStarted && _orderValid,
                    queryOk: _queryStarted && _queryValid,
                  ),
                ),

                // ── Order ──────────────────────────────────────────────────
                _OrderPurposeCard(
                  key: _orderKey,
                  isExpanded: _expandedPurpose == FarmerPurposeType.order,
                  onToggle: () => _toggle(FarmerPurposeType.order),
                  onValidityChanged: _updateOrderValidity,
                  farmerId: widget.farmerId,
                  farmerType: 'Farmer',
                  isStarted: _orderStarted,
                  isValid: _orderValid,
                ),

                const SizedBox(height: 12),

                // ── Query Button (opens bottom sheet) ──────────────────────
                _QueryButtonCard(
                  onTap: () => _showQueryBottomSheet(context),
                  isStarted: _queryStarted,
                  isValid: _queryValid,
                  remarksPreview: _queryDraft.remarksPreview,
                  pondCount: _queryDraft.ponds.length,
                  imageCount: _queryDraft.images.length,
                ),
                const SizedBox(height: 12),

                // ── Other Visit ──────────────────────────────────
                _LeadPurposeCard(
                  key: _visitKey,
                  isExpanded: true,
                  onToggle: () {},
                  onSuccess: _collapseAll,
                  farmerId: widget.farmerId,
                  farmerName: widget.farmerName,
                  address: widget.address,
                  mobile: widget.mobile,
                  isStarted: _visitStarted,
                  isValid: _visitValid,
                  onValidityChanged: _updateVisitValidity,
                ),
              ],
            ),
          ),

          // ── Unified Sticky Submit Button ───────────────────────────────
          if (_atLeastOneStarted)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _UnifiedSubmitBar(
                canSubmit: _canSubmitAll,
                isSubmitting: _isSubmitting,
                readyCount: [
                  _visitStarted && _visitValid,
                  _orderStarted && _orderValid,
                  _queryStarted && _queryValid,
                ].where((v) => v).length,
                onSubmit: () => _submitAllPurposes(context),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Query Bottom Sheet
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _showQueryBottomSheet(BuildContext context) async {
    _markQueryStarted();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QueryBottomSheet(
        farmerId: widget.farmerId,
        farmerName: widget.farmerName,
        address: widget.address,
        mobile: widget.mobile,
        latitude: widget.latitude,
        longitude: widget.longitude,
        tripCompleted: widget.tripCompleted,
        onValidityChanged: _updateQueryValidity,
        draft: _queryDraft,
      ),
    );

    if (mounted) {
      setState(() {
        _queryValid = _queryDraft.canSubmitFarmer;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Unified Submit
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _submitAllPurposes(BuildContext context) async {
    if (!_canSubmitAll) return;

    setState(() => _isSubmitting = true);

    final List<String> successes = [];
    final List<String> errors = [];

    try {
      // ── 1. Visit (only if started + valid) ────────────────────
      if (_visitValid) {
        final ok = await _visitKey.currentState?._submitAndReturn();

        if (ok == true) {
          successes.add('Other Purpose');
        } else {
          errors.add('Other Purpose submission failed');
        }
      }

      if (errors.isNotEmpty) {
        _showResultSnack(errors.first, isError: true);
        return;
      }

      // ── 2. Order (only if started + valid) ────────────────────
      if (_orderStarted && _orderValid) {
        final ok = await _orderKey.currentState?._submitAndReturn();
        if (ok == true) {
          successes.add('Order');
        } else {
          errors.add('Order submission failed');
        }
      }

      if (errors.isNotEmpty) {
        _showResultSnack(errors.first, isError: true);
        return;
      }

      if (_queryStarted && _queryValid) {
        final ok = await _submitQuery();
        if (ok) {
          successes.add('Query');
        } else {
          errors.add('Query submission failed');
        }
      }

      if (errors.isNotEmpty) {
        _showResultSnack(errors.first, isError: true);
        return;
      }

      // ── All selected purposes succeeded ───────────────────────
      if (mounted && successes.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅  ${successes.join(' • ')}  submitted'),
            backgroundColor: _kGreen,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );

        await Future.delayed(const Duration(milliseconds: 600));

        if (!mounted) return;

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const MainPage(initialMenu: MenuState.homedashboard),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      _showResultSnack('Unexpected error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<bool> _submitQuery() async {
    if (!_queryDraft.canSubmitFarmer) {
      _showResultSnack('Please complete the query details.', isError: true);
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final companyId = prefs.getString('companyId') ?? '';
      final employeeId = prefs.getString('userId') ?? '';
      final tripId = prefs.getString('currentTripId') ?? '';
      final tripCompleted = prefs.getBool('tripCompleted') ?? false;
      final effectiveTripId = tripCompleted ? tripId : '';
      final token = await SecureStorageService.getToken();

      final body = <String, String>{
        'companyId': companyId,
        if (effectiveTripId.isNotEmpty) 'tripId': effectiveTripId,
        'employeeId': employeeId,
        'farmerId': widget.farmerId,
        'farmerName': _queryDraft.farmerNameCtrl.text.trim(),
        'mobileNumber': _queryDraft.mobileCtrl.text.trim(),
        'address': _queryDraft.locationCtrl.text.trim().isNotEmpty
            ? _queryDraft.locationCtrl.text.trim()
            : '(Offline - address unavailable)',
        'remarks': _queryDraft.remarksCtrl.text.trim(),
        'status': 'Pending',
      };

      final ponds = _queryDraft.ponds.map((p) => p.toJson()).toList();
      for (int i = 0; i < ponds.length; i++) {
        final pond = ponds[i];
        body['ponds[$i][pondName]'] = pond['pondName'].toString();
        body['ponds[$i][culturedArea]'] = pond['culturedArea'].toString();
        body['ponds[$i][culturedSpecies]'] = pond['culturedSpecies'].toString();

        final phys = (pond['physicalReadings'] as List).first;
        body['ponds[$i][physicalReadings][0][stockingPL]'] = phys['stockingPL']
            .toString();
        body['ponds[$i][physicalReadings][0][doc]'] = phys['doc'].toString();
        body['ponds[$i][physicalReadings][0][feedIntakePerDay]'] =
            phys['feedIntakePerDay'].toString();
        body['ponds[$i][physicalReadings][0][count]'] = phys['count']
            .toString();
        if (phys['avgWeight'] != null) {
          body['ponds[$i][physicalReadings][0][avgWeight]'] = phys['avgWeight']
              .toString();
        }

        final chem = (pond['chemicalReadings'] as List).first;
        body['ponds[$i][chemicalReadings][0][salinity]'] = chem['salinity']
            .toString();
        body['ponds[$i][chemicalReadings][0][ph]'] = chem['ph'].toString();
        body['ponds[$i][chemicalReadings][0][alkalinity]'] = chem['alkalinity']
            .toString();
        body['ponds[$i][chemicalReadings][0][ammonia]'] = chem['ammonia']
            .toString();
        body['ponds[$i][chemicalReadings][0][nitrite]'] = chem['nitrite']
            .toString();
        body['ponds[$i][chemicalReadings][0][dissolvedOxygen]'] =
            chem['dissolvedOxygen'].toString();

        final disease = pond['diseaseReadings'] as List;
        if (disease.isNotEmpty) {
          body['ponds[$i][diseaseReadings][0][vibrios]'] = disease
              .first['vibrios']
              .toString();
        }
      }

      final files = await _prepareQueryImages();

      debugPrint('[FarmerQuery] POST ${AppConfig.farmerTicket}');
      debugPrint('[FarmerQuery] body: ${jsonEncode(body)}');

      final resp = await apiClient.sendOrQueue(
        method: HttpVerb.post,
        path: AppConfig.farmerTicket,
        jsonBody: body,
        files: files,
        headers: {'Authorization': 'Bearer $token'},
        optimisticOk: true,
      );

      if (resp == null || resp.statusCode == 200 || resp.statusCode == 201) {
        _queryDraft.resetToFarmer(
          farmerId: widget.farmerId,
          farmerName: widget.farmerName,
          mobile: widget.mobile,
          address: widget.address,
        );
        if (mounted) {
          setState(() {
            _queryStarted = false;
            _queryValid = false;
          });
        }
        return true;
      }

      String msg = 'HTTP ${resp.statusCode}';
      try {
        final j = jsonDecode(resp.body);
        if (j is Map && j['message'] is String) msg = j['message'];
      } catch (_) {}
      _showResultSnack('Failed to raise query: $msg', isError: true);
      return false;
    } catch (e) {
      _showResultSnack('Network error: $e', isError: true);
      return false;
    }
  }

  Future<List<QueuedFile>> _prepareQueryImages() async {
    final files = <QueuedFile>[];

    for (final image in _queryDraft.images) {
      final originalFile = File(image.path);
      if (!originalFile.existsSync()) continue;

      final optimizedFile = await MediaOptimizer.getOptimizedImage(
        originalFile,
      );
      final finalFile = optimizedFile ?? originalFile;
      final sizeMB = await MediaOptimizer.getFileSizeMB(finalFile);

      if (sizeMB > 5) {
        throw Exception(
          'Image too large (${sizeMB.toStringAsFixed(2)} MB). Please select a smaller image.',
        );
      }

      final fileName = image.name.isNotEmpty
          ? image.name
          : finalFile.path.split('/').last;
      final ext = fileName.split('.').last.toLowerCase();

      files.add(
        QueuedFile(
          field: 'images',
          path: finalFile.path,
          filename: fileName,
          contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
        ),
      );
    }

    return files;
  }

  void _showResultSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red[700] : _kGreen,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _UnifiedSubmitBar — sticky bottom bar with animated submit button
// ═══════════════════════════════════════════════════════════════════════════════

class _UnifiedSubmitBar extends StatelessWidget {
  final bool canSubmit;
  final bool isSubmitting;
  final int readyCount;
  final VoidCallback onSubmit;

  const _UnifiedSubmitBar({
    required this.canSubmit,
    required this.isSubmitting,
    required this.readyCount,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.95),
            Colors.white,
          ],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (readyCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _kGreenLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$readyCount purpose${readyCount == 1 ? '' : 's'} ready',
                  style: const TextStyle(
                    color: _kGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: canSubmit && !isSubmitting ? onSubmit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGreen,
                disabledBackgroundColor: Colors.grey[300],
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.grey[600],
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: isSubmitting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(
                          canSubmit ? Colors.white : Colors.grey[600],
                        ),
                      ),
                    )
                  : const Icon(Icons.check_circle_rounded),
              label: Text(
                isSubmitting ? 'Submitting...' : 'Submit All Purposes',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _HintStrip — shows which purposes are ready / incomplete
// ═══════════════════════════════════════════════════════════════════════════════

class _HintStrip extends StatelessWidget {
  final bool visitOk;
  final bool orderOk;
  final bool queryOk;

  const _HintStrip({
    required this.visitOk,
    required this.orderOk,
    required this.queryOk,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _HintItem(label: 'Visit', ready: visitOk),
      _HintItem(label: 'Order', ready: orderOk),
      _HintItem(label: 'Query', ready: queryOk),
    ];

    final active = items.where((it) => it.ready).toList();

    if (active.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kGreenLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kGreen.withValues(alpha: 0.3)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(
            active.length,
            (i) => Padding(
              padding: EdgeInsets.only(right: i < active.length - 1 ? 10 : 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _kGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: _kGreen,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      active[i].label,
                      style: const TextStyle(
                        color: _kGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HintItem {
  final String label;
  final bool ready;
  const _HintItem({required this.label, required this.ready});
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _PurposeCardShell  — reusable expandable card wrapper
// ═══════════════════════════════════════════════════════════════════════════════

class _PurposeCardShell extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget expandedContent;
  final bool isStarted;
  final bool isValid;

  const _PurposeCardShell({
    required this.isExpanded,
    required this.onToggle,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.expandedContent,
    required this.isStarted,
    this.isValid = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kGreen.withValues(alpha: 0.2), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: _kGreen.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _kGreenLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: _kGreen, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _CardStatusBadge(isStarted: isStarted, isValid: isValid),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _kGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: _kGreen,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded Content ───────────────────────────────────────────
          if (isExpanded)
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Column(
                children: [
                  Divider(color: _kGreen.withValues(alpha: 0.1), height: 0),
                  expandedContent,
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Status badge shown in each card header ───────────────────────────────────

class _CardStatusBadge extends StatelessWidget {
  final bool isStarted;
  final bool isValid;

  const _CardStatusBadge({required this.isStarted, required this.isValid});

  @override
  Widget build(BuildContext context) {
    if (!isStarted) {
      return SizedBox.shrink();
    }

    if (isValid) {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.green.shade100,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.check_circle_rounded,
          size: 18,
          color: Colors.green.shade600,
        ),
      );
    }

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.radio_button_checked,
        size: 14,
        color: Colors.orange.shade600,
      ),
    );
  }
}
// ═══════════════════════════════════════════════════════════════════════════════
//  _LeadPurposeCard — Farmer Lead Purpose (matches _VisitPurposeCard pattern)
// ═══════════════════════════════════════════════════════════════════════════════

class _LeadPurposeCard extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onSuccess;
  final String farmerId;
  final String farmerName;
  final String address;
  final String mobile;
  final bool isStarted;
  final bool isValid;
  final ValueChanged<bool> onValidityChanged;

  const _LeadPurposeCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    required this.onSuccess,
    required this.farmerId,
    required this.farmerName,
    required this.address,
    required this.mobile,
    required this.isStarted,
    required this.isValid,
    required this.onValidityChanged,
  });

  @override
  State<_LeadPurposeCard> createState() => _LeadPurposeCardState();
}

class _LeadPurposeCardState extends State<_LeadPurposeCard> {
  File? _imageFile;
  bool _uploadingImage = false;

  double? _latitude;
  double? _longitude;
  String? _locationAddress;

  final _descriptionCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _descriptionCtrl.addListener(_updateValidity);
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _imageFile != null &&
      !_uploadingImage &&
      _latitude != null &&
      _longitude != null &&
      _locationAddress != null &&
      _locationAddress!.trim().isNotEmpty &&
      _descriptionCtrl.text.trim().isNotEmpty;

  void _updateValidity() => widget.onValidityChanged(_isValid);

  // ----- Fix EXIF rotation (bake orientation) -----
  Future<File> _fixExifRotation(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final original = img.decodeImage(bytes);
      if (original == null) return file;

      final fixed = img.bakeOrientation(original);

      final newPath =
          "${file.parent.path}/fixed_${DateTime.now().millisecondsSinceEpoch}.jpg";

      final fixedFile = File(newPath)
        ..writeAsBytesSync(img.encodeJpg(fixed, quality: 100));

      return fixedFile;
    } catch (e) {
      debugPrint("EXIF FIX ERROR: $e");
      return file;
    }
  }

  // ----- Stamp image with address/lat/lng/time using canvas -----
  Future<File> _stampImage(
    File imageFile,
    double lat,
    double lng,
    String time,
    String address,
  ) async {
    try {
      final bytes = await imageFile.readAsBytes();

      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ui.Image image = frame.image;

      final int width = image.width;
      final int height = image.height;

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(
        recorder,
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      );

      canvas.drawImage(image, ui.Offset.zero, ui.Paint());

      final text =
          "Address: $address\n"
          "Lat: ${lat.toStringAsFixed(6)}\n"
          "Lng: ${lng.toStringAsFixed(6)}\n"
          "Time: $time";

      final double fontSize = (width.toDouble() / 15.0)
          .clamp(22.0, 60.0)
          .toDouble();

      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            shadows: const [
              Shadow(color: Colors.black, blurRadius: 6, offset: Offset(2, 2)),
            ],
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      );

      painter.layout(maxWidth: width * 0.9);

      const double pad = 40.0;
      final double dx = pad;

      double dy = height.toDouble() - painter.height - pad;
      if (dy < pad) dy = pad;

      final bgRect = ui.Rect.fromLTWH(
        dx - 12,
        dy - 12,
        painter.width + 24,
        painter.height + 24,
      );

      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(bgRect, const ui.Radius.circular(14)),
        ui.Paint()..color = const Color(0x99000000),
      );

      painter.paint(canvas, Offset(dx, dy));

      final picture = recorder.endRecording();
      final stampedImage = await picture.toImage(width, height);
      final byteData = await stampedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      final stampedPath =
          "${imageFile.parent.path}/farmer_stamp_${DateTime.now().millisecondsSinceEpoch}.png";

      final stampedFile = File(stampedPath);
      await stampedFile.writeAsBytes(byteData!.buffer.asUint8List());

      return stampedFile;
    } catch (e, st) {
      debugPrint("STAMP ERROR: $e\n$st");
      return imageFile;
    }
  }

  // ---------- Camera capture ----------
  Future<void> _pickImageFromCamera() async {
    try {
      final XFile? picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );

      if (picked == null) return;

      setState(() => _imageFile = File(picked.path));
      setState(() => _uploadingImage = true);

      await _fetchLocation();

      if (_latitude == null || _longitude == null) {
        _snack("Unable to capture location.");
        setState(() => _uploadingImage = false);
        return;
      }

      final timestamp = DateFormat(
        "yyyy-MM-dd HH:mm:ss",
      ).format(DateTime.now());
      final address = _locationAddress ?? "Unknown Address";
      final original = File(picked.path);

      final fixedFile = await _fixExifRotation(original);
      final stamped = await _stampImage(
        fixedFile,
        _latitude!,
        _longitude!,
        timestamp,
        address,
      );

      final optimized =
          await MediaOptimizer.getOptimizedImage(stamped) ?? stamped;

      if (!mounted) return;
      setState(() {
        _imageFile = optimized;
        _uploadingImage = false;
      });
      _updateValidity();
    } catch (e, st) {
      debugPrint("CAMERA FLOW ERROR: $e\n$st");
      _snack('Failed to capture image: $e');
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  void _removeImage() {
    setState(() {
      _imageFile = null;
      _latitude = null;
      _longitude = null;
      _locationAddress = null;
    });
    _updateValidity();
  }

  // ---------- Location (Geolocator + reverse geocode) ----------
  Future<void> _fetchLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _snack('Location permission denied');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _snack('Location permission permanently denied');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
      });

      String? addr;
      try {
        final key = AppConfig.googleMapsApiKey;
        final url =
            "https://maps.googleapis.com/maps/api/geocode/json"
            "?latlng=${pos.latitude},${pos.longitude}"
            "&key=$key";

        final resp = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 4));

        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);

          if (data["status"] == "OK" && data["results"].isNotEmpty) {
            addr = data["results"][0]["formatted_address"];
          } else {
            throw Exception("Google returned no results");
          }
        } else {
          throw Exception("Google returned ${resp.statusCode}");
        }
      } catch (_) {
        try {
          final placemarks = await placemarkFromCoordinates(
            pos.latitude,
            pos.longitude,
          ).timeout(const Duration(seconds: 4));

          if (placemarks.isNotEmpty) {
            final p = placemarks.first;

            addr = [
              p.name,
              p.street,
              p.subLocality,
              p.locality,
              p.subAdministrativeArea,
              p.administrativeArea,
              p.postalCode,
              p.country,
            ].where((e) => e != null && e.trim().isNotEmpty).join(", ");
          } else {
            throw Exception("Placemark empty");
          }
        } catch (_) {
          addr = "Offline — address unavailable";
        }
      }

      setState(() {
        _locationAddress = addr ?? 'Offline — address unavailable';
      });
    } catch (e) {
      _snack('Failed to get location: $e');
    }
  }

  // ── Called by unified submit button ──────────────────────────────────────
  Future<bool> _submitAndReturn() async {
    if (_imageFile == null) return false;
    if (_latitude == null || _longitude == null) return false;
    if (_descriptionCtrl.text.trim().isEmpty) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getString('userId') ?? "";
      final tripId = prefs.getString('currentTripId') ?? '';
      final tripCompleted = prefs.getBool('tripCompleted') ?? false;
      final effectiveTripId = tripCompleted == true ? tripId : '';

      if (employeeId.isEmpty) return false;

      final address = _locationAddress?.trim().isNotEmpty == true
          ? _locationAddress!
          : widget.address;

      final body = {
        "employeeId": employeeId,
        if (effectiveTripId.isNotEmpty) "tripId": effectiveTripId,
        "idOfVisitor[id]": widget.farmerId,
        "idOfVisitor[type]": "Farmer",
        "purpose": "Lead Purpose",
        "reason": _descriptionCtrl.text.trim(),
        "address": address,
      };

      final ext = _imageFile!.path.split('.').last.toLowerCase();
      final mime = (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/png';

      final img = QueuedFile(
        field: "images",
        path: _imageFile!.path,
        filename: "farmer_lead_${DateTime.now().millisecondsSinceEpoch}.$ext",
        contentType: mime,
      );

      final resp = await apiClient.sendOrQueue(
        method: HttpVerb.post,
        path: AppConfig.othervisits,
        jsonBody: body,
        files: [img],
        optimisticOk: true,
      );

      return resp == null || resp.statusCode == 200 || resp.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Row(
        //   children: [
        //     Container(
        //       width: 34,
        //       height: 34,
        //       decoration: BoxDecoration(
        //         color: _kGreenLight,
        //         borderRadius: BorderRadius.circular(10),
        //       ),
        //       alignment: Alignment.center,
        //       child: const Icon(
        //         Icons.lightbulb_rounded,
        //         color: _kGreen,
        //         size: 18,
        //       ),
        //     ),
        //     const SizedBox(width: 10),
        //     const Expanded(
        //       child: Column(
        //         crossAxisAlignment: CrossAxisAlignment.start,
        //         children: [
        //           Text(
        //             'Other Purpose',
        //             style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        //           ),
        //           Text(
        //             'Required - capture photo and describe visit',
        //             style: TextStyle(fontSize: 12, color: Colors.black54),
        //           ),
        //         ],
        //       ),
        //     ),
        //     Container(
        //       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        //       decoration: BoxDecoration(
        //         color: const Color(0xFFFFE8E8),
        //         borderRadius: BorderRadius.circular(8),
        //         border: Border.all(color: Colors.red.shade200),
        //       ),
        //       child: Text(
        //         'Required',
        //         style: TextStyle(
        //           fontSize: 11,
        //           fontWeight: FontWeight.w700,
        //           color: Colors.red.shade600,
        //         ),
        //       ),
        //     ),
        //   ],
        // ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isValid ? _kGreen : Colors.red.shade200,
              width: 1.6,
            ),
            boxShadow: [
              BoxShadow(
                color: _isValid
                    ? _kGreen.withValues(alpha: 0.12)
                    : Colors.red.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: _buildForm(),
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Camera + location card ──────────────────────────────
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: _kGreen, width: 1.2),
              ),
              clipBehavior: Clip.hardEdge,
              child: Container(
                height: 220,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // LEFT: Image preview
                    Expanded(
                      flex: 2,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: _imageFile == null
                            ? Material(
                                color: _kGreenLight.withValues(alpha: 0.18),
                                child: InkWell(
                                  onTap: _uploadingImage
                                      ? null
                                      : _pickImageFromCamera,
                                  child: Center(
                                    child: _uploadingImage
                                        ? const CircularProgressIndicator(
                                            color: _kGreen,
                                          )
                                        : Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: const [
                                              Icon(
                                                Icons.camera_alt_outlined,
                                                color: _kGreen,
                                                size: 28,
                                              ),
                                              SizedBox(height: 6),
                                              Text(
                                                'Tap to capture\n(camera only)',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: _kGreen,
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              )
                            : Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(_imageFile!, fit: BoxFit.cover),
                                  Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withValues(alpha: 0.12),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 8,
                                    top: 8,
                                    child: Material(
                                      color: Colors.white,
                                      shape: const CircleBorder(),
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: _removeImage,
                                        child: const Padding(
                                          padding: EdgeInsets.all(6),
                                          child: Icon(
                                            Icons.close,
                                            size: 18,
                                            color: _kGreen,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // RIGHT: Address + Lat/Lng
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.02),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: _uploadingImage
                                  ? const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: _kGreen,
                                      ),
                                    )
                                  : (_latitude != null && _longitude != null)
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (_locationAddress != null &&
                                            _locationAddress!.isNotEmpty) ...[
                                          Text(
                                            _locationAddress!,
                                            textAlign: TextAlign.right,
                                            maxLines: 8,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[800],
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                        ],
                                        // Text(
                                        //   'Lat: ${_latitude!.toStringAsFixed(6)}',
                                        //   textAlign: TextAlign.right,
                                        //   style: TextStyle(
                                        //     fontSize: 10.5,
                                        //     color: Colors.grey[700],
                                        //   ),
                                        // ),
                                        // Text(
                                        //   'Lng: ${_longitude!.toStringAsFixed(6)}',
                                        //   textAlign: TextAlign.right,
                                        //   style: TextStyle(
                                        //     fontSize: 10.5,
                                        //     color: Colors.grey[700],
                                        //   ),
                                        // ),
                                        const Spacer(),
                                      ],
                                    )
                                  : Center(
                                      child: Text(
                                        'No location.\nTap camera to capture.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // ── Description ─────────────────────────────────────────
            TextFormField(
              controller: _descriptionCtrl,
              minLines: 2,
              maxLines: 5,
              decoration: _inputDec(
                'Description / Details (required)',
                Icons.notes_rounded,
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Description is required' : null,
            ),

            const SizedBox(height: 16),

            // ── Validity hint ─────────────────────────────────────
            if (widget.isStarted && !widget.isValid)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: _IncompleteHint(
                  message: 'Capture photo and add description',
                ),
              ),

            // if (widget.isStarted && widget.isValid)
            //   const Padding(
            //     padding: EdgeInsets.only(top: 12),
            //     child: _CompleteHint(message: 'Ready ✓'),
            //   ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _OrderPurposeCard — API-driven cart for Farmers (mirrors DealerPurposesScreen)
// ═══════════════════════════════════════════════════════════════════════════════

class _OrderPurposeCard extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final ValueChanged<bool> onValidityChanged;
  final String farmerId;
  final String farmerType;
  final bool isStarted;
  final bool isValid;

  const _OrderPurposeCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    required this.onValidityChanged,
    required this.farmerId,
    required this.farmerType,
    required this.isStarted,
    required this.isValid,
  });

  @override
  State<_OrderPurposeCard> createState() => _OrderPurposeCardState();
}

class _OrderPurposeCardState extends State<_OrderPurposeCard> {
  // ── Cart state (mirrors dealer screen) ─────────────────────
  Map<String, dynamic>? _serverCart;
  bool _isLoadingCart = false;
  String? _cartError;
  String? _employeeId;
  String? _tripId;
  bool _tripCompleted = false;
  final Set<String> _pendingProductOps = {};
  final TextEditingController _remarksCtrl = TextEditingController();

  // ── Product sheet dependencies ─────────────────────────────
  final CacheStore _cache = CacheStore();
  late Box _imageBox;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Hive.initFlutter();
    await _cache.init();
    _imageBox = await Hive.openBox('image_cache');
    if (mounted) setState(() => _initialized = true);
    await _loadSessionAndFetchCart();
  }

  @override
  void dispose() {
    _remarksCtrl.dispose();
    super.dispose();
  }

  // ── Session meta ───────────────────────────────────────────
  Future<void> _loadSessionAndFetchCart() async {
    final prefs = await SharedPreferences.getInstance();
    _employeeId = prefs.getString('userId') ?? '';
    _tripId = prefs.getString('currentTripId') ?? '';
    _tripCompleted = prefs.getBool('tripCompleted') ?? false;

    debugPrint('📦 [FarmerOrder] employeeId=$_employeeId tripId=$_tripId');

    await _fetchCart(employeeId: _employeeId);
  }

  // ── Headers ────────────────────────────────────────────────
  Future<Map<String, String>> _buildHeaders({bool json = false}) async {
    final token = await SecureStorageService.getToken();
    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // ── Parse cart from response ───────────────────────────────
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

  // ── Fetch cart ─────────────────────────────────────────────
  Future<void> _fetchCart({String? employeeId}) async {
    if (!mounted) return;
    setState(() {
      _isLoadingCart = true;
      _cartError = null;
    });

    try {
      final effectiveEmployeeId = (employeeId ?? _employeeId ?? '').trim();

      if (effectiveEmployeeId.isEmpty) {
        if (mounted) setState(() => _cartError = 'Missing employee id.');
        return;
      }

      final headers = await _buildHeaders();
      final uri = AppConfig.u(
        AppConfig.fill(AppConfig.getCart, {'employeeid': effectiveEmployeeId}),
      );

      final resp = await http
          .get(uri, headers: headers)
          .timeout(AppConfig.httpTimeout);

      debugPrint('📦 [FarmerOrder] GET cart ${resp.statusCode}: ${resp.body}');

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        final cart = _cartFromResponse(body);
        if (mounted) {
          setState(() => _serverCart = cart ?? {'_id': '', 'items': []});
        }
      } else if (resp.statusCode == 404) {
        if (mounted) setState(() => _serverCart = {'_id': '', 'items': []});
      } else if (resp.statusCode == 401) {
        if (mounted) setState(() => _cartError = 'Session expired.');
      } else {
        if (mounted) {
          setState(() => _cartError = 'Server error (${resp.statusCode})');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _cartError = 'No internet: $e');
    } finally {
      if (mounted) setState(() => _isLoadingCart = false);
    }

    _updateValidity();
  }

  // ── Items helper ───────────────────────────────────────────
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

  String? _productIdOf(Map<String, dynamic> item) {
    final productId = item['productId'];
    if (productId == null) return null;
    if (productId is String) return productId;
    if (productId is Map && productId['_id'] != null) {
      return productId['_id'].toString();
    }
    return productId.toString();
  }

  double get _totalAmount {
    double tot = 0.0;
    for (final it in _itemsFromServer()) {
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

  bool get _isValid => _itemsFromServer().isNotEmpty;

  void _updateValidity() {
    if (mounted) widget.onValidityChanged(_isValid);
  }

  // ── Add to cart API ────────────────────────────────────────
  Future<void> _addToCart(Product product) async {
    final productId = product.id ?? '';
    if (productId.isEmpty) {
      _snack('Invalid product — missing id.');
      return;
    }

    setState(() => _pendingProductOps.add(productId));

    try {
      final headers = await _buildHeaders(json: true);

      // POST to addToCart — backend expects customerId as object {id, type}
      final body = <String, dynamic>{
        'customerId': {'id': widget.farmerId, 'type': widget.farmerType},
        'productId': productId,
        'quantity': 1,
        'price': product.productPrice ?? 0,
        if (_employeeId != null && _employeeId!.isNotEmpty)
          'employeeId': _employeeId,
        if (_tripId != null && _tripId!.isNotEmpty) 'tripId': _tripId,
      };

      debugPrint('📦 [FarmerOrder] addToCart POST body: ${jsonEncode(body)}');

      final resp = await http
          .post(
            AppConfig.u(AppConfig.addToCart),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(AppConfig.httpTimeout);

      debugPrint('📦 [FarmerOrder] addToCart ${resp.statusCode}: ${resp.body}');

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final parsed = jsonDecode(resp.body);
        final cart = _cartFromResponse(parsed);
        if (mounted && cart != null) setState(() => _serverCart = cart);
        await _fetchCart();
      } else {
        final parsed = jsonDecode(resp.body);
        final msg =
            parsed['message']?.toString() ??
            'Failed to add product (${resp.statusCode})';
        _snack(msg);
      }
    } catch (e) {
      _snack('Network error: $e');
    } finally {
      if (mounted) setState(() => _pendingProductOps.remove(productId));
    }
  }

  // ── Update cart quantity ───────────────────────────────────
  Future<void> _updateCartQuantity(String productId, String action) async {
    if (action != 'increase' && action != 'decrease') return;
    setState(() => _pendingProductOps.add(productId));

    try {
      final headers = await _buildHeaders(json: true);

      // tripId/employeeId must be omitted if empty (BSON ObjectId cast)
      final body = <String, dynamic>{
        'customerId': widget.farmerId, // plain string
        'type': widget.farmerType, // separate field
        'productId': productId,
        'action': action,
        if (_employeeId != null && _employeeId!.isNotEmpty)
          'employeeId': _employeeId,
        if (_tripId != null && _tripId!.isNotEmpty) 'tripId': _tripId,
      };

      debugPrint('📦 [FarmerOrder] updateQty body: ${jsonEncode(body)}');

      final resp = await http
          .put(
            AppConfig.u(AppConfig.updateCart),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(AppConfig.httpTimeout);

      debugPrint('📦 [FarmerOrder] updateQty ${resp.statusCode}: ${resp.body}');

      if (resp.statusCode == 200) {
        final parsed = jsonDecode(resp.body);
        final cart = _cartFromResponse(parsed);
        if (mounted && cart != null) setState(() => _serverCart = cart);
        await _fetchCart();
      } else {
        final parsed = jsonDecode(resp.body);
        _snack(
          parsed['message']?.toString() ??
              'Failed to update (${resp.statusCode})',
        );
      }
    } catch (e) {
      _snack('Network error: $e');
    } finally {
      if (mounted) setState(() => _pendingProductOps.remove(productId));
    }
  }

  // ── Bulk set quantity ──────────────────────────────────────
  Future<void> _updateCartQuantityBulk(String productId, int newQty) async {
    if (newQty < 1) return;
    setState(() => _pendingProductOps.add(productId));

    try {
      final headers = await _buildHeaders(json: true);

      // tripId/employeeId must be omitted if empty (BSON ObjectId cast)
      final body = <String, dynamic>{
        'customerId': widget.farmerId, // plain string
        'type': widget.farmerType, // separate field
        'productId': productId,
        'action': 'setQuantity',
        'quantity': newQty,
        if (_employeeId != null && _employeeId!.isNotEmpty)
          'employeeId': _employeeId,
        if (_tripId != null && _tripId!.isNotEmpty) 'tripId': _tripId,
      };

      debugPrint('📦 [FarmerOrder] bulkQty body: ${jsonEncode(body)}');

      final resp = await http
          .put(
            AppConfig.u(AppConfig.updateCart),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(AppConfig.httpTimeout);

      debugPrint('📦 [FarmerOrder] bulkQty ${resp.statusCode}: ${resp.body}');

      if (resp.statusCode == 200) {
        final parsed = jsonDecode(resp.body);
        final cart = _cartFromResponse(parsed);
        if (mounted && cart != null) setState(() => _serverCart = cart);
        await _fetchCart();
      } else {
        final parsed = jsonDecode(resp.body);
        _snack(
          parsed['message']?.toString() ??
              'Failed to update quantity (${resp.statusCode})',
        );
      }
    } catch (e) {
      _snack('Network error: $e');
    } finally {
      if (mounted) setState(() => _pendingProductOps.remove(productId));
    }
  }

  // ── Delete cart item ───────────────────────────────────────
  Future<void> _deleteCartItem(Map<String, dynamic> item) async {
    final productId = _productIdOf(item);
    if (productId == null) return;

    final cartId = _serverCart?['_id']?.toString();
    if (cartId == null || cartId.isEmpty) {
      _snack('Unable to delete: missing cartId');
      return;
    }

    setState(() => _pendingProductOps.add(productId));

    try {
      final headers = await _buildHeaders(json: true);

      // Exact same shape as cart_screen's _deleteCartItem
      final body = <String, dynamic>{'cartId': cartId, 'productId': productId};

      debugPrint('📦 [FarmerOrder] delete body: ${jsonEncode(body)}');

      final resp = await http
          .delete(
            AppConfig.u(AppConfig.deleteCart),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(AppConfig.httpTimeout);

      debugPrint('📦 [FarmerOrder] delete ${resp.statusCode}: ${resp.body}');

      final parsed = jsonDecode(resp.body);
      if (resp.statusCode == 200) {
        final cart = _cartFromResponse(parsed);
        if (mounted && cart != null) setState(() => _serverCart = cart);
        final msg = parsed['message']?.toString() ?? 'Item removed from cart.';
        _snack(msg);
        await _fetchCart();
      } else {
        _snack(
          parsed['message']?.toString() ??
              'Failed to remove (${resp.statusCode})',
        );
      }
    } catch (e) {
      _snack('Network error: $e');
    } finally {
      if (mounted) setState(() => _pendingProductOps.remove(productId));
    }
  }

  // ── Submit order ───────────────────────────────────────────
  Future<bool> _submitAndReturn() async {
    final items = _itemsFromServer();
    if (items.isEmpty) return false;

    try {
      final headers = await _buildHeaders(json: true);

      final body = <String, dynamic>{
        'customerId': {'id': widget.farmerId, 'type': widget.farmerType},
        if (_employeeId != null && _employeeId!.isNotEmpty)
          'employeeId': _employeeId,
        if (_tripId != null && _tripId!.isNotEmpty) 'tripId': _tripId,
        'items': items
            .map(
              (e) => {
                'productId': _productIdOf(e),
                'quantity': e['quantity'],
                'price': e['price'],
              },
            )
            .toList(),
        'remarks': _remarksCtrl.text.trim(),
      };

      debugPrint('📦 [FarmerOrder] POST ${AppConfig.createOrder}');
      debugPrint('📦 body: ${jsonEncode(body)}');

      final resp = await http
          .post(
            AppConfig.u(AppConfig.createOrder),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(AppConfig.httpTimeout);

      debugPrint('📦 [FarmerOrder] response ${resp.statusCode}: ${resp.body}');

      return resp.statusCode == 200 || resp.statusCode == 201;
    } catch (e) {
      debugPrint('📦 [FarmerOrder] error: $e');
      return false;
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  // ── Open products sheet ────────────────────────────────────
  Future<void> _openProductsSheet() async {
    if (!_initialized) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => ProductsBottomSheet(
          onProductSelected: (item) {
            _addToCart(item.product);
          },
          cache: _cache,
          imageBox: _imageBox,
          scrollController: scrollController,
        ),
      ),
    );
  }

  // ── Set quantity bottom sheet ──────────────────────────────
  void _showQuantityOptions(String productId, int currentQty) {
    final customCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
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
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Update Quantity',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _kGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _kGreen, width: 1),
                  ),
                  child: Text(
                    'Current: $currentQty',
                    style: const TextStyle(
                      color: _kGreen,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
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
                          color: _kGreen,
                          width: 1.2,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: _kGreen,
                          width: 1.2,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: _kGreen,
                          width: 1.8,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
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
                      _snack('Enter a valid quantity (≥ 1)');
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
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final items = _itemsFromServer();
    return _PurposeCardShell(
      isExpanded: widget.isExpanded,
      onToggle: widget.onToggle,
      icon: Icons.shopping_cart_rounded,
      title: 'Order',
      subtitle: items.isEmpty
          ? 'Place a new order.'
          : '${items.length} product(s) · ₹${_totalAmount.toStringAsFixed(2)}',
      isStarted: widget.isStarted,
      isValid: widget.isValid,
      expandedContent: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final items = _itemsFromServer();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Add Products Button ──────────────────────────────
          ElevatedButton.icon(
            onPressed: _openProductsSheet,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.add_shopping_cart_rounded),
            label: const Text(
              'Add Products',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
            ),
          ),

          const SizedBox(height: 14),

          // ── Cart loading / error / empty / list ──────────────
          if (_isLoadingCart)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(color: _kGreen),
              ),
            )
          else if (_cartError != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE8E8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFC2C2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _cartError!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                  GestureDetector(
                    onTap: _fetchCart,
                    child: const Icon(Icons.refresh, color: _kGreen, size: 20),
                  ),
                ],
              ),
            )
          else if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.shopping_bag_outlined,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No products added yet',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Cart items list ────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _kGreenLight.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kGreen.withValues(alpha: 0.3)),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, idx) => _buildCartTile(items[idx]),
                  ),
                ),

                const SizedBox(height: 12),

                // ── Total ──────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _kGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${items.length} item(s)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '₹${_totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: _kGreen,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ── Remarks ────────────────────────────────────
                TextField(
                  controller: _remarksCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Description / Requirement (Optional)',
                    alignLabelWithHint: true,
                    prefixIcon: const Icon(
                      Icons.notes_rounded,
                      color: _kGreen,
                      size: 20,
                    ),
                    filled: true,
                    fillColor: Colors.grey.withValues(alpha: 0.05),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    labelStyle: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 13.5,
                    ),
                    floatingLabelStyle: const TextStyle(
                      color: _kGreen,
                      fontSize: 13,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _kGreen, width: 1.3),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _kGreen, width: 2),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _kGreen, width: 1.3),
                    ),
                  ),
                ),

                if (widget.isStarted && widget.isValid)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: _CompleteHint(message: 'Cart ready ✓'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  // ── Cart tile ──────────────────────────────────────────────
  Widget _buildCartTile(Map<String, dynamic> it) {
    final productId = _productIdOf(it) ?? '';
    final busy = productId.isNotEmpty && _pendingProductOps.contains(productId);

    final Map<String, dynamic>? productMeta = () {
      final raw = it['productId'];
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) return Map<String, dynamic>.from(raw);
      return null;
    }();

    final productName =
        (it['productName'] ?? productMeta?['productName'] ?? 'Unnamed product')
            .toString();

    final rawImage =
        it['productImage'] ??
        (productMeta != null &&
                productMeta['productImages'] is List &&
                (productMeta['productImages'] as List).isNotEmpty
            ? productMeta['productImages'][0].toString()
            : null);

    final imageUrl = () {
      if (rawImage == null || (rawImage as String).isEmpty) return null;
      if (rawImage.startsWith('http')) return rawImage;
      return AppConfig.imageUrl(rawImage);
    }();

    final qty = it['quantity'];
    final rawPrice = it['price'];

    final priceNum = (rawPrice is num)
        ? rawPrice.toDouble()
        : (rawPrice is String ? double.tryParse(rawPrice) ?? 0.0 : 0.0);
    final qtyNum = (qty is num)
        ? qty.toInt()
        : int.tryParse(qty.toString()) ?? 0;
    final lineTotal = priceNum * qtyNum;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Image ──────────────────────────────────────────
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              image: imageUrl != null
                  ? DecorationImage(
                      image: NetworkImage(imageUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: imageUrl == null
                ? Icon(
                    Icons.image_not_supported_outlined,
                    color: Colors.grey[500],
                    size: 22,
                  )
                : null,
          ),
          const SizedBox(width: 10),

          // ── Info + controls ────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${priceNum.toStringAsFixed(2)} × $qtyNum  =  ₹${lineTotal.toStringAsFixed(2)}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 10),

                // ── ± controls ──────────────────────────────
                Row(
                  children: [
                    // minus
                    GestureDetector(
                      onTap: busy || productId.isEmpty || qtyNum <= 1
                          ? null
                          : () => _updateCartQuantity(productId, 'decrease'),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: (busy || qtyNum <= 1)
                              ? Colors.grey.withValues(alpha: 0.12)
                              : _kGreen.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: (busy || qtyNum <= 1)
                                ? Colors.grey.withValues(alpha: 0.3)
                                : _kGreen.withValues(alpha: 0.4),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.remove,
                          size: 15,
                          color: (busy || qtyNum <= 1)
                              ? Colors.grey[400]
                              : _kGreen,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),

                    // qty badge — tappable → set-quantity sheet
                    GestureDetector(
                      onTap: busy || productId.isEmpty
                          ? null
                          : () => _showQuantityOptions(productId, qtyNum),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _kGreen.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: busy
                                ? Colors.transparent
                                : _kGreen.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$qtyNum',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: _kGreen,
                              ),
                            ),
                            if (!busy) ...[
                              const SizedBox(width: 3),
                              Icon(
                                Icons.edit,
                                size: 11,
                                color: _kGreen.withValues(alpha: 0.7),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),

                    // plus
                    GestureDetector(
                      onTap: busy || productId.isEmpty
                          ? null
                          : () => _updateCartQuantity(productId, 'increase'),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: busy
                              ? Colors.grey.withValues(alpha: 0.2)
                              : _kGreen,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.add,
                          size: 15,
                          color: busy ? Colors.grey[400] : Colors.white,
                        ),
                      ),
                    ),

                    if (busy)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _kGreen,
                          ),
                        ),
                      ),

                    const Spacer(),

                    // delete
                    GestureDetector(
                      onTap: busy || productId.isEmpty
                          ? null
                          : () => _deleteCartItem(it),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.delete_outline_rounded,
                          size: 15,
                          color: Colors.red[400],
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
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _QueryButtonCard — Opens Query Bottom Sheet
// ═══════════════════════════════════════════════════════════════════════════════

class _QueryButtonCard extends StatelessWidget {
  final VoidCallback onTap;
  final bool isStarted;
  final bool isValid;
  final String remarksPreview;
  final int pondCount;
  final int imageCount;

  const _QueryButtonCard({
    required this.onTap,
    required this.isStarted,
    required this.isValid,
    required this.remarksPreview,
    required this.pondCount,
    required this.imageCount,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kGreen.withValues(alpha: 0.2), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: _kGreen.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _kGreenLight,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.help_outline_rounded,
                color: _kGreen,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Query / Issue',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  Text(
                    remarksPreview.isEmpty
                        ? 'Report any queries or issues.'
                        : remarksPreview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12.5,
                    ),
                  ),
                  if (isStarted)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _MiniQueryChip(
                            icon: Icons.water,
                            label:
                                '$pondCount pond${pondCount == 1 ? '' : 's'}',
                          ),
                          _MiniQueryChip(
                            icon: Icons.image_outlined,
                            label:
                                '$imageCount image${imageCount == 1 ? '' : 's'}',
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _CardStatusBadge(isStarted: isStarted, isValid: isValid),
            const SizedBox(width: 8),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.arrow_forward_rounded,
                color: _kGreen,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniQueryChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MiniQueryChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _kGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kGreen.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _kGreen),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: _kGreen,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
// ═══════════════════════════════════════════════════════════════════════════════
//  _PondForm — data holder for a single pond
// ═══════════════════════════════════════════════════════════════════════════════

class _PondForm {
  final pondName = TextEditingController();
  final size = TextEditingController();
  final speciesCtrl = TextEditingController(); // ✅ Stable controller
  String? species;
  final menuCtrl = MenuController();
  final speciesKey = GlobalKey<FormFieldState>();
  final stockingPL = TextEditingController();
  final doc = TextEditingController();
  final feed = TextEditingController();
  final count = TextEditingController();
  final avgWeight = TextEditingController();
  final salinity = TextEditingController();
  final ph = TextEditingController();
  final alkalinity = TextEditingController();
  final ammonia = TextEditingController();
  final nitrite = TextEditingController();
  final dissolvedOxygen = TextEditingController();
  final vibrios = TextEditingController();

  Map<String, dynamic> toJson() => {
    'pondName': pondName.text.trim(),
    'culturedArea': size.text.trim(),
    'culturedSpecies': species ?? '',
    'physicalReadings': [
      {
        'stockingPL': stockingPL.text.trim(),
        'doc': doc.text.trim(),
        'feedIntakePerDay': feed.text.trim(),
        'count': count.text.trim(),
        if (species == 'Fish' && avgWeight.text.trim().isNotEmpty)
          'avgWeight': avgWeight.text.trim(),
      },
    ],
    'chemicalReadings': [
      {
        'salinity': salinity.text.trim(),
        'ph': ph.text.trim(),
        'alkalinity': alkalinity.text.trim(),
        'ammonia': ammonia.text.trim(),
        'nitrite': nitrite.text.trim(),
        'dissolvedOxygen': dissolvedOxygen.text.trim(),
      },
    ],
    'diseaseReadings': vibrios.text.trim().isNotEmpty
        ? [
            {'vibrios': vibrios.text.trim()},
          ]
        : [],
  };

  void dispose() {
    pondName.dispose();
    size.dispose();
    speciesCtrl.dispose(); // ✅ Properly disposed
    stockingPL.dispose();
    doc.dispose();
    feed.dispose();
    count.dispose();
    avgWeight.dispose();
    salinity.dispose();
    ph.dispose();
    alkalinity.dispose();
    ammonia.dispose();
    nitrite.dispose();
    dissolvedOxygen.dispose();
    vibrios.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _QueryBottomSheet — Farmer Query/Ticket form
// ═══════════════════════════════════════════════════════════════════════════════

class _QueryDraft {
  _FarmerLite? selected;

  final farmerNameCtrl = TextEditingController();
  final mobileCtrl = TextEditingController();
  final locationCtrl = TextEditingController();
  final remarksCtrl = TextEditingController();
  final List<_PondForm> ponds = [_PondForm()];
  final List<XFile> images = [];

  void seedFarmer({
    required String farmerId,
    required String farmerName,
    required String mobile,
    required String address,
  }) {
    selected = _FarmerLite(
      id: farmerId,
      name: farmerName,
      mobile: mobile,
      location: address,
    );
    farmerNameCtrl.text = farmerName;
    mobileCtrl.text = mobile;
    locationCtrl.text = address;
  }

  bool get canSubmitFarmer {
    if (remarksCtrl.text.trim().isEmpty) return false;
    for (final p in ponds) {
      if (p.pondName.text.trim().isEmpty) return false;
      if (p.size.text.trim().isEmpty) return false;
      if (p.species == null) return false;
      if (!_isInt(p.stockingPL.text)) return false;
      if (!_isInt(p.doc.text)) return false;
      if (p.feed.text.trim().isEmpty) return false;
      if (!_isInt(p.count.text)) return false;
    }
    return true;
  }

  String get remarksPreview => remarksCtrl.text.trim();

  void resetToFarmer({
    required String farmerId,
    required String farmerName,
    required String mobile,
    required String address,
  }) {
    for (final p in ponds) {
      p.dispose();
    }
    ponds
      ..clear()
      ..add(_PondForm());
    images.clear();
    remarksCtrl.clear();
    seedFarmer(
      farmerId: farmerId,
      farmerName: farmerName,
      mobile: mobile,
      address: address,
    );
  }

  void dispose() {
    farmerNameCtrl.dispose();
    mobileCtrl.dispose();
    locationCtrl.dispose();
    remarksCtrl.dispose();
    for (final p in ponds) {
      p.dispose();
    }
  }

  static bool _isInt(String value) => RegExp(r'^\d+$').hasMatch(value.trim());
}

class _QueryBottomSheet extends StatefulWidget {
  final String farmerId;
  final String farmerName;
  final String address;
  final String mobile;
  final double latitude;
  final double longitude;
  final bool tripCompleted;
  final ValueChanged<bool> onValidityChanged;
  final _QueryDraft draft;

  const _QueryBottomSheet({
    required this.farmerId,
    required this.farmerName,
    required this.address,
    required this.mobile,
    required this.latitude,
    required this.longitude,
    required this.tripCompleted,
    required this.onValidityChanged,
    required this.draft,
  });

  @override
  State<_QueryBottomSheet> createState() => _QueryBottomSheetState();
}

class _QueryBottomSheetState extends State<_QueryBottomSheet> {
  // ─────────────────────────── constants ────────────────────────────────────
  static const Color _appGreen = Color(0xFF1AB69C);
  static const int _maxPonds = 4;

  // ─────────────────────────── farmer fields ────────────────────────────────
  _FarmerLite? get _selected => widget.draft.selected;
  set _selected(_FarmerLite? value) => widget.draft.selected = value;
  TextEditingController get _farmerNameCtrl => widget.draft.farmerNameCtrl;
  TextEditingController get _mobileCtrl => widget.draft.mobileCtrl;
  TextEditingController get _locationCtrl => widget.draft.locationCtrl;

  // ─────────────────────────── form ─────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  TextEditingController get _remarksCtrl => widget.draft.remarksCtrl;

  // ─────────────────────────── ponds ────────────────────────────────────────
  List<_PondForm> get _ponds => widget.draft.ponds;

  // ─────────────────────────── images ───────────────────────────────────────
  List<XFile> get _images => widget.draft.images;
  final ImagePicker _picker = ImagePicker();

  // ─────────────────────────── state ────────────────────────────────────────
  String? _inlineBanner;
  bool _submitting = false;

  // ══════════════════════════════════════════════════════════════════════════
  //  PUBLIC API — called by the parent's unified submit button
  // ══════════════════════════════════════════════════════════════════════════

  /// Parent reads this to gate its submit button.
  bool get canSubmitFarmer {
    if (_submitting) return false;
    if (_remarksCtrl.text.trim().isEmpty) return false;
    for (final p in _ponds) {
      if (p.pondName.text.trim().isEmpty) return false;
      if (p.size.text.trim().isEmpty) return false;
      if (p.species == null) return false;
      if (p.stockingPL.text.trim().isEmpty) return false;
      if (p.doc.text.trim().isEmpty) return false;
      if (p.feed.text.trim().isEmpty) return false;
      if (p.count.text.trim().isEmpty) return false;
    }
    return true;
  }

  /// Parent reads this to show its own loading spinner.
  bool get isSubmitting => _submitting;

  /// Parent calls this on its unified submit button tap.
  /// Returns true on success, false on validation failure or server error.
  Future<bool> submitTicket() => _submitFarmerTicket();

  // ══════════════════════════════════════════════════════════════════════════
  //  FORMATTERS
  // ══════════════════════════════════════════════════════════════════════════

  // ✅ FIX — regular string (not raw r'') so $maxInt/$maxDecimal interpolate
  TextInputFormatter decimalLimit({int maxInt = 4, int maxDecimal = 2}) =>
      FilteringTextInputFormatter.allow(
        RegExp('^\\d{0,$maxInt}(\\.\\d{0,$maxDecimal})?\$'),
      );

  TextInputFormatter intLimit(int maxDigits) =>
      LengthLimitingTextInputFormatter(maxDigits);

  static final List<TextInputFormatter> _pondNameFmt = [
    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 ]')),
    LengthLimitingTextInputFormatter(40),
  ];

  static final List<TextInputFormatter> _lettersAndDigitsOnly = [
    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 ]')),
    LengthLimitingTextInputFormatter(100),
  ];

  // ══════════════════════════════════════════════════════════════════════════
  //  LIFECYCLE
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    if (_selected == null) {
      widget.draft.seedFarmer(
        farmerId: widget.farmerId,
        farmerName: widget.farmerName,
        mobile: widget.mobile,
        address: widget.address,
      );
    }
  }

  @override
  void dispose() => super.dispose();

  // ══════════════════════════════════════════════════════════════════════════
  //  HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  void _safeSet(void Function() fn) {
    if (!mounted) return;
    setState(fn);
  }

  void _errorTop(String msg) => _safeSet(() => _inlineBanner = msg);

  void _updateValidity() => widget.onValidityChanged(canSubmitFarmer);

  // ── Save draft and close bottom sheet ─────────────────────────────────────
  void _saveAndClose() {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) {
      _errorTop('Please correct the highlighted fields.');
      return;
    }

    if (_remarksCtrl.text.trim().isEmpty) {
      _errorTop('Remarks are required.');
      return;
    }

    // All ponds must have species selected (validator won't catch MenuAnchor)
    for (int i = 0; i < _ponds.length; i++) {
      if (_ponds[i].species == null) {
        _errorTop('Please select a species for Pond ${i + 1}.');
        return;
      }
    }

    // Draft is already live (controllers are the draft's controllers),
    // so just notify parent of validity and close.
    widget.onValidityChanged(canSubmitFarmer);
    Navigator.of(context).pop();
  }

  // ── validators ────────────────────────────────────────────────────────────
  String? _vRequired(String? v, String label) {
    if ((v ?? '').trim().isEmpty) return '$label is required';
    return null;
  }

  String? _vRequiredInt(String? v, String label) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return '$label is required';
    if (!RegExp(r'^\d+$').hasMatch(s)) return '$label must be a whole number';
    return null;
  }

  // ── pond management ───────────────────────────────────────────────────────
  void _addPond() {
    if (_ponds.length >= _maxPonds) {
      _errorTop('You can add up to $_maxPonds ponds only');
      return;
    }
    _safeSet(() => _ponds.add(_PondForm()));
  }

  void _removePond(int index) {
    if (_ponds.length == 1) return;
    final removed = _ponds.removeAt(index);
    removed.dispose();
    _safeSet(() {});
  }

  // ── image management ──────────────────────────────────────────────────────
  Future<void> _pickFromCamera() async {
    if (_images.length >= 3) return;
    final img = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 1280,
    );
    if (img != null) _safeSet(() => _images.add(img));
  }

  Future<void> _pickFromGallery() async {
    final imgs = await _picker.pickMultiImage(imageQuality: 70, maxWidth: 1280);
    if (imgs.isNotEmpty) {
      final remaining = 3 - _images.length;
      _safeSet(() => _images.addAll(imgs.take(remaining)));
    }
  }

  void _removeImage(int index) => _safeSet(() => _images.removeAt(index));

  // ── image preparation ─────────────────────────────────────────────────────
  Future<List<QueuedFile>> _prepareTicketImages() async {
    final files = <QueuedFile>[];

    for (final image in _images) {
      final originalFile = File(image.path);
      if (!originalFile.existsSync()) {
        debugPrint('⚠️ FarmerTicket image missing: ${image.path}');
        continue;
      }

      final optimizedFile = await MediaOptimizer.getOptimizedImage(
        originalFile,
      );
      final finalFile = optimizedFile ?? originalFile;
      final sizeMB = await MediaOptimizer.getFileSizeMB(finalFile);

      if (sizeMB > 5) {
        throw Exception(
          'Image too large (${sizeMB.toStringAsFixed(2)} MB). '
          'Please select a smaller image.',
        );
      }

      final fileName = image.name.isNotEmpty
          ? image.name
          : finalFile.path.split('/').last;
      final ext = fileName.split('.').last.toLowerCase();
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';

      debugPrint('📦 FarmerTicket image: $fileName @ ${finalFile.path}');
      debugPrint('📊 FarmerTicket size : ${sizeMB.toStringAsFixed(2)} MB');

      files.add(
        QueuedFile(
          field: 'images',
          path: finalFile.path,
          filename: fileName,
          contentType: mime,
        ),
      );
    }

    return files;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SUBMIT — private, exposed publicly via submitTicket()
  //  ✅ Returns bool; no Navigator.pop() (parent decides when to pop)
  // ══════════════════════════════════════════════════════════════════════════
  Future<bool> _submitFarmerTicket() async {
    FocusScope.of(context).unfocus();

    if (_selected == null) {
      _errorTop('Please select a farmer.');
      return false;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      _errorTop('Please correct the highlighted fields.');
      return false;
    }

    if (_remarksCtrl.text.trim().isEmpty) {
      _errorTop('Remarks are required.');
      return false;
    }

    _errorTop('');
    _safeSet(() => _submitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final companyId = prefs.getString('companyId') ?? '';
      final employeeId = prefs.getString('userId') ?? '';
      final tripId = prefs.getString('currentTripId') ?? '';
      final tripCompleted = prefs.getBool('tripCompleted') ?? false;
      final effectiveTripId = tripCompleted ? tripId : '';
      final token = await SecureStorageService.getToken();

      final location = _locationCtrl.text.trim().isNotEmpty
          ? _locationCtrl.text.trim()
          : '(Offline — address unavailable)';

      final ponds = _ponds.map((p) => p.toJson()).toList();
      final List<QueuedFile> files = await _prepareTicketImages();

      final body = <String, String>{
        'companyId': companyId,
        if (effectiveTripId.isNotEmpty) 'tripId': effectiveTripId,
        'employeeId': employeeId,
        'farmerId': _selected!.id ?? '',
        'farmerName': _farmerNameCtrl.text.trim(),
        'mobileNumber': _mobileCtrl.text.trim(),
        'address': location,
        'remarks': _remarksCtrl.text.trim(),
        'status': 'Pending',
      };

      for (int i = 0; i < ponds.length; i++) {
        final pond = ponds[i];

        body['ponds[$i][pondName]'] = pond['pondName'].toString();
        body['ponds[$i][culturedArea]'] = pond['culturedArea'].toString();
        body['ponds[$i][culturedSpecies]'] = pond['culturedSpecies'].toString();

        // Physical
        final phys = (pond['physicalReadings'] as List).first;
        body['ponds[$i][physicalReadings][0][stockingPL]'] = phys['stockingPL']
            .toString();
        body['ponds[$i][physicalReadings][0][doc]'] = phys['doc'].toString();
        body['ponds[$i][physicalReadings][0][feedIntakePerDay]'] =
            phys['feedIntakePerDay'].toString();
        body['ponds[$i][physicalReadings][0][count]'] = phys['count']
            .toString();
        if (phys['avgWeight'] != null) {
          body['ponds[$i][physicalReadings][0][avgWeight]'] = phys['avgWeight']
              .toString();
        }

        // Chemical
        final chem = (pond['chemicalReadings'] as List).first;
        body['ponds[$i][chemicalReadings][0][salinity]'] = chem['salinity']
            .toString();
        body['ponds[$i][chemicalReadings][0][ph]'] = chem['ph'].toString();
        body['ponds[$i][chemicalReadings][0][alkalinity]'] = chem['alkalinity']
            .toString();
        body['ponds[$i][chemicalReadings][0][ammonia]'] = chem['ammonia']
            .toString();
        body['ponds[$i][chemicalReadings][0][nitrite]'] = chem['nitrite']
            .toString();
        body['ponds[$i][chemicalReadings][0][dissolvedOxygen]'] =
            chem['dissolvedOxygen'].toString();

        // Disease (optional)
        final disease = pond['diseaseReadings'] as List;
        if (disease.isNotEmpty) {
          body['ponds[$i][diseaseReadings][0][vibrios]'] = disease
              .first['vibrios']
              .toString();
        }
      }

      debugPrint('🧾 [FarmerTicket] POST ${AppConfig.farmerTicket}');
      debugPrint('🧾 [FarmerTicket] body: ${jsonEncode(body)}');

      final resp = await apiClient.sendOrQueue(
        method: HttpVerb.post,
        path: AppConfig.farmerTicket,
        jsonBody: body,
        files: files,
        headers: {'Authorization': 'Bearer $token'},
        optimisticOk: true,
      );

      if (!mounted) return false;

      if (resp == null) {
        // ── queued offline ──────────────────────────────────────────────────
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Queued offline — will sync automatically'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _safeResetFarmerForm();
        return true; // ✅ success (queued)
      } else if (resp.statusCode == 200 || resp.statusCode == 201) {
        // ── server accepted ────────────────────────────────────────────────
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Farmer query submitted successfully'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _safeResetFarmerForm();
        return true; // ✅ success
      } else {
        // ── server error ───────────────────────────────────────────────────
        String msg = 'HTTP ${resp.statusCode}';
        try {
          final j = jsonDecode(resp.body);
          if (j is Map && j['message'] is String) msg = j['message'];
        } catch (_) {}
        _errorTop('Failed to raise query: $msg');
        return false; // ❌ server rejected
      }
    } catch (e) {
      _errorTop('Network error: $e');
      return false; // ❌ exception
    } finally {
      _safeSet(() => _submitting = false);
    }
  }

  // ── form reset ────────────────────────────────────────────────────────────
  void _safeResetFarmerForm() {
    for (final p in _ponds) p.dispose();
    _safeSet(() {
      _selected = null;
      _farmerNameCtrl.clear();
      _mobileCtrl.clear();
      _locationCtrl.clear();
      _remarksCtrl.clear();
      _images.clear();
      _ponds
        ..clear()
        ..add(_PondForm());
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  DECORATION HELPER
  // ══════════════════════════════════════════════════════════════════════════
  InputDecoration _pondDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.grey.withValues(alpha: 0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Colors.grey.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _appGreen, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1.6),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // ── inline error banner ──────────────────────────────────────────
          if ((_inlineBanner ?? '').isNotEmpty)
            _TopBarMessage(
              message: _inlineBanner!,
              onClose: () => _safeSet(() => _inlineBanner = null),
            ),

          // ── scrollable form ──────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [_formCard()],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  FORM CARD
  // ══════════════════════════════════════════════════════════════════════════
  Widget _formCard() {
    return Card(
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── ponds header ───────────────────────────────────────────────
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(
                    'Ponds (${_ponds.length}/$_maxPonds)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _ponds.length >= _maxPonds ? null : _addPond,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Pond'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _appGreen,
                      side: const BorderSide(color: _appGreen),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // ── pond cards ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: List.generate(
                  _ponds.length,
                  (i) => _pondCard(
                    index: i,
                    pf: _ponds[i],
                    onRemove: _ponds.length == 1 ? null : () => _removePond(i),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── image upload ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ Dynamic count
                  Text(
                    'Upload Images (${_images.length}/3)',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _images.length >= 3 ? null : _pickFromCamera,
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Camera'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _appGreen,
                          side: const BorderSide(color: _appGreen),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _images.length >= 3
                            ? null
                            : _pickFromGallery,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Gallery'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _appGreen,
                          side: const BorderSide(color: _appGreen),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_images.isNotEmpty)
                    SizedBox(
                      height: 90,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _images.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) {
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  File(_images[i].path),
                                  width: 90,
                                  height: 90,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => _removeImage(i),
                                  child: const CircleAvatar(
                                    radius: 10,
                                    backgroundColor: Colors.black54,
                                    child: Icon(
                                      Icons.close,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── remarks ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextFormField(
                controller: _remarksCtrl,
                decoration: _pondDecoration('Remarks (required)'),
                inputFormatters: _lettersAndDigitsOnly,
                maxLines: 3,
                cursorColor: _appGreen,
                validator: (v) => _vRequired(v, 'Remarks'),
                onChanged: (_) {
                  _safeSet(() {});
                  _updateValidity();
                },
              ),
            ),

            // ── Save & Close button ────────────────────────────────────────
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _saveAndClose,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _appGreen,
                    disabledBackgroundColor: Colors.grey[300],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(
                    _submitting ? 'Saving...' : 'Save Query',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  POND CARD
  // ══════════════════════════════════════════════════════════════════════════
  Widget _pondCard({
    required int index,
    required _PondForm pf,
    VoidCallback? onRemove,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── pond header ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _appGreen.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
              border: const Border(
                left: BorderSide(color: _appGreen, width: 3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.water, size: 16, color: _appGreen),
                const SizedBox(width: 6),
                Text(
                  'Pond ${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: _appGreen,
                  ),
                ),
                const Spacer(),
                if (onRemove != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: onRemove,
                    tooltip: 'Remove pond',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── pond name ──────────────────────────────────────────────────
          TextFormField(
            controller: pf.pondName,
            decoration: _pondDecoration('Pond Name'),
            inputFormatters: _pondNameFmt,
            validator: (v) => _vRequired(v, 'Pond name'),
          ),

          const SizedBox(height: 10),

          // ── pond size ──────────────────────────────────────────────────
          TextFormField(
            controller: pf.size,
            decoration: _pondDecoration('Pond Size (acres)'),
            inputFormatters: [decimalLimit(maxInt: 4, maxDecimal: 2)],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) => _vRequired(v, 'Pond size'),
          ),

          const SizedBox(height: 10),

          // ── species selector ───────────────────────────────────────────
          MenuAnchor(
            controller: pf.menuCtrl,
            childFocusNode: FocusNode(),
            builder: (context, controller, _) {
              return TextFormField(
                key: pf.speciesKey,
                readOnly: true,
                controller: pf.speciesCtrl,
                decoration: _pondDecoration(
                  'Culture Species',
                ).copyWith(suffixIcon: const Icon(Icons.keyboard_arrow_down)),
                onTap: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                validator: (_) =>
                    pf.species == null ? 'Species is required' : null,
              );
            },
            menuChildren: [
              _pondMenuItem('Shrimp', pf),
              _pondMenuItem('Fish', pf),
            ],
          ),

          // ─────────────────── PHYSICAL ─────────────────────────────────
          const SizedBox(height: 14),
          _sectionHeader(Icons.thermostat_outlined, 'Physical Parameters'),
          const SizedBox(height: 10),

          TextFormField(
            controller: pf.stockingPL,
            decoration: _pondDecoration('Stocking PL'),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              intLimit(7),
            ],
            keyboardType: TextInputType.number,
            validator: (v) => _vRequiredInt(v, 'Stocking PL'),
          ),
          const SizedBox(height: 10),

          // ✅ digitsOnly formatter added to DOC
          TextFormField(
            controller: pf.doc,
            decoration: _pondDecoration('DOC (Days of Culture)'),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            keyboardType: TextInputType.number,
            validator: (v) => _vRequiredInt(v, 'DOC'),
          ),
          const SizedBox(height: 10),

          TextFormField(
            controller: pf.feed,
            decoration: _pondDecoration('Feed Intake / Day (kg)'),
            inputFormatters: [decimalLimit(maxInt: 5, maxDecimal: 2)],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) => _vRequired(v, 'Feed intake'),
          ),
          const SizedBox(height: 10),

          // ✅ digitsOnly formatter added to Count
          TextFormField(
            controller: pf.count,
            decoration: _pondDecoration('Count'),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(7),
            ],
            keyboardType: TextInputType.number,
            validator: (v) => _vRequiredInt(v, 'Count'),
          ),

          if (pf.species == 'Fish') ...[
            const SizedBox(height: 10),
            TextFormField(
              controller: pf.avgWeight,
              decoration: _pondDecoration('Avg Weight (g)'),
              inputFormatters: [decimalLimit(maxInt: 5, maxDecimal: 2)],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
          ],

          // ─────────────────── CHEMICAL ─────────────────────────────────
          const SizedBox(height: 16),
          _sectionHeader(Icons.science_outlined, 'Chemical Parameters'),
          const SizedBox(height: 10),

          TextFormField(
            controller: pf.salinity,
            decoration: _pondDecoration('Salinity (ppt)'),
            inputFormatters: [decimalLimit(maxInt: 3, maxDecimal: 2)],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 10),

          TextFormField(
            controller: pf.ph,
            decoration: _pondDecoration('pH'),
            inputFormatters: [decimalLimit(maxInt: 2, maxDecimal: 2)],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 10),

          TextFormField(
            controller: pf.alkalinity,
            decoration: _pondDecoration('Alkalinity (mg/L)'),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 10),

          TextFormField(
            controller: pf.ammonia,
            decoration: _pondDecoration('Ammonia (mg/L)'),
            inputFormatters: [decimalLimit(maxInt: 3, maxDecimal: 3)],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 10),

          TextFormField(
            controller: pf.nitrite,
            decoration: _pondDecoration('Nitrite (mg/L)'),
            inputFormatters: [decimalLimit(maxInt: 3, maxDecimal: 3)],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 10),

          TextFormField(
            controller: pf.dissolvedOxygen,
            decoration: _pondDecoration('Dissolved Oxygen (mg/L)'),
            inputFormatters: [decimalLimit(maxInt: 2, maxDecimal: 2)],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),

          // ─────────────────── DISEASE ───────────────────────────────────
          const SizedBox(height: 16),
          _sectionHeader(Icons.bug_report_outlined, 'Disease Parameters'),
          const SizedBox(height: 10),

          TextFormField(
            controller: pf.vibrios,
            decoration: _pondDecoration('Vibrios (CFU/ml)'),
            inputFormatters: [decimalLimit(maxInt: 6, maxDecimal: 2)],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),

          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SECTION HEADER — icon + label + trailing divider
  // ══════════════════════════════════════════════════════════════════════════
  Widget _sectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _appGreen),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: _appGreen,
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(child: Divider(color: _appGreen, thickness: 0.6)),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  POND MENU ITEM
  // ══════════════════════════════════════════════════════════════════════════
  Widget _pondMenuItem(String value, _PondForm pf) {
    final selected = pf.species == value;
    return InkWell(
      onTap: () {
        _safeSet(() {
          pf.species = value;
          pf.speciesCtrl.text = value;
          if (value != 'Fish') pf.avgWeight.clear();
        });
        _updateValidity();
        pf.menuCtrl.close();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: selected ? _appGreen.withValues(alpha: 0.12) : null,
        child: Row(
          children: [
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? _appGreen : Colors.black87,
              ),
            ),
            const Spacer(),
            if (selected)
              const Icon(Icons.check_circle, size: 18, color: _appGreen),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Supporting Classes (match farmer_ticket_screen.dart exactly)
// ═══════════════════════════════════════════════════════════════════════════════

class _FarmerInfoCard extends StatelessWidget {
  final String name;
  final String mobile;
  final String address;
  final int pendingAmount;

  const _FarmerInfoCard({
    required this.name,
    required this.mobile,
    required this.address,
    required this.pendingAmount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1AB69C), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color.fromARGB(
              255,
              180,
              64,
              64,
            ).withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.agriculture, size: 28, color: Color(0xFF1AB69C)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),

                if (mobile.isNotEmpty)
                  Row(
                    children: [
                      const Icon(
                        Icons.phone,
                        size: 16,
                        color: Color(0xFF1AB69C),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        mobile,
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                    ],
                  ),

                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.place, size: 16, color: Color(0xFF1AB69C)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        address,
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.account_balance_wallet,
                      size: 15,
                      color: Color(0xFF1AB69C),
                    ),
                    const SizedBox(width: 8),
                    Builder(
                      builder: (_) {
                        final fmt = NumberFormat.currency(
                          locale: 'en_IN',
                          symbol: '₹',
                          decimalDigits: 2,
                        );
                        final pending = pendingAmount;
                        final noDue = pending <= 0.0;
                        return Flexible(
                          child: Text(
                            noDue ? 'No Due' : 'Due: ${fmt.format(pending)}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              color: noDue
                                  ? Colors.green
                                  : const Color.fromARGB(255, 255, 0, 0),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FarmerLite {
  final String? id;
  final String? name;
  final String? mobile;
  final String? location;

  _FarmerLite({this.id, this.name, this.mobile, this.location});
}

class _TopBarMessage extends StatelessWidget {
  const _TopBarMessage({required this.message, required this.onClose});
  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    if (message.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE8E8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFC2C2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red, fontSize: 13.5),
            ),
          ),
          InkWell(
            onTap: onClose,
            child: const Icon(Icons.close, size: 18, color: Colors.red),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _FarmerHeaderCard
// ═══════════════════════════════════════════════════════════════════════════════

class _FarmerHeaderCard extends StatelessWidget {
  final String farmerName;
  final String subtitle;
  final String address;
  final double latitude;
  final double longitude;
  final double pendingAmount;
  final num totalCultureArea;

  const _FarmerHeaderCard({
    required this.farmerName,
    required this.subtitle,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.pendingAmount,
    required this.totalCultureArea,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kGreen.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // FARMER HEADER
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _kGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.agriculture, color: _kGreen),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      farmerName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ADDRESS
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.place, size: 18, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  address,
                  style: const TextStyle(color: Colors.black87),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // PENDING AMOUNT & CULTURE AREA
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet,
                      size: 15,
                      color: _kGreen,
                    ),
                    const SizedBox(width: 8),
                    Builder(
                      builder: (_) {
                        final fmt = NumberFormat.currency(
                          locale: 'en_IN',
                          symbol: '₹',
                          decimalDigits: 2,
                        );
                        final noDue = pendingAmount <= 0.0;
                        return Text(
                          noDue
                              ? 'No Due'
                              : 'Due: ${fmt.format(pendingAmount)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: noDue
                                ? Colors.green
                                : const Color.fromARGB(255, 255, 0, 0),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.water_drop, size: 15, color: _kGreen),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Area: ${totalCultureArea.toStringAsFixed(2)} acres',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _kGreen,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Inline hint widgets
// ═══════════════════════════════════════════════════════════════════════════════

class _IncompleteHint extends StatelessWidget {
  final String message;

  const _IncompleteHint({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.orange.shade700, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompleteHint extends StatelessWidget {
  final String message;

  const _CompleteHint({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        border: Border.all(color: Colors.green.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 18,
            color: Colors.green.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.green.shade700, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Shared helpers
// ═══════════════════════════════════════════════════════════════════════════════

InputDecoration _inputDec(String label, [IconData? icon]) {
  return InputDecoration(
    labelText: label,
    prefixIcon: icon != null ? Icon(icon, color: _kGreen) : null,
    filled: true,
    fillColor: Colors.grey.withValues(alpha: 0.06),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: _kGreen.withValues(alpha: 0.2), width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _kGreen, width: 1.8),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Colors.red, width: 1),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Colors.red, width: 1.8),
    ),
  );
}

class _DateTimeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool hasValue;
  final VoidCallback onTap;

  const _DateTimeButton({
    required this.icon,
    required this.label,
    required this.hasValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasValue ? _kGreen : _kGreen.withValues(alpha: 0.3),
            width: hasValue ? 1.8 : 1,
          ),
          color: hasValue ? _kGreenLight : Colors.grey.withValues(alpha: 0.06),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: _kGreen),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: hasValue ? FontWeight.w600 : FontWeight.w500,
                  color: hasValue ? _kGreen : Colors.black54,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ProductsBottomSheet — Search & select products for order (mirrors DealerPurposesScreen)
// ═══════════════════════════════════════════════════════════════════════════════

class ProductsBottomSheet extends StatefulWidget {
  final ValueChanged<OrderProductItem> onProductSelected;
  final CacheStore cache;
  final Box imageBox;
  final ScrollController? scrollController;

  const ProductsBottomSheet({
    required this.onProductSelected,
    required this.cache,
    required this.imageBox,
    this.scrollController,
  });

  @override
  State<ProductsBottomSheet> createState() => _ProductsBottomSheetState();
}

class _ProductsBottomSheetState extends State<ProductsBottomSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  bool _isLoading = true;
  String? _error;

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

  /// Tracks which products have been added in this sheet session (for ✓ indicator).
  final Set<String> _addedQtyMap = {};

  int get _activeFilterCount {
    var count = 0;
    if (_selectedCategoryId != null) count++;
    if (_selectedSubCategoryId != null) count++;
    if (_selectedChildCategoryId != null) count++;
    return count;
  }

  /// Adds product with qty=1 via callback and marks it as added in the sheet.
  void _setProductQty(Product product, int qty) {
    final id = product.id ?? '';
    setState(() {
      if (qty <= 0) {
        _addedQtyMap.remove(id);
      } else {
        _addedQtyMap.add(id);
        widget.onProductSelected(
          OrderProductItem(product: product, quantity: 1),
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _fetchCategories();
    _fetchProducts();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _filterProducts();
  }

  void _filterProducts() {
    final query = _searchCtrl.text.toLowerCase();
    if (query.isEmpty) {
      _filteredProducts = List.from(_allProducts);
    } else {
      _filteredProducts = _allProducts
          .where(
            (p) =>
                (p.productName ?? '').toLowerCase().contains(query) ||
                (p.shortDescription ?? '').toLowerCase().contains(query),
          )
          .toList();
    }
    setState(() {});
  }

  Future<void> _fetchProducts({
    String? categoryId,
    String? subCategoryId,
    String? childCategoryId,
  }) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final uri = () {
      if (categoryId != null && categoryId.isNotEmpty) {
        if (childCategoryId != null && childCategoryId.isNotEmpty) {
          return AppConfig.u(
            AppConfig.fill(AppConfig.productsByChildCategoriesId, {
              'id': categoryId,
              'subid': subCategoryId ?? '',
              'childid': childCategoryId,
            }),
          );
        }
        if (subCategoryId != null && subCategoryId.isNotEmpty) {
          return AppConfig.u(
            AppConfig.fill(AppConfig.productsBySubCategoriesId, {
              'id': categoryId,
              'subid': subCategoryId,
            }),
          );
        }
        return AppConfig.u(
          AppConfig.fill(AppConfig.productsByCategoriesId, {'id': categoryId}),
        );
      }
      return AppConfig.u(AppConfig.apiProducts);
    }();

    try {
      final token = await SecureStorageService.getToken();
      final headers = {
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final resp = await http
          .get(uri, headers: headers)
          .timeout(AppConfig.httpTimeout);

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        final items = <Product>[];

        if (body is Map && body['data'] is List) {
          for (final item in body['data'] as List) {
            if (item is Map<String, dynamic>) {
              items.add(Product.fromJson(item));
            }
          }
        } else if (body is List) {
          for (final item in body) {
            if (item is Map<String, dynamic>) {
              items.add(Product.fromJson(item));
            }
          }
        }

        if (mounted) {
          setState(() {
            _allProducts = items;
            _filterProducts();
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Failed to load products';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Network error: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                gradient: LinearGradient(
                  colors: [Color(0xFF52D494), _kGreen],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Select Products',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: TextField(
                              controller: _searchCtrl,
                              decoration: InputDecoration(
                                hintText: 'Search products...',
                                prefixIcon: const Icon(
                                  Icons.search_rounded,
                                  color: _kGreen,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                hintStyle: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _FilterButton(
                          activeCount: _activeFilterCount,
                          onTap: _openFilterSheet,
                        ),
                      ],
                    ),
                    if (_activeFilterCount > 0) ...[
                      const SizedBox(height: 10),
                      _ActiveFiltersBreadcrumb(
                        selectedCategoryId: _selectedCategoryId,
                        selectedSubCategoryId: _selectedSubCategoryId,
                        selectedChildCategoryId: _selectedChildCategoryId,
                        categories: _categories,
                        subcategories: _subcategories,
                        childCategories: _childCategories,
                        onClear: _clearAllFilters,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Products List ──────────────────────────────────────────────
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.red[300],
                          ),
                          const SizedBox(height: 12),
                          Text(_error ?? 'Unknown error'),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _fetchProducts,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kGreen,
                            ),
                            child: const Text(
                              'Retry',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    )
                  : _filteredProducts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shopping_bag_outlined,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _searchCtrl.text.isEmpty
                                ? 'No products available'
                                : 'No products found',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      controller: widget.scrollController,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_filteredProducts.length} product(s) found',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _filteredProducts.length,
                              itemBuilder: (_, idx) =>
                                  _buildProductCard(_filteredProducts[idx]),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(Product product) {
    final price = product.productPrice ?? 0;
    final isAdded = _addedQtyMap.contains(product.id ?? '');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAdded ? _kGreen : Colors.grey[300]!,
          width: isAdded ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isAdded
                ? _kGreen.withValues(alpha: 0.10)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // ── Product Image ──────────────────────────────────────
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              bottomLeft: Radius.circular(12),
            ),
            child: _buildProductImage(product),
          ),
          // ── Product Info ──────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.productName ?? 'Unknown Product',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (product.shortDescription != null &&
                      product.shortDescription!.isNotEmpty)
                    Text(
                      product.shortDescription!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[600], fontSize: 11.5),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    '₹${price.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: _kGreen,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Add / Added indicator ─────────────────────────────
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: isAdded ? null : () => _setProductQty(product, 1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isAdded ? _kGreen.withValues(alpha: 0.12) : _kGreen,
                  borderRadius: BorderRadius.circular(9),
                  border: isAdded
                      ? Border.all(color: _kGreen, width: 1.5)
                      : null,
                ),
                alignment: Alignment.center,
                child: Icon(
                  isAdded ? Icons.check_rounded : Icons.add_rounded,
                  color: isAdded ? _kGreen : Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductImage(Product p) {
    final imageName = p.productImage;
    if (imageName == null || imageName.isEmpty) {
      return Container(
        width: 90,
        height: 90,
        color: Colors.grey[200],
        alignment: Alignment.center,
        child: Icon(
          Icons.image_not_supported_outlined,
          color: Colors.grey[500],
          size: 28,
        ),
      );
    }

    return FutureBuilder<Uint8List?>(
      future: _loadImageBytes(imageName),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
            width: 90,
            height: 90,
            color: Colors.grey[100],
            alignment: Alignment.center,
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Colors.grey[400]),
              ),
            ),
          );
        }
        if (snap.hasData && snap.data != null) {
          return Image.memory(
            snap.data!,
            width: 90,
            height: 90,
            fit: BoxFit.cover,
          );
        }
        // Fallback for error or null data
        return Container(
          width: 90,
          height: 90,
          color: Colors.grey[200],
          alignment: Alignment.center,
          child: Icon(
            Icons.broken_image_outlined,
            color: Colors.grey[500],
            size: 28,
          ),
        );
      },
    );
  }

  Future<Uint8List?> _loadImageBytes(String imageName) async {
    final cached = widget.imageBox.get(imageName);
    if (cached != null) return cached as Uint8List;

    try {
      final token = await SecureStorageService.getToken();
      final headers = {
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final resp = await http
          .get(AppConfig.u(AppConfig.imageUrl(imageName)), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final bytes = resp.bodyBytes;
        await widget.imageBox.put(imageName, bytes);
        return bytes;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _fetchCategories() async {
    if (!mounted) return;
    setState(() {
      _categoriesLoading = true;
      _categoriesError = null;
    });
    try {
      final token = await SecureStorageService.getToken();
      final headers = {
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
      final resp = await http
          .get(AppConfig.u(AppConfig.apiCategories), headers: headers)
          .timeout(AppConfig.httpTimeout);
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        final items = <ProductCategory>[];
        if (body is Map && body['data'] is List) {
          for (final item in body['data'] as List) {
            if (item is Map<String, dynamic>) {
              items.add(ProductCategory.fromJson(item));
            }
          }
        } else if (body is List) {
          for (final item in body) {
            if (item is Map<String, dynamic>) {
              items.add(ProductCategory.fromJson(item));
            }
          }
        }
        if (mounted) {
          setState(() {
            _categories = items;
            _categoriesLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _categoriesError = 'Failed to load categories';
            _categoriesLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _categoriesError = 'Network error: $e';
          _categoriesLoading = false;
        });
      }
    }
  }

  Future<void> _fetchSubcategories(String categoryId) async {
    if (!mounted) return;
    setState(() {
      _subcategoriesLoading = true;
      _subcategoriesError = null;
    });
    try {
      final token = await SecureStorageService.getToken();
      final headers = {
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
      final uri = AppConfig.u(
        AppConfig.fill(AppConfig.apiSubCategories, {'id': categoryId}),
      );
      final resp = await http
          .get(uri, headers: headers)
          .timeout(AppConfig.httpTimeout);
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        final items = <ProductCategory>[];
        if (body is Map && body['data'] is List) {
          for (final item in body['data'] as List) {
            if (item is Map<String, dynamic>) {
              items.add(ProductCategory.fromJson(item));
            }
          }
        } else if (body is List) {
          for (final item in body) {
            if (item is Map<String, dynamic>) {
              items.add(ProductCategory.fromJson(item));
            }
          }
        }
        if (mounted) {
          setState(() {
            _subcategories = items;
            _subcategoriesLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _subcategoriesError = 'Failed to load sub-categories';
            _subcategoriesLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _subcategoriesError = 'Network error: $e';
          _subcategoriesLoading = false;
        });
      }
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
    try {
      final token = await SecureStorageService.getToken();
      final headers = {
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
      final uri = AppConfig.u(
        AppConfig.fill(AppConfig.apiChildCategories, {
          'id': categoryId,
          'subid': subCategoryId,
        }),
      );
      final resp = await http
          .get(uri, headers: headers)
          .timeout(AppConfig.httpTimeout);
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        final items = <ProductCategory>[];
        if (body is Map && body['data'] is List) {
          for (final item in body['data'] as List) {
            if (item is Map<String, dynamic>) {
              items.add(ProductCategory.fromJson(item));
            }
          }
        } else if (body is List) {
          for (final item in body) {
            if (item is Map<String, dynamic>) {
              items.add(ProductCategory.fromJson(item));
            }
          }
        }
        if (mounted) {
          setState(() {
            _childCategories = items;
            _childCategoriesLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _childCategoriesError = 'Failed to load product types';
            _childCategoriesLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _childCategoriesError = 'Network error: $e';
          _childCategoriesLoading = false;
        });
      }
    }
  }

  Future<void> _onCategorySelected(String? categoryId) async {
    if (!mounted) return;
    setState(() {
      _selectedCategoryId = categoryId;
      _selectedSubCategoryId = null;
      _selectedChildCategoryId = null;
      _subcategories = [];
      _childCategories = [];
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
    });
    if (subCategoryId != null &&
        subCategoryId.isNotEmpty &&
        _selectedCategoryId != null &&
        _selectedCategoryId!.isNotEmpty) {
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

  void _clearAllFilters() {
    if (!mounted) return;
    setState(() {
      _selectedCategoryId = null;
      _selectedSubCategoryId = null;
      _selectedChildCategoryId = null;
      _subcategories = [];
      _childCategories = [];
    });
    _fetchProducts();
  }

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
          onCategorySelect: (id) async {
            await _onCategorySelected(id);
          },
          onSubCategorySelect: (id) async {
            await _onSubCategorySelected(id);
          },
          onChildCategorySelect: (id) async {
            await _onChildCategorySelected(id);
          },
          onClearAll: () {
            _clearAllFilters();
            Navigator.of(ctx).pop();
          },
          onApply: () => Navigator.of(ctx).pop(),
          onRetryCategories: _fetchCategories,
          onRetrySubcategories: () {
            if (_selectedCategoryId != null &&
                _selectedCategoryId!.isNotEmpty) {
              _fetchSubcategories(_selectedCategoryId!);
            }
          },
          onRetryChildCategories: () {
            if (_selectedCategoryId != null &&
                _selectedCategoryId!.isNotEmpty &&
                _selectedSubCategoryId != null &&
                _selectedSubCategoryId!.isNotEmpty) {
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
}

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
                  : Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Center(
              child: Icon(Icons.tune_rounded, color: _kGreen, size: 22),
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
          const Icon(Icons.filter_list_rounded, size: 15, color: _kGreen),
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
        color: _kGreenLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kGreen.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: _kGreen),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFF0D9A84),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

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
    var count = 0;
    if (_catId != null) count++;
    if (_subId != null) count++;
    if (_childId != null) count++;
    return count;
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
                              ? _kGreen
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
                                  ? _kGreen
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
                                    ? _kGreen
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
                  color: _kGreenLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: _kGreen, size: 15),
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
                    color: _kGreen,
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
                    foregroundColor: _kGreen,
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
                    color: Colors.black.withOpacity(0.04),
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
