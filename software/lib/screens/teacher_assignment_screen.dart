import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/models.dart';
import '../services/database_service.dart';

class TeacherAssignmentScreen extends StatefulWidget {
  const TeacherAssignmentScreen({Key? key}) : super(key: key);

  @override
  State<TeacherAssignmentScreen> createState() => _TeacherAssignmentScreenState();
}

class _TeacherAssignmentScreenState extends State<TeacherAssignmentScreen> {
  final DatabaseService _dbService = DatabaseService();

  void _showAssignmentModal(UserProfile teacher) {
    String? selectedClass = teacher.classId;
    String? selectedSection = teacher.section;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Assign Class & Section', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.slate800)),
                    const SizedBox(height: 8),
                    Text('Assigning ${teacher.name} (${teacher.email})', style: const TextStyle(color: AppTheme.slate500)),
                    const SizedBox(height: 24),
                    
                    const Text('Class', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.slate500)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.slate200),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: selectedClass,
                          hint: const Text('Select Class'),
                          items: ['8', '9', '10', '11'].map((c) => DropdownMenuItem(value: c, child: Text('Class $c'))).toList(),
                          onChanged: (val) => setState(() => selectedClass = val),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    const Text('Section', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.slate500)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.slate200),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: selectedSection,
                          hint: const Text('Select Section'),
                          items: ['A', 'B', 'C'].map((s) => DropdownMenuItem(value: s, child: Text('Section $s'))).toList(),
                          onChanged: (val) => setState(() => selectedSection = val),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isSaving ? null : () async {
                          if (selectedClass == null || selectedSection == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please select both Class and Section'), backgroundColor: Colors.red),
                            );
                            return;
                          }
                          
                          setState(() => isSaving = true);
                          
                          try {
                            await _dbService.assignTeacher(teacher.uid, selectedClass!, selectedSection!);
                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Teacher assigned successfully!'), backgroundColor: AppTheme.emerald500),
                              );
                            }
                          } catch (e) {
                            setState(() => isSaving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error assigning teacher: $e'), backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.sky500,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: isSaving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Save Assignment', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.slate50,
      appBar: AppBar(
        title: const Text('Assign Teachers', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: StreamBuilder<List<UserProfile>>(
        stream: _dbService.getTeachersStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.sky500));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error loading teachers: ${snapshot.error}'));
          }
          
          final teachers = snapshot.data ?? [];
          
          if (teachers.isEmpty) {
            return const Center(
              child: Text(
                'No teachers registered yet.\nUse "Register -> Add Teacher" to invite one.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.slate500),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: teachers.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final teacher = teachers[index];
              final isAssigned = teacher.classId != null && teacher.section != null;
              
              return InkWell(
                onTap: () => _showAssignmentModal(teacher),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.slate200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppTheme.sky50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.person, color: AppTheme.sky500),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(teacher.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.slate800)),
                            const SizedBox(height: 2),
                            Text(teacher.email, style: const TextStyle(fontSize: 12, color: AppTheme.slate500)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isAssigned ? AppTheme.emerald50 : AppTheme.amber50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isAssigned ? '${teacher.classId} ${teacher.section}' : 'Unassigned',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isAssigned ? AppTheme.emerald600 : AppTheme.amber600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
