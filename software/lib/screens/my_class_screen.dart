import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/local_db_service.dart';
import '../services/app_state.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
class MyClassScreen extends StatefulWidget {
  const MyClassScreen({Key? key}) : super(key: key);

  @override
  State<MyClassScreen> createState() => _MyClassScreenState();
}

class _MyClassScreenState extends State<MyClassScreen> {
  final DatabaseService _dbService = DatabaseService();
  final LocalDbService _localDbService = LocalDbService();
  String? _teacherClassId;
  String? _teacherSection;
  String? _teacherId;
  String _userRole = 'teacher';
  bool _isLoading = true;
  late VoidCallback _refreshListener;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    
    _refreshListener = () {
      if (mounted) _loadProfile();
    };
    AppState.refreshNotifier.addListener(_refreshListener);
  }

  @override
  void dispose() {
    AppState.refreshNotifier.removeListener(_refreshListener);
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await _dbService.getCurrentUserProfile();
    if (mounted) {
      setState(() {
        _userRole = profile?.role ?? 'teacher'; // Fail-safe: default to least privilege
        _teacherClassId = profile?.classId;
        _teacherSection = profile?.section;
        _teacherId = profile?.teacherId ?? profile?.uid;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.slate50,
      appBar: AppBar(
        title: const Text('My Class', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_teacherClassId == null && _userRole != 'admin')
              ? const Center(
                  child: Text(
                    'You have not been assigned a class yet.',
                    style: TextStyle(color: AppTheme.slate500, fontSize: 16),
                  ),
                )
              : _buildStudentsTable(),
    );
  }

  Widget _buildStudentsTable() {
    var students = _localDbService.getAllStudents();
    if (_userRole != 'admin' && _teacherClassId != null && _teacherClassId != 'ALL') {
      students = students.where((s) => s.classId == _teacherClassId).toList();
      if (_teacherSection != null && _teacherSection != 'ALL') {
        students = students.where((s) => s.section == _teacherSection).toList();
      }
    }

    if (students.isEmpty) {
      return const Center(
        child: Text('No students found in local database.', style: TextStyle(color: AppTheme.slate500)),
      );
    }

    // Sort by Roll No
    students.sort((a, b) => a.rollNo.compareTo(b.rollNo));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.slate200),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: MaterialStateProperty.all(AppTheme.slate100),
            dataRowMinHeight: 48,
            dataRowMaxHeight: 48,
            columns: const [
              DataColumn(label: Text('Roll No', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('DOB', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Fingerprint ID', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: students.map((s) {
              final hasFingerprint = s.fingerprintId != -1;
              return DataRow(
                cells: [
                  DataCell(Text(s.rollNo.toString(), style: const TextStyle(fontWeight: FontWeight.w600))),
                  DataCell(Text(s.name)),
                  DataCell(Text(s.dob.isNotEmpty ? s.dob : '-')),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: hasFingerprint ? AppTheme.emerald50 : AppTheme.amber50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: hasFingerprint ? AppTheme.emerald100 : AppTheme.amber100),
                      ),
                      child: Text(
                        hasFingerprint ? s.fingerprintId.toString() : 'Pending',
                        style: TextStyle(
                          color: hasFingerprint ? AppTheme.emerald700 : AppTheme.amber700,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
