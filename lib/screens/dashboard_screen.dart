import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import '../models/models.dart';
import 'device_management_screen.dart';
import 'device_sync_screen.dart';
import 'synced_files_screen.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../services/ble_service.dart';
import '../services/app_state.dart';
import '../widgets/ble_scanner_modal.dart';
import 'student_details_screen.dart';

class DashboardScreen extends StatefulWidget {
  DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  final LocalDbService _localDbService = LocalDbService();
  final BleService _bleService = BleService();

  List<AttendanceRecord> _offlineRecords = [];
  bool _isSimulatingBle = false;
  String? _userName;
  String? _userRole;
  String? _teacherClassId;
  String? _teacherSection;

  List<String> _adminClasses = [];
  String? _selectedAdminClassFilter;

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  StreamSubscription? _teachersSub;
  late VoidCallback _refreshListener;

  @override
  void initState() {
    super.initState();
    _loadOfflineRecords();

    _refreshListener = () {
      if (mounted) _loadOfflineRecords();
    };
    AppState.refreshNotifier.addListener(_refreshListener);
  }

  void _listenToTeachers() {
    _teachersSub?.cancel(); // Cancel any existing sub
    _teachersSub = _dbService.getTeachersStream().listen((teachers) {
      if (!mounted || _userRole != 'admin') return;

      setState(() {
        final uniqueClasses = teachers
            .where((t) =>
                t.classId != null && t.section != null && t.classId != 'ALL')
            .map((t) => '${t.classId} ${t.section}')
            .toSet()
            .toList();
        uniqueClasses.sort();
        _adminClasses = uniqueClasses;

        if (_adminClasses.isNotEmpty &&
            (_selectedAdminClassFilter == null ||
                !_adminClasses.contains(_selectedAdminClassFilter))) {
          _selectedAdminClassFilter = _adminClasses.first;
        } else if (_adminClasses.isEmpty) {
          _selectedAdminClassFilter = null;
        }
      });
    });
  }

