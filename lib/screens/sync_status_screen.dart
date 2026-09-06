import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/models.dart';
import '../services/ble_service.dart';
import 'dart:async';

class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({Key? key}) : super(key: key);

  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  bool _syncing = false;
  bool _synced = false;
  List<SyncRecord> _pending = List.from(pendingSyncRecords);
  
  final BleService _bleService = BleService();
  bool _isSimulatingBle = false;

  void _handleBleSimulate() async {
    setState(() {
      _isSimulatingBle = true;
    });
    
    await _bleService.simulateEsp32Sync();
    
    if (mounted) {
      setState(() {
        _isSimulatingBle = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('BLE Sync Complete! Records saved to local database.')),
      );
    }
  }

  void _handleSync() {
    setState(() {
      _syncing = true;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _syncing = false;
          _synced = true;
          _pending.clear();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isAllSynced = _synced || _pending.isEmpty;

    return Scaffold(
      backgroundColor: AppTheme.slate50,
      appBar: AppBar(
        title: const Text('Sync Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isAllSynced ? AppTheme.emerald50 : AppTheme.amber50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isAllSynced ? AppTheme.emerald100 : AppTheme.amber100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isAllSynced ? Icons.check_circle : Icons.wifi_off,
                    color: isAllSynced ? AppTheme.emerald600 : AppTheme.amber600,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAllSynced ? 'All Synced to Supabase' : '${_pending.length} Records Pending',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isAllSynced ? AppTheme.emerald700 : AppTheme.amber700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isAllSynced ? 'Last sync: just now' : 'Last sync: 2h 41m ago · Offline mode',
                        style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // BLE Device Sync Section
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.bluetooth, size: 16, color: AppTheme.sky500),
                    SizedBox(width: 8),
                    Text('Bluetooth Device Sync', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.slate700)),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Connect to the gate device to pull offline attendance records into your phone.', style: TextStyle(fontSize: 12, color: AppTheme.slate500)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSimulatingBle ? null : _handleBleSimulate,
                    icon: _isSimulatingBle
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.bluetooth_searching, size: 16),
                    label: Text(_isSimulatingBle ? 'Receiving BLE stream...' : 'Simulate ESP32 Sync', style: const TextStyle(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.slate800,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppTheme.slate400,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Queue
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.storage, size: 16, color: AppTheme.slate400),
                        SizedBox(width: 8),
                        Text('Local Queue (SQLite)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.slate700)),
                      ],
                    ),
                    Text('${_pending.length} pending', style: const TextStyle(fontSize: 12, fontFamily: 'Courier', color: AppTheme.slate400)),
                  ],
                ),
                const SizedBox(height: 16),

                if (_pending.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    alignment: Alignment.center,
                    child: Column(
                      children: const [
                        Icon(Icons.check_circle, size: 32, color: AppTheme.emerald400),
                        SizedBox(height: 8),
                        Text('Queue is empty', style: TextStyle(fontSize: 14, color: AppTheme.slate400)),
                      ],
                    ),
                  )
                else
                  Column(
                    children: _pending.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.slate50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: r.type == 'attendance' ? AppTheme.sky400 : Colors.purple.shade400,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                r.type == 'attendance' ? 'Attendance record' : 'Template update',
                                style: const TextStyle(fontSize: 12, color: AppTheme.slate600),
                              ),
                            ),
                            Text(r.timestamp, style: const TextStyle(fontSize: 12, color: AppTheme.slate400)),
                            const SizedBox(width: 12),
                            const Text('PENDING', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.amber600)),
                          ],
                        ),
                      ),
                    )).toList(),
                  ),
                
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (_syncing || _pending.isEmpty) ? null : _handleSync,
                    icon: _syncing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.sync, size: 16),
                    label: Text(_syncing ? 'Syncing…' : 'Sync Now', style: const TextStyle(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.sky500,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppTheme.slate400,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // History
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sync History', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.slate700)),
                const SizedBox(height: 16),
                _HistoryRow(label: 'Today 06:00', status: 'success', count: '36 records'),
                const SizedBox(height: 12),
                _HistoryRow(label: 'Yesterday 16:22', status: 'partial', count: '12 / 18 records'),
                const SizedBox(height: 12),
                _HistoryRow(label: 'Yesterday 06:00', status: 'success', count: '34 records'),
                const SizedBox(height: 12),
                _HistoryRow(label: 'Aug 15 · 06:00', status: 'failed', count: 'Network error'),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final String label;
  final String status;
  final String count;

  const _HistoryRow({required this.label, required this.status, required this.count});

  @override
  Widget build(BuildContext context) {
    Color dotColor;
    Color textColor;

    switch (status) {
      case 'success':
        dotColor = AppTheme.emerald400;
        textColor = AppTheme.emerald600;
        break;
      case 'partial':
        dotColor = AppTheme.amber400;
        textColor = AppTheme.amber600;
        break;
      case 'failed':
      default:
        dotColor = AppTheme.red400;
        textColor = AppTheme.red500;
        break;
    }

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.slate500)),
        ),
        Text(count, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textColor)),
      ],
    );
  }
}
