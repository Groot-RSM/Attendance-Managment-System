import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/models.dart';
import '../services/local_db_service.dart';
import '../services/database_service.dart';
import '../services/app_state.dart';
import 'student_details_screen.dart';

class LiveAttendanceScreen extends StatefulWidget {
  const LiveAttendanceScreen({Key? key}) : super(key: key);

  @override
  State<LiveAttendanceScreen> createState() => _LiveAttendanceScreenState();
}

class _LiveAttendanceScreenState extends State<LiveAttendanceScreen> {
  final LocalDbService _localDbService = LocalDbService();
  final DatabaseService _dbService = DatabaseService();
  List<AttendanceRecord> _todayRecords = [];
  List<AttendanceRecord> _displayRecords = [];
  String _currentFilter = 'All'; // 'All', 'Present', 'Absent'
  String _selectedClass = 'All';
  String _selectedSection = 'All';
  List<String> _availableClasses = ['All'];
  List<String> _availableSections = ['All'];
  bool _isTeacher = false;
  String? _teacherClassId;
  String? _teacherSection;
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();
  late VoidCallback _refreshListener;

  @override
  void initState() {
    super.initState();
    _loadTodayAttendance();
    
    _refreshListener = () {
      if (mounted) _loadTodayAttendance();
    };
    AppState.refreshNotifier.addListener(_refreshListener);
  }

  @override
  void dispose() {
    AppState.refreshNotifier.removeListener(_refreshListener);
    super.dispose();
  }

  Future<void> _loadTodayAttendance() async {
    setState(() {
      _isLoading = true;
    });

    final profile = await _dbService.getCurrentUserProfile();
    _isTeacher = (profile?.role ?? 'teacher') != 'admin';
    if (_isTeacher) {
      _teacherClassId = profile?.classId;
      _teacherSection = profile?.section;
    } else {
      _teacherClassId = null;
      _teacherSection = null;
    }

    final now = DateTime.now();
    var allRecords = _localDbService.getAllReceivedAttendance().toList();
    try {
      final cloudRecords = await _dbService.getAttendanceForDateRange(_selectedDate, _selectedDate);
      allRecords.addAll(cloudRecords);
    } catch (e) {
      print("Failed to fetch cloud records: $e");
    }
    var allStudents = _localDbService.getAllStudents();
    
    // Filter by class/section if teacher
    if (_isTeacher) {
      if (_teacherClassId == null) {
        // Security fix: If class ID is unknown, do NOT show all students
        allStudents = [];
        allRecords = [];
      } else if (_teacherClassId != 'ALL') {
        allStudents = allStudents.where((s) => s.classId == _teacherClassId).toList();
        if (_teacherSection != null && _teacherSection != 'ALL') {
          allStudents = allStudents.where((s) => s.section == _teacherSection).toList();
        }
        final allowedFingerprints = allStudents.map((s) => s.fingerprintId).toSet();
        allRecords = allRecords.where((r) => allowedFingerprints.contains(r.fingerprintId)).toList();
      }
    }
    
    // Filter by selected date from calendar (strict day-wise reset).
    var filteredRecords = allRecords.where((record) {
      return record.timestamp.year == _selectedDate.year &&
             record.timestamp.month == _selectedDate.month &&
             record.timestamp.day == _selectedDate.day;
    }).toList();
    
    // Group by student ID and keep only the most recent scan to prevent duplicates
    Map<String, AttendanceRecord> uniqueRecords = {};
    for (var record in filteredRecords) {
      String key = record.studentId.isNotEmpty && record.studentId != 'UNKNOWN' 
          ? record.studentId 
          : record.fingerprintId.toString();
          
      if (!uniqueRecords.containsKey(key) || 
          record.timestamp.isAfter(uniqueRecords[key]!.timestamp)) {
        uniqueRecords[key] = record;
      }
    }
    
    _todayRecords = uniqueRecords.values.toList();
    
    // Sort descending by time
    _todayRecords.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    _applyFilter();
  }

