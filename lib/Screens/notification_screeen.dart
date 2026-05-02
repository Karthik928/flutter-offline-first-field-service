// lib/Screens/notification_page.dart
import 'package:flutter/material.dart';
//import 'package:FieldService_app/services/notifications_service';
import 'package:FieldService_app/services/notifications_service.dart'; // defines NotificationsService & AppNotification

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  NotificationPageState createState() => NotificationPageState();
}

class NotificationPageState extends State<NotificationPage> {
  //final Color appGreen = const Color(0xFF2E7D32);
  final Color appGreen = Color(0xFF1EB89C);
  final Color backgroundColor = const Color(0xFFF5F5F5);

  String selectedFilter = 'All';
  final List<String> filters = [
    'All',
    'Notices',
    'Reminders',
  ]; // Added 'Notices' filter

  bool _loading = true;
  String? _error;
  List<AppNotification> _all = [];

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list =
          await NotificationsService.fetchAll(); // returns [] on 404/missing id
      if (!mounted) return;
      // compute unread based on persisted last-seen
      final lastSeen = await NotificationsService.getLastSeen();
      final unread = list
          .where((n) => n.sent && n.createdAt.toUtc().isAfter(lastSeen.toUtc()))
          .length;

      setState(() {
        _all = list;
        _loading = false;
      });
      try {
        NotificationsService.unreadNotifier.value = unread;
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    try {
      final list = await NotificationsService.fetchAll();
      if (!mounted) return;
      final lastSeen = await NotificationsService.getLastSeen();
      final unread = list
          .where((n) => n.sent && n.createdAt.toUtc().isAfter(lastSeen.toUtc()))
          .length;
      setState(() {
        _all = list;
        _error = null;
      });
      try {
        NotificationsService.unreadNotifier.value = unread;
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  List<AppNotification> get _filtered {
    final now = DateTime.now();
    bool isToday(DateTime dt) =>
        dt.year == now.year && dt.month == now.month && dt.day == now.day;

    switch (selectedFilter) {
      case 'Reminders':
        return _all.where((n) {
          if (_isNotice(n)) return false;
          if (n.sent) return false;
          return isToday(n.sendAt.toLocal());
        }).toList();

      case 'Notices':
        return _all.where(_isNotice).toList();

      case 'All':
        return _all.where((n) {
          // hide notices from All
          if (_isNotice(n)) return false;

          // allow sent notifications always
          if (n.sent) return true;

          // reminders only if today
          return isToday(n.sendAt.toLocal());
        }).toList();
      default:
        return _all;
    }
  }

  String _formatLocalDateTime(BuildContext context, DateTime utc) {
    final dt = utc.toLocal();
    const dayAbbr = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const monAbbr = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final dow = dayAbbr[(dt.weekday - 1).clamp(0, 6)];
    final mon = monAbbr[(dt.month - 1).clamp(0, 11)];

    final use24h = MediaQuery.of(context).alwaysUse24HourFormat;
    final mm = dt.minute.toString().padLeft(2, '0');
    String time;
    if (use24h) {
      final hh = dt.hour.toString().padLeft(2, '0');
      time = '$hh:$mm';
    } else {
      final isPM = dt.hour >= 12;
      var h12 = dt.hour % 12;
      if (h12 == 0) h12 = 12;
      time = '$h12:$mm ${isPM ? 'PM' : 'AM'}';
    }
    final tzAbbr = dt.timeZoneName; // e.g., IST
    return '$dow, ${dt.day} $mon ${dt.year}, $time $tzAbbr';
  }

  String _formatINR(num n) {
    final isNeg = n < 0;
    final abs = n.abs();
    final str = abs.toStringAsFixed(abs % 1 == 0 ? 0 : 2);
    final parts = str.split('.');
    var intPart = parts[0];
    final decPart = parts.length > 1 ? '.${parts[1]}' : '';

    if (intPart.length > 3) {
      final last3 = intPart.substring(intPart.length - 3);
      var rest = intPart.substring(0, intPart.length - 3);
      final buf = <String>[];
      while (rest.length > 2) {
        buf.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) buf.insert(0, rest);
      intPart = '${buf.join(',')},$last3';
    }
    return '${isNeg ? '-₹' : '₹'}$intPart$decPart';
  }

  bool _isNotice(AppNotification n) {
    final noShop = n.shopName.trim().isEmpty;
    final noAmount = n.amount == 0;
    return noShop && noAmount;
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            gradient: LinearGradient(
              colors: [
                Color(0xFF52D494), // top gradient color
                Color((0xFF1AB69C)), // bottom gradient color
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent, // must be transparent
            elevation: 0,
            automaticallyImplyLeading: false,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            title: const Text(
              'Notifications',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 20,
              ),
            ),
            centerTitle: true,
          ),
        ),
      ),

      body: Column(
        children: [
          // Filter Chips (All, Reminders)
          SizedBox(
            height: 60,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              scrollDirection: Axis.horizontal,
              itemCount: filters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final f = filters[index];
                final isSelected = selectedFilter == f;
                return FilterChip(
                  label: Text(f),
                  selected: isSelected,
                  onSelected: (_) => setState(() => selectedFilter = f),
                  selectedColor: appGreen.withValues(alpha: 0.2),
                  checkmarkColor: appGreen,
                  labelStyle: TextStyle(
                    color: isSelected ? appGreen : Colors.grey[600],
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  backgroundColor: Colors.white,
                  side: BorderSide(
                    color: isSelected ? appGreen : Colors.grey[300]!,
                    width: 1,
                  ),
                );
              },
            ),
          ),

          // Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _errorView(_error!)
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: items.isEmpty
                        ? (selectedFilter == 'Notices'
                              ? _emptyView('No notices')
                              : _emptyView())
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final n = items[i];
                              final isReminder = !n.sent;
                              final when = _formatLocalDateTime(
                                context,
                                n.sendAt,
                              );

                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: appGreen.withValues(alpha: 0.25),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.06,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _statusIcon(isReminder),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            n.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15.5,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _isNotice(n)
                                                ? 'System notice'
                                                : '${_formatINR(n.amount)} · ${n.shopName}',

                                            style: TextStyle(
                                              color: Colors.black87.withValues(
                                                alpha: 0.75,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            when,
                                            style: const TextStyle(
                                              color: Colors.black54,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                          if (n.body.trim().isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              n.body,
                                              maxLines: 5,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statusIcon(bool isReminder) {
    final bg = isReminder
        ? Colors.amber.withValues(alpha: 0.15)
        : appGreen.withValues(alpha: 0.15);
    final fg = isReminder ? Colors.amber[700]! : appGreen;
    final icon = isReminder ? Icons.schedule : Icons.mark_email_read;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: fg),
    );
  }

  Widget _emptyView([String? message]) {
    final msg = message ?? 'No Alerts';
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.5,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.notifications_off_outlined,
                  color: Colors.grey[400],
                  size: 72,
                ),
                const SizedBox(height: 16),
                Text(
                  msg,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorView(String err) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Text(
              'Failed to load notifications.\n$err',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _loadInitial,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
