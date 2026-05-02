// // Field name the backend expects for uploaded files
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/main.dart';
import 'package:FieldService_app/offline/request_envelope.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:FieldService_app/utils/mediaoptimizer.dart';
import 'package:FieldService_app/zonal_services/zonal_employee_service.dart';
// <-- import your service

class ZonalAddDealerScreen extends StatefulWidget {
  const ZonalAddDealerScreen({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const ZonalAddDealerScreen(),
    );
  }

  @override
  State<ZonalAddDealerScreen> createState() => _ZonalAddDealerScreenState();
}

// --- Document entry model ---
class _DocumentEntry {
  final GlobalKey docTypeKey = GlobalKey();
  final TextEditingController docTypeCtrl = TextEditingController();

  String? docType;
  PlatformFile? file;
  String? error;

  String? validate() {
    if (docType == null || docType!.trim().isEmpty) return 'Select type';
    if (file == null) return 'Choose file';
    return null;
  }

  Map<String, dynamic> meta() => {
    'fileName': file?.name ?? '',
    'type': docType ?? '',
  };

  void dispose() {
    docTypeCtrl.dispose();
  }
}

class _ZonalAddDealerScreenState extends State<ZonalAddDealerScreen> {
  final _formKey = GlobalKey<FormState>();
  final Color appGreen = const Color(0xFF1AB69C);

  final _dealerNameCtrl = TextEditingController();
  final _shopNameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  bool _submitting = false;
  String? _errorText;

  final List<_DocumentEntry> _documents = [];

  // ── Employee dropdown state ──────────────────────────────────────────
  List<Employee> _employees = [];
  bool _loadingEmployees = true;

  /// null  → nothing selected yet
  /// non-null id → a fetched employee selected (or kSelfId sentinel)
  static const String _kSelfSentinel = '__self__';
  String? _selectedEmployeeId; // the id we will send
  String? _selectedEmployeeLabel; // display label
  // ─────────────────────────────────────────────────────────────────────

  final List<String> _docTypes = [
    'Deal Agreement Form',
    'GST Copy',
    'Security Cheque',
    'Aadhaar Card',
    'Dealer Image',
  ];

  String _fieldNameForDocType(String? docType) {
    if (docType == null) return 'documents';
    switch (docType) {
      case 'Deal Agreement Form':
        return 'dealAgreementForm';
      case 'GST Copy':
        return 'gstCopy';
      case 'Security Cheque':
        return 'securityCheque';
      case 'Dealer Image':
        return 'dealerImage';
      case 'Aadhaar Card':
        return 'aadhaarCard';
      default:
        return 'documents';
    }
  }

