// FILE: lib/screens/dealer_purposes_screen.dart
//
// DealerPurposesScreen — Expandable inline purpose cards.
// Tap + on any card to expand the full form in-place.
// Tap - to collapse. Only one card open at a time.
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

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'package:FieldService_app/services/notification_api.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';
import 'package:FieldService_app/utils/mediaoptimizer.dart';
import 'package:FieldService_app/widgets/shared_bottom_nav.dart';

// ─── Shared constants ─────────────────────────────────────────────────────────

const Color _kGreen = Color(0xFF1AB69C);
const Color _kGreenLight = Color.fromARGB(255, 144, 252, 234);
const Color _surfaceColor = Color(0xFFF6F8FA);

// ─── Purpose type enum ────────────────────────────────────────────────────────

enum DealerPurposeType { payment, order, ticket, lead }

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
//  DealerPurposesScreen
// ═══════════════════════════════════════════════════════════════════════════════

class DealerPurposesScreen extends StatefulWidget {
  final String dealerId;
  final String dealerName;
  final String shopName;
  final String address;
  final String mobile;
  final double latitude;
  final double longitude;
  final double pendingAmount;
  final bool allowOtherPurpose;
  final bool tripCompleted;

  const DealerPurposesScreen({
    super.key,
    required this.dealerId,
    required this.dealerName,
    required this.shopName,
    required this.address,
    required this.mobile,
    required this.latitude,
    required this.longitude,
    required this.pendingAmount,
    required this.allowOtherPurpose,
    required this.tripCompleted,
  });

  @override
  State<DealerPurposesScreen> createState() => _DealerPurposesScreenState();
}

class _DealerPurposesScreenState extends State<DealerPurposesScreen> {
  DealerPurposeType? _expandedPurpose;

  // ── Purpose started flags ─────────────────────────────────────
  bool _paymentStarted = false;
  bool _orderStarted = false;
  bool _ticketStarted = false;
  //bool _leadStarted = false;

  // ── Purpose validity flags (reported by child cards) ──────────
  bool _paymentValid = false;
  bool _orderValid = false;
  bool _ticketValid = false;
  bool _leadValid = false;

  // ── Submit state ──────────────────────────────────────────────
  bool _isSubmitting = false;

  // ── Keys to access child card submit methods ───────────────────
  final GlobalKey<_PaymentPurposeCardState> _paymentKey =
      GlobalKey<_PaymentPurposeCardState>();
  final GlobalKey<_OrderPurposeCardState> _orderKey =
      GlobalKey<_OrderPurposeCardState>();
  final GlobalKey<_TicketPurposeCardState> _ticketKey =
      GlobalKey<_TicketPurposeCardState>();
  final GlobalKey<_OtherPurposeMandatorySectionState> _leadKey =
      GlobalKey<_OtherPurposeMandatorySectionState>();

  // ── Toggle / collapse ─────────────────────────────────────────
  void _toggle(DealerPurposeType type) {
    setState(() {
      _expandedPurpose = _expandedPurpose == type ? null : type;
      if (_expandedPurpose == type) {
        if (type == DealerPurposeType.payment) _paymentStarted = true;
        if (type == DealerPurposeType.order) _orderStarted = true;
        if (type == DealerPurposeType.ticket) _ticketStarted = true;
      }
    });
  }

  void _collapseAll() {
    if (mounted) setState(() => _expandedPurpose = null);
  }

  // ── Validity callbacks from child cards ───────────────────────
  void _updatePaymentValidity(bool v) {
    if (mounted) setState(() => _paymentValid = v);
  }

  void _updateOrderValidity(bool v) {
    if (mounted) setState(() => _orderValid = v);
  }

  void _updateTicketValidity(bool v) {
    if (mounted) setState(() => _ticketValid = v);
  }

  void _updateLeadValidity(bool v) {
    if (mounted) {
      setState(() {
        _leadValid = v;
      });
    }
  }

  // ── Submit gate ───────────────────────────────────────────────
  /// True when at least one started purpose is fully valid.
  /// Submit is enabled when Other Purpose (mandatory) is valid.
  /// Optional cards are submitted only if started + valid.
  bool get _canSubmitAll => !_isSubmitting && _leadValid;

  /// Always true — Other Purpose section is always visible.
  bool get _atLeastOneStarted => true;

