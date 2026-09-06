import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:file_selector/file_selector.dart';
import 'dart:io';
import '../theme.dart';
import '../services/ble_service.dart';
import '../services/biometric_service.dart';
import '../services/database_service.dart';
import 'package:path_provider/path_provider.dart';

class DeviceSyncScreen extends StatefulWidget {
  final BluetoothDevice device;
  final BleService bleService;
  final VoidCallback onSyncComplete;

  const DeviceSyncScreen({
    Key? key,
    required this.device,
    required this.bleService,
    required this.onSyncComplete,
  }) : super(key: key);

  @override
  State<DeviceSyncScreen> createState() => _DeviceSyncScreenState();
}

class _DeviceSyncScreenState extends State<DeviceSyncScreen> {
  final DatabaseService _dbService = DatabaseService();
  String _userRole = 'teacher';

  bool _isInitializing = true;
  String _statusMessage = "Initializing connection...";
  
  List<String> _availableFiles = [];
  bool _isLoadingFiles = false;
  
  String? _downloadingFile;
  String _downloadProgress = "";
  
  bool _isUploading = false;
  String _uploadProgress = "";
  
  bool _isRetraining = false;
  String _retrainProgress = "";

  Widget _buildFileList(List<String> files) {
    if (files.isEmpty) {
      return const Center(
        child: Text('No files in this category', style: TextStyle(color: AppTheme.slate400)),
      );
    }
    return ListView.separated(
      itemCount: files.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final file = files[index];
        final isDownloading = _downloadingFile == file;
        
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDownloading ? AppTheme.sky100 : AppTheme.slate200),
          ),
          child: Row(
            children: [
              Icon(
                file.contains('template') ? Icons.fingerprint : Icons.list_alt,
                color: AppTheme.slate400,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(file, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.slate800)),
                    if (isDownloading) ...[
                      const SizedBox(height: 4),
                      Text(_downloadProgress, style: const TextStyle(fontSize: 12, color: AppTheme.sky500)),
                    ]
                  ],
                ),
              ),
              if (isDownloading)
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: AppTheme.sky500, strokeWidth: 2))
              else
                IconButton(
                  icon: const Icon(Icons.download, color: AppTheme.sky500),
                  onPressed: _downloadingFile != null ? null : () => _downloadFile(file),
                  tooltip: 'Download and Sync',
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _setupConnection();
  }

  Future<void> _setupConnection() async {
    try {
      bool success = await widget.bleService.initializeUart(widget.device);
      if (!success) {
        if (mounted) {
          setState(() {
            _isInitializing = false;
            _statusMessage = "Device does not support UART service.";
          });
        }
        return;
      }
      final profile = await _dbService.getCurrentUserProfile();
      if (mounted && profile != null) {
        setState(() {
          _userRole = profile.role;
        });
      }
      
      _fetchFileList();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _statusMessage = "Error initializing: $e";
        });
      }
    }
  }

  Future<void> _fetchFileList() async {
    if (mounted) {
      setState(() {
        _isInitializing = false;
        _isLoadingFiles = true;
        _statusMessage = "Fetching available files...";
      });
    }

    try {
      List<String> files = await widget.bleService.listFiles();
      

      if (mounted) {
        setState(() {
          _availableFiles = files;
          _isLoadingFiles = false;
          _statusMessage = "Connected to ${widget.device.platformName.isNotEmpty ? widget.device.platformName : 'Gate Device'}";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingFiles = false;
          _statusMessage = "Failed to list files: $e";
        });
      }
    }
  }

  Future<void> _downloadFile(String filename) async {
    if (_downloadingFile != null) return; // Prevent concurrent downloads

    setState(() {
      _downloadingFile = filename;
      _downloadProgress = "Starting download...";
    });

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      // Small artificial delay for UX
      await Future.delayed(const Duration(milliseconds: 500));
      
      await widget.bleService.downloadFile(widget.device, filename, (progress) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress;
          });
        }
      });
      

      if (mounted) {
        setState(() {
          _downloadingFile = null;
          _statusMessage = "Successfully synced $filename!";
        });
        
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text("Synced $filename successfully!"),
            backgroundColor: AppTheme.emerald500,
          ),
        );
        
        // Notify dashboard to refresh
        widget.onSyncComplete();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadingFile = null;
          _statusMessage = "Error downloading $filename: $e";
        });
      }
    }
  }

  Future<void> _uploadCsv() async {
    if (_isUploading || _downloadingFile != null) return;
    
    try {
      const XTypeGroup typeGroup = XTypeGroup(
        label: 'csvs',
        extensions: <String>['csv'],
      );
      final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
      
      if (file == null) return; // User canceled

      setState(() {
        _isUploading = true;
        _uploadProgress = "Preparing upload...";
        _statusMessage = "Uploading ${file.name}...";
      });

      final scaffoldMessenger = ScaffoldMessenger.of(context);
      
      await widget.bleService.uploadCsvToGate(widget.device, File(file.path), (progress) {
        if (mounted) {
          setState(() {
            _uploadProgress = progress;
          });
        }
      });
      
      if (mounted) {
        setState(() {
          _isUploading = false;
          _statusMessage = "Successfully uploaded ${file.name}!";
        });
        
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text("Uploaded ${file.name} to gate!"),
            backgroundColor: AppTheme.emerald500,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _statusMessage = "Upload error: $e";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Upload failed: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _runAdaptiveRetraining() async {
    if (_isRetraining || _isUploading || _downloadingFile != null) return;
    
    setState(() {
      _isRetraining = true;
      _retrainProgress = "Finding template file...";
      _statusMessage = "Starting Adaptive Retraining...";
    });

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final dir = await getApplicationDocumentsDirectory();
    final scansFile = File('${dir.path}/all_scanned_templates.csv');
    final t0File = File('${dir.path}/template.csv');

    try {
      // Find the name of the original template file (could be template.csv or templates.csv)
      String t0Filename = 'template.csv';
      if (_availableFiles.contains('templates.csv')) {
        t0Filename = 'templates.csv';
      }

      // 1. Download original T0 templates
      if (mounted) setState(() => _retrainProgress = "Downloading $t0Filename...");
      await widget.bleService.downloadFile(widget.device, t0Filename, (progress) {
        if (mounted) setState(() => _retrainProgress = progress);
      });
      // Copy to standard name if different
      if (t0Filename != 'template.csv') {
        File('${dir.path}/$t0Filename').copySync(t0File.path);
      }

      // 2. Download the scans file
      if (mounted) setState(() => _retrainProgress = "Downloading scans...");
      await widget.bleService.downloadFile(widget.device, 'all_scanned_templates.csv', (progress) {
        if (mounted) setState(() => _retrainProgress = progress);
      });

      // 3. Run Algorithm (Dart-based medoid similarity matching)
      if (mounted) setState(() => _retrainProgress = "Finding best templates...");
      
      final bestTemplates = await BiometricService.findBestTemplates(scansFile.path, t0File.path);
      
      if (bestTemplates.isEmpty) {
        throw Exception("No valid templates found to train.");
      }

      // 3. Generate Optimized CSV
      if (mounted) setState(() => _retrainProgress = "Generating optimized CSV...");
      final optimizedFile = await BiometricService.generateOptimizedCsv(bestTemplates);

      if (mounted) {
        setState(() {
          _isRetraining = false;
          _statusMessage = "Retraining complete! Optimized ${bestTemplates.length} templates.";
        });
        
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text("Retraining complete. Ready to upload!"),
            backgroundColor: AppTheme.emerald500,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRetraining = false;
          _statusMessage = "Retraining error: $e";
        });
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text("Retraining failed: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _uploadOptimizedTemplates() async {
    if (_isRetraining || _isUploading || _downloadingFile != null) return;
    
    final dir = await getApplicationDocumentsDirectory();
    final optimizedFile = File('${dir.path}/optimized_templates.csv');

    if (!await optimizedFile.exists()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Run retraining first! Optimized file not found."), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = "Preparing to upload optimized templates...";
      _statusMessage = "Uploading optimized_templates.csv...";
    });

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    try {
      await widget.bleService.uploadCsvToGate(widget.device, optimizedFile, (progress) {
        if (mounted) setState(() => _uploadProgress = progress);
      });
      
      if (mounted) {
        setState(() {
          _isUploading = false;
          _statusMessage = "Successfully uploaded optimized templates!";
        });
        
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text("Optimized templates uploaded to gate!"),
            backgroundColor: AppTheme.emerald500,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _statusMessage = "Upload error: $e";
        });
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text("Upload failed: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool> _onWillPop() async {
    // Keep connection alive in the background
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: AppTheme.slate50,
        appBar: AppBar(
          title: const Text('Device Sync', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              await _onWillPop();
              if (mounted) Navigator.of(context).pop();
            },
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(color: AppTheme.sky50, shape: BoxShape.circle),
                      child: const Icon(Icons.bluetooth_connected, color: AppTheme.sky500),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Connection Status', style: TextStyle(fontSize: 12, color: AppTheme.slate500)),
                          const SizedBox(height: 4),
                          Text(_statusMessage, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.slate800)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              
              // Upload Section
              const Text('Upload Students to Gate', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.slate800)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.slate200),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Select the exported CSV file containing the roll numbers to program the ESP32.',
                      style: TextStyle(color: AppTheme.slate500, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (_isUploading)
                      Column(
                        children: [
                          const CircularProgressIndicator(color: AppTheme.sky500),
                          const SizedBox(height: 8),
                          Text(_uploadProgress, style: const TextStyle(color: AppTheme.sky600, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: _isInitializing || _isLoadingFiles || _downloadingFile != null ? null : _uploadCsv,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Select & Upload CSV'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.sky600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                  ],
                ),
              ),

              if (_userRole == 'admin') ...[
                const SizedBox(height: 24),

                // Adaptive Retraining Section
                const Text('Adaptive Template Retraining', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.slate800)),
                const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.sky50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.sky100),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Download recent scans and find the best fingerprint template for each student.',
                      style: TextStyle(color: AppTheme.slate600, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (_isRetraining)
                      Column(
                        children: [
                          const CircularProgressIndicator(color: AppTheme.sky500),
                          const SizedBox(height: 8),
                          Text(_retrainProgress, style: const TextStyle(color: AppTheme.sky600, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      )
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isInitializing || _isLoadingFiles || _downloadingFile != null || _isUploading ? null : _runAdaptiveRetraining,
                            icon: const Icon(Icons.psychology),
                            label: const Text('Retrain'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.sky600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: _isInitializing || _isLoadingFiles || _downloadingFile != null || _isUploading ? null : _uploadOptimizedTemplates,
                            icon: const Icon(Icons.upload),
                            label: const Text('Upload'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.emerald600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              ],

              const SizedBox(height: 32),
              const Text('Available Files', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.slate800)),
              const SizedBox(height: 16),

              if (_isInitializing || _isLoadingFiles)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: AppTheme.sky500),
                  ),
                )
              else if (_availableFiles.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_off_outlined, size: 48, color: AppTheme.slate300),
                        const SizedBox(height: 16),
                        const Text('No files found on device', style: TextStyle(color: AppTheme.slate500)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _fetchFileList,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.sky500, foregroundColor: Colors.white),
                        )
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: DefaultTabController(
                    length: 3,
                    child: Column(
                      children: [
                        const TabBar(
                          labelColor: AppTheme.sky600,
                          unselectedLabelColor: AppTheme.slate400,
                          indicatorColor: AppTheme.sky500,
                          tabs: [
                            Tab(text: 'Attendance'),
                            Tab(text: 'Templates'),
                            Tab(text: 'Scans'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildFileList(_availableFiles.where((f) => !f.contains('_scans') && !f.contains('template') && !f.contains('registered_student') && f != 'all_scanned_templates.csv').toList()),
                              _buildFileList(_availableFiles.where((f) => f.contains('template') && f != 'all_scanned_templates.csv').toList()),
                              _buildFileList(_availableFiles.where((f) => f.contains('_scans') || f == 'all_scanned_templates.csv').toList()),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
