import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/models.dart';
import '../services/local_db_service.dart';
import '../services/database_service.dart';
import '../services/app_state.dart';
import 'student_details_screen.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({Key? key}) : super(key: key);

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  final LocalDbService _localDbService = LocalDbService();
  final DatabaseService _dbService = DatabaseService();
  
  List<Student> _allStudents = [];
  List<Student> _filteredStudents = [];
  final TextEditingController _searchController = TextEditingController();
  String _selectedClass = 'All';
  String _selectedSection = 'All';
  List<String> _availableClasses = ['All'];
  List<String> _availableSections = ['All'];
  bool _isRefreshing = false;
  late VoidCallback _refreshListener;

  @override
  void initState() {
    super.initState();
    _loadStudents();
    _searchController.addListener(_applyFilters);
    
    _refreshListener = () {
      if (mounted) _loadStudents();
    };
    AppState.refreshNotifier.addListener(_refreshListener);
  }

  @override
  void dispose() {
    AppState.refreshNotifier.removeListener(_refreshListener);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    final profile = await _dbService.getCurrentUserProfile();
    final role = profile?.role ?? 'teacher'; // Fail-safe: default to least privilege
    final isTeacher = role != 'admin';
    final teacherClassId = profile?.classId;
    final teacherSection = profile?.section;

    if (!mounted) return;
    setState(() {
      var rawStudents = _localDbService.getAllStudents();
      if (isTeacher) {
        if (teacherClassId == null) {
          // Security fix: If class ID is unknown, do NOT show all students
          rawStudents = [];
        } else if (teacherClassId != 'ALL') {
          rawStudents = rawStudents.where((s) => s.classId == teacherClassId).toList();
          if (teacherSection != null && teacherSection != 'ALL') {
            rawStudents = rawStudents.where((s) => s.section == teacherSection).toList();
          }
        }
      }
      _allStudents = rawStudents;
      
      // Extract unique classes and sections
      Set<String> classes = {'All'};
      Set<String> sections = {'All'};
      for (var s in _allStudents) {
        if (s.classId.isNotEmpty) classes.add(s.classId);
        if (s.section.isNotEmpty) sections.add(s.section);
      }
      
      _availableClasses = classes.toList()..sort();
      _availableSections = sections.toList()..sort();
      
      _applyFilters();
    });
  }

  Future<void> _refreshStudents() async {
    setState(() => _isRefreshing = true);
    try {
      final cloudStudents = await _dbService.fetchAllStudents();
      // If fetch succeeds but is empty, it means they were deleted from the cloud, so clear the local DB
      await _localDbService.saveStudentRoster(cloudStudents);
      _loadStudents();
    } catch (e) {
      print('Error fetching students: $e');
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  void _applyFilters() {
    String query = _searchController.text.toLowerCase();
    setState(() {
      _filteredStudents = _allStudents.where((s) {
        bool matchesSearch = s.name.toLowerCase().contains(query) ||
               s.rollNo.toString().contains(query) ||
               s.classId.toLowerCase().contains(query);
               
        bool matchesClass = _selectedClass == 'All' || s.classId == _selectedClass;
        bool matchesSection = _selectedSection == 'All' || s.section == _selectedSection;
        
        return matchesSearch && matchesClass && matchesSection;
      }).toList();
    });
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.slate50,
      appBar: AppBar(
        title: const Text('Students', style: TextStyle(color: AppTheme.slate800, fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.download, color: AppTheme.sky600),
            onPressed: _exportCsv,
          ),
          if (_isRefreshing)
            const Center(child: Padding(padding: EdgeInsets.only(right: 16.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
          else
            IconButton(
              icon: const Icon(Icons.refresh, color: AppTheme.slate600),
              onPressed: _refreshStudents,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name, roll no...',
                    hintStyle: const TextStyle(color: AppTheme.slate400, fontSize: 14),
                    prefixIcon: const Icon(Icons.search, color: AppTheme.slate400),
                    filled: true,
                    fillColor: AppTheme.slate50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
                const SizedBox(height: 8),
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
                                _applyFilters();
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
                                _applyFilters();
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
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshStudents,
        child: _filteredStudents.isEmpty
            ? SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 48, color: AppTheme.slate300),
                  const SizedBox(height: 16),
                  Text(
                    _searchController.text.isEmpty ? 'No students found in database' : 'No students match your search',
                    style: const TextStyle(color: AppTheme.slate500),
                  ),
                ],
              ),
            ),
          ),
        )
      : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _filteredStudents.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final student = _filteredStudents[index];
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
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
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
                        radius: 24,
                        backgroundImage: student.photo.isNotEmpty
                            ? NetworkImage(student.photo)
                            : null,
                        backgroundColor: AppTheme.sky100,
                        child: student.photo.isEmpty 
                            ? Text(student.name.substring(0, 1).toUpperCase(), style: const TextStyle(color: AppTheme.sky600, fontWeight: FontWeight.bold))
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              student.name,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.slate800),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  'Class ${student.classId} ${student.section}',
                                  style: const TextStyle(fontSize: 13, color: AppTheme.slate500),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Roll: ${student.rollNo}',
                                  style: const TextStyle(fontSize: 13, color: AppTheme.slate500),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: AppTheme.slate300),
                    ],
                  ),
                ),
                );
              },
            ),
      ),
    );
  }

  Future<void> _exportCsv() async {
    try {
      if (_filteredStudents.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No students to export.'), backgroundColor: Colors.orange),
        );
        return;
      }
      
      List<List<dynamic>> rows = [];
      // Only exporting the roll number
      for (var s in _filteredStudents) {
        rows.add([s.rollNo]);
      }
      String csv = const ListToCsvConverter().convert(rows);
      
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
      
      final String fileName = _filteredStudents.isNotEmpty ? '${_filteredStudents.first.classId}_roll_numbers.csv' : 'export.csv';
      final String filePath = '${directory!.path}/$fileName';
      final file = File(filePath);
      await file.writeAsString(csv);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported ${_filteredStudents.length} roll numbers to:\n$filePath'),
            backgroundColor: AppTheme.emerald600,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