  @override
  void dispose() {
    AppState.refreshNotifier.removeListener(_refreshListener);
    _teachersSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOfflineRecords() async {
    final profile = await _dbService.getCurrentUserProfile();

    if (mounted) {
      setState(() {
        _userName = profile?.name ?? 'User';
        _userRole = profile?.role ?? 'teacher'; // Fail-safe: default to least privilege
        if (_userRole != 'admin') {
          _teacherClassId = profile?.classId;
          _teacherSection = profile?.section;
        } else {
          _teacherClassId = null;
          _teacherSection = null;
          _listenToTeachers(); // Start listening to teachers if admin
        }

        var allRecords = _localDbService.getAllReceivedAttendance();
        var allStudents = _localDbService.getAllStudents();

        if (_userRole == 'teacher') {
          if (_teacherClassId == null) {
            // Security fix: If class ID is unknown, do NOT show all students
            allStudents = [];
            allRecords = [];
          } else if (_teacherClassId != 'ALL') {
            allStudents =
                allStudents.where((s) => s.classId == _teacherClassId).toList();
            if (_teacherSection != null && _teacherSection != 'ALL') {
              allStudents = allStudents
                  .where((s) => s.section == _teacherSection)
                  .toList();
            }
            final allowedFingerprints =
                allStudents.map((s) => s.fingerprintId).toSet();
            allRecords = allRecords
                .where((r) => allowedFingerprints.contains(r.fingerprintId))
                .toList();
          }
        } else if (_teacherClassId != null && _teacherClassId != 'ALL') {
          allStudents =
              allStudents.where((s) => s.classId == _teacherClassId).toList();
          if (_teacherSection != null && _teacherSection != 'ALL') {
            allStudents =
                allStudents.where((s) => s.section == _teacherSection).toList();
          }
          final allowedFingerprints =
              allStudents.map((s) => s.fingerprintId).toSet();
          allRecords = allRecords
              .where((r) => allowedFingerprints.contains(r.fingerprintId))
              .toList();
        }

        // Daily filter: Only count records that occurred today! (strict day-wise reset)
        final now = DateTime.now();
        var filteredRecords = allRecords.where((record) {
          return record.timestamp.year == now.year &&
              record.timestamp.month == now.month &&
              record.timestamp.day == now.day;
        }).toList();

        // Group by student ID and keep only the most recent scan to prevent duplicates
        Map<String, AttendanceRecord> uniqueRecords = {};
        for (var record in filteredRecords) {
          String key =
              record.studentId.isNotEmpty && record.studentId != 'UNKNOWN'
                  ? record.studentId
                  : record.fingerprintId.toString();

          if (!uniqueRecords.containsKey(key) ||
              record.timestamp.isAfter(uniqueRecords[key]!.timestamp)) {
            uniqueRecords[key] = record;
          }
        }

        _offlineRecords = uniqueRecords.values.toList();
      });
    }
  }

  void _showBleScanner() {
    if (_bleService.connectedDevice != null) {
      // Already connected, jump straight to Sync screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => DeviceSyncScreen(
            device: _bleService.connectedDevice!,
            bleService: _bleService,
            onSyncComplete: () {
              _loadOfflineRecords(); // Refresh the list
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'BLE Sync Complete! Records added to Recent Attendance.')),
                );
              }
            },
          ),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(modalContext).viewInsets.bottom),
        child: BleScannerModal(
          bleService: _bleService,
          onSyncComplete: () {
            _loadOfflineRecords(); // Refresh the list
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text(
                        'BLE Sync Complete! Records added to Recent Attendance.')),
              );
            }
          },
        ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good Morning,';
    } else if (hour < 17) {
      return 'Good Afternoon,';
    } else {
      return 'Good Evening,';
    }
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    const months = [
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
      'Dec'
    ];
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }

  IconData _getGreetingIcon() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return Icons.wb_sunny_outlined;
    } else if (hour < 17) {
      return Icons.wb_cloudy_outlined;
    } else {
      return Icons.nights_stay_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _authService.currentUser;

    return StreamBuilder<List<AttendanceRecord>>(
      stream: _dbService.getTodayFeedStream(),
      builder: (context, snapshot) {
        List<AttendanceRecord> todayRecords = [];
        if (snapshot.hasData) {
          final now = DateTime.now();
          todayRecords.addAll(snapshot.data!.where((r) =>
              r.timestamp.year == now.year &&
              r.timestamp.month == now.month &&
              r.timestamp.day == now.day));
        }
        todayRecords.addAll(_offlineRecords);

        // Deduplicate records
        final uniqueRecords = <String, AttendanceRecord>{};
        for (var record in todayRecords) {
          uniqueRecords[record.eventId] = record;
        }
        final feed = uniqueRecords.values.toList();

        var allStudents = _localDbService.getAllStudents();
        String currentClassIdFilter = 'ALL';
        String currentSectionFilter = 'ALL';

        if (_userRole == 'admin') {
          if (_selectedAdminClassFilter != null) {
            final parts = _selectedAdminClassFilter!.split(' ');
            if (parts.length >= 2) {
              currentClassIdFilter = parts[0];
              currentSectionFilter = parts[1];
            }
          } else {
            currentClassIdFilter = 'NONE';
          }
        } else {
          if (_teacherClassId == null) {
            currentClassIdFilter =
                'NONE'; // Security fix: If class ID is unknown, do NOT show all students
          } else {
            currentClassIdFilter = _teacherClassId!;
            currentSectionFilter = _teacherSection ?? 'ALL';
          }
        }

        if (currentClassIdFilter == 'NONE') {
          allStudents = [];
        } else if (currentClassIdFilter != 'ALL') {
          allStudents = allStudents
              .where((s) => s.classId == currentClassIdFilter)
              .toList();
          if (currentSectionFilter != 'ALL') {
            allStudents = allStudents
                .where((s) => s.section == currentSectionFilter)
                .toList();
          }
        }

        // Filter by search query
        if (_searchQuery.isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          allStudents = allStudents.where((s) {
            return s.name.toLowerCase().contains(query) ||
                s.rollNo.toString().contains(query) ||
                s.studentId.toLowerCase().contains(query);
          }).toList();
        }

        // Filter feed for this class only
        final classFeed = currentClassIdFilter == 'NONE'
            ? []
            : currentClassIdFilter != 'ALL'
                ? feed.where((r) => r.classId == currentClassIdFilter).toList()
                : feed;

        // Create a set of PRESENT student IDs
        final presentStudentIds = classFeed
            .where((r) => r.status != 'ABSENT') // DO NOT COUNT ABSENT RECORDS!
            .map((e) => e.studentId)
            .where((id) =>
                id.isNotEmpty && id != 'UNREGISTERED' && id != 'UNKNOWN')
            .toSet();

        final presentCount = presentStudentIds.length;

        final actualTotal = allStudents.length;
        final absentCount = (actualTotal - presentCount).clamp(0, actualTotal);
        final rate =
            actualTotal > 0 ? ((presentCount / actualTotal) * 100).round() : 0;
        final className = currentClassIdFilter != 'ALL'
            ? 'Class $currentClassIdFilter ${currentSectionFilter != 'ALL' ? currentSectionFilter : ''}'
                .trim()
            : 'No Classes Assigned';

        return ListView(
          padding: EdgeInsets.zero,
          children: [
            // Dark Hero Header
            Container(
              padding: const EdgeInsets.only(
                  top: 60, left: 20, right: 20, bottom: 32),
              decoration: const BoxDecoration(
                color: AppTheme.slate800,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _getGreetingIcon(),
                                color: AppTheme.sky400,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _getGreeting(),
                                style: const TextStyle(
                                    color: AppTheme.sky400,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _userName ?? 'User',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          InkWell(
                            onTap: () {
                              AppState.triggerRefresh();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Refreshing App Data...')),
                              );
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.2)),
                              ),
                              child: const Icon(Icons.refresh,
                                  color: Colors.white, size: 20),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.2)),
                            ),
                            child: const Icon(Icons.notifications_none,
                                color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.2),
                                  width: 2),
                              image: const DecorationImage(
                                image: NetworkImage(
                                    'https://i.pravatar.cc/150?u=priya'),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Device Status & Interactive Sync
                  if (_userRole == 'admin') ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Gate Device (ESP32)',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white)),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.emerald500.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('Online',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.emerald400)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _showBleScanner,
                              icon: const Icon(Icons.bluetooth_searching,
                                  size: 16),
                              label: const Text('Scan & Connect Gate Device',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.sky500,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Search Bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val;
                        });
                      },
                      decoration: InputDecoration(
                        icon: Icon(Icons.search,
                            color: Colors.white.withOpacity(0.5), size: 18),
                        hintText: 'Search students...',
                        hintStyle:
                            TextStyle(color: Colors.white.withOpacity(0.5)),
                        border: InputBorder.none,
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close,
                                    color: Colors.white70, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                  });
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'YOUR CLASS',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 8),
                  // Hero Class Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.amber400, width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          className,
                          style: const TextStyle(
                              color: AppTheme.amber400,
                              fontSize: 18,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$rate%',
                          style: const TextStyle(
                              color: AppTheme.amber400,
                              fontSize: 42,
                              fontWeight: FontWeight.w800,
                              height: 1.1),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text('$presentCount Present',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 12)),
                            Text('  •  ',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.4),
                                    fontSize: 12)),
                            Text('$actualTotal Students',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  // Admin Class Filter
                  if (_userRole == 'admin') ...[
                    SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _adminClasses.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final c = _adminClasses[index];
                          final isSelected = c == _selectedAdminClassFilter;
                          return ChoiceChip(
                            label: Text(c),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  _selectedAdminClassFilter = c;
                                });
                              }
                            },
                            selectedColor: AppTheme.amber400,
                            backgroundColor: Colors.white,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? AppTheme.slate800
                                  : AppTheme.slate600,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                            side: BorderSide(
                              color: isSelected
                                  ? AppTheme.amber400
                                  : AppTheme.slate200,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Live Class Seating Grid
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.slate800,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.adjust,
                                    color: AppTheme.sky400, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'LIVE CLASS ${currentClassIdFilter != 'ALL' ? currentClassIdFilter : 'ALL'} ${currentSectionFilter != 'ALL' ? currentSectionFilter : ''}'
                                      .trim()
                                      .toUpperCase(),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.0),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                        color: AppTheme.emerald500,
                                        shape: BoxShape.circle)),
                                const SizedBox(width: 4),
                                const Text('Live',
                                    style: TextStyle(
                                        color: AppTheme.emerald500,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 2.2,
                          ),
                          itemCount: allStudents.length,
                          itemBuilder: (context, index) {
                            final student = allStudents[index];
                            final isPresent =
                                presentStudentIds.contains(student.studentId);

                            return InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => StudentDetailsScreen(
                                      studentId: student.studentId,
                                      onBack: () => Navigator.pop(context),
                                    ),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isPresent
                                      ? AppTheme.emerald500
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isPresent
                                        ? AppTheme.emerald500
                                        : Colors.white.withOpacity(0.1),
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'A${student.rollNo.toString().padLeft(2, '0')}',
                                      style: TextStyle(
                                        color: isPresent
                                            ? Colors.white
                                            : Colors.white.withOpacity(0.5),
                                        fontSize: 10,
                                      ),
                                    ),
                                    Text(
                                      student.name.split(' ').first,
                                      style: TextStyle(
                                        color: isPresent
                                            ? Colors.white
                                            : Colors.white.withOpacity(0.5),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        if (allStudents.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                                child: Text('No students found in this class.',
                                    style: TextStyle(color: Colors.white54))),
                          ),
                        const SizedBox(height: 24),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  color: Colors.white.withOpacity(0.5),
                                  size: 14),
                              const SizedBox(width: 8),
                              Text(
                                'Seats fill automatically as students enter.',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
