// lib/offline/failed_record_model.dart
//
// Persistent model for requests that exhausted all retries or were permanently
// rejected by the server.  Stored locally so the user can review them on the
// Failed Records screen.

/// High-level category used for grouping / icon selection in the UI.
enum FailedRecordType {
  tripStart,
  tripEnd,
  tripUpdate,
  fileUpload,
  shopVisit,
  orderSubmit,
  generic,
}

/// How the record died.
enum FailureReason {
  maxAttemptsReached, // exhausted retry budget
  permanentClientError, // 4xx that will never succeed
  droppedDeferredNoMapping, // TripEnd with no TripStart mapping
  authFailure, // 401 / 403
  unknown,
}

class FailedRecord {
  /// Unique id — copied from RequestEnvelope.id
  final String id;

  /// Original queue envelope id (same as [id] unless overridden)
  final String envelopeId;

  /// HTTP verb: POST / PUT / DELETE
  final String method;

  /// API path, e.g. "/api/trips" or "/api/trips/abc123/end"
  final String path;

  /// Serialised request body (may be null for DELETE)
  final Map<String, dynamic>? jsonBody;

  /// Request headers *excluding* Authorization (stripped for security)
  final Map<String, String> headers;

  /// Filenames that were attached (paths omitted — file may be gone)
  final List<String> attachedFileNames;

  /// Last HTTP status code received (0 = never reached server)
  final int lastStatusCode;

  /// Human-readable failure reason label
  final FailureReason failureReason;

  /// Free-text error detail
  final String? errorDetail;

  /// When the original request was first enqueued
  final DateTime enqueuedAt;

  /// When this record was written to the failed store
  final DateTime failedAt;

  /// How many times we tried before giving up
  final int attemptCount;

  /// Derived type — set from [path] by factory
  final FailedRecordType recordType;

  const FailedRecord({
    required this.id,
    required this.envelopeId,
    required this.method,
    required this.path,
    required this.jsonBody,
    required this.headers,
    required this.attachedFileNames,
    required this.lastStatusCode,
    required this.failureReason,
    required this.errorDetail,
    required this.enqueuedAt,
    required this.failedAt,
    required this.attemptCount,
    required this.recordType,
  });