  String get _subtitle => [
    if (widget.shopName.trim().isNotEmpty) widget.shopName.trim(),
    if (widget.mobile.trim().isNotEmpty) widget.mobile.trim(),
  ].join(' • ');

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
                // ── Dealer header card ─────────────────────────────────────
                _DealerHeaderCard(
                  dealerName: widget.dealerName,
                  subtitle: _subtitle,
                  address: widget.address,
                  latitude: widget.latitude,
                  longitude: widget.longitude,
                  pendingAmount: widget.pendingAmount,
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
                    paymentOk: _paymentStarted && _paymentValid,
                    orderOk: _orderStarted && _orderValid,
                    ticketOk: _ticketStarted && _ticketValid,
                    leadOk: _leadValid,
                    allowLead: true,
                  ),
                ),

                // ── Payment ────────────────────────────────────────────────
                _PaymentPurposeCard(
                  key: _paymentKey,
                  isExpanded: _expandedPurpose == DealerPurposeType.payment,
                  onToggle: () => _toggle(DealerPurposeType.payment),
                  onSuccess: _collapseAll,
                  dealerId: widget.dealerId,
                  dealerName: widget.dealerName,
                  shopName: widget.shopName,
                  mobile: widget.mobile,
                  pendingAmount: widget.pendingAmount,
                  isStarted: _paymentStarted,
                  isValid: _paymentValid,
                  onValidityChanged: _updatePaymentValidity,
                ),

                const SizedBox(height: 12),

                // ── Order ──────────────────────────────────────────────────
                _OrderPurposeCard(
                  key: _orderKey,
                  isExpanded: _expandedPurpose == DealerPurposeType.order,
                  onToggle: () => _toggle(DealerPurposeType.order),
                  onValidityChanged: _updateOrderValidity,
                  dealerId: widget.dealerId,
                  dealerType: 'Dealer',
                  isStarted: _orderStarted,
                  isValid: _orderValid,
                ),

                const SizedBox(height: 12),

                // ── Ticket / Query ─────────────────────────────────────────
                _TicketPurposeCard(
                  key: _ticketKey,
                  isExpanded: _expandedPurpose == DealerPurposeType.ticket,
                  onToggle: () => _toggle(DealerPurposeType.ticket),
                  onSuccess: _collapseAll,
                  dealerId: widget.dealerId,
                  dealerName: widget.dealerName,
                  shopName: widget.shopName,
                  address: widget.address,
                  mobile: widget.mobile,
                  latitude: widget.latitude,
                  longitude: widget.longitude,
                  pendingAmount: widget.pendingAmount,
                  tripCompleted: widget.tripCompleted,
                  isStarted: _ticketStarted,
                  isValid: _ticketValid,
                  onValidityChanged: _updateTicketValidity,
                ),

                // ── Lead / Other (conditional) ─────────────────────────────
                // ── Other Purpose — MANDATORY, always shown outside cards ──
                const SizedBox(height: 20),
                _OtherPurposeMandatorySection(
                  key: _leadKey,
                  dealerId: widget.dealerId,
                  dealerName: widget.dealerName,
                  shopName: widget.shopName,
                  address: widget.address,
                  mobile: widget.mobile,
                  latitude: widget.latitude,
                  longitude: widget.longitude,
                  pendingAmount: widget.pendingAmount,
                  onValidityChanged: _updateLeadValidity,
                  onSuccess: _collapseAll,
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
                  _paymentStarted && _paymentValid,
                  _orderStarted && _orderValid,
                  _ticketStarted && _ticketValid,
                ].where((v) => v).length,
                onSubmit: () => _submitAllPurposes(context),
              ),
            ),
        ],
      ),
    );
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
      // ── 1. Payment (only if started + valid) ──────────────────
      if (_paymentStarted && _paymentValid) {
        final result = await _paymentKey.currentState?._saveAndReturn();

        if (result?.success == true) {
          successes.add('Payment reminder');
        } else {
          errors.add(result?.message ?? 'Payment reminder failed');
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

      // ── 3. Ticket / Query (only if started + valid) ───────────
      if (_ticketStarted && _ticketValid) {
        final ok = await _ticketKey.currentState?._submitAndReturn();
        if (ok == true) {
          successes.add('Query ticket');
        } else {
          errors.add('Query submission failed');
        }
      }

      if (errors.isNotEmpty) {
        _showResultSnack(errors.first, isError: true);
        return;
      }

      // ── 4. Other Purpose (mandatory — always submitted) ────────
      {
        final ok = await _leadKey.currentState?._submitAndReturn();
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
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Ready count label ────────────────────────────────────
          if (readyCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: _kGreen,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$readyCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    readyCount == 1
                        ? '1 purpose ready to submit'
                        : '$readyCount purposes ready to submit',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          // ── Submit button ────────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 52,
            child: ElevatedButton(
              onPressed: canSubmit ? onSubmit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGreen,
                disabledBackgroundColor: Colors.grey[300],
                elevation: canSubmit ? 2 : 0,
                shadowColor: _kGreen.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: isSubmitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          canSubmit
                              ? Icons.check_circle_outline_rounded
                              : Icons.lock_outline_rounded,
                          color: canSubmit ? Colors.white : Colors.grey[500],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Submit All Purposes',
                          style: TextStyle(
                            color: canSubmit ? Colors.white : Colors.grey[500],
                            fontWeight: FontWeight.w700,
                            fontSize: 15.5,
                            letterSpacing: 0.2,
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

// ═══════════════════════════════════════════════════════════════════════════════
//  _HintStrip — shows which purposes are ready / incomplete
// ═══════════════════════════════════════════════════════════════════════════════

class _HintStrip extends StatelessWidget {
  final bool paymentOk;
  final bool orderOk;
  final bool ticketOk;
  final bool leadOk;
  final bool allowLead;

  const _HintStrip({
    required this.paymentOk,
    required this.orderOk,
    required this.ticketOk,
    required this.leadOk,
    required this.allowLead,
  });

  @override
  Widget build(BuildContext context) {
    final items = <_HintItem>[
      _HintItem(label: 'Payment', ready: paymentOk),
      _HintItem(label: 'Order', ready: orderOk),
      _HintItem(label: 'Query', ready: ticketOk),
      if (allowLead) _HintItem(label: 'Lead', ready: leadOk),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kGreen.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: _kGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 10,
              runSpacing: 4,
              children: items
                  .map(
                    (it) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          it.ready
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 13,
                          color: it.ready ? _kGreen : Colors.grey[400],
                        ),
                        const SizedBox(width: 3),
                        Text(
                          it.label,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: it.ready ? Colors.black87 : Colors.grey[500],
                            fontWeight: it.ready
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
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
    this.isStarted = false,
    this.isValid = false,
  });

  @override
  Widget build(BuildContext context) {
    // Border / shadow colour drives from expanded OR completed state
    final isHighlighted = isExpanded || (isStarted && isValid);
    final borderColor = isStarted && isValid
        ? _kGreen
        : isExpanded
        ? _kGreen.withValues(alpha: 0.8)
        : Colors.grey.withValues(alpha: 0.22);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: isHighlighted ? 1.6 : 1),
        boxShadow: [
          BoxShadow(
            color: isHighlighted
                ? _kGreen.withValues(alpha: 0.14)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: isHighlighted ? 10 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Card header / toggle row ──────────────────────────────
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      // Purpose icon
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: (isExpanded || (isStarted && isValid))
                              ? _kGreenLight
                              : Colors.grey.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          icon,
                          color: (isExpanded || (isStarted && isValid))
                              ? _kGreen
                              : Colors.grey[600],
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Title + subtitle
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
                                color: isExpanded || (isStarted && isValid)
                                    ? Colors.black87
                                    : Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: isExpanded || (isStarted && isValid)
                                    ? Colors.black45
                                    : Colors.black38,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // ── Status badge ──────────────────────────────
                      _CardStatusBadge(isStarted: isStarted, isValid: isValid),
                      const SizedBox(width: 8),

                      // ── +/- toggle button ─────────────────────────
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: isExpanded
                              ? _kGreen
                              : Colors.grey.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          isExpanded ? Icons.remove : Icons.add,
                          color: isExpanded ? Colors.white : Colors.grey[600],
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Expandable form content ───────────────────────────────
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: isExpanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Divider(height: 1, thickness: 1),
                        expandedContent,
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
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
    if (!isStarted) return const SizedBox.shrink();

    if (isValid) {
      // Green check — purpose is complete
      return Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(color: _kGreen, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 13),
      );
    } else {
      // Amber dot — started but incomplete
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFFFB74D), width: 1.5),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.edit_outlined,
          color: Color(0xFFFFB74D),
          size: 12,
        ),
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _PaymentPurposeCard
// ═══════════════════════════════════════════════════════════════════════════════

class _PaymentPurposeCard extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onSuccess;
  final String dealerId;
  final String dealerName;
  final String shopName;
  final String mobile;
  final double pendingAmount;
  final bool isStarted;
  final bool isValid;
  final ValueChanged<bool> onValidityChanged;

  const _PaymentPurposeCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    required this.onSuccess,
    required this.dealerId,
    required this.dealerName,
    required this.shopName,
    required this.mobile,
    required this.pendingAmount,
    required this.isStarted,
    required this.isValid,
    required this.onValidityChanged,
  });

  @override
  State<_PaymentPurposeCard> createState() => _PaymentPurposeCardState();
}

class _PaymentPurposeCardState extends State<_PaymentPurposeCard> {
  DateTime? _commitDate;
  TimeOfDay? _commitTime;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_updateValidity);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _commitDate != null &&
      _commitTime != null &&
      _amountCtrl.text.trim().isNotEmpty &&
      double.tryParse(_amountCtrl.text.trim()) != null;

  void _updateValidity() => widget.onValidityChanged(_isValid);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _commitDate ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365 * 3)),
      builder: (ctx, child) => Theme(
        data: Theme.of(
          ctx,
        ).copyWith(colorScheme: const ColorScheme.light(primary: _kGreen)),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _commitDate = picked);
      _updateValidity();
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _commitTime ?? TimeOfDay.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(
          ctx,
        ).copyWith(colorScheme: const ColorScheme.light(primary: _kGreen)),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _commitTime = picked);
      _updateValidity();
    }
  }

  // ── Called by unified submit button ──────────────────────────────────────
  Future<ScheduleResult> _saveAndReturn() async {
    if (_commitDate == null || _commitTime == null) {
      return ScheduleResult(
        success: false,
        message: 'Date & time required',
        id: '',
      );
    }
    if (_amountCtrl.text.trim().isEmpty) {
      return ScheduleResult(success: false, message: 'Invalid amount', id: '');
    }
    if (_noteCtrl.text.trim().isEmpty) {
      return ScheduleResult(
        success: false,
        message: 'Notes are required',
        id: '',
      );
    }

    final localDt = DateTime(
      _commitDate!.year,
      _commitDate!.month,
      _commitDate!.day,
      _commitTime!.hour,
      _commitTime!.minute,
    );

    if (!localDt.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return ScheduleResult(
        success: false,
        message: 'Please select a future time',
        id: '',
      );
    }

    try {
      final token = await FirebaseMessaging.instance.getToken();

      if (token == null || token.isEmpty) {
        return ScheduleResult(
          success: false,
          message: 'FCM token not available',
          id: '',
        );
      }

      final prefs = await SharedPreferences.getInstance();
      final tripId = prefs.getString('currentTripId') ?? '';
      final tripCompleted = prefs.getBool('tripCompleted') ?? false;
      final effectiveTripId = tripCompleted ? tripId : '';

      final res = await NotificationsApi.schedule(
        title: widget.dealerName,
        dealerId: widget.dealerId,
        dealerName: widget.dealerName,
        shopName: widget.shopName,
        amount: num.tryParse(_amountCtrl.text.trim()) ?? 0,
        mobile: widget.mobile,
        body: _noteCtrl.text.trim(),
        fcmToken: token,
        sendAtUtc: localDt.toUtc().toIso8601String(),
        tripId: effectiveTripId,
      );

      return res;
    } catch (e) {
      return ScheduleResult(success: false, message: 'Exception: $e', id: '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PurposeCardShell(
      isExpanded: widget.isExpanded,
      onToggle: widget.onToggle,
      icon: Icons.payment_rounded,
      title: 'Payment Purpose',
      subtitle: 'Create a payment commitment.',
      isStarted: widget.isStarted,
      isValid: widget.isValid,
      expandedContent: _buildForm(),
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
            // ── Amount ────────────────────────────────────────────
            TextFormField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: _inputDec('Amount (₹)', Icons.currency_rupee_rounded),
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.isEmpty) return 'Amount is required';
                if (double.tryParse(s) == null) return 'Enter a valid number';
                return null;
              },
            ),
            const SizedBox(height: 14),

            // ── Date + Time ───────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _DateTimeButton(
                    icon: Icons.calendar_today_rounded,
                    label: _commitDate == null
                        ? 'Pick Date'
                        : '${_commitDate!.day}/${_commitDate!.month}/${_commitDate!.year}',
                    hasValue: _commitDate != null,
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DateTimeButton(
                    icon: Icons.access_time_rounded,
                    label: _commitTime == null
                        ? 'Pick Time'
                        : _commitTime!.format(context),
                    hasValue: _commitTime != null,
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Notes ─────────────────────────────────────────────
            TextFormField(
              controller: _noteCtrl,
              maxLines: 3,
              decoration: _inputDec('Notes (required)', Icons.notes_rounded),
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.isEmpty) return 'Notes are required';
                return null;
              },
            ),

            // ── Validity hint ─────────────────────────────────────
            if (widget.isStarted && !widget.isValid)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: _IncompleteHint(message: 'Fill amount, date & time'),
              ),

            if (widget.isStarted && widget.isValid)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: _CompleteHint(message: 'Ready ✓'),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _OrderPurposeCard — API-driven cart
