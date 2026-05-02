import 'package:flutter/material.dart';
import 'package:FieldService_app/zonal_Screens/employee_tracking_screen.dart';
import 'package:FieldService_app/zonal_services/zonal_employees_service.dart';


class FieldTeamScreen extends StatefulWidget {
  const FieldTeamScreen({super.key});

  @override
  State<FieldTeamScreen> createState() => _FieldTeamScreenState();
}

class _FieldTeamScreenState extends State<FieldTeamScreen> {
  static const _gradientStart = Color(0xFF52D494);
  static const _gradientEnd = Color(0xFF1AB69C);
  static const _accentGreen = Color(0xFF1AB69C);
  static const _background = Color(0xFFF2F6F3);

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  late final ZonalEmployeesService _employeesService;

  List<dynamic> employees = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _employeesService = ZonalEmployeesService();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    final result = await _employeesService.fetchEmployees();

    if (!mounted) return;

    if (result.error == 'UNAUTHORIZED') {
      Navigator.pop(context); // or logout flow
      return;
    }

    if (!result.success) {
      _showSnackBar(result.error ?? 'Error');
      return;
    }

    setState(() {
      employees = result.data ?? [];
      _isLoading = false;
    });
  }

  List<dynamic> get _filtered {
    if (_searchQuery.isEmpty) return employees;

    return employees.where((e) {
      final name = (e['name'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _accentGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 2),
      ),
    );
  }


  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(child: _buildEmployeeList()),
        ],
      ),
    );
  }

  // ─── App Bar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_gradientStart, _gradientEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
          ),
          leading: Builder(
            builder: (context) => IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          title: const Text(
            'Employees',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          // actions: [
          //   Container(
          //     margin: const EdgeInsets.only(right: 12),
          //     child: IconButton(
          //       onPressed: _showFilterSheet,
          //       icon: Container(
          //         padding: const EdgeInsets.all(6),
          //         decoration: BoxDecoration(
          //           color: Colors.white.withValues(alpha: 0.18),
          //           borderRadius: BorderRadius.circular(10),
          //         ),
          //         child: const Icon(
          //           Icons.filter_list,
          //           color: Colors.white,
          //           size: 20,
          //         ),
          //       ),
          //     ),
          //   ),
          // ],
        ),
      ),
    );
  }

  // ─── Search Bar ──────────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (val) => setState(() => _searchQuery = val),
          style: const TextStyle(fontSize: 14, color: Colors.black87),
          decoration: InputDecoration(
            hintText: 'Search employees...',
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
            prefixIcon: const Icon(
              Icons.search,
              size: 20,
              color: Color(0xFF1AB69C),
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                    onPressed: () => setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                    }),
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 13,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Employee List ───────────────────────────────────────────────────────────

  Widget _buildEmployeeList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final list = _filtered;

    if (list.isEmpty) {
      return Center(child: Text('No employees found'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final e = list[index];

        return _EmployeeCard(
          employee: _EmployeeData.fromApi(e),

          // ── In FieldTeamScreen._buildEmployeeList(), replace the onTrackGps callback ──
          // ── In FieldTeamScreen._buildEmployeeList(), replace the onTrackGps callback ──
          onTrackGps: () {
            final gps = e['gps'] as Map<String, dynamic>?;

            if (gps == null ||
                gps['latitude'] == null ||
                gps['longitude'] == null) {
              _showSnackBar('No GPS data available for ${e['name']}');
              return;
            }

            // Parse gps.updatedAt from the API — this is the DEVICE timestamp,
            // not when we made the API call.
            DateTime? gpsUpdatedAt;
            try {
              final raw = gps['updatedAt'];
              if (raw != null) gpsUpdatedAt = DateTime.parse(raw).toLocal();
            } catch (_) {
              gpsUpdatedAt = null;
            }

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EmployeeTrackingScreen(
                  // Shown immediately on open (from list API response)
                  latitude: (gps['latitude'] as num).toDouble(),
                  longitude: (gps['longitude'] as num).toDouble(),

                  // Device timestamp — used as initial "Last updated" label
                  gpsUpdatedAt: gpsUpdatedAt,

                  // Used by ZonalGpsService to poll: ?search=EMP0019
                  empCode: e['empCode'] ?? '',

                  // Display info
                  name: e['name'] ?? 'Employee',
                  role: e['role'] ?? e['designation'],
                  zone: e['zone'] ?? e['region'],
                  status: e['status'] ?? 'Active',
                ),
              ),
            );
          },
          onViewProfile: () {
            final employeeId = (e['employeeId'] ?? '').toString();

            if (employeeId.isEmpty) {
              _showSnackBar('Employee ID not found');
              return;
            }

            _showEmployeeProfileSheet(employeeId);
          },
        );
      },
    );
  }

  void _showEmployeeProfileSheet(String employeeId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (_, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: FutureBuilder<EmployeeProfileResult>(
                future: _employeesService.fetchEmployeeById(employeeId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data == null) {
                    return const Center(child: Text('No employee data found'));
                  }

                  final result = snapshot.data!;

                  if (result.error == 'UNAUTHORIZED') {
                    Navigator.pop(context);
                    Navigator.pop(context);
                    return const SizedBox.shrink();
                  }

                  if (!result.success || result.data == null) {
                    return Center(
                      child: Text(result.error ?? 'Failed to load employee'),
                    );
                  }

                  final emp = result.data!;
                  final firstName = (emp['firstName'] ?? '').toString();
                  final lastName = (emp['lastName'] ?? '').toString();
                  final fullName = ('$firstName $lastName').trim().isEmpty
                      ? 'Employee'
                      : ('$firstName $lastName').trim();

                  final empCode = (emp['empCode'] ?? '').toString();
                  final email = (emp['email'] ?? '').toString();
                  final phone = (emp['contactNumber'] ?? '').toString();
                  final gender = (emp['gender'] ?? '').toString();
                  final nationality = (emp['nationality'] ?? '').toString();
                  final role = (emp['role'] ?? '').toString();
                  final department = (emp['department']?['name'] ?? '')
                      .toString();
                  final designation = (emp['designation']?['name'] ?? '')
                      .toString();
                  final shift = (emp['shift']?['name'] ?? '').toString();
                  final isActive = emp['isActive'] == true
                      ? 'Active'
                      : 'Inactive';
                  final location = (emp['currentLocation']?['updatedAt'] ?? '')
                      .toString();

                  return SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 42,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF1AB69C,
                                  ).withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    fullName.isNotEmpty ? fullName[0] : 'E',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1AB69C),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fullName,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      empCode,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF1AB69C,
                                  ).withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  isActive,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1AB69C),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const Divider(height: 1),
                          const SizedBox(height: 12),

                          Expanded(
                            child: ListView(
                              controller: scrollController,
                              children: [
                                _profileRow('Email', email),
                                _profileRow('Phone', phone),
                                _profileRow('Gender', gender),
                                _profileRow('Nationality', nationality),
                                _profileRow('Role', role),
                                _profileRow('Department', department),
                                _profileRow('Designation', designation),
                                _profileRow('Shift', shift),
                                _profileRow('Last Location Update', location),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _profileRow(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6F3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Data Model ───────────────────────────────────────────────────────────────

class _EmployeeData {
  final String name;
  final String location;
  final String status;
  final Color statusColor;
  final String visits;
  final String orders;
  final String target;

  const _EmployeeData({
    required this.name,
    required this.location,
    required this.status,
    required this.statusColor,
    required this.visits,
    required this.orders,
    required this.target,
  });

  factory _EmployeeData.fromApi(Map<String, dynamic> json) {
    String status = json['status'] ?? 'Unknown';

    Color color;
    switch (status) {
      case 'Present':
      case 'Active':
        color = const Color(0xFF1AB69C);
        break;
      case 'Absent':
        color = Colors.grey;
        break;
      default:
        color = Colors.orange;
    }

    return _EmployeeData(
      name: json['name'] ?? '',
      location: json['empCode'] ?? '', // using empCode as subtitle
      status: status,
      statusColor: color,
      visits: '${json['visits'] ?? 0}',
      orders: '${json['orders'] ?? 0}',
      target: '${json['targetPercent'] ?? 0}%',
    );
  }
}

// ─── Employee Card ────────────────────────────────────────────────────────────

class _EmployeeCard extends StatelessWidget {
  final _EmployeeData employee;
  final VoidCallback onTrackGps;
  final VoidCallback onViewProfile;

  const _EmployeeCard({
    required this.employee,
    required this.onTrackGps,
    required this.onViewProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top Row: Avatar + Name + Status ──
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF1AB69C).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    employee.name[0],
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1AB69C),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 13,
                          color: Colors.black38,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          employee.location,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: employee.statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  employee.status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: employee.statusColor,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFEEEEEE)),
          const SizedBox(height: 12),

          // ── Stats Row ──
          Row(
            children: [
              _StatItem(label: 'VISITS', value: employee.visits),
              _buildDivider(),
              _StatItem(label: 'ORDERS', value: employee.orders),
              _buildDivider(),
              _StatItem(label: 'TARGET', value: employee.target),
            ],
          ),

          const SizedBox(height: 14),

          // ── Action Buttons ──
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF1AB69C), width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    foregroundColor: const Color(0xFF1AB69C),
                  ),
                  icon: const Icon(Icons.location_on_outlined, size: 17),
                  label: const Text(
                    'Track GPS',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  onPressed: onTrackGps,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1AB69C),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  icon: const Icon(Icons.person_outline, size: 17),
                  label: const Text(
                    'View Profile',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  onPressed: onViewProfile,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 28,
      color: const Color(0xFFEEEEEE),
      margin: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
}

// ─── Stat Item ────────────────────────────────────────────────────────────────

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.grey[500],
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
