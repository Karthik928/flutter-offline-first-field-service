// lib/screena/add_farmer_screen.dart
// Extracted Add Farmer bottom sheet (same behavior & validations as original).
// Use: await ZonalAddFarmerScreen.show(context);

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/Screens/farmer_visit_screen.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/main.dart';
import 'package:FieldService_app/offline/request_envelope.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:FieldService_app/utils/mediaoptimizer.dart';
import 'package:FieldService_app/zonal_services/zonal_employee_service.dart';

class ZonalAddFarmerScreen extends StatefulWidget {
  const ZonalAddFarmerScreen({super.key});

  /// Show as a draggable bottom sheet and return true when a farmer was created.
  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          minChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SingleChildScrollView(
                controller: controller,
                child: const ZonalAddFarmerScreen(),
              ),
            );
          },
        );
      },
    );
  }

  @override
  State<ZonalAddFarmerScreen> createState() => _ZonalAddFarmerScreenState();
}

class _ZonalAddFarmerScreenState extends State<ZonalAddFarmerScreen>
    with ZonalAddFarmerScreenStateMix {
  final _formKey = GlobalKey<FormState>();
  final Color appGreen = const Color(0xFF1AB69C);

  // Main fields
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();

  // Ponds (farms)
  final List<_PondForm> _ponds = [_PondForm()];

  // picked farm images (PlatformFile)
  final List<PlatformFile> _farmImages = [];

  bool _submitting = false;
  bool _locating = false;
  String? _topError;

  // location
  double? _lat;
  double? _lng;

  static const int _maxPonds = 4;

  // ── Employee dropdown state ──────────────────────────────────────────
  List<Employee> _employees = [];
  bool _loadingEmployees = true;
  static const String _kSelfSentinel = '__self__';
  String? _selectedEmployeeId;
  String? _selectedEmployeeLabel;
  // ─────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _fetchEmployees();
  }

  // ── Fetch employees from API ─────────────────────────────────────────
  Future<void> _fetchEmployees() async {
    setState(() => _loadingEmployees = true);
    try {
      final list = await ZonalEmployeeService().fetchEmployees();
      if (mounted) {
        setState(() {
          _employees = list;
          _loadingEmployees = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingEmployees = false);
    }
  }
  // ─────────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _addressCtrl.dispose();
    _areaCtrl.dispose();
    for (final p in _ponds) {
      p.dispose();
    }
    super.dispose();
  }

  void _setTopError(String? msg) {
    if (!mounted) return;
    setState(() => _topError = msg);
  }

  // Input formatters
  static final List<TextInputFormatter> _lettersOnly = [
    FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z ]")),
    LengthLimitingTextInputFormatter(40),
  ];
  static final List<TextInputFormatter> _tenDigits = [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(10),
  ];
  static final TextInputFormatter _oneDotNumber =
      TextInputFormatter.withFunction(
        (oldValue, newValue) => RegExp(r'^\d*\.?\d*$').hasMatch(newValue.text)
            ? newValue
            : oldValue,
      );

  // Validators
  String? _vName(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Name is required';
    if (!RegExp(r'^[A-Za-z ]+$').hasMatch(s)) return 'Letters & spaces only';
    return null;
  }

  String? _vMobile(String? v) {
    final s = (v ?? '').trim();
    if (s.length != 10) return 'Enter exactly 10 digits';
    if (!RegExp(r'^\d{10}$').hasMatch(s)) return 'Invalid number';
    return null;
  }

  String? _vRequired(String? v, String label) {
    if ((v ?? '').trim().isEmpty) return '$label is required';
    return null;
  }

  String? _vDoublePos(String? v, String label) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return '$label is required';
    final d = double.tryParse(s);
    if (d == null || d <= 0) return 'Enter a valid positive number';
    return null;
  }

  // Location
  Future<void> _getLocation() async {
    _setTopError(null);
    if (mounted) setState(() => _locating = true);

    debugPrint('📍 [_getLocation] Starting location lookup...');

    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        debugPrint('⚠️ [_getLocation] Permission not granted, requesting...');
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied ||
            perm == LocationPermission.deniedForever) {
          _setTopError('Location permission denied');
          debugPrint('❌ [_getLocation] Permission denied');
          return;
        }
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      debugPrint(
        '✅ [_getLocation] GPS acquired: '
        '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}',
      );

      String address = '';
      bool reverseDone = false;

      try {
        debugPrint('🌐 [_getLocation] Trying reverse geocode...');
        final pm = await placemarkFromCoordinates(pos.latitude, pos.longitude);

        if (pm.isNotEmpty) {
          final p = pm.first;
          address = [
            p.name,
            p.street,
            p.subLocality,
            p.locality,
            p.subAdministrativeArea,
            p.administrativeArea,
            p.postalCode,
            p.country,
          ].where((e) => e != null && e.trim().isNotEmpty).join(', ');

          reverseDone = true;
          debugPrint('✅ [_getLocation] Full address: $address');
        }
      } catch (e) {
        debugPrint('⚠️ [_getLocation] Reverse geocode failed/offline: $e');
        address = '(Offline — address unavailable)';
      }

      if (!mounted) return;

      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _addressCtrl.text = address;
      });

      debugPrint(
        '📦 [_getLocation] Updated fields:\n'
        '│ → lat: ${_lat?.toStringAsFixed(6)}\n'
        '│ → lng: ${_lng?.toStringAsFixed(6)}\n'
        '│ → address: "$address"\n'
        '│ → reverse: ${reverseDone ? '✅ done' : '🟡 offline'}',
      );
    } catch (e) {
      _setTopError('Failed to get location: $e');
      debugPrint('❌ [_getLocation] Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
      debugPrint('🏁 [_getLocation] Done (locating=false)');
    }
  }

  void _addPond() {
    if (_ponds.length >= _maxPonds) {
      _setTopError('You can add up to 4 ponds only');
      return;
    }
    setState(() => _ponds.add(_PondForm()));
  }

  void _removePond(int i) {
    if (_ponds.length == 1) return;
    setState(() => _ponds.removeAt(i).dispose());
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    _setTopError(null);

    // ── Validate employee selection ──────────────────────────────────
    if (_selectedEmployeeId == null) {
      _setTopError('Please select an employee or choose Self.');
      return;
    }
    // ─────────────────────────────────────────────────────────────────

    // sanitize mobile
    _mobileCtrl.text = _mobileCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (_mobileCtrl.text.length > 10) {
      _mobileCtrl.text = _mobileCtrl.text.substring(0, 10);
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      _setTopError('Please correct the highlighted fields.');
      return;
    }
    for (int i = 0; i < _ponds.length; i++) {
      final err = _ponds[i].validate();
      if (err != null) {
        _setTopError('Pond ${i + 1}: $err');
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final companyId = prefs.getString('companyId') ?? '';
      final selfId = prefs.getString('userId') ?? '';

      if (companyId.isEmpty || selfId.isEmpty) {
        _setTopError('Missing companyId/employeeId. Please re-login.');
        return;
      }

      // ── Resolve employee id ──────────────────────────────────────
      // "Self" → use SharedPreferences userId; otherwise use selected employee's id
      final String resolvedEmployeeId = (_selectedEmployeeId == _kSelfSentinel)
          ? selfId
          : _selectedEmployeeId!;
      // ─────────────────────────────────────────────────────────────

      debugPrint(
        '🧩 [ZonalAddFarmerScreen] employeeId: $resolvedEmployeeId '
        '(${_selectedEmployeeLabel ?? "Self"})',
      );

      final ponds = _ponds.map((p) => p.toJson()).toList();
      final bool hasImages = _farmImages.isNotEmpty;

      Map<String, dynamic> body;
      if (hasImages) {
        body = <String, dynamic>{
          'name': _nameCtrl.text.trim(),
          'mobileNumber': _mobileCtrl.text.trim(),
          'employeeId': resolvedEmployeeId, // <── resolved id
          'companyId': companyId,
          'address': _addressCtrl.text.trim(),
          'location':
              "${(_lat ?? 0).toStringAsFixed(6)} ${(_lng ?? 0).toStringAsFixed(6)}",
          'totalCultureArea': _areaCtrl.text.trim(),
        };

        for (int i = 0; i < ponds.length; i++) {
          final p = ponds[i];
          p.forEach((k, v) {
            body['farms[$i][$k]'] = v.toString();
          });
        }
      } else {
        body = {
          "name": _nameCtrl.text.trim(),
          "mobileNumber": _mobileCtrl.text.trim(),
          "employeeId": resolvedEmployeeId, // <── resolved id
          "companyId": companyId,
          "address": _addressCtrl.text.trim(),
          "location":
              "${(_lat ?? 0).toStringAsFixed(6)} ${(_lng ?? 0).toStringAsFixed(6)}",
          "totalCultureArea": double.parse(_areaCtrl.text.trim()),
          "farms": ponds,
        };
      }

      debugPrint(
        "🚀 [Farmers] POST ${AppConfig.farmers}\n"
        "companyId=$companyId employeeId=$resolvedEmployeeId\n"
        "address=${body['address']}\n"
        "location=${body['location']}",
      );

      final List<QueuedFile>? files = _farmImages.isNotEmpty
          ? await _farmQueuedFiles()
          : null;

      final resp = await apiClient.sendOrQueue(
        method: HttpVerb.post,
        path: AppConfig.farmers,
        jsonBody: body,
        files: files,
      );

      if (!mounted) return;

      if (resp == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved offline — will sync automatically'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(true);
        return;
      }

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Farmer added successfully!'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(true);
        Navigator.of(context).pop(true);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const FarmerVisitScreen(
              display: true,
              showPendingOnStart: true,
              refreshOnStart: true,
            ),
          ),
        );
      } else {
        String msg = 'HTTP ${resp.statusCode}';
        try {
          final d = jsonDecode(resp.body);
          if (d is Map && d['message'] is String) msg = d['message'];
        } catch (_) {}
        _setTopError('Failed to add farmer: $msg');
      }
    } catch (e) {
      _setTopError('Network error: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Employee dropdown widget ─────────────────────────────────────────
  Widget _buildEmployeeDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'Select Employee',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
          ),
          _loadingEmployees
              ? Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: appGreen.withValues(alpha: 0.4),
                      width: 1.2,
                    ),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: appGreen,
                      ),
                    ),
                  ),
                )
              : _EmployeeMenuAnchor(
                  appGreen: appGreen,
                  employees: _employees,
                  selectedLabel: _selectedEmployeeLabel,
                  onSelected: (id, label) {
                    setState(() {
                      _selectedEmployeeId = id;
                      _selectedEmployeeLabel = label;
                    });
                  },
                ),
        ],
      ),
    );
  }
  // ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: bottomInset + 12,
          top: 12,
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // error bar
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _topError == null
                    ? const SizedBox.shrink()
                    : Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE8E8),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFFC2C2)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _topError!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => _setTopError(null),
                              child: const Icon(
                                Icons.close,
                                size: 18,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),

              const Text(
                'Add Farmer',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),

              Form(
                key: _formKey,
                child: Column(
                  children: [
                    // ── ① Employee dropdown (TOP of form) ────────────
                    _buildEmployeeDropdown(),

                    // ─────────────────────────────────────────────────
                    _field(
                      label: 'Farmer Name',
                      controller: _nameCtrl,
                      inputFormatters: _lettersOnly,
                      textInputAction: TextInputAction.next,
                      validator: _vName,
                    ),
                    _field(
                      label: 'Mobile Number',
                      controller: _mobileCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: _tenDigits,
                      textInputAction: TextInputAction.next,
                      validator: _vMobile,
                      maxLength: 10,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      onChanged: (v) {
                        final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
                        final trimmed = digits.length > 10
                            ? digits.substring(0, 10)
                            : digits;
                        if (trimmed != _mobileCtrl.text) {
                          final sel = trimmed.length;
                          _mobileCtrl.value = TextEditingValue(
                            text: trimmed,
                            selection: TextSelection.collapsed(offset: sel),
                          );
                        }
                      },
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _field(
                            label: 'Address / Location (auto)',
                            controller: _addressCtrl,
                            readOnly: true,
                            enableInteractiveSelection: false,
                            validator: (v) => _vRequired(v, 'Location'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _locating ? null : _getLocation,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1AB69C),
                              foregroundColor: Colors.white,
                            ),
                            icon: _locating
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.my_location),
                            label: Text(_locating ? 'Locating…' : 'Get'),
                          ),
                        ),
                      ],
                    ),
                    _field(
                      label: 'Total Culture Area (acres)',
                      controller: _areaCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [_oneDotNumber],
                      textInputAction: TextInputAction.next,
                      validator: (v) => _vDoublePos(v, 'Total culture area'),
                    ),

                    const SizedBox(height: 12),

                    // Ponds header
                    Row(
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
                          onPressed: _ponds.length >= _maxPonds
                              ? null
                              : _addPond,
                          icon: Icon(Icons.add, color: appGreen),
                          label: Text(
                            'Add Pond',
                            style: TextStyle(color: appGreen),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: appGreen, width: 1.2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // pond cards
                    Column(
                      children: List.generate(_ponds.length, (i) {
                        final p = _ponds[i];
                        return _pondCard(
                          index: i,
                          pf: p,
                          onRemove: _ponds.length == 1
                              ? null
                              : () => _removePond(i),
                        );
                      }),
                    ),

                    // Farm images section
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Farm images',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const Spacer(),
                            OutlinedButton.icon(
                              onPressed: _pickFarmImages,
                              icon: Icon(Icons.photo_library, color: appGreen),
                              label: Text(
                                'Add Images ${_farmImages.isEmpty ? '' : '(${_farmImages.length})'}',
                                style: TextStyle(color: appGreen),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: appGreen, width: 1.2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 0, bottom: 8),
                          child: Text(
                            'Up to 3 images',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                        if (_farmImages.isNotEmpty)
                          SizedBox(
                            height: 80,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _farmImages.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (_, i) {
                                final f = _farmImages[i];
                                return Stack(
                                  children: [
                                    Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        color: Colors.grey.withValues(
                                          alpha: 0.08,
                                        ),
                                      ),
                                      child: Image.file(
                                        File(f.path!),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      child: InkWell(
                                        onTap: () => setState(
                                          () => _farmImages.removeAt(i),
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          size: 18,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 8),
                      ],
                    ),

                    const SizedBox(height: 14),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1AB69C),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Save Farmer',
                                style: TextStyle(fontWeight: FontWeight.w700),
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
    );
  }

  Future<void> _pickFarmImages() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
        withData: false,
        withReadStream: false,
      );
      if (res == null) return;
      final picked = res.files.take(3).toList();
      setState(() {
        _farmImages.clear();
        _farmImages.addAll(picked);
      });
    } catch (e) {
      _setTopError('Failed to pick images: $e');
    }
  }

  Future<List<QueuedFile>> _farmQueuedFiles() async {
    final result = <QueuedFile>[];

    for (final f in _farmImages) {
      String path = f.path!;

      File originalFile = File(path);

      // 🔥 STEP 1: OPTIMIZE IMAGE (THIS IS THE KEY FIX)
      final optimizedFile = await MediaOptimizer.getOptimizedImage(
        originalFile,
      );

      final finalFile = optimizedFile ?? originalFile;

      // 🔥 STEP 2: SIZE CHECK (PREVENT 413)
      final sizeMB = await MediaOptimizer.getFileSizeMB(finalFile);

      if (sizeMB > 5) {
        throw Exception(
          "Image too large (${sizeMB.toStringAsFixed(2)} MB). Please select smaller image.",
        );
      }

      debugPrint("📦 Uploading image: ${finalFile.path}");
      debugPrint("📊 Size: ${sizeMB.toStringAsFixed(2)} MB");

      final mime = _mimeFromExt(f.name);

      result.add(
        QueuedFile(
          field: 'farmImage',
          path: finalFile.path,
          filename: f.name,
          contentType: mime,
        ),
      );
    }

    return result;
  }

  String _mimeFromExt(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream';
    }
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextInputAction? textInputAction,
    bool readOnly = false,
    bool enableInteractiveSelection = true,
    int? maxLength,
    MaxLengthEnforcement? maxLengthEnforcement,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        textInputAction: textInputAction,
        readOnly: readOnly,
        enableInteractiveSelection: enableInteractiveSelection,
        maxLength: maxLength,
        maxLengthEnforcement: maxLengthEnforcement,
        onChanged: onChanged,
        buildCounter:
            (_, {required currentLength, required isFocused, maxLength}) =>
                null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: Colors.grey.withValues(alpha: 0.06),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFF1AB69C), width: 1.4),
          ),
          errorBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Colors.red),
          ),
          focusedErrorBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Colors.red),
          ),
        ),
      ),
    );
  }

  Widget _pondCard({
    required int index,
    required _PondForm pf,
    VoidCallback? onRemove,
  }) {
    final ts = MediaQuery.textScalerOf(context).scale(1);
    final double gap = (16 + (ts - 1.0) * 8).clamp(12.0, 24.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Pond ${index + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
            ],
          ),
          SizedBox(height: gap),
          MenuAnchor(
            controller: pf.menuCtrl,
            childFocusNode: FocusNode(),
            builder: (context, controller, _) {
              return TextFormField(
                key: pf.speciesKey,
                readOnly: true,
                controller: pf.speciesCtrl,
                decoration: InputDecoration(
                  labelText: 'Culture Species',
                  hintText: 'Select species',
                  filled: true,
                  fillColor: Colors.grey.withValues(alpha: 0.06),
                  suffixIcon: const Icon(Icons.keyboard_arrow_down),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: Colors.grey.withValues(alpha: 0.2),
                    ),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                    borderSide: BorderSide(
                      color: Color(0xFF1AB69C),
                      width: 1.2,
                    ),
                  ),
                ),
                onTap: () {
                  controller.isOpen ? controller.close() : controller.open();
                },
                validator: (_) =>
                    pf.species == null ? 'Species is required' : null,
              );
            },
            menuChildren: [
              Builder(
                builder: (context) {
                  final box =
                      pf.speciesKey.currentContext!.findRenderObject()
                          as RenderBox;
                  final width = box.size.width;

                  return SizedBox(
                    width: width,
                    child: Material(
                      elevation: 6,
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _menuItem('Shrimp', pf),
                            const SizedBox(height: 4),
                            _menuItem('Fish', pf),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          SizedBox(height: gap),
          _miniField(
            label: 'Stocking Density',
            controller: pf.density,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (v) => _reqInt(v, 'Stocking density'),
          ),
          SizedBox(height: gap),
          _miniField(
            label: 'Days of Culture',
            controller: pf.days,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (v) => _reqInt(v, 'Days of culture'),
          ),
          SizedBox(height: gap),
          _miniField(
            label: 'Salinity',
            controller: pf.salinity,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (v) => _reqInt(v, 'Salinity'),
          ),
          SizedBox(height: gap),
          _miniField(
            label: 'Feed Intake / Day',
            controller: pf.feed,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [ZonalAddFarmerScreenStateMix._oneDot],
            validator: (v) => _reqDouble(v, 'Feed intake'),
          ),
          if (pf.species == 'Fish') ...[
            SizedBox(height: gap),
            _miniField(
              label: 'Avg Wt (e.g., 20g)',
              controller: pf.size,
              validator: (v) {
                if (pf.species != 'Fish') return null;
                if ((v ?? '').trim().isEmpty) {
                  return 'Avg weight is required for Fish';
                }
                return null;
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _menuItem(String value, _PondForm pf) {
    final bool selected = pf.species == value;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        setState(() {
          pf.species = value;
          pf.speciesCtrl.text = value;
          if (value != 'Fish') pf.size.clear();
        });
        pf.menuCtrl.close();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF1AB69C).withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              value == 'Shrimp' ? Icons.set_meal : Icons.phishing,
              size: 20,
              color: selected ? const Color(0xFF1AB69C) : Colors.grey.shade700,
            ),
            const SizedBox(width: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: selected ? const Color(0xFF1AB69C) : Colors.black87,
              ),
            ),
            const Spacer(),
            if (selected)
              const Icon(
                Icons.check_circle,
                size: 18,
                color: Color(0xFF1AB69C),
              ),
          ],
        ),
      ),
    );
  }

  String? _reqInt(String? v, String label) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return '$label is required';
    if (int.tryParse(s) == null) return 'Enter a valid integer';
    return null;
  }

  String? _reqDouble(String? v, String label) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return '$label is required';
    if (double.tryParse(s) == null) return 'Enter a valid number';
    return null;
  }

  Widget _miniField({
    required String label,
    required TextEditingController controller,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.grey.withValues(alpha: 0.06),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: Color(0xFF1AB69C), width: 1.2),
          ),
          errorBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: Colors.red),
          ),
          focusedErrorBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: Colors.red),
          ),
        ),
      ),
    );
  }
}