// ═══════════════════════════════════════════════════════════════════════════════

class _OrderPurposeCard extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final ValueChanged<bool> onValidityChanged;
  final String dealerId;
  final String dealerType;
  final bool isStarted;
  final bool isValid;

  const _OrderPurposeCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    required this.onValidityChanged,
    required this.dealerId,
    required this.dealerType,
    required this.isStarted,
    required this.isValid,
  });

  @override
  State<_OrderPurposeCard> createState() => _OrderPurposeCardState();
}

class _OrderPurposeCardState extends State<_OrderPurposeCard> {
  Map<String, dynamic>? _serverCart;
  bool _isLoadingCart = false;
  String? _cartError;
  String? _employeeId;
  String? _tripId;
  bool _tripCompleted = false;
  final Set<String> _pendingProductOps = {};
  final TextEditingController _remarksCtrl = TextEditingController();

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

  Future<void> _loadSessionAndFetchCart() async {
    final prefs = await SharedPreferences.getInstance();
    final employeeId = prefs.getString('userId') ?? '';
    final currentTripId = prefs.getString('currentTripId') ?? '';
    final tripCompleted = prefs.getBool('tripCompleted') ?? false;
    final effectiveTripId = tripCompleted ? currentTripId : '';

    if (mounted) {
      setState(() {
        _employeeId = employeeId;
        _tripId = effectiveTripId;
        _tripCompleted = tripCompleted;
      });
    }
    await _fetchCart(employeeId: employeeId);
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

  Future<void> _fetchCart({String? employeeId}) async {
    if (!mounted) return;
    setState(() {
      _isLoadingCart = true;
      _cartError = null;
    });

    try {
      final id = (employeeId ?? _employeeId ?? '').trim();
      if (id.isEmpty) {
        if (mounted) setState(() => _cartError = 'Missing employee id.');
        return;
      }

      final headers = await _buildHeaders();
      final uri = AppConfig.u(
        AppConfig.fill(AppConfig.getCart, {'employeeid': id}),
      );
      final resp = await http
          .get(uri, headers: headers)
          .timeout(AppConfig.httpTimeout);

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

  List<Map<String, dynamic>> _itemsFromServer() {
    final items = <Map<String, dynamic>>[];
    try {
      final rawItems = _serverCart?['items'] as List<dynamic>?;
      if (rawItems != null) {
        for (final it in rawItems) {
          if (it is Map<String, dynamic>) {
            items.add(it);
          } else if (it is Map)
            items.add(Map<String, dynamic>.from(it));
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
      final p = it['price'];
      final qn = q is num ? q.toDouble() : double.tryParse(q.toString()) ?? 0;
      final pn = p is num ? p.toDouble() : double.tryParse(p.toString()) ?? 0;
      tot += qn * pn;
    }
    return tot;
  }

  bool get _isValid => _itemsFromServer().isNotEmpty;
  void _updateValidity() {
    if (mounted) widget.onValidityChanged(_isValid);
  }

  Future<void> _addToCart(Product product) async {
    final productId = product.id ?? '';
    if (productId.isEmpty) {
      _snack('Invalid product — missing id.');
      return;
    }
    setState(() => _pendingProductOps.add(productId));

    try {
      final headers = await _buildHeaders(json: true);
      final body = <String, dynamic>{
        'customerId': {'id': widget.dealerId, 'type': widget.dealerType},
        'productId': productId,
        'quantity': 1,
        'price': product.productPrice ?? 0,
        if (_employeeId != null && _employeeId!.isNotEmpty)
          'employeeId': _employeeId,
        if (_tripId != null && _tripId!.isNotEmpty) 'tripId': _tripId,
      };

      final resp = await http
          .post(
            AppConfig.u(AppConfig.addToCart),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(AppConfig.httpTimeout);

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final parsed = jsonDecode(resp.body);
        final cart = _cartFromResponse(parsed);
        if (mounted && cart != null) setState(() => _serverCart = cart);
        await _fetchCart();
        _snack(parsed['message']?.toString() ?? 'Product added');
      } else {
        final parsed = jsonDecode(resp.body);
        _snack(
          parsed['message']?.toString() ?? 'Failed to add (${resp.statusCode})',
        );
      }
    } catch (e) {
      _snack('Network error: $e');
    } finally {
      if (mounted) setState(() => _pendingProductOps.remove(productId));
    }
  }

  Future<void> _updateCartQuantity(String productId, String action) async {
    if (action != 'increase' && action != 'decrease') return;
    setState(() => _pendingProductOps.add(productId));
    try {
      final headers = await _buildHeaders(json: true);
      final body = <String, dynamic>{
        'customerId': widget.dealerId,
        'type': widget.dealerType,
        'employeeId': _employeeId ?? '',
        if (_tripId != null && _tripId!.isNotEmpty) 'tripId': _tripId,
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

  Future<void> _updateCartQuantityBulk(String productId, int newQty) async {
    if (newQty < 1) return;
    setState(() => _pendingProductOps.add(productId));
    try {
      final headers = await _buildHeaders(json: true);
      final body = <String, dynamic>{
        'customerId': widget.dealerId,
        'type': widget.dealerType,
        'employeeId': _employeeId ?? '',
        if (_tripId != null && _tripId!.isNotEmpty) 'tripId': _tripId,
        'productId': productId,
        'action': 'setQuantity',
        'quantity': newQty,
      };
      final resp = await http
          .put(
            AppConfig.u(AppConfig.updateCart),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(AppConfig.httpTimeout);
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
        if (mounted && cart != null) setState(() => _serverCart = cart);
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

  // ── Called by unified submit ───────────────────────────────────────────────
  Future<bool> _submitAndReturn() async {
    final items = _itemsFromServer();
    if (items.isEmpty) return false;
    try {
      final headers = await _buildHeaders(json: true);
      final body = <String, dynamic>{
        'customerId': {'id': widget.dealerId, 'type': widget.dealerType},
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
      final resp = await http
          .post(
            AppConfig.u(AppConfig.createOrder),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(AppConfig.httpTimeout);
      return resp.statusCode == 200 || resp.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

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
        builder: (_, sc) => ProductsBottomSheet(
          onProductSelected: (item) => _addToCart(item.product),
          cache: _cache,
          imageBox: _imageBox,
          scrollController: sc,
        ),
      ),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final items = _itemsFromServer();
    return _PurposeCardShell(
      isExpanded: widget.isExpanded,
      onToggle: widget.onToggle,
      icon: Icons.shopping_cart_rounded,
      title: 'Order Purpose',
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
          // ── Add Products ─────────────────────────────────────────
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

          // ── Cart state ───────────────────────────────────────────
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
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, idx) => _buildCartTile(items[idx]),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Total ─────────────────────────────────────────
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

                // ── Remarks ───────────────────────────────────────
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

                // ── Validity hint ─────────────────────────────────
                if (widget.isStarted && widget.isValid)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: _CompleteHint(
                      message:
                          'Ready ✓  — will be submitted with the button below.',
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCartTile(Map<String, dynamic> it) {
    final productId = _productIdOf(it);
    final busy = productId != null && _pendingProductOps.contains(productId);

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
      if (rawImage.startsWith('http')) return rawImage as String;
      return AppConfig.imageUrl(rawImage as String);
    }();

    final qty = it['quantity'];
    final rawPrice = it['price'];
    final priceNum = rawPrice is num
        ? rawPrice.toDouble()
        : double.tryParse(rawPrice.toString()) ?? 0.0;
    final qtyNum = qty is num ? qty.toInt() : int.tryParse(qty.toString()) ?? 0;
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
                Row(
                  children: [
                    // minus
                    GestureDetector(
                      onTap: busy || productId == null || qtyNum <= 1
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

                    // qty badge
                    GestureDetector(
                      onTap: busy || productId == null
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
                      onTap: busy || productId == null
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
                      onTap: busy || productId == null
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
//  _TicketPurposeCard
// ═══════════════════════════════════════════════════════════════════════════════

class _TicketPurposeCard extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onSuccess;
  final String dealerId;
  final String dealerName;
  final String shopName;
  final String address;
  final String mobile;
  final double latitude;
  final double longitude;
  final double pendingAmount;
  final bool tripCompleted;
  final bool isStarted;
  final bool isValid;
  final ValueChanged<bool> onValidityChanged;

  const _TicketPurposeCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    required this.onSuccess,
    required this.dealerId,
    required this.dealerName,
    required this.shopName,
    required this.address,
    required this.mobile,
    required this.latitude,
    required this.longitude,
    required this.pendingAmount,
    required this.tripCompleted,
    required this.isStarted,
    required this.isValid,
    required this.onValidityChanged,
  });

  @override
  State<_TicketPurposeCard> createState() => _TicketPurposeCardState();
}

class _TicketPurposeCardState extends State<_TicketPurposeCard> {
  final _remarksCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _inlineBanner;

  @override
  void initState() {
    super.initState();
    _remarksCtrl.addListener(() {
      widget.onValidityChanged(_canSubmit);
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _remarksCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit => _remarksCtrl.text.trim().isNotEmpty;

  // ── Called by unified submit button ──────────────────────────────────────
  Future<bool> _submitAndReturn() async {
    if (_remarksCtrl.text.trim().isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final companyId = prefs.getString('companyId') ?? '';
      final employeeId = prefs.getString('userId') ?? '';
      final tripId = prefs.getString('currentTripId') ?? '';
      final tripCompleted = prefs.getBool('tripCompleted') ?? false;
      final effectiveTripId = tripCompleted ? tripId : '';
      final token = await SecureStorageService.getToken();

      final body = {
        'companyId': companyId,
        'dealerId': widget.dealerId,
        'employeeId': employeeId,
        if (effectiveTripId.isNotEmpty) 'tripId': effectiveTripId,
        'dealerName': widget.dealerName.isNotEmpty
            ? widget.dealerName
            : widget.shopName,
        'mobileNumber': widget.mobile,
        'dealerLocation': widget.address,
        'remarks': _remarksCtrl.text.trim(),
      };

      final resp = await apiClient.sendOrQueue(
        method: HttpVerb.post,
        path: AppConfig.dealerTickets,
        jsonBody: body,
        headers: {'Authorization': 'Bearer $token'},
        optimisticOk: true,
      );

      if (resp == null) return true; // queued offline
      return resp.statusCode == 200 || resp.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  void _clearError() {
    if (mounted) setState(() => _inlineBanner = null);
  }

  @override
  Widget build(BuildContext context) {
    return _PurposeCardShell(
      isExpanded: widget.isExpanded,
      onToggle: widget.onToggle,
      icon: Icons.support_agent_rounded,
      title: 'Raise a Query',
      subtitle: 'Submit a dealer query / ticket.',
      isStarted: widget.isStarted,
      isValid: widget.isValid,
      expandedContent: _buildForm(),
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
            if ((_inlineBanner ?? '').isNotEmpty) ...[
              _InlineBanner(message: _inlineBanner!, onClose: _clearError),
              const SizedBox(height: 10),
            ],

            TextFormField(
              controller: _remarksCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: _inputDec(
                'Remarks (required)',
                Icons.edit_note_rounded,
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Remarks are required' : null,
            ),

            // ── Validity hint ─────────────────────────────────────
            if (widget.isStarted && !widget.isValid)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: _IncompleteHint(message: 'Enter your remarks'),
              ),

            if (widget.isStarted && widget.isValid)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: _CompleteHint(message: 'Ready ✓'),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _LeadPurposeCard
// ═══════════════════════════════════════════════════════════════════════════════

class _LeadPurposeCard extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onSuccess;
  final String dealerId;
  final String dealerName;
  final String shopName;
  final String address;
  final String mobile;
  final double latitude;
  final double longitude;
  final double pendingAmount;
  final bool isStarted;
  final bool isValid;
  final ValueChanged<bool> onValidityChanged;

  const _LeadPurposeCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    required this.onSuccess,
    required this.dealerId,
    required this.dealerName,
    required this.shopName,
    required this.address,
    required this.mobile,
    required this.latitude,
    required this.longitude,
    required this.pendingAmount,
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

  double? _capturedLat;
  double? _capturedLng;
  String? _capturedAddress;

  final _descriptionCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _inlineBanner;

  @override
  void initState() {
    super.initState();
    _descriptionCtrl.addListener(() {
      widget.onValidityChanged(_canSubmit);
    });
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    super.dispose();
  }

  void _safeSet(void Function() fn) {
    if (mounted) setState(fn);
  }

  bool get _canSubmit =>
      _imageFile != null &&
      _descriptionCtrl.text.trim().isNotEmpty &&
      !_uploadingImage &&
      _capturedLat != null &&
      _capturedLng != null;

  // ── Called by unified submit button ──────────────────────────────────────
  Future<bool> _submitAndReturn() async {
    if (_imageFile == null) return false;
    if (_descriptionCtrl.text.trim().isEmpty) return false;
    if (_capturedLat == null || _capturedLng == null) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getString('userId') ?? '';
      final tripId = prefs.getString('currentTripId') ?? '';
      final tripCompleted = prefs.getBool('tripCompleted') ?? false;
      final effectiveTripId = tripCompleted ? tripId : '';
      if (employeeId.isEmpty) return false;

      final address = _capturedAddress ?? 'Unknown Address';
      final body = {
        'employeeId': employeeId,
        if (effectiveTripId.isNotEmpty) 'tripId': effectiveTripId,
        'idOfVisitor[id]': widget.dealerId,
        'idOfVisitor[type]': 'Dealer',
        'purpose': 'Lead',
        'reason': _descriptionCtrl.text.trim(),
        'address': address,
      };

      final ext = _imageFile!.path.split('.').last.toLowerCase();
      final mime = (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/png';

      final imageFile = QueuedFile(
        field: 'images',
        path: _imageFile!.path,
        filename: 'lead_${DateTime.now().millisecondsSinceEpoch}.$ext',
        contentType: mime,
      );

      final resp = await apiClient.sendOrQueue(
        method: HttpVerb.post,
        path: AppConfig.othervisits,
        jsonBody: body,
        files: [imageFile],
        optimisticOk: true,
      );

      if (resp == null) return true; // queued offline
      return resp.statusCode == 200 || resp.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // ── Camera & Location ─────────────────────────────────────────────────────

  Future<File> _fixExifRotation(File file) async {
    final bytes = await file.readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) return file;
    final fixed = img.bakeOrientation(original);
    final newPath =
        '${file.parent.path}/fixed_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return File(newPath)..writeAsBytesSync(img.encodeJpg(fixed, quality: 100));
  }

  Future<void> _pickImageFromCamera() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.camera);
      if (picked == null) return;

      _safeSet(() => _uploadingImage = true);

      await _fetchLocation();
      if (_capturedLat == null || _capturedLng == null) {
        _setError('Unable to capture location. Please try again.');
        _safeSet(() => _uploadingImage = false);
        return;
      }

      final timestamp = DateFormat(
        'yyyy-MM-dd HH:mm:ss',
      ).format(DateTime.now());
      final address = _capturedAddress ?? 'Unknown Address';
      final original = File(picked.path);
      final fixedFile = await _fixExifRotation(original);
      final stamped = await _stampImage(
        fixedFile,
        _capturedLat!,
        _capturedLng!,
        timestamp,
        address,
      );
      final optimized =
          await MediaOptimizer.getOptimizedImage(stamped) ?? stamped;

      if (!mounted) return;
      _safeSet(() {
        _imageFile = optimized;
        _uploadingImage = false;
      });
      widget.onValidityChanged(_canSubmit);
    } catch (e) {
      _setError('Camera error: $e');
      _safeSet(() => _uploadingImage = false);
    }
  }

  void _removeImage() {
    _safeSet(() {
      _imageFile = null;
      _capturedLat = null;
      _capturedLng = null;
      _capturedAddress = null;
    });
    widget.onValidityChanged(_canSubmit);
  }

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
          'Address: $address\nLat: ${lat.toStringAsFixed(6)}\n'
          'Lng: ${lng.toStringAsFixed(6)}\nTime: $time';
      final fontSize = (width.toDouble() / 15.0).clamp(22.0, 60.0).toDouble();

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
          '${imageFile.parent.path}/lead_stamp_${DateTime.now().millisecondsSinceEpoch}.png';
      return File(stampedPath)
        ..writeAsBytesSync(byteData!.buffer.asUint8List());
    } catch (e) {
      debugPrint('STAMP ERROR: $e');
      return imageFile;
    }
  }

  Future<void> _fetchLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _setError('Location permission denied.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _setError('Location permission permanently denied.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _safeSet(() {
        _capturedLat = pos.latitude;
        _capturedLng = pos.longitude;
      });

      String? addr;
      try {
        final key = AppConfig.googleMapsApiKey;
        final url =
            'https://maps.googleapis.com/maps/api/geocode/json'
            '?latlng=${pos.latitude},${pos.longitude}&key=$key';
        final resp = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          if (data['status'] == 'OK' && (data['results'] as List).isNotEmpty) {
            addr = data['results'][0]['formatted_address'];
          } else {
            throw Exception('no results');
          }
        } else {
          throw Exception('${resp.statusCode}');
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
            ].where((e) => e != null && e.trim().isNotEmpty).join(', ');
          } else {
            throw Exception('empty');
          }
        } catch (_) {
          addr = 'Offline — address unavailable';
        }
      }
      _safeSet(
        () => _capturedAddress = addr ?? 'Offline — address unavailable',
      );
    } catch (e) {
      _setError('Failed to get location: $e');
    }
  }

  void _setError(String msg) => _safeSet(() => _inlineBanner = msg);
  void _clearError() => _safeSet(() => _inlineBanner = null);

  // REPLACE the entire build() in _LeadPurposeCardState:
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
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
                Icons.lightbulb_rounded,
                color: _kGreen,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Other Purpose',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  Text(
                    'Required — capture photo & describe visit',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE8E8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                'Required',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.red.shade600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _canSubmit ? _kGreen : Colors.red.shade200,
              width: 1.6,
            ),
            boxShadow: [
              BoxShadow(
                color: _canSubmit
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
            if ((_inlineBanner ?? '').isNotEmpty) ...[
              _InlineBanner(message: _inlineBanner!, onClose: _clearError),
              const SizedBox(height: 10),
            ],

            // ── Camera + location card ────────────────────────────
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _kGreen.withValues(alpha: 0.6),
                  width: 1.3,
                ),
              ),
              clipBehavior: Clip.hardEdge,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
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
                                    : const Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.camera_alt_outlined,
                                            size: 32,
                                            color: _kGreen,
                                          ),
                                          SizedBox(height: 8),
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
                                      Colors.black.withValues(alpha: 0.15),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 8,
                                top: 8,
                                child: Material(
                                  color: Colors.black54,
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: _removeImage,
                                    child: const Padding(
                                      padding: EdgeInsets.all(6),
                                      child: Icon(
                                        Icons.close,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  Container(width: 1, color: _kGreen.withValues(alpha: 0.3)),
                  Expanded(
                    flex: 1,
                    child: Container(
                      color: Colors.grey.withValues(alpha: 0.02),
                      padding: const EdgeInsets.all(10),
                      child: _uploadingImage
                          ? const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: _kGreen,
                              ),
                            )
                          : (_capturedLat != null && _capturedLng != null)
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Icon(
                                  Icons.location_on,
                                  color: _kGreen,
                                  size: 18,
                                ),
                                const SizedBox(height: 4),
                                if ((_capturedAddress ?? '').isNotEmpty)
                                  Expanded(
                                    child: Text(
                                      _capturedAddress!,
                                      textAlign: TextAlign.right,
                                      maxLines: 8,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[800],
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  'Lat: ${_capturedLat!.toStringAsFixed(6)}',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                Text(
                                  'Lng: ${_capturedLng!.toStringAsFixed(6)}',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                  ),
                                ),
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

            const SizedBox(height: 14),

            // ── Description ───────────────────────────────────────
            TextFormField(
              controller: _descriptionCtrl,
              minLines: 2,
              maxLines: 5,
              onChanged: (_) => _safeSet(() {}),
              decoration: _inputDec(
                'Description / Details (required)',
                Icons.notes_rounded,
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Description is required' : null,
            ),

            // ── Validity hint ─────────────────────────────────────
            // ── Validity hint (always shown — mandatory section) ──
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _canSubmit
                  ? const _CompleteHint(message: 'Ready ✓')
                  : const _IncompleteHint(
                      message: 'Required: Capture a photo & enter description',
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _OtherPurposeMandatorySection — always-visible mandatory form (no card shell)
// ═══════════════════════════════════════════════════════════════════════════════

class _OtherPurposeMandatorySection extends StatefulWidget {
  final String dealerId;
  final String dealerName;
  final String shopName;
  final String address;
  final String mobile;
  final double latitude;
  final double longitude;
  final double pendingAmount;
  final ValueChanged<bool> onValidityChanged;
  final VoidCallback onSuccess;

  const _OtherPurposeMandatorySection({
    super.key,
    required this.dealerId,
    required this.dealerName,
    required this.shopName,
    required this.address,
    required this.mobile,
    required this.latitude,
    required this.longitude,
    required this.pendingAmount,
    required this.onValidityChanged,
    required this.onSuccess,
  });

  @override
  State<_OtherPurposeMandatorySection> createState() =>
      _OtherPurposeMandatorySectionState();
}

class _OtherPurposeMandatorySectionState
    extends State<_OtherPurposeMandatorySection> {
  File? _imageFile;
  bool _uploadingImage = false;

  double? _capturedLat;
  double? _capturedLng;
  String? _capturedAddress;

  final _descriptionCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _inlineBanner;

  @override
  void initState() {
    super.initState();
    _descriptionCtrl.addListener(() {
      widget.onValidityChanged(_canSubmit);
    });
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    super.dispose();
  }

  void _safeSet(void Function() fn) {
    if (mounted) setState(fn);
  }

  bool get _canSubmit =>
      _imageFile != null &&
      _descriptionCtrl.text.trim().isNotEmpty &&
      !_uploadingImage &&
      _capturedLat != null &&
      _capturedLng != null;

  // ── Called by unified submit button ──────────────────────────────────────
  Future<bool> _submitAndReturn() async {
    if (_imageFile == null) return false;
    if (_descriptionCtrl.text.trim().isEmpty) return false;
    if (_capturedLat == null || _capturedLng == null) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getString('userId') ?? '';
      final tripId = prefs.getString('currentTripId') ?? '';
      final tripCompleted = prefs.getBool('tripCompleted') ?? false;
      final effectiveTripId = tripCompleted ? tripId : '';
      if (employeeId.isEmpty) return false;

      final address = _capturedAddress ?? 'Unknown Address';
      final body = {
        'employeeId': employeeId,
        if (effectiveTripId.isNotEmpty) 'tripId': effectiveTripId,
        'idOfVisitor[id]': widget.dealerId,
        'idOfVisitor[type]': 'Dealer',
        'purpose': 'Lead',
        'reason': _descriptionCtrl.text.trim(),
        'address': address,
      };

      final ext = _imageFile!.path.split('.').last.toLowerCase();
      final mime = (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/png';

      final imageFile = QueuedFile(
        field: 'images',
        path: _imageFile!.path,
        filename: 'lead_${DateTime.now().millisecondsSinceEpoch}.$ext',
        contentType: mime,
      );

      final resp = await apiClient.sendOrQueue(
        method: HttpVerb.post,
        path: AppConfig.othervisits,
        jsonBody: body,
        files: [imageFile],
        optimisticOk: true,
      );

      if (resp == null) return true; // queued offline
      return resp.statusCode == 200 || resp.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // ── Camera & Location ─────────────────────────────────────────────────────

  Future<File> _fixExifRotation(File file) async {
    final bytes = await file.readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) return file;
    final fixed = img.bakeOrientation(original);
    final newPath =
        '${file.parent.path}/fixed_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return File(newPath)..writeAsBytesSync(img.encodeJpg(fixed, quality: 100));
  }

  Future<void> _pickImageFromCamera() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.camera);
      if (picked == null) return;

      _safeSet(() => _uploadingImage = true);

      await _fetchLocation();
      if (_capturedLat == null || _capturedLng == null) {
        _setError('Unable to capture location. Please try again.');
        _safeSet(() => _uploadingImage = false);
        return;
      }

      final timestamp = DateFormat(
        'yyyy-MM-dd HH:mm:ss',
      ).format(DateTime.now());
      final address = _capturedAddress ?? 'Unknown Address';
      final original = File(picked.path);
      final fixedFile = await _fixExifRotation(original);
      final stamped = await _stampImage(
        fixedFile,
        _capturedLat!,
        _capturedLng!,
        timestamp,
        address,
      );
      final optimized =
          await MediaOptimizer.getOptimizedImage(stamped) ?? stamped;

      if (!mounted) return;
      _safeSet(() {
        _imageFile = optimized;
        _uploadingImage = false;
      });
      widget.onValidityChanged(_canSubmit);
    } catch (e) {
      _setError('Camera error: $e');
      _safeSet(() => _uploadingImage = false);
    }
  }

  void _removeImage() {
    _safeSet(() {
      _imageFile = null;
      _capturedLat = null;
      _capturedLng = null;
      _capturedAddress = null;
    });
    widget.onValidityChanged(_canSubmit);
  }

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
          'Address: $address\nLat: ${lat.toStringAsFixed(6)}\n'
          'Lng: ${lng.toStringAsFixed(6)}\nTime: $time';
      final fontSize = (width.toDouble() / 15.0).clamp(22.0, 60.0).toDouble();

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
          '${imageFile.parent.path}/lead_stamp_${DateTime.now().millisecondsSinceEpoch}.png';
      return File(stampedPath)
        ..writeAsBytesSync(byteData!.buffer.asUint8List());
    } catch (e) {
      debugPrint('STAMP ERROR: $e');
      return imageFile;
    }
  }

  Future<void> _fetchLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _setError('Location permission denied.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _setError('Location permission permanently denied.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _safeSet(() {
        _capturedLat = pos.latitude;
        _capturedLng = pos.longitude;
      });

      String? addr;
      try {
        final key = AppConfig.googleMapsApiKey;
        final url =
            'https://maps.googleapis.com/maps/api/geocode/json'
            '?latlng=${pos.latitude},${pos.longitude}&key=$key';
        final resp = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          if (data['status'] == 'OK' && (data['results'] as List).isNotEmpty) {
            addr = data['results'][0]['formatted_address'];
          } else {
            throw Exception('no results');
          }
        } else {
          throw Exception('${resp.statusCode}');
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
            ].where((e) => e != null && e.trim().isNotEmpty).join(', ');
          } else {
            throw Exception('empty');
          }
        } catch (_) {
          addr = 'Offline — address unavailable';
        }
      }
      _safeSet(
        () => _capturedAddress = addr ?? 'Offline — address unavailable',
      );
    } catch (e) {
      _setError('Failed to get location: $e');
    }
  }

  void _setError(String msg) => _safeSet(() => _inlineBanner = msg);
  void _clearError() => _safeSet(() => _inlineBanner = null);

  // REPLACE the entire build() in _LeadPurposeCardState:
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _canSubmit ? _kGreen : Colors.red.shade200,
              width: 1.6,
            ),
            boxShadow: [
              BoxShadow(
                color: _canSubmit
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
            if ((_inlineBanner ?? '').isNotEmpty) ...[
              _InlineBanner(message: _inlineBanner!, onClose: _clearError),
              const SizedBox(height: 10),
            ],

            // ── Camera + location card ────────────────────────────
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _kGreen.withValues(alpha: 0.6),
                  width: 1.3,
                ),
              ),
              clipBehavior: Clip.hardEdge,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
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
                                    : const Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.camera_alt_outlined,
                                            size: 32,
                                            color: _kGreen,
                                          ),
                                          SizedBox(height: 8),
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
                                      Colors.black.withValues(alpha: 0.15),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 8,
                                top: 8,
                                child: Material(
                                  color: Colors.black54,
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: _removeImage,
                                    child: const Padding(
                                      padding: EdgeInsets.all(6),
                                      child: Icon(
                                        Icons.close,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  Container(width: 1, color: _kGreen.withValues(alpha: 0.3)),
                  Expanded(
                    flex: 1,
                    child: Container(
                      color: Colors.grey.withValues(alpha: 0.02),
                      padding: const EdgeInsets.all(10),
                      child: _uploadingImage
                          ? const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: _kGreen,
                              ),
                            )
                          : (_capturedLat != null && _capturedLng != null)
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Icon(
                                  Icons.location_on,
                                  color: _kGreen,
                                  size: 18,
                                ),
                                const SizedBox(height: 4),
                                if ((_capturedAddress ?? '').isNotEmpty)
                                  Expanded(
                                    child: Text(
                                      _capturedAddress!,
                                      textAlign: TextAlign.right,
                                      maxLines: 8,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[800],
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  'Lat: ${_capturedLat!.toStringAsFixed(6)}',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                Text(
                                  'Lng: ${_capturedLng!.toStringAsFixed(6)}',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                  ),
                                ),
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

            const SizedBox(height: 14),

            // ── Description ───────────────────────────────────────
            TextFormField(
              controller: _descriptionCtrl,
              minLines: 2,
              maxLines: 5,
              onChanged: (_) => _safeSet(() {}),
              decoration: _inputDec(
                'Description / Details (required)',
                Icons.notes_rounded,
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Description is required' : null,
            ),

            // ── Validity hint ─────────────────────────────────────
            // ── Validity hint (always shown — mandatory section) ──
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _canSubmit
                  ? const _CompleteHint(message: 'Ready ✓')
                  : const _IncompleteHint(
                      message: 'Required: Capture a photo & enter description',
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
//  _DealerHeaderCard
// ═══════════════════════════════════════════════════════════════════════════════

class _DealerHeaderCard extends StatelessWidget {
  final String dealerName;
  final String subtitle;
  final String address;
  final double latitude;
  final double longitude;
  final double pendingAmount;

  const _DealerHeaderCard({
    required this.dealerName,
    required this.subtitle,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.pendingAmount,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    );
    final noDue = pendingAmount <= 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: _kGreen, blurRadius: 3, offset: Offset(0, 0.5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _kGreenLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.store_rounded, color: _kGreen),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dealerName,
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.place, size: 18, color: _kGreen),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (address.trim().isNotEmpty)
                      Text(
                        address,
                        style: const TextStyle(color: Colors.black87),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Text(
                      '($latitude, $longitude)',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
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
                color: _kGreen,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  noDue ? 'No Due' : 'Due: ${fmt.format(pendingAmount)}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    color: noDue ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
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

/// Amber hint shown when a card is started but not yet complete.
class _IncompleteHint extends StatelessWidget {
  final String message;
  const _IncompleteHint({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFD54F)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: Color(0xFFFF8F00),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF795548)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Green hint shown when a card is fully valid.
class _CompleteHint extends StatelessWidget {
  final String message;
  const _CompleteHint({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kGreen.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            size: 16,
            color: _kGreen,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF1A6B5A)),
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
    prefixIcon: icon != null ? Icon(icon, color: _kGreen, size: 20) : null,
    filled: true,
    fillColor: Colors.grey.withValues(alpha: 0.05),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    labelStyle: TextStyle(color: Colors.grey[700], fontSize: 13.5),
    floatingLabelStyle: const TextStyle(color: _kGreen, fontSize: 13),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _kGreen, width: 1.3),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _kGreen, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.red, width: 1.3),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.red, width: 2),
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
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        side: BorderSide(
          color: hasValue ? _kGreen : Colors.grey.withValues(alpha: 0.5),
          width: hasValue ? 1.5 : 1,
        ),
        foregroundColor: hasValue ? _kGreen : Colors.grey[600],
        backgroundColor: hasValue
            ? _kGreenLight.withValues(alpha: 0.2)
            : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
      icon: Icon(icon, size: 17),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          color: hasValue ? Colors.black87 : Colors.grey[600],
          fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _InlineBanner extends StatelessWidget {
  final String message;
  final VoidCallback onClose;

  const _InlineBanner({required this.message, required this.onClose});

  @override
  Widget build(BuildContext context) {
    if (message.trim().isEmpty) return const SizedBox.shrink();
    return Container(
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
              style: const TextStyle(color: Colors.red, fontSize: 13),
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
//  ProductsBottomSheet
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
  final Set<String> _addedQtyMap = {};

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

  int get _activeFilterCount {
    int count = 0;
    if (_selectedCategoryId != null) count++;
    if (_selectedSubCategoryId != null) count++;
    if (_selectedChildCategoryId != null) count++;
    return count;
  }

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
    _searchCtrl.addListener(_filterProducts);
    _fetchCategories();
    _fetchProducts();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filterProducts() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      _filteredProducts = query.isEmpty
          ? List.from(_allProducts)
          : _allProducts
                .where(
                  (p) =>
                      (p.productName ?? '').toLowerCase().contains(query) ||
                      (p.shortDescription ?? '').toLowerCase().contains(query),
                )
                .toList();
    });
  }

  Future<void> _fetchProducts({
    String? categoryId,
    String? subCategoryId,
    String? childCategoryId,
  }) async {
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
            if (item is Map<String, dynamic>) items.add(Product.fromJson(item));
          }
        } else if (body is List) {
          for (final item in body) {
            if (item is Map<String, dynamic>) items.add(Product.fromJson(item));
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
          onCategorySelect: (id) async => await _onCategorySelected(id),
          onSubCategorySelect: (id) async => await _onSubCategorySelected(id),
          onChildCategorySelect: (id) async =>
              await _onChildCategorySelected(id),
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
            // ── Header ────────────────────────────────────────────────
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

            // ── List ──────────────────────────────────────────────────
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
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              bottomLeft: Radius.circular(12),
            ),
            child: _buildProductImage(product),
          ),
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
}

// ═════════════════════════════════════════════════════════════════════════════
// FILTER BUTTON
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
                  : Colors.black.withOpacity(0.05),
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
