// lib/offline/request_envelope.dart
enum HttpVerb { get, post, put, delete }

class RequestEnvelope {
  final String id;                // uuid v4 (idempotency key / de-dupe on server)
  final HttpVerb method;
  String path;              // relative e.g. '/api/dealers'
  late final Map<String, String> headers;
  final Map<String, dynamic>? jsonBody;
  final List<QueuedFile>? files;  // for multipart
  final DateTime createdAt;
  int attempt;                    // retry count
  DateTime? nextAttemptAt;        // backoff scheduling
  String? authTokenSnapshot;      // token used when enqueued (for troubleshooting)

  RequestEnvelope({
    required this.id,
    required this.method,
    required this.path,
    required this.headers,
    this.jsonBody,
    this.files,
    DateTime? createdAt,
    this.attempt = 0,
    this.nextAttemptAt,
    this.authTokenSnapshot,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
    'id': id,
    'method': method.name,
    'path': path,
    'headers': headers,
    'jsonBody': jsonBody,
    'files': files?.map((f) => f.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'attempt': attempt,
    'nextAttemptAt': nextAttemptAt?.toIso8601String(),
    'authTokenSnapshot': authTokenSnapshot,
  };

  static RequestEnvelope fromJson(Map<String, dynamic> j) => RequestEnvelope(
    id: j['id'],
    method: HttpVerb.values.firstWhere((e) => e.name == j['method']),
    path: j['path'],
    headers: Map<String, String>.from(j['headers'] ?? {}),
    jsonBody: j['jsonBody'] as Map<String, dynamic>?,
    files: (j['files'] as List?)?.map((e) => QueuedFile.fromJson(Map<String, dynamic>.from(e))).toList(),
    createdAt: DateTime.parse(j['createdAt']),
    attempt: j['attempt'] ?? 0,
    nextAttemptAt: j['nextAttemptAt'] != null ? DateTime.parse(j['nextAttemptAt']) : null,
    authTokenSnapshot: j['authTokenSnapshot'],
  );
}

class QueuedFile {
  final String field;     // e.g. 'documents' or 'photos'
  final String path;      // absolute file path on device
  final String filename;  // 'photo_123.png'
  final String contentType; // 'image/png' etc.

  QueuedFile({
    required this.field,
    required this.path,
    required this.filename,
    required this.contentType,
  });

  Map<String, dynamic> toJson() => {
    'field': field,
    'path': path,
    'filename': filename,
    'contentType': contentType,
  };

  static QueuedFile fromJson(Map<String, dynamic> j) => QueuedFile(
    field: j['field'],
    path: j['path'],
    filename: j['filename'],
    contentType: j['contentType'],
  );
}