// tiny mixin to reuse formatters inside pond card
mixin ZonalAddFarmerScreenStateMix {
  static final TextInputFormatter _oneDot = TextInputFormatter.withFunction(
    (oldValue, newValue) =>
        RegExp(r'^\d*\.?\d*$').hasMatch(newValue.text) ? newValue : oldValue,
  );
}

/* ========================= Pond helper ========================= */

class _PondForm {
  final GlobalKey speciesKey = GlobalKey();
  final speciesCtrl = TextEditingController();
  final MenuController menuCtrl = MenuController();

  String? species;

  final density = TextEditingController();
  final days = TextEditingController();
  final salinity = TextEditingController();
  final feed = TextEditingController();
  final size = TextEditingController();

  String? validate() {
    if (species == null || species!.isEmpty) return 'Species is required';
    if (int.tryParse(density.text.trim()) == null) {
      return 'Stocking density must be an integer';
    }
    if (int.tryParse(days.text.trim()) == null) {
      return 'Days of culture must be an integer';
    }
    if (int.tryParse(salinity.text.trim()) == null) {
      return 'Salinity must be an integer';
    }
    if (double.tryParse(feed.text.trim()) == null) {
      return 'Feed intake must be a number';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    "cultureSpecies": species,
    "stockingDensity": int.parse(density.text.trim()),
    "daysOfCulture": int.parse(days.text.trim()),
    "salinity": int.parse(salinity.text.trim()),
    "feedIntakePerDay": double.parse(feed.text.trim()),
    "sizeOrCount": size.text.trim(),
  };

  void dispose() {
    speciesCtrl.dispose();
    density.dispose();
    days.dispose();
    salinity.dispose();
    feed.dispose();
    size.dispose();
  }
}

/* ========================= Employee dropdown widgets ========================= */

/// Animated MenuAnchor dropdown listing fetched employees + Self at the bottom.
class _EmployeeMenuAnchor extends StatelessWidget {
  const _EmployeeMenuAnchor({
    required this.appGreen,
    required this.employees,
    required this.selectedLabel,
    required this.onSelected,
  });

