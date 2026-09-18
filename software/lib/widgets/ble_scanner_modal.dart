import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ble_service.dart';
import '../screens/device_sync_screen.dart';
import '../theme.dart';

class BleScannerModal extends StatefulWidget {
  final BleService bleService;
  final VoidCallback onSyncComplete;

  const BleScannerModal({
    Key? key,
    required this.bleService,
    required this.onSyncComplete,
  }) : super(key: key);

  @override
  State<BleScannerModal> createState() => _BleScannerModalState();
}

class _BleScannerModalState extends State<BleScannerModal> {
  bool _isConnecting = false;
  String _statusMessage = "Scanning for devices...";
  StreamSubscription? _scanSubscription;

  @override
  void initState() {
    super.initState();
    // Start scanning as soon as the modal opens
    widget.bleService.startScan();
    
    _scanSubscription = widget.bleService.scanResults.listen((results) {
      if (_isConnecting) return;
      
      final espDevice = results.where((r) {
        final name = r.device.platformName.toUpperCase();
        return name.contains('ESP32') || name.contains('ESP 32');
      }).firstOrNull;

      if (espDevice != null) {
        _connectAndSync(espDevice.device);
      }
    });
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    widget.bleService.stopScan();
    super.dispose();
  }

  Future<void> _connectAndSync(BluetoothDevice device) async {
    widget.bleService.stopScan();
    
    setState(() {
      _isConnecting = true;
      _statusMessage = "Connecting to ${device.platformName}...";
    });

    try {
      await widget.bleService.connectToDevice(device);
      
      setState(() {
        _statusMessage = "Connected! Syncing attendance data...";
      });

      if (mounted) {
        Navigator.of(context).pop(); // Close scanner modal
        
        // Navigate to the new sync screen where user can pick files
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => DeviceSyncScreen(
              device: device,
              bleService: widget.bleService,
              onSyncComplete: widget.onSyncComplete,
            ),
          ),
        );
      }
      
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _statusMessage = "Connection failed: $e";
        });
      }
      widget.bleService.disconnectFromDevice();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(24),
        topRight: Radius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connect to ESP32 Gate Device',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.slate800),
          ),
          const SizedBox(height: 8),
          Text(
            _statusMessage,
            style: const TextStyle(fontSize: 14, color: AppTheme.slate500),
          ),
          const SizedBox(height: 24),
          
          if (_isConnecting)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(color: AppTheme.sky500),
              ),
            )
          else
            SizedBox(
              height: 300,
              child: StreamBuilder<List<ScanResult>>(
                stream: widget.bleService.scanResults,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text("Error: ${snapshot.error}"));
                  }
                  
                  final results = snapshot.data ?? [];
                  
                  // Filter to only show ESP32 gate devices
                  final displayDevices = results.where((r) {
                    final name = r.device.platformName.toUpperCase();
                    return name.contains('ESP32') || name.contains('ESP 32');
                  }).toList();

                  if (displayDevices.isEmpty) {
                    return const Center(
                      child: Text("No devices found yet. Make sure Bluetooth is on.", 
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.slate400)),
                    );
                  }

                  return ListView.separated(
                    itemCount: displayDevices.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final result = displayDevices[index];
                      final name = result.device.platformName.isNotEmpty 
                          ? result.device.platformName 
                          : 'Unknown Device';
                          
                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: AppTheme.sky50,
                          child: Icon(Icons.bluetooth, color: AppTheme.sky500),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Text(result.device.remoteId.toString(), style: const TextStyle(fontSize: 12)),
                        trailing: Text('${result.rssi} dBm', style: const TextStyle(fontSize: 12, color: AppTheme.slate400)),
                        onTap: () => _connectAndSync(result.device),
                      );
                    },
                  );
                },
              ),
            ),
            
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.slate500)),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