  void _applyFilter() {
    var allStudents = _localDbService.getAllStudents();
    if (_isTeacher) {
      if (_teacherClassId == null) {
        // Security fix: If class ID is unknown, do NOT show all students
        allStudents = [];
      } else if (_teacherClassId != 'ALL') {
        allStudents = allStudents.where((s) => s.classId == _teacherClassId).toList();
        if (_teacherSection != null && _teacherSection != 'ALL') {
          allStudents = allStudents.where((s) => s.section == _teacherSection).toList();
        }
      }
    }
    
    // Extract available classes and sections from all students
    Set<String> classes = {'All'};
    Set<String> sections = {'All'};
    for (var s in allStudents) {
      if (s.classId.isNotEmpty) classes.add(s.classId);
      if (s.section.isNotEmpty) sections.add(s.section);
    }
    _availableClasses = classes.toList()..sort();
    _availableSections = sections.toList()..sort();

    final presentStudentIds = _todayRecords.map((r) => r.fingerprintId).toSet();
    
    List<AttendanceRecord> computedRecords = [];
    
    // Add present and absent students from the database
    computedRecords.addAll(_todayRecords);

    // If the database doesn't have an official record (Present or Absent) for a student today, 
    // dynamically generate an Absent record so the UI isn't empty before the first sync.
    final existingStudentIds = computedRecords.map((r) => r.studentId).toSet();
    final existingFingerprintIds = computedRecords.map((r) => r.fingerprintId).toSet();
    
    for (var student in allStudents) {
      if (!existingStudentIds.contains(student.studentId) && 
          !existingFingerprintIds.contains(student.fingerprintId)) {
        computedRecords.add(
          AttendanceRecord(
            eventId: 'mock_${student.studentId}',
            deviceId: 'NONE',
            fingerprintId: student.fingerprintId,
            studentId: student.studentId,
            studentName: student.name,
            photo: student.photo,
            classId: student.classId,
            timestamp: DateTime.now(),
            status: 'ABSENT',
            schoolId: student.schoolId,
            confidence: 0,
          )
        );
      }
    }

    if (!mounted) return;
    setState(() {
      if (_currentFilter == 'Present') {
        _displayRecords = computedRecords.where((r) => r.status != 'ABSENT').toList();
      } else if (_currentFilter == 'Absent') {
        _displayRecords = computedRecords.where((r) => r.status == 'ABSENT').toList();
      } else {
        _displayRecords = computedRecords;
      }
      
      // Apply class/section filters
      _displayRecords = _displayRecords.where((r) {
        bool matchesClass = _selectedClass == 'All' || r.classId == _selectedClass;
        // Lookup student section
        final student = allStudents.firstWhere(
          (s) => s.studentId == r.studentId || (s.fingerprintId > 0 && s.fingerprintId == r.fingerprintId), 
          orElse: () => Student(studentId: '', name: '', rollNo: 0, fingerprintId: 0, classId: '', section: '', dob: '', enrollDate: '', photo: '', attendancePct: 0, templateQuality: 0, templateDay: 0, teacherId: '', schoolId: '', status: '')
        );
        bool matchesSection = _selectedSection == 'All' || student.section == _selectedSection;
        
        return matchesClass && matchesSection;
      }).toList();
      
      // Sort: Present first (by time), then Absent (alphabetical)
      _displayRecords.sort((a, b) {
        if (a.status == 'ABSENT' && b.status != 'ABSENT') return 1;
        if (a.status != 'ABSENT' && b.status == 'ABSENT') return -1;
        if (a.status == 'ABSENT' && b.status == 'ABSENT') return a.studentName.compareTo(b.studentName);
        return b.timestamp.compareTo(a.timestamp);
      });
      
      _isLoading = false;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.sky500,
              onPrimary: Colors.white,
              onSurface: AppTheme.slate800,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadTodayAttendance();
    }
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    if (_selectedDate.year == now.year && _selectedDate.month == now.month && _selectedDate.day == now.day) {
      return 'Today';
    }
    return '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.slate50,
      appBar: AppBar(
        title: Text(_getFormattedDate() == 'Today' ? 'Live Attendance' : 'Attendance: ${_getFormattedDate()}', style: const TextStyle(color: AppTheme.slate800, fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month, color: AppTheme.sky500),
            onPressed: _pickDate,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.slate600),
            onPressed: _loadTodayAttendance,
          )
        ],
      ),
      body: Column(
        children: [
          // Filter Tabs & Dropdowns
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: AppTheme.slate200)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () { setState(() { _currentFilter = 'All'; _applyFilter(); }); },
                      child: _FilterChip(label: 'All', isSelected: _currentFilter == 'All'),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () { setState(() { _currentFilter = 'Present'; _applyFilter(); }); },
                      child: _FilterChip(label: 'Present', isSelected: _currentFilter == 'Present'),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () { setState(() { _currentFilter = 'Absent'; _applyFilter(); }); },
                      child: _FilterChip(label: 'Absent', isSelected: _currentFilter == 'Absent'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.slate50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedClass,
                            isExpanded: true,
                            icon: const Icon(Icons.arrow_drop_down, color: AppTheme.slate400),
                            style: const TextStyle(color: AppTheme.slate800, fontSize: 14),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setState(() => _selectedClass = newValue);
                                _applyFilter();
                              }
                            },
                            items: _availableClasses.map<DropdownMenuItem<String>>((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value == 'All' ? 'All Classes' : 'Class $value'),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.slate50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedSection,
                            isExpanded: true,
                            icon: const Icon(Icons.arrow_drop_down, color: AppTheme.slate400),
                            style: const TextStyle(color: AppTheme.slate800, fontSize: 14),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setState(() => _selectedSection = newValue);
                                _applyFilter();
                              }
                            },
                            items: _availableSections.map<DropdownMenuItem<String>>((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value == 'All' ? 'All Sections' : 'Section $value'),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _displayRecords.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.how_to_reg, size: 48, color: AppTheme.slate300),
                        const SizedBox(height: 16),
                        Text(
                          _currentFilter == 'All' ? 'No students found.' : 'No students found for this filter.',
                          style: const TextStyle(color: AppTheme.slate500),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _displayRecords.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final record = _displayRecords[index];
                      // Dynamically resolve name to fix "Unknown Student"
                      final student = _localDbService.getStudentById(record.studentId) ?? _localDbService.getStudentByFingerprint(record.fingerprintId);
                      String displayName = student?.name ?? '';
                      if (displayName.isEmpty) {
                        // For absent students or students with -1 ID, the record already has the correct name
                        if (record.studentName.isNotEmpty && !record.studentName.startsWith('ID: ')) {
                          displayName = record.studentName;
                        } else {
                          displayName = 'ID: ${record.fingerprintId}';
                        }
                      }
                      final displayPhoto = student?.photo ?? record.photo;
                      final teacherId = student?.teacherId ?? 'Unknown Teacher';

                      return InkWell(
                        onTap: () {
                          if (student != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => StudentDetailsScreen(
                                  studentId: student.studentId,
                                  onBack: () => Navigator.pop(context),
                                ),
                              ),
                            );
                          } else if (record.studentId.isNotEmpty) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => StudentDetailsScreen(
                                  studentId: record.studentId,
                                  onBack: () => Navigator.pop(context),
                                ),
                              ),
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.slate200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundImage: displayPhoto.isNotEmpty
                                  ? NetworkImage(displayPhoto)
                                  : null,
                              backgroundColor: AppTheme.slate100,
                              child: displayPhoto.isEmpty 
                                ? Text(displayName.substring(0, 1).toUpperCase(), style: const TextStyle(color: AppTheme.sky600))
                                : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(displayName, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.slate800)),
                                      const SizedBox(width: 6),
                                      Text('($teacherId)', style: const TextStyle(fontSize: 11, color: AppTheme.slate400)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      record.status == 'ABSENT' 
                                        ? const Icon(Icons.cancel, color: Colors.red, size: 16)
                                        : const Icon(Icons.check_circle, color: AppTheme.emerald500, size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        record.status == 'ABSENT' ? 'Absent' : 'Present',
                                        style: TextStyle(
                                          color: record.status == 'ABSENT' ? Colors.red : AppTheme.emerald600,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 13,
                                        ),
                                      ),
                                      if (record.status != 'ABSENT') ...[
                                        const SizedBox(width: 12),
                                        const Icon(Icons.access_time, color: AppTheme.slate400, size: 14),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${record.timestamp.hour.toString().padLeft(2, '0')}:${record.timestamp.minute.toString().padLeft(2, '0')}',
                                          style: const TextStyle(color: AppTheme.slate500, fontSize: 13),
                                        ),
                                      ]
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: record.status == 'IN' ? AppTheme.emerald500.withOpacity(0.1) : AppTheme.slate500.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                record.status == 'IN' ? 'Present' : (record.status == 'ABSENT' ? 'Absent' : 'Out'), 
                                style: TextStyle(
                                  color: record.status == 'IN' ? AppTheme.emerald500 : (record.status == 'ABSENT' ? Colors.red : AppTheme.slate600), 
                                  fontSize: 12, 
                                  fontWeight: FontWeight.w500
                                )
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;

  const _FilterChip({required this.label, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.sky500 : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isSelected ? AppTheme.sky500 : AppTheme.slate200),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : AppTheme.slate600,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          fontSize: 13,
        ),
      ),
    );
  }
}
