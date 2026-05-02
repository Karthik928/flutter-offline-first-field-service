// lib/screens/sync_center.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../offline/queue_store.dart';
import '../offline/request_envelope.dart';
import '../offline/sync_service.dart';

class SyncCenterPage extends StatefulWidget {
  final QueueStore queueStore;
  final SyncService syncService;

  const SyncCenterPage({
    super.key,
    required this.queueStore,
    required this.syncService,
  });

  @override
  State<SyncCenterPage> createState() => _SyncCenterPageState();
}

class _SyncCenterPageState extends State<SyncCenterPage> {
  List<RequestEnvelope> _items = [];
  bool _loading = true;
  StreamSubscription<SyncEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = widget.syncService.events.listen((_) => _load());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await widget.queueStore.all();
    all.sort((a, b) {
      // newest first
      final ca = a.createdAt;
      final cb = b.createdAt;
      return cb.compareTo(ca);
    });
    setState(() {
      _items = all;
      _loading = false;
    });
  }

  Future<void> _retryNow() async {
    // Force an immediate flush of everything (ignores backoff)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Retrying now…'),
        duration: Duration(milliseconds: 800),
      ),
    );
    await widget.syncService.flush(force: true);
  }

  Future<void> _discard(String id) async {
    await widget.queueStore.remove(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Discarded'),
        duration: Duration(milliseconds: 800),
      ),
    );
    await _load();
  }

  Future<void> _copyPayload(RequestEnvelope env) async {
    final map = {
      'id': env.id,
      'method': env.method.name.toUpperCase(),
      'path': env.path,
      'headers': env.headers,
      'jsonBody': env.jsonBody,
      'files': env.files
          ?.map(
            (f) => {'field': f.field, 'filename': f.filename, 'path': f.path},
          )
          .toList(),
      'attempt': env.attempt,
      'nextAttemptAt': env.nextAttemptAt?.toIso8601String(),
      'createdAt': env.createdAt.toIso8601String(),
    };
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(map)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied payload'),
        duration: Duration(milliseconds: 800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Center'),
        actions: [
          IconButton(
            tooltip: 'Retry Now',
            icon: const Icon(Icons.refresh),
            onPressed: _items.isEmpty ? null : _retryNow,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_items.isEmpty
                ? const _Empty()
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      itemBuilder: (_, i) => _Tile(
                        env: _items[i],
                        onDiscard: () => _discard(_items[i].id),
                        onCopy: () => _copyPayload(_items[i]),
                      ),
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                    ),
                  )),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Queue is empty', style: TextStyle(color: Colors.black54)),
    );
  }
}

class _Tile extends StatelessWidget {
  final RequestEnvelope env;
  final VoidCallback onDiscard;
  final VoidCallback onCopy;

  const _Tile({
    required this.env,
    required this.onDiscard,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final next = env.nextAttemptAt;
    final created = env.createdAt;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: onCopy,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.blueGrey.shade50,
                child: Text(
                  env.method.name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.black87),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${env.method.name.toUpperCase()}  ${env.path}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Created: ${created.toLocal()}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                    if (next != null)
                      Text(
                        'Next retry: ${next.toLocal()}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                    Text(
                      'Attempt: ${env.attempt}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                    if ((env.files ?? const []).isNotEmpty)
                      Text(
                        'Files: ${env.files!.map((f) => f.filename).join(', ')}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  IconButton(
                    tooltip: 'Copy payload',
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: onCopy,
                  ),
                  IconButton(
                    tooltip: 'Discard',
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: onDiscard,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
