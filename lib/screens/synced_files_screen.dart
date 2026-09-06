import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../theme.dart';

class SyncedFilesScreen extends StatefulWidget {
  const SyncedFilesScreen({Key? key}) : super(key: key);

  @override
  State<SyncedFilesScreen> createState() => _SyncedFilesScreenState();
}

class _SyncedFilesScreenState extends State<SyncedFilesScreen> {
  List<FileSystemEntity> _csvFiles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final directory = await getApplicationDocumentsDirectory();
      final List<FileSystemEntity> entities = directory.listSync();
      setState(() {
        _csvFiles = entities.where((e) => e.path.endsWith('.csv')).toList();
        // Sort by modified date descending
        _csvFiles.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
        _isLoading = false;
      });
    } catch (e) {
      print("Error loading files: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _openFile(File file) async {
    try {
      String contents = await file.readAsString();
      
      if (!mounted) return;
      
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppTheme.slate200)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        file.path.split('/').last,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    )
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    contents,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reading file: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.slate50,
      appBar: AppBar(
        title: const Text('Downloaded CSV Files', style: TextStyle(color: AppTheme.slate800, fontSize: 16)),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.slate800,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppTheme.slate200, height: 1),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.sky500))
          : _csvFiles.isEmpty
              ? const Center(
                  child: Text("No CSV files downloaded yet.", style: TextStyle(color: AppTheme.slate400)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _csvFiles.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final file = _csvFiles[index] as File;
                    final filename = file.path.split('/').last;
                    final stat = file.statSync();
                    final sizeKb = (stat.size / 1024).toStringAsFixed(1);
                    
                    return InkWell(
                      onTap: () => _openFile(file),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.slate200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.description, color: AppTheme.sky500),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(filename, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text("$sizeKb KB", style: const TextStyle(fontSize: 12, color: AppTheme.slate500)),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: AppTheme.slate400),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
