import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/models.dart';
import '../services/local_db_service.dart';
import '../services/database_service.dart';

class StudentDetailsScreen extends StatefulWidget {
  final String studentId;
  final VoidCallback onBack;

  const StudentDetailsScreen({
    Key? key,
    required this.studentId,
    required this.onBack,
  }) : super(key: key);

  @override
  State<StudentDetailsScreen> createState() => _StudentDetailsScreenState();
}

class _StudentDetailsScreenState extends State<StudentDetailsScreen> {
  final LocalDbService _localDbService = LocalDbService();
  final DatabaseService _dbService = DatabaseService();
  
  bool _isLoading = true;
  int _presentDays = 0;
  int _absentDays = 0;
  int _lateDays = 0;
  
  UserProfile? _teacherProfile;

  @override
  void initState() {
    super.initState();
    _loadRealStats();
  }
  
  Future<void> _loadRealStats() async {
    try {
      final cloudRecords = await _dbService.getStudentAttendanceHistory(widget.studentId);
      final localRecords = _localDbService.getAllReceivedAttendance()
          .where((r) => r.studentId == widget.studentId)
          .toList();
          
      // Merge records
      final allRecords = [...cloudRecords, ...localRecords];
      
      // Group by date (yyyy-MM-dd) to calculate unique working days
      Map<String, List<AttendanceRecord>> dailyRecords = {};
      for (var r in allRecords) {
        String dateKey = '${r.timestamp.year}-${r.timestamp.month.toString().padLeft(2, '0')}-${r.timestamp.day.toString().padLeft(2, '0')}';
        dailyRecords.putIfAbsent(dateKey, () => []).add(r);
      }
      
      int present = 0;
      int absent = 0;
      
      dailyRecords.forEach((date, dailyList) {
        // If they have any IN record for the day, they are present.
        bool wasPresent = dailyList.any((r) => r.status != 'ABSENT');
        if (wasPresent) {
          present++;
        } else {
          absent++;
        }
      });
      
      final allStudents = _localDbService.getAllStudents();
      final student = allStudents.firstWhere((s) => s.studentId == widget.studentId, orElse: () => allStudents.first);
      
      if (student.teacherId.isNotEmpty) {
        // Fetch teacher profile using the assigned teacherId string
        final tProfile = await _dbService.getUserProfileByTeacherId(student.teacherId);
        if (mounted) {
          setState(() => _teacherProfile = tProfile);
        }
      }

      if (mounted) {
        setState(() {
          _presentDays = present;
          _absentDays = absent;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showEditDialog(Student student) {
    final nameCtrl = TextEditingController(text: student.name);
    final rollCtrl = TextEditingController(text: student.rollNo == 0 ? '' : student.rollNo.toString());
    final classCtrl = TextEditingController(text: student.classId);
    final sectionCtrl = TextEditingController(text: student.section);
    final parentNameCtrl = TextEditingController(text: student.parentName);
    final parentPhoneCtrl = TextEditingController(text: student.parentPhone);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Student', style: TextStyle(fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: rollCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Roll Number', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: classCtrl,
                decoration: const InputDecoration(labelText: 'Class ID', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sectionCtrl,
                decoration: const InputDecoration(labelText: 'Section', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: parentNameCtrl,
                decoration: const InputDecoration(labelText: 'Parent / Guardian Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: parentPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Parent Phone Number', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.sky500, foregroundColor: Colors.white),
            onPressed: () async {
              final newRoll = int.tryParse(rollCtrl.text.trim()) ?? 0;
              final newClass = classCtrl.text.trim();
              final newSection = sectionCtrl.text.trim();

              // Duplicate roll number check (exclude current student)
              final allStudents = _localDbService.getAllStudents();
              final duplicate = allStudents.where((s) =>
                s.studentId != student.studentId &&
                s.classId == newClass &&
                s.section == newSection &&
                s.rollNo == newRoll &&
                newRoll != 0
              ).firstOrNull;

              if (duplicate != null) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Roll No. $newRoll is already assigned to "${duplicate.name}" in Class $newClass $newSection.'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 4),
                  ),
                );
                return;
              }

              final updated = Student(
                studentId: student.studentId,
                name: nameCtrl.text.trim(),
                rollNo: newRoll,
                fingerprintId: newRoll > 0 ? newRoll : student.fingerprintId,
                classId: newClass,
                section: newSection,
                dob: student.dob,
                enrollDate: student.enrollDate,
                photo: student.photo,
                attendancePct: student.attendancePct,
                templateQuality: student.templateQuality,
                templateDay: student.templateDay,
                teacherId: student.teacherId,
                schoolId: student.schoolId,
                status: student.status,
                parentName: parentNameCtrl.text.trim(),
                parentPhone: parentPhoneCtrl.text.trim(),
              );

              try {
                await _dbService.updateStudent(updated);
                await _localDbService.saveStudentRoster([
                  ...allStudents.where((s) => s.studentId != student.studentId),
                  updated,
                ]);
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Student updated successfully!'), backgroundColor: Colors.green),
                  );
                  setState(() {}); // Refresh UI
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error updating student: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allStudents = _localDbService.getAllStudents();
    final student = allStudents.firstWhere(
      (s) => s.studentId == widget.studentId,
      orElse: () => allStudents.isNotEmpty ? allStudents.first : Student(
        studentId: '',
        name: 'Not Found',
        rollNo: 0,
        fingerprintId: 0,
        classId: '',
        section: '',
        dob: '',
        enrollDate: '',
        photo: '',
        attendancePct: 0,
        templateQuality: 0,
        templateDay: 0,
        teacherId: '',
        schoolId: '',
        status: 'inactive',
      ),
    );
    
    final totalDays = _presentDays + _absentDays;
    final realPct = totalDays > 0 ? ((_presentDays / totalDays) * 100).round() : 0;
    
    final qualityColor = student.templateQuality >= 90
        ? AppTheme.emerald500
        : student.templateQuality >= 75
            ? AppTheme.amber500
            : AppTheme.red500;
    final qualityLabel = student.templateQuality >= 90
        ? 'Excellent'
        : student.templateQuality >= 75
            ? 'Good'
            : 'Poor';

    return Scaffold(
      backgroundColor: AppTheme.slate50,
      appBar: AppBar(
        backgroundColor: AppTheme.slate800,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: widget.onBack,
        ),
        title: const Text('Student Details', style: TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.white),
            tooltip: 'Edit Student',
            onPressed: () => _showEditDialog(student),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Profile Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Stack(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            image: DecorationImage(
                            image: student.photo.isNotEmpty
                                  ? NetworkImage(student.photo) as ImageProvider
                                  : const NetworkImage('https://i.pravatar.cc/150?u=fallback'),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: -4,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.emerald500,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text('Active', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(student.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.slate800)),
                          Text(student.studentId, style: const TextStyle(fontSize: 14, color: AppTheme.slate500)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: AppTheme.slate100),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _InfoRow(label: 'Class', value: '${student.classId} ${student.section}')),
                    Expanded(child: _InfoRow(label: 'Roll No.', value: student.rollNo.toString())),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _InfoRow(label: 'Fingerprint ID', value: student.fingerprintId.toString(), mono: true)),
                    Expanded(child: _InfoRow(label: 'Date of Birth', value: student.dob)),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: AppTheme.slate100),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Assigned Teacher', style: TextStyle(color: AppTheme.slate500, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                          const SizedBox(height: 4),
                          Text(_teacherProfile?.name ?? 'Not Assigned', style: const TextStyle(color: AppTheme.slate800, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Teacher ID', style: TextStyle(color: AppTheme.slate500, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                          const SizedBox(height: 4),
                          Text(_teacherProfile?.teacherId ?? (student.teacherId.isNotEmpty ? student.teacherId : 'N/A'), style: const TextStyle(color: AppTheme.slate800, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: AppTheme.slate100),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _InfoRow(label: 'Parent / Guardian', value: student.parentName.isNotEmpty ? student.parentName : 'Not provided')),
                    Expanded(child: _InfoRow(label: 'Parent Phone', value: student.parentPhone.isNotEmpty ? student.parentPhone : 'Not provided')),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),

          // Attendance Overview
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Attendance Overview', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.slate700)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    SizedBox(
                      width: 160,
                      height: 160,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Background circle (forced to fill the Stack)
                          SizedBox.expand(
                            child: CircularProgressIndicator(
                              value: 1.0,
                              strokeWidth: 22,
                              color: AppTheme.slate100,
                            ),
                          ),
                          // Foreground circle (forced to fill the Stack)
                          SizedBox.expand(
                            child: CircularProgressIndicator(
                              value: totalDays > 0 ? _presentDays / totalDays : 0,
                              strokeWidth: 22,
                              backgroundColor: Colors.transparent,
                              color: AppTheme.emerald500,
                            ),
                          ),
                          _isLoading 
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))
                            : Text('$realPct%', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: AppTheme.emerald500)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: _isLoading 
                        ? const Center(child: Text("Loading..."))
                        : Column(
                            children: [
                              _StatLine(label: 'Present Days', value: '$_presentDays', color: AppTheme.emerald500),
                              const SizedBox(height: 10),
                              _StatLine(label: 'Absent Days', value: '$_absentDays', color: AppTheme.red500),
                              const SizedBox(height: 10),
                              _StatLine(label: 'Total Active Days', value: '$totalDays', color: AppTheme.sky500),
                            ],
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.sky500,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                    child: const Text('View History', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),

          // Fingerprint Quality
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.fingerprint, size: 16, color: AppTheme.slate400),
                    const SizedBox(width: 8),
                    const Text('Fingerprint Quality', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.slate700)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('${student.templateQuality}%', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: qualityColor)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: student.templateQuality / 100,
                              backgroundColor: AppTheme.slate100,
                              color: qualityColor,
                              minHeight: 8,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.check_circle, size: 14, color: qualityColor),
                              const SizedBox(width: 6),
                              Text(qualityLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: qualityColor)),
                              const SizedBox(width: 6),
                              Text('· Day ${student.templateDay} similarity', style: const TextStyle(fontSize: 12, color: AppTheme.slate400)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;

  const _InfoRow({required this.label, required this.value, this.mono = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.slate400)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppTheme.slate800,
            fontFamily: mono ? 'Courier' : null,
          ),
        ),
      ],
    );
  }
}

class _StatLine extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatLine({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.slate500)),
          ],
        ),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}
