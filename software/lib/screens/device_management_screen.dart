import 'package:flutter/material.dart';
import '../theme.dart';
import 'dart:async';
import '../services/ble_service.dart';
import '../widgets/ble_scanner_modal.dart';

class DeviceManagementScreen extends StatefulWidget {
  const DeviceManagementScreen({Key? key}) : super(key: key);

  @override
  State<DeviceManagementScreen> createState() => _DeviceManagementScreenState();
}

class _DeviceManagementScreenState extends State<DeviceManagementScreen> {
  final BleService _bleService = BleService();
  bool _bleConnected = false;
  bool _rtcSynced = true;
  String _firmwareStatus = 'idle'; // 'idle', 'pushing', 'done'
  StreamSubscription? _bleSub;

  @override
  void initState() {
    super.initState();
    _bleConnected = _bleService.connectedDevice != null;
    _bleSub = _bleService.isConnectedStream.listen((connected) {
      if (mounted) {
        setState(() {
          _bleConnected = connected;
        });
      }
    });
  }

  @override
  void dispose() {
    _bleSub?.cancel();
    super.dispose();
  }

  void _toggleBle() {
    if (_bleConnected) {
      _bleService.disconnectFromDevice();
    } else {
      // Show scanner if disconnected
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (modalContext) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(modalContext).viewInsets.bottom),
          child: BleScannerModal(
            bleService: _bleService,
            onSyncComplete: () {},
          ),
        ),
      );
    }
  }

  void _handleFirmwarePush() {
    setState(() {
      _firmwareStatus = 'pushing';
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _firmwareStatus = 'done';
        });
      }
    });
  }

  void _syncRtc() {
    setState(() {
      _rtcSynced = false;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _rtcSynced = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.slate50,
      appBar: AppBar(
        title: const Text('Device Management', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // BLE Connection
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
                const Text('BLE Connection', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.slate700)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _bleConnected ? AppTheme.emerald50 : AppTheme.red50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _bleConnected ? AppTheme.emerald100 : AppTheme.red100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _bleConnected ? Icons.bluetooth : Icons.bluetooth_disabled,
                          color: _bleConnected ? AppTheme.emerald600 : AppTheme.red500,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'GATE-01 — ${_bleConnected ? 'Connected' : 'Disconnected'}',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _bleConnected ? AppTheme.emerald700 : AppTheme.red600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _bleConnected ? 'Signal: -62 dBm · MAC: 3C:71:BF:9A:D2:11' : 'Last seen: 08:14 today',
                              style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _toggleBle,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _bleConnected ? AppTheme.red100 : AppTheme.sky500,
                          foregroundColor: _bleConnected ? AppTheme.red600 : Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                        ),
                        child: Text(_bleConnected ? 'Disconnect' : 'Reconnect', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                ),
                if (!_bleConnected) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.slate50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Pairing steps:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.slate600)),
                        SizedBox(height: 4),
                        Text('1. Ensure GATE-01 is powered on (green LED)', style: TextStyle(fontSize: 12, color: AppTheme.slate500)),
                        Text('2. Hold BOOT button 3s until LED blinks blue', style: TextStyle(fontSize: 12, color: AppTheme.slate500)),
                        Text('3. Tap Reconnect above', style: TextStyle(fontSize: 12, color: AppTheme.slate500)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Diagnostics
          const Text('Device Diagnostics', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.slate700)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.1,
            children: [
              _DiagCard(
                icon: Icons.battery_full,
                iconColor: AppTheme.amber500,
                label: 'Battery',
                value: '82%',
                sub: '≈ 10h left',
                pct: 82,
                barColor: AppTheme.amber400,
                connected: _bleConnected,
              ),
              _DiagCard(
                icon: Icons.sd_storage,
                iconColor: AppTheme.sky500,
                label: 'SD Card',
                value: '5.2 GB',
                sub: 'of 32 GB free',
                pct: 84,
                barColor: AppTheme.sky400,
                connected: _bleConnected,
              ),
              _DiagCard(
                icon: Icons.memory,
                iconColor: Colors.purple.shade500,
                label: 'Templates',
                value: '128',
                sub: 'enrolled · R307',
                pct: 25,
                barColor: Colors.purple.shade400,
                connected: _bleConnected,
              ),
              Opacity(
                opacity: _bleConnected ? 1.0 : 0.5,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 16, color: _rtcSynced ? AppTheme.emerald500 : AppTheme.amber500),
                          const SizedBox(width: 8),
                          const Text('RTC Clock', style: TextStyle(fontSize: 12, color: AppTheme.slate500)),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        _rtcSynced ? 'Synced' : 'Syncing…',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _rtcSynced ? AppTheme.emerald600 : AppTheme.amber600),
                      ),
                      const SizedBox(height: 2),
                      const Text('DS3231 · ±2 ppm', style: TextStyle(fontSize: 12, color: AppTheme.slate400)),
                      const Spacer(),
                      InkWell(
                        onTap: _bleConnected ? _syncRtc : null,
                        child: Row(
                          children: [
                            Icon(Icons.refresh, size: 12, color: _bleConnected ? AppTheme.sky500 : AppTheme.slate300),
                            const SizedBox(width: 4),
                            Text(
                              'Sync now',
                              style: TextStyle(fontSize: 12, color: _bleConnected ? AppTheme.sky500 : AppTheme.slate300),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Template Push
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
                const Text('Adapted Template Push', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.slate700)),
                const SizedBox(height: 4),
                const Text('Push ML-optimized templates: Cloud → ESP32 → R307', style: TextStyle(fontSize: 12, color: AppTheme.slate400)),
                const SizedBox(height: 16),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Last pushed', style: TextStyle(fontSize: 12, color: AppTheme.slate400)),
                        SizedBox(height: 2),
                        Text('Aug 16 · 14:33 · 6 templates', style: TextStyle(fontSize: 12, fontFamily: 'Courier', color: AppTheme.slate600)),
                      ],
                    ),
                    Row(
                      children: const [
                        Icon(Icons.check_circle, size: 14, color: AppTheme.emerald600),
                        SizedBox(width: 4),
                        Text('Up to date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.emerald600)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (_firmwareStatus == 'pushing') ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('Pushing templates…', style: TextStyle(fontSize: 12, color: AppTheme.sky600)),
                      Text('3 / 8', style: TextStyle(fontSize: 12, fontFamily: 'Courier', color: AppTheme.slate400)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: const LinearProgressIndicator(
                      value: 0.37,
                      backgroundColor: AppTheme.slate100,
                      color: AppTheme.sky500,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (_firmwareStatus == 'done') ...[
                  Row(
                    children: const [
                      Icon(Icons.check_circle, size: 14, color: AppTheme.emerald600),
                      SizedBox(width: 6),
                      Text('8 templates pushed successfully', style: TextStyle(fontSize: 12, color: AppTheme.emerald600)),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (_bleConnected && _firmwareStatus != 'pushing') ? _handleFirmwarePush : null,
                    icon: const Icon(Icons.upload, size: 16),
                    label: const Text('Push Adapted Templates', style: TextStyle(fontWeight: FontWeight.w600)),
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
          const Center(
            child: Text('GATE-01 · ESP32-WROOM · FW v2.4.1', style: TextStyle(fontSize: 12, color: AppTheme.slate400)),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _DiagCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String sub;
  final int pct;
  final Color barColor;
  final bool connected;

  const _DiagCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.sub,
    required this.pct,
    required this.barColor,
    required this.connected,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: connected ? 1.0 : 0.5,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.slate500)),
              ],
            ),
            const Spacer(),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.slate800)),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(fontSize: 12, color: AppTheme.slate400)),
            const Spacer(),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct / 100,
                backgroundColor: AppTheme.slate100,
                color: barColor,
                minHeight: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