  static const List<String> _allowedExt = [
    'jpg',
    'jpeg',
    'png',
    'pdf',
    'doc',
    'docx',
  ];

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
    _dealerNameCtrl.dispose();
    _shopNameCtrl.dispose();
    _mobileCtrl.dispose();
    _addressCtrl.dispose();
    _locationCtrl.dispose();
    for (final e in _documents) {
      try {
        e.dispose();
      } catch (_) {}
    }
    super.dispose();
  }

  void _setError(String? msg) {
    if (!mounted) return;
    setState(() => _errorText = msg);
  }

  void _addDocument() {
    if (_documents.length >= 5) {
      _setError('You can attach up to 5 files only.');
      return;
    }
    setState(() => _documents.add(_DocumentEntry()));
  }

  void _removeDocumentAt(int idx) {
    if (idx < 0 || idx >= _documents.length) return;
    setState(() {
      final removed = _documents.removeAt(idx);
      try {
        removed.dispose();
      } catch (_) {}
    });
  }

  Future<void> _pickFileFor(int idx) async {
    if (idx < 0 || idx >= _documents.length) return;
    final entry = _documents[idx];

    if (entry.docType == null) {
      setState(() => entry.error = 'Please select a document type first.');
      return;
    }

    _setError(null);
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: _allowedExt,
      withData: false,
      withReadStream: false,
    );

    if (result == null) return;

    final f = result.files.single;
    final ext = p.extension(f.name).replaceFirst('.', '').toLowerCase();
    if (!_allowedExt.contains(ext)) {
      setState(() => entry.error = 'Unsupported file type');
      return;
    }

    setState(() {
      entry.file = f;
      entry.error = null;
    });
  }

  Future<List<QueuedFile>> _toQueuedFiles() async {
    final files = <QueuedFile>[];
    for (final e in _documents) {
      final f = e.file;
      if (f == null) continue;

      final fieldName = _fieldNameForDocType(e.docType);
      String path = (f.path ?? '').trim();

      File file = File(path);

      final ext = f.extension?.toLowerCase();

      // 🔥 OPTIMIZE ONLY IMAGES
      if (['jpg', 'jpeg', 'png'].contains(ext)) {
        final optimized = await MediaOptimizer.getOptimizedImage(file);
        file = optimized ?? file;
      }

      // 🔥 SIZE CHECK (PREVENT 413)
      final sizeMB = await MediaOptimizer.getFileSizeMB(file);

      if (sizeMB > 5) {
        throw Exception(
          'File "${f.name}" too large (${sizeMB.toStringAsFixed(2)} MB)',
        );
      }

      final mime = _mimeFromExt(f.name);
      files.add(
        QueuedFile(
          field: fieldName,
          path: path,
          filename: f.name,
          contentType: mime,
        ),
      );
    }
    return files;
  }

  List<Map<String, dynamic>> _documentMetaForBody() =>
      _documents.map((e) => e.meta()).toList();

  static final List<TextInputFormatter> _lettersOnly = [
    FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z ]")),
    LengthLimitingTextInputFormatter(40),
  ];
  static final List<TextInputFormatter> _tenDigits = [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(10),
  ];

  String? _validatePhone(String? v) {
    final s = (v ?? '').trim();
    if (s.length != 10) return 'Enter exactly 10 digits';
    if (!RegExp(r'^\d{10}$').hasMatch(s)) return 'Invalid number';
    return null;
  }

  String? _vName(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Name is required';
    if (!RegExp(r'^[A-Za-z ]+$').hasMatch(s)) return 'Letters & spaces only';
    return null;
  }

  String? _validateRequired(String? v, String label) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return '$label is required';
    return null;
  }

  String? _validateLatLng(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Location is required';
    final parts = s
        .split(RegExp(r'[,\s]+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length != 2) return 'Use "lat long" (e.g., 17.385046 78.486675)';
    final lat = double.tryParse(parts[0]);
    final lon = double.tryParse(parts[1]);
    if (lat == null || lon == null) return 'Invalid coordinates';
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      return 'Coordinates out of range';
    }
    return null;
  }

  Future<void> _submitDealer() async {
    FocusScope.of(context).unfocus();
    _setError(null);

    // ── Validate employee selection ──────────────────────────────────
    if (_selectedEmployeeId == null) {
      _setError('Please select an employee or choose Self.');
      return;
    }
    // ─────────────────────────────────────────────────────────────────

    if (!_formKey.currentState!.validate()) {
      _setError('Please correct the highlighted fields.');
      return;
    }

    setState(() => _submitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final companyId = prefs.getString('companyId') ?? '';
      final selfId = prefs.getString('userId') ?? '';

      if (companyId.isEmpty || selfId.isEmpty) {
        _setError('Missing companyId/employeeId. Please re-login.');
        return;
      }

      // ── Resolve employee id ──────────────────────────────────────
      // If user chose "Self" we send the SharedPreferences userId,
      // otherwise we send the selected employee's actual id.
      final String resolvedEmployeeId = (_selectedEmployeeId == _kSelfSentinel)
          ? selfId
          : _selectedEmployeeId!;
      // ─────────────────────────────────────────────────────────────

      final body = {
        'companyId': companyId,
        'employeeId': resolvedEmployeeId, // <── uses resolved id
        'dealerName': _dealerNameCtrl.text.trim(),
        'shopName': _shopNameCtrl.text.trim(),
        'mobileNumber': _mobileCtrl.text.trim(),
        'shopAddress': _addressCtrl.text.trim(),
        'location': _locationCtrl.text.trim(),
      };

      debugPrint('🧩 [ZonalAddDealerScreen] Preparing request for queue:');
      debugPrint('│  → companyId:   $companyId');
      debugPrint(
        '│  → employeeId:  $resolvedEmployeeId (${_selectedEmployeeLabel ?? "Self"})',
      );
      debugPrint(
        '│  → Dealer: ${body['dealerName']} (${body['mobileNumber']})',
      );

      for (final e in _documents) {
        final v = e.validate();
        if (v != null) {
          _setError('Document entry error: $v');
          return;
        }
      }

      final files = await _toQueuedFiles();
      body['documentMeta'] = jsonEncode(_documentMetaForBody());

      debugPrint('🚀 [ZonalAddDealerScreen] Sending or queuing request...');
      final resp = await apiClient.sendOrQueue(
        method: HttpVerb.post,
        path: AppConfig.dealers,
        jsonBody: body,
        files: files.isEmpty ? null : files,
        optimisticOk: true,
      );

      if (resp == null) {
        debugPrint(
          '🟡 [ZonalAddDealerScreen] Queued offline — will retry automatically.',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📡 Offline – saved to queue, will auto-sync later'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(true);
        return;
      }

      debugPrint(
        '🟢 [ZonalAddDealerScreen] Server responded: HTTP ${resp.statusCode} (${resp.reasonPhrase})',
      );

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        debugPrint('✅ [ZonalAddDealerScreen] Dealer created successfully!');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dealer created successfully'),
            backgroundColor: Color(0xFF1AB69C),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(true);
        Navigator.of(context).pop(true);
        // Navigator.of(context).push(
        //   MaterialPageRoute(
        //     builder: (_) => const DealersScreen(
        //       display: true,
        //       showPendingOnStart: true,
        //       refreshOnStart: true,
        //     ),
        //   ),
        // );
      } else {
        String msg = 'HTTP ${resp.statusCode}';
        try {
          final j = jsonDecode(resp.body);
          if (j is Map && j['message'] is String) msg = j['message'];
        } catch (_) {}
        debugPrint('❌ [ZonalAddDealerScreen] Failed: $msg');
        _setError('Failed to raise dealer: $msg');
      }
    } catch (e, st) {
      debugPrint('💥 [ZonalAddDealerScreen] Exception: $e\n$st');
      _setError('Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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

  // ── Employee dropdown widget ─────────────────────────────────────────
  Widget _buildEmployeeDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
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

          // Loading shimmer / dropdown
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

          // Validation hint (shown after first submit attempt)
          if (_selectedEmployeeId == null &&
              _submitting == false &&
              _errorText != null)
            const SizedBox.shrink(),
        ],
      ),
    );
  }

  Set<String> _selectedDocTypes() {
    return _documents.map((e) => e.docType).whereType<String>().toSet();
  }
  // ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final selectedTypes = _selectedDocTypes();
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
          top: 12,
        ),
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: appGreen, width: 1.2),
                ),
              ),

              // Top error bar
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _errorText == null
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
                                _errorText!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 13.5,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => _setError(null),
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

              Row(
                children: const [
                  Text(
                    'Add Dealer',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Form(
                key: _formKey,
                child: Column(
                  children: [
                    // ── ① Employee dropdown (TOP of form) ────────────
                    _buildEmployeeDropdown(),

                    // ─────────────────────────────────────────────────
                    _field(
                      label: 'Dealer Name',
                      controller: _dealerNameCtrl,
                      inputFormatters: _lettersOnly,
                      textInputAction: TextInputAction.next,
                      validator: (v) => _validateRequired(v, 'Dealer name'),
                    ),
                    _field(
                      label: 'Shop Name',
                      controller: _shopNameCtrl,
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
                      validator: _validatePhone,
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
                    _field(
                      label: 'Shop Address',
                      controller: _addressCtrl,
                      textInputAction: TextInputAction.next,
                      maxLines: 2,
                      validator: (v) => _validateRequired(v, 'Shop address'),
                      readOnly: true,
                    ),
                    _field(
                      label: 'Location (lat long)',
                      controller: _locationCtrl,
                      hint: 'Tap "Use current location"',
                      textInputAction: TextInputAction.done,
                      validator: _validateLatLng,
                      readOnly: true,
                    ),

                    // "Use current location" button
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _submitting || _locating
                                ? null
                                : _getCurrentLocationAndTime,
                            icon: _locating
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: appGreen,
                                    ),
                                  )
                                : Icon(Icons.my_location, color: appGreen),
                            label: Text(
                              _locating
                                  ? 'Getting location...'
                                  : 'Use current location',
                              style: TextStyle(color: appGreen),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: appGreen, width: 1.2),
                              foregroundColor: appGreen,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const SizedBox(height: 8),

                    // Documents header
                    Row(
                      children: [
                        const Text(
                          'Documents',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: _submitting || _documents.length >= 5
                              ? null
                              : _addDocument,
                          icon: Icon(Icons.add, color: appGreen),
                          label: Text(
                            'Add File',
                            style: TextStyle(color: appGreen),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: appGreen, width: 1.2),
                            foregroundColor: appGreen,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Document entry rows
                    Column(
                      children: List.generate(_documents.length, (i) {
                        final entry = _documents[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: entry.file != null
                                  ? [
                                      appGreen.withValues(alpha: 0.12),
                                      appGreen.withValues(alpha: 0.04),
                                    ]
                                  : [Colors.white, const Color(0xFFF5F7FA)],
                            ),
                            border: Border.all(
                              color: entry.file != null
                                  ? appGreen.withValues(alpha: 0.6)
                                  : Colors.black12,
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 14,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Document type dropdown
                              MenuAnchor(
                                childFocusNode: FocusNode(),
                                builder: (context, controller, _) {
                                  final isOpen = controller.isOpen;
                                  return InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () => isOpen
                                        ? controller.close()
                                        : controller.open(),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        gradient: LinearGradient(
                                          colors: isOpen
                                              ? [
                                                  appGreen.withValues(
                                                    alpha: 0.12,
                                                  ),
                                                  appGreen.withValues(
                                                    alpha: 0.05,
                                                  ),
                                                ]
                                              : [Colors.white, Colors.white],
                                        ),
                                        border: Border.all(
                                          color: isOpen
                                              ? appGreen
                                              : Colors.black12,
                                          width: isOpen ? 1.6 : 1.2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.06,
                                            ),
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
                                                  appGreen.withValues(
                                                    alpha: 0.9,
                                                  ),
                                                  appGreen.withValues(
                                                    alpha: 0.6,
                                                  ),
                                                ],
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: appGreen.withValues(
                                                    alpha: 0.45,
                                                  ),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 6),
                                                ),
                                              ],
                                            ),
                                            child: const Icon(
                                              Icons.description_rounded,
                                              size: 20,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'Document Type',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.black54,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  entry.docType ??
                                                      'Select document type',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                    color: entry.docType == null
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
                                            duration: const Duration(
                                              milliseconds: 180,
                                            ),
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
                                  Builder(
                                    builder: (context) {
                                      final box =
                                          entry.docTypeKey.currentContext
                                                  ?.findRenderObject()
                                              as RenderBox?;
                                      final width = box?.size.width ?? 300;
                                      return SizedBox(
                                        width: width,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: _docTypes.map((t) {
                                            final isAlreadySelected =
                                                selectedTypes.contains(t) &&
                                                entry.docType != t;

                                            return _docTypeMenuItem(
                                              t,
                                              entry,
                                              isDisabled: isAlreadySelected,
                                            );
                                          }).toList(),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),

                              const SizedBox(height: 10),

                              // File picker row
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: _submitting || entry.docType == null
                                        ? null
                                        : () => _pickFileFor(i),
                                    child: Ink(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: entry.file == null
                                              ? [
                                                  Colors.grey.shade300,
                                                  Colors.grey.shade200,
                                                ]
                                              : [
                                                  appGreen,
                                                  appGreen.withValues(
                                                    alpha: 0.75,
                                                  ),
                                                ],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: entry.file == null
                                            ? []
                                            : [
                                                BoxShadow(
                                                  color: appGreen.withValues(
                                                    alpha: 0.35,
                                                  ),
                                                  blurRadius: 12,
                                                  offset: const Offset(0, 6),
                                                ),
                                              ],
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.upload_file,
                                              size: 18,
                                              color: entry.file == null
                                                  ? Colors.black54
                                                  : Colors.white,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              entry.file == null
                                                  ? 'Choose File'
                                                  : 'Change File',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: entry.file == null
                                                    ? Colors.black87
                                                    : Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      entry.file?.name ?? 'No file selected',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        color: entry.file != null
                                            ? Colors.black87
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove file',
                                    onPressed: _submitting
                                        ? null
                                        : () => _removeDocumentAt(i),
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 20,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),

                              if (entry.error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    entry.error!,
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submitDealer,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: appGreen,
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
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text(
                                'Save Dealer',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _docTypeMenuItem(
    String value,
    _DocumentEntry entry, {
    bool isDisabled = false,
  }) {
    final isSelected = entry.docType == value;
    final textColor = isDisabled
        ? Colors.grey
        : (isSelected ? appGreen : Colors.black87);
    return MenuItemButton(
      onPressed: isDisabled
          ? null
          : () {
              setState(() {
                entry.docType = value;
                entry.docTypeCtrl.text = value;
                entry.error = null;
              });
            },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? appGreen.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 18,
              color: isSelected ? appGreen : Colors.black54,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                style: TextStyle(fontWeight: FontWeight.w700, color: textColor),
              ),
            ),
            if (isSelected) Icon(Icons.check_circle, size: 18, color: appGreen),
          ],
        ),
      ),
    );
  }

  // --- Location state ---
  bool _locating = false;

  void safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _getCurrentLocationAndTime() async {
    _setError(null);
    safeSetState(() => _locating = true);
    debugPrint('📍 [Location] Starting location lookup...');

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      debugPrint(
        '✅ [Location] GPS acquired: '
        '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}',
      );

      String area = '';
      bool reverseDone = false;

      try {
        debugPrint('🌐 [Location] Attempting reverse geocode...');
        final placemarks = await placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        );

        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          area = [
            place.name,
            place.street,
            place.subLocality,
            place.locality,
            place.subAdministrativeArea,
            place.administrativeArea,
            place.postalCode,
            place.country,
          ].where((e) => e != null && e.trim().isNotEmpty).join(', ');
          reverseDone = true;
          debugPrint('✅ [Location] Full reverse geocode success: $area');
        }
      } catch (e) {
        debugPrint('⚠️ [Location] Reverse geocode skipped or failed: $e');
        area = '(Offline — address unavailable)';
      }

      safeSetState(() {
        _locationCtrl.text =
            '${pos.latitude.toStringAsFixed(6)} ${pos.longitude.toStringAsFixed(6)}';
        if (_addressCtrl.text.trim().isEmpty && area.isNotEmpty) {
          _addressCtrl.text = area;
        }
      });

      debugPrint(
        '📦 [Location] Fields updated:\n'
        '│ → locationCtrl: "${_locationCtrl.text}"\n'
        '│ → addressCtrl:  "${_addressCtrl.text}"\n'
        '│ → reverse lookup: ${reverseDone ? '✅ done' : '🟡 offline fallback'}',
      );
    } on PermissionDeniedException catch (_) {
      _setError('Location permission denied. Please enable it in Settings.');
      debugPrint('❌ [Location] Permission denied');
    } catch (e) {
      _setError('Error getting location: $e');
      debugPrint('❌ [Location] Unexpected error: $e');
    } finally {
      safeSetState(() => _locating = false);
      debugPrint('🏁 [Location] Done (locating=false)');
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
    int maxLines = 1,
  }) {
    final isReadOnly = readOnly == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        textInputAction: textInputAction,
        readOnly: isReadOnly,
        enableInteractiveSelection: enableInteractiveSelection,
        maxLength: maxLength,
        maxLengthEnforcement: maxLengthEnforcement,
        onChanged: onChanged,
        maxLines: maxLines,
        buildCounter:
            (_, {required currentLength, required isFocused, maxLength}) =>
                null,
        onTap: isReadOnly ? () => FocusScope.of(context).unfocus() : null,
        style: TextStyle(color: isReadOnly ? Colors.black87 : null),
        cursorColor: appGreen,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: isReadOnly
              ? Colors.grey.withValues(alpha: 0.10)
              : Colors.grey.withValues(alpha: 0.06),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          labelStyle: TextStyle(color: isReadOnly ? Colors.grey : null),
          floatingLabelStyle: TextStyle(
            color: appGreen,
            fontWeight: FontWeight.w600,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isReadOnly
                  ? Colors.grey.withValues(alpha: 0.2)
                  : appGreen.withValues(alpha: 0.5),
              width: 1.2,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: appGreen, width: 1.6),
          ),
          errorBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Colors.red),
          ),
          focusedErrorBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Colors.red),
          ),
          suffixIcon: isReadOnly
              ? const Icon(Icons.lock_rounded, size: 18, color: Colors.grey)
              : null,
        ),
      ),
    );
  }
}

// ── Extracted employee MenuAnchor widget ────────────────────────────────────
/// Keeps the main state class lean. Renders the animated dropdown that lists
/// fetched employees + a "Self" option pinned at the bottom.
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
                // Leading icon circle
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
        // ── Fetched employees ─────────────────────────────────────
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

        // ── Divider ───────────────────────────────────────────────
        if (employees.isNotEmpty)
          const Divider(height: 1, thickness: 1, indent: 12, endIndent: 12),

        // ── Self (always at the bottom) ───────────────────────────
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

/// Single row inside the employee menu.
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