  final Color appGreen;
  final List<Employee> employees;
  final String? selectedLabel;
  final void Function(String id, String label) onSelected;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      childFocusNode: FocusNode(),
      builder: (context, controller, _) {
        final isOpen = controller.isOpen;

        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => isOpen ? controller.close() : controller.open(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: isOpen
                    ? [
                        appGreen.withValues(alpha: 0.12),
                        appGreen.withValues(alpha: 0.05),
                      ]
                    : [Colors.white, Colors.white],
              ),
              border: Border.all(
                color: isOpen ? appGreen : appGreen.withValues(alpha: 0.5),
                width: isOpen ? 1.6 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        appGreen.withValues(alpha: 0.9),
                        appGreen.withValues(alpha: 0.6),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: appGreen.withValues(alpha: 0.45),
                        blurRadius: 10,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Employee',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        selectedLabel ?? 'Select employee',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: selectedLabel == null
                              ? Colors.black45
                              : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: isOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 26,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      menuChildren: [
        // Fetched employees
        ...employees.map(
          (emp) => MenuItemButton(
            onPressed: () => onSelected(emp.id, emp.name),
            child: _EmployeeMenuItem(
              label: emp.name,
              isSelected: selectedLabel == emp.name,
              appGreen: appGreen,
              icon: Icons.person_outline_rounded,
            ),
          ),
        ),

        // Divider
        if (employees.isNotEmpty)
          const Divider(height: 1, thickness: 1, indent: 12, endIndent: 12),

        // Self — always pinned at the bottom
        MenuItemButton(
          onPressed: () => onSelected('__self__', 'Self'),
          child: _EmployeeMenuItem(
            label: 'Self',
            isSelected: selectedLabel == 'Self',
            appGreen: appGreen,
            icon: Icons.account_circle_rounded,
          ),
        ),
      ],
    );
  }
}

class _EmployeeMenuItem extends StatelessWidget {
  const _EmployeeMenuItem({
    required this.label,
    required this.isSelected,
    required this.appGreen,
    required this.icon,
  });

  final String label;
  final bool isSelected;
  final Color appGreen;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? appGreen.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: isSelected ? appGreen : Colors.black54),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isSelected ? appGreen : Colors.black87,
              ),
            ),
          ),
          if (isSelected) Icon(Icons.check_circle, size: 18, color: appGreen),
        ],
      ),
    );
  }
}