  // ─── Serialisation ────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'id': id,
    'envelopeId': envelopeId,
    'method': method,
    'path': path,
    'jsonBody': jsonBody,
    'headers': headers,
    'attachedFileNames': attachedFileNames,
    'lastStatusCode': lastStatusCode,
    'failureReason': failureReason.name,
    'errorDetail': errorDetail,
    'enqueuedAt': enqueuedAt.toIso8601String(),
    'failedAt': failedAt.toIso8601String(),
    'attemptCount': attemptCount,
    'recordType': recordType.name,
  };

  factory FailedRecord.fromJson(Map<String, dynamic> json) {
    return FailedRecord(
      id: json['id'] as String,
      envelopeId: json['envelopeId'] as String? ?? json['id'] as String,
      method: json['method'] as String,
      path: json['path'] as String,
      jsonBody: json['jsonBody'] != null
          ? Map<String, dynamic>.from(json['jsonBody'] as Map)
          : null,
      headers: json['headers'] != null
          ? Map<String, String>.from(
              (json['headers'] as Map).map(
                (k, v) => MapEntry(k.toString(), v.toString()),
              ),
            )
          : {},
      attachedFileNames: json['attachedFileNames'] != null
          ? List<String>.from(json['attachedFileNames'] as List)
          : [],
      lastStatusCode: (json['lastStatusCode'] as num?)?.toInt() ?? 0,
      failureReason: FailureReason.values.firstWhere(
        (r) => r.name == json['failureReason'],
        orElse: () => FailureReason.unknown,
      ),
      errorDetail: json['errorDetail'] as String?,
      enqueuedAt:
          DateTime.tryParse(json['enqueuedAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
      failedAt:
          DateTime.tryParse(json['failedAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
      attemptCount: (json['attemptCount'] as num?)?.toInt() ?? 1,
      recordType: FailedRecordType.values.firstWhere(
        (t) => t.name == json['recordType'],
        orElse: () => FailedRecordType.generic,
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// Derive [FailedRecordType] from the API path and method.
  static FailedRecordType typeFromPath(String path, String method) {
    final p = path.toLowerCase();
    if (p == '/api/trips' && method.toUpperCase() == 'POST') {
      return FailedRecordType.tripStart;
    }
    if (p.contains('/api/trips') && p.endsWith('/end')) {
      return FailedRecordType.tripEnd;
    }
    if (p.contains('/api/trips') && method.toUpperCase() == 'PUT') {
      return FailedRecordType.tripUpdate;
    }
    if (p.contains('upload') || p.contains('file') || p.contains('document')) {
      return FailedRecordType.fileUpload;
    }
    if (p.contains('shop') || p.contains('visit')) {
      return FailedRecordType.shopVisit;
    }
    if (p.contains('order')) {
      return FailedRecordType.orderSubmit;
    }
    return FailedRecordType.generic;
  }

  /// Human-readable label for UI chips.
  String get typeLabel {
    switch (recordType) {
      case FailedRecordType.tripStart:
        return 'Trip Start';
      case FailedRecordType.tripEnd:
        return 'Trip End';
      case FailedRecordType.tripUpdate:
        return 'Trip Update';
      case FailedRecordType.fileUpload:
        return 'File Upload';
      case FailedRecordType.shopVisit:
        return 'Shop Visit';
      case FailedRecordType.orderSubmit:
        return 'Order Submit';
      case FailedRecordType.generic:
        return 'API Request';
    }
  }

  String get failureLabel {
    switch (failureReason) {
      case FailureReason.maxAttemptsReached:
        return 'Max retries exceeded';
      case FailureReason.permanentClientError:
        return 'Server rejected ($lastStatusCode)';
      case FailureReason.droppedDeferredNoMapping:
        return 'Trip mapping not found';
      case FailureReason.authFailure:
        return 'Authentication failed';
      case FailureReason.unknown:
        return 'Unknown error';
    }
  }

  /// Strip sensitive keys from the body for safe display.
  Map<String, dynamic> get sanitisedBody {
    if (jsonBody == null) return {};
    const hidden = {
      'password',
      'token',
      'secret',
      'authorization',
      '__localTripId',
      '__deferUntilMapped',
    };
    return Map.fromEntries(
      jsonBody!.entries.where((e) => !hidden.contains(e.key.toLowerCase())),
    );
  }

  FailedRecord copyWith({
    String? id,
    String? envelopeId,
    String? method,
    String? path,
    Map<String, dynamic>? jsonBody,
    Map<String, String>? headers,
    List<String>? attachedFileNames,
    int? lastStatusCode,
    FailureReason? failureReason,
    String? errorDetail,
    DateTime? enqueuedAt,
    DateTime? failedAt,
    int? attemptCount,
    FailedRecordType? recordType,
  }) => FailedRecord(
    id: id ?? this.id,
    envelopeId: envelopeId ?? this.envelopeId,
    method: method ?? this.method,
    path: path ?? this.path,
    jsonBody: jsonBody ?? this.jsonBody,
    headers: headers ?? this.headers,
    attachedFileNames: attachedFileNames ?? this.attachedFileNames,
    lastStatusCode: lastStatusCode ?? this.lastStatusCode,
    failureReason: failureReason ?? this.failureReason,
    errorDetail: errorDetail ?? this.errorDetail,
    enqueuedAt: enqueuedAt ?? this.enqueuedAt,
    failedAt: failedAt ?? this.failedAt,
    attemptCount: attemptCount ?? this.attemptCount,
    recordType: recordType ?? this.recordType,
  );
}
