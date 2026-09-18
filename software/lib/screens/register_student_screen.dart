import 'package:flutter/material.dart';
import '../theme.dart';
import 'dart:math' as math;
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/local_db_service.dart';
import 'package:file_selector/file_selector.dart';
import 'package:csv/csv.dart';

class RegisterStudentScreen extends StatefulWidget {
  const RegisterStudentScreen({Key? key}) : super(key: key);

  @override
  State<RegisterStudentScreen> createState() => _RegisterStudentScreenState();
}

class _RegisterStudentScreenState extends State<RegisterStudentScreen> {
  final LocalDbService _localDbService = LocalDbService();
  final DatabaseService _dbService = DatabaseService();
  
  int _currentStep = 0;
  bool _waitingDevice = false;
  bool _scanComplete = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _rollNoController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _parentNameController = TextEditingController();
  final TextEditingController _parentPhoneController = TextEditingController();
  String? _selectedClass;
  String? _selectedSection;

  String _userRole = 'teacher';
  String? _teacherClassId;
  String? _teacherSection;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await _dbService.getCurrentUserProfile();
    if (mounted) {
      setState(() {
        _userRole = profile?.role ?? 'teacher';
        if (_userRole != 'admin') {
          _teacherClassId = profile?.classId;
          _teacherSection = profile?.section;
          _selectedClass = _teacherClassId; // Preset for teacher
          _selectedSection = _teacherSection; // Preset for teacher
        }
      });
    }
  }

  void _handleStartScan() {
    setState(() {
      _waitingDevice = true;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _waitingDevice = false;
          _scanComplete = true;
        });
      }
    });
  }

  bool _isUploading = false;

  Future<void> _handleCsvUpload() async {
    try {
      final XTypeGroup typeGroup = XTypeGroup(
        label: 'CSV',
        extensions: <String>['csv'],
      );
      final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);

      if (file != null) {
        setState(() => _isUploading = true);
        final fileContent = await file.readAsString();
        final normalizedContent = fileContent.replaceAll('\r\n', '\n');
        final fields = const CsvToListConverter(eol: '\n').convert(normalizedContent);

        int addedCount = 0;
        int skipCount = 0;
        bool isHeader = true;

        final classId = _userRole == 'admin' ? (_selectedClass ?? '10') : (_teacherClassId ?? '10');
        final sectionId = _userRole == 'admin' ? (_selectedSection ?? 'A') : (_teacherSection ?? 'A');
        
        final profile = await _dbService.getCurrentUserProfile();
        final teacherId = profile?.teacherId ?? profile?.uid ?? 'TEACHER001';

        if (_userRole == 'teacher') {
          // Verify that the file name matches the teacher ID (e.g. TCH1234.csv)
          final fileNameWithoutExt = file.name.split('.').first;
          if (fileNameWithoutExt.toUpperCase() != teacherId.toUpperCase()) {
            setState(() => _isUploading = false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Invalid File! Please rename the file to exactly match your Teacher ID ($teacherId).'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
            return;
          }
        }

        for (var row in fields) {
          if (row.isEmpty || row.length < 2) continue;
          
          final nameStr = row[0].toString().trim();
          final rollNoStr = row[1].toString().trim();
          final dobStr = row.length >= 3 ? row[2].toString().trim() : '';
          
          if (isHeader && nameStr.toLowerCase().contains('name')) {
            isHeader = false;
            continue;
          }
          isHeader = false;

          if (nameStr.isNotEmpty && rollNoStr.isNotEmpty) {
            final rollNo = int.tryParse(rollNoStr) ?? 0;
            
            final newStudent = Student(
              studentId: 'STU${math.Random().nextInt(9000) + 1000}',
              name: nameStr,
              rollNo: rollNo,
              fingerprintId: rollNo, // AUTOMATIC HARDWARE MAPPING
              classId: classId,
              section: sectionId,
              dob: dobStr,
              enrollDate: DateTime.now().toIso8601String().split('T')[0],
              photo: '',
              attendancePct: 100,
              templateQuality: 0,
              templateDay: 0,
              teacherId: teacherId,
              schoolId: 'SCHOOL001',
              status: 'active',
            );

            // Check duplicate
            final existingStudents = _localDbService.getAllStudents();
            final isDuplicate = existingStudents.any((s) => s.classId == classId && s.section == sectionId && s.rollNo == rollNo);

            if (!isDuplicate) {
              await _dbService.addStudent(newStudent);
              addedCount++;
            } else {
              skipCount++;
            }
          } else {
            skipCount++;
          }
        }

        if (mounted) {
          setState(() {
            _isUploading = false;
          });
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Upload Complete'),
              content: Text('Successfully registered $addedCount students.\nSkipped $skipCount invalid or duplicate rows.\n\nNote: These students have a Pending (-1) Fingerprint ID. They must be physically enrolled on the gate device later.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error parsing CSV: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.slate50,
      appBar: AppBar(
        title: const Text('Register Student', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Bulk Upload Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isUploading ? null : _handleCsvUpload,
                icon: _isUploading 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.upload_file),
                label: Text(_isUploading ? 'Uploading...' : 'Bulk Upload (CSV)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.slate800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('OR REGISTER MANUALLY', style: TextStyle(color: AppTheme.slate400, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),

            // Stepper
            _buildStepper(),
            const SizedBox(height: 24),
            
            // Step Content
            _buildStepContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepper() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          _buildStepIndicator(0, 'Info'),
          _buildStepDivider(0),
          _buildStepIndicator(1, 'Done'),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(int index, String label) {
    bool isActive = _currentStep == index;
    bool isCompleted = _currentStep > index;

    return Expanded(
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isCompleted
                  ? AppTheme.emerald500
                  : isActive
                      ? AppTheme.sky500
                      : AppTheme.slate200,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: isActive ? Colors.white : AppTheme.slate400,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
              color: isActive ? AppTheme.sky600 : AppTheme.slate400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepDivider(int index) {
    bool isCompleted = _currentStep > index;
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 20, left: 4, right: 4), // Align with circle center
        color: isCompleted ? AppTheme.emerald400 : AppTheme.slate200,
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildInfoStep();
      case 1:
        return _buildDoneStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildInfoStep() {
    return Container(
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
          const Text('Student Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.slate800)),
          const SizedBox(height: 16),
          _buildTextField('Full Name', 'Ravi Kumar Sharma', _nameController),
          const SizedBox(height: 16),
          _buildTextField('Roll Number', 'e.g. 15', _rollNoController),
          const SizedBox(height: 12),
          _buildTextField('Date of Birth', 'DD/MM/YYYY', _dobController),
          const SizedBox(height: 12),
          _buildTextField('Parent / Guardian Name', 'e.g. Ravi Kumar', _parentNameController),
          const SizedBox(height: 12),
          _buildTextField('Parent Phone Number', 'e.g. 9876543210', _parentPhoneController, keyboardType: TextInputType.phone),
          const SizedBox(height: 16),
          if (_userRole == 'admin')
          Row(
            children: [
              Expanded(
                child: _buildDropdownField('Class', ['8', '9', '10', '11'], _selectedClass, (val) => setState(() => _selectedClass = val)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdownField('Section', ['A', 'B', 'C'], _selectedSection, (val) => setState(() => _selectedSection = val)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                if (_nameController.text.isEmpty || _rollNoController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill Name and Roll Number'), backgroundColor: Colors.red),
                  );
                  return;
                }

                final rollNo = int.tryParse(_rollNoController.text) ?? 0;
                final classId = _userRole == 'admin' ? (_selectedClass ?? '10') : (_teacherClassId ?? '10');
                final sectionId = _userRole == 'admin' ? (_selectedSection ?? 'A') : (_teacherSection ?? 'A');
                
                final existingStudents = _localDbService.getAllStudents();
                final duplicate = existingStudents.where((s) => s.classId == classId && s.section == sectionId && s.rollNo == rollNo).firstOrNull;
                
                if (duplicate != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Roll No. $rollNo is already assigned to "${duplicate.name}" in Class $classId $sectionId. Please use a different roll number.'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                  return;
                }
                
                try {
                  final profile = await DatabaseService().getCurrentUserProfile();
                  final teacherId = profile?.teacherId ?? profile?.uid ?? 'TEACHER001';

                  final newStudent = Student(
                    studentId: 'STU${math.Random().nextInt(9000) + 1000}',
                    name: _nameController.text.trim(),
                    rollNo: rollNo,
                    fingerprintId: rollNo, // AUTOMATIC HARDWARE MAPPING
                    classId: classId,
                    section: sectionId,
                    dob: _dobController.text,
                    enrollDate: DateTime.now().toIso8601String().split('T')[0],
                    photo: '',
                    attendancePct: 100,
                    templateQuality: 0,
                    templateDay: 0,
                    teacherId: teacherId,
                    schoolId: 'SCHOOL001',
                    status: 'active',
                    parentName: _parentNameController.text.trim(),
                    parentPhone: _parentPhoneController.text.trim(),
                  );
                  
                  await DatabaseService().addStudent(newStudent);
                  await LocalDbService().addStudentLocal(newStudent);
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Successfully registered student!'), backgroundColor: AppTheme.emerald500),
                    );
                    setState(() => _currentStep = 1);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error saving: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.emerald500,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Register Student', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildDoneStep() {
    return Container(
      padding: const EdgeInsets.all(24),
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
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: AppTheme.emerald50,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle, color: AppTheme.emerald500, size: 40),
          ),
          const SizedBox(height: 16),
          const Text('Registration Complete!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.slate800)),
          const SizedBox(height: 4),
          const Text('Student is ready for attendance tracking', style: TextStyle(fontSize: 14, color: AppTheme.slate500)),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.slate50,
              border: Border.all(color: AppTheme.slate100),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildResultRow('Name', _nameController.text.isEmpty ? 'Ravi Kumar Sharma' : _nameController.text),
                const SizedBox(height: 10),
                _buildResultRow('Class', '${_selectedClass ?? '8'}${_selectedSection ?? 'A'}'),
                const SizedBox(height: 10),
                _buildResultRow('Fingerprint ID', 'FP-088', mono: true),
                const SizedBox(height: 10),
                _buildResultRow('Quality Score', '94%'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _currentStep = 0;
                  _scanComplete = false;
                  _waitingDevice = false;
                  _nameController.clear();
                  _dobController.clear();
                  _selectedClass = null;
                  _selectedSection = null;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.sky500,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Register Another Student', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, String placeholder, TextEditingController controller, {TextInputType keyboardType = TextInputType.text}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.slate500)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: const TextStyle(color: AppTheme.slate400),
            filled: true,
            fillColor: AppTheme.slate50,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.slate200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.slate200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.sky400),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField(String label, List<String> options, String? value, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.slate500)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppTheme.slate50,
            border: Border.all(color: AppTheme.slate200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: value,
              hint: const Text('Select', style: TextStyle(color: AppTheme.slate400)),
              items: options.map((String dropDownStringItem) {
                return DropdownMenuItem<String>(
                  value: dropDownStringItem,
                  child: Text(dropDownStringItem),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultRow(String label, String value, {bool mono = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.slate500)),
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

class FingerprintPainter extends CustomPainter {
  final bool active;

  FingerprintPainter({required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final Paint borderPaint = Paint()
      ..color = active ? const Color(0xFF0EA5E9) : const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, 39, borderPaint);

    final Paint innerPaint1 = Paint()
      ..color = active ? const Color(0xFF0EA5E9) : const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, 6, innerPaint1);

    final Paint arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    arcPaint.color = active ? const Color(0xFF0EA5E9) : const Color(0xFFCBD5E1);
    arcPaint.strokeWidth = 2.0;
    canvas.drawArc(Rect.fromCircle(center: center, radius: 13), math.pi, math.pi, false, arcPaint);

    arcPaint.color = active ? const Color(0xFF38BDF8) : const Color(0xFFE2E8F0);
    canvas.drawArc(Rect.fromCircle(center: center, radius: 18), math.pi * 0.8, math.pi * 1.4, false, arcPaint);

    arcPaint.color = active ? const Color(0xFF7DD3FC) : const Color(0xFFF1F5F9);
    arcPaint.strokeWidth = 1.5;
    canvas.drawArc(Rect.fromCircle(center: center, radius: 23), math.pi * 0.7, math.pi * 1.6, false, arcPaint);

    arcPaint.color = active ? const Color(0xFFBAE6FD) : const Color(0xFFF8FAFC);
    arcPaint.strokeWidth = 1.0;
    canvas.drawArc(Rect.fromCircle(center: center, radius: 27), math.pi * 0.6, math.pi * 1.8, false, arcPaint);

    if (active) {
      final Paint dashPaint = Paint()
        ..color = const Color(0xFF0EA5E9).withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;
      // Simple dashed circle approximation
      canvas.drawCircle(center, 29, dashPaint);
    }
  }

  @override
  bool shouldRepaint(covariant FingerprintPainter oldDelegate) {
    return oldDelegate.active != active;
  }
}
