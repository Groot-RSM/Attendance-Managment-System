import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:csv/csv.dart';
import '../theme.dart';
import '../services/database_service.dart';

class RegisterTeacherScreen extends StatefulWidget {
  const RegisterTeacherScreen({Key? key}) : super(key: key);

  @override
  State<RegisterTeacherScreen> createState() => _RegisterTeacherScreenState();
}

class _RegisterTeacherScreenState extends State<RegisterTeacherScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  
  bool _isSuccess = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _handleRegister() async {
    if (_nameController.text.trim().isEmpty || _emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      await DatabaseService().addTeacherWhitelist(
        _emailController.text.trim(),
        _nameController.text.trim(),
        _phoneController.text.trim(),
      );
      
      if (mounted) {
        setState(() {
          _isSuccess = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding teacher: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleCsvUpload() async {
    try {
      final XTypeGroup typeGroup = XTypeGroup(
        label: 'CSV',
        extensions: <String>['csv'],
      );
      final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);

      if (file != null) {
        setState(() => _isLoading = true);
        final fileContent = await file.readAsString();
        // Normalize line endings to ensure it parses correctly regardless of the OS that created the file
        final normalizedContent = fileContent.replaceAll('\r\n', '\n');
        final fields = const CsvToListConverter(eol: '\n').convert(normalizedContent);

        int addedCount = 0;
        int skipCount = 0;
        bool isHeader = true;

        for (var row in fields) {
          if (row.isEmpty || row.length < 2) continue;
          
          final nameStr = row[0].toString().trim();
          final emailStr = row[1].toString().trim();
          final phoneStr = row.length >= 3 ? row[2].toString().trim() : '';

          if (isHeader && nameStr.toLowerCase().contains('name')) {
            isHeader = false;
            continue;
          }
          isHeader = false;

          if (nameStr.isNotEmpty && emailStr.isNotEmpty && emailStr.contains('@')) {
            await DatabaseService().addTeacherWhitelist(emailStr, nameStr, phoneStr);
            addedCount++;
          } else {
            skipCount++;
          }
        }

        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Upload Complete'),
              content: Text('Successfully added $addedCount teachers.\nSkipped $skipCount invalid rows.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reading CSV: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.slate50,
      appBar: AppBar(
        title: const Text('Add Teacher', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        child: _isSuccess ? _buildSuccessView() : _buildFormView(),
      ),
    );
  }

  Widget _buildFormView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                const Text('Teacher Whitelist', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.slate800)),
                const SizedBox(height: 8),
                const Text(
                  'Enter the teacher\'s Google account email. Once added, they can simply sign in with Google.',
                  style: TextStyle(fontSize: 12, color: AppTheme.slate500),
                ),
                const SizedBox(height: 24),
                _buildTextField('Full Name *', 'e.g. Priya Sharma', _nameController, TextInputType.name),
                const SizedBox(height: 16),
                _buildTextField('Email Address *', 'teacher@school.com', _emailController, TextInputType.emailAddress),
                const SizedBox(height: 16),
                _buildTextField('Phone Number', 'e.g. +91 9876543210', _phoneController, TextInputType.phone),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleRegister,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.emerald500,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _isLoading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Add Teacher', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Bulk Upload Section
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.sky100),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.sky50.withOpacity(0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.file_upload_outlined, color: AppTheme.sky600, size: 20),
                    SizedBox(width: 8),
                    Text('Bulk Upload (CSV)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.slate800)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Upload a CSV file to add multiple teachers at once.\nFormat: name, email, phone',
                  style: TextStyle(fontSize: 12, color: AppTheme.slate500),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _handleCsvUpload,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Select CSV File', style: TextStyle(fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.sky600,
                      side: const BorderSide(color: AppTheme.sky600),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
            const Text('Teacher Added!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppTheme.slate800)),
            const SizedBox(height: 8),
            const Text(
              'The teacher can now log in using Google Sign-In with that email address. You can assign them to a class from the Assign Teachers menu.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.slate500),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.sky500,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, String hint, TextEditingController controller, [TextInputType keyboardType = TextInputType.text]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.slate500)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 14, color: AppTheme.slate800),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppTheme.slate300),
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
              borderSide: const BorderSide(color: AppTheme.sky500, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
