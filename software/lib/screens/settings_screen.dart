import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/database_service.dart';
import '../services/local_db_service.dart';
import '../services/app_state.dart';
import '../models/models.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final Function(String) onNavigate;

  const SettingsScreen({
    Key? key,
    required this.onLogout,
    required this.onNavigate,
  }) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final DatabaseService _dbService = DatabaseService();
  UserProfile? _profile;

  Map<String, bool> _notifications = {
    'absent': true,
    'lowBattery': true,
    'syncFail': true,
    'unknown': false,
  };

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
    // Show cached profile instantly for immediate UI render
    final localDb = LocalDbService();
    final cached = localDb.getCachedUserProfile();
    final currentUid = DatabaseService().currentUserUid;
    if (cached != null && cached.uid == currentUid && mounted) {
      setState(() => _profile = cached);
    }
    // Then refresh from Firebase in background
    final p = await _dbService.getCurrentUserProfile();
    if (mounted) setState(() => _profile = p);
  }

  void _handleWipeData() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset Test Data', style: TextStyle(color: AppTheme.red600)),
        content: const Text('This will permanently delete all students, attendance records, and non-admin users from the cloud and local storage. This action cannot be undone.\n\nAre you sure you want to proceed?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.slate500)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red600, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dialogContext); // Close dialog
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (loadingContext) => const Center(child: CircularProgressIndicator(color: AppTheme.red600)),
              );
              
              try {
                await _dbService.wipeTestData();
                final localDb = await importLocalDb();
                await localDb.wipeAllLocalData();
                
                if (mounted) {
                  Navigator.pop(context); // Close loading
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Test data successfully wiped!'), backgroundColor: AppTheme.emerald500),
                  );
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context); // Close loading
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error wiping data: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Wipe Data'),
          ),
        ],
      ),
    );
  }

  // We use this tiny helper so we don't have to worry about replacing imports right now
  Future<dynamic> importLocalDb() async {
    return _localDbService;
  }
  final _localDbService = LocalDbService();

  void _showRegisterOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('What would you like to register?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.slate800)),
                const SizedBox(height: 24),
                ListTile(
                  leading: const CircleAvatar(backgroundColor: AppTheme.sky50, child: Icon(Icons.school, color: AppTheme.sky500)),
                  title: const Text('Add Student', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Register a new student to a class', style: TextStyle(fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onNavigate('register');
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const CircleAvatar(backgroundColor: AppTheme.emerald50, child: Icon(Icons.person, color: AppTheme.emerald500)),
                  title: const Text('Add Teacher', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Whitelist a teacher\'s Google account', style: TextStyle(fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onNavigate('register_teacher');
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.slate50,
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Account
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.sky400, Color(0xFF0284C7)], // sky400 to sky600
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.person, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_profile?.name ?? 'Loading...', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.slate800)),
                      Text(_profile?.email ?? '', style: const TextStyle(fontSize: 12, color: AppTheme.slate500)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.sky100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(_profile?.role == 'admin' ? 'Administrator' : 'Class Teacher', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppTheme.sky700)),
                      ),
                      if (_profile?.role != 'admin' && _profile?.teacherId != null && _profile!.teacherId!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('ID: ${_profile!.teacherId}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.slate600)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Quick Access
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('QUICK ACCESS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.slate500, letterSpacing: 1)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _QuickAccessBtn(
                        icon: Icons.person_add,
                        label: 'Add',
                        color: AppTheme.sky600,
                        bgColor: AppTheme.sky50,
                        onTap: () {
                          if (_profile?.role == 'admin') {
                            _showRegisterOptions();
                          } else {
                            widget.onNavigate('register');
                          }
                        },
                      ),
                    ),
                    if (_profile?.role == 'admin') ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: _QuickAccessBtn(
                          icon: Icons.assignment_ind,
                          label: 'Assign',
                          color: AppTheme.emerald600,
                          bgColor: AppTheme.emerald50,
                          onTap: () => widget.onNavigate('assign_teachers'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _QuickAccessBtn(
                          icon: Icons.memory,
                          label: 'Gate',
                          color: Colors.purple.shade600,
                          bgColor: Colors.purple.shade50,
                          onTap: () => widget.onNavigate('device'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _QuickAccessBtn(
                          icon: Icons.sync,
                          label: 'Sync',
                          color: AppTheme.amber600,
                          bgColor: AppTheme.amber50,
                          onTap: () => widget.onNavigate('sync'),
                        ),
                      ),
                    ] else if (_profile?.role == 'teacher') ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: _QuickAccessBtn(
                          icon: Icons.table_chart,
                          label: 'My Class',
                          color: AppTheme.amber600,
                          bgColor: AppTheme.amber50,
                          onTap: () => widget.onNavigate('my_class'),
                        ),
                      ),
                      const Spacer(),
                      const Spacer(),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // School
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
                    Icon(Icons.school, size: 16, color: AppTheme.slate400),
                    SizedBox(width: 8),
                    Text('SCHOOL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.slate500, letterSpacing: 1)),
                  ],
                ),
                const SizedBox(height: 12),
                const _SettingsRow(label: 'School Name', value: 'Vidyodaya High School'),
                const SizedBox(height: 12),
                const _SettingsRow(label: 'Academic Year', value: '2025–26'),
                const SizedBox(height: 12),
                const Text('Classes Managed', style: TextStyle(fontSize: 12, color: AppTheme.slate400)),
                const SizedBox(height: 8),
                Row(
                  children: ['8A', '8B', '9A', '9B'].map((c) => Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.sky100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(c, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.sky700)),
                    ),
                  )).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Notifications
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
                    Icon(Icons.notifications, size: 16, color: AppTheme.slate400),
                    SizedBox(width: 8),
                    Text('NOTIFICATIONS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.slate500, letterSpacing: 1)),
                  ],
                ),
                const SizedBox(height: 16),
                _SwitchRow(
                  label: 'High absence alerts',
                  value: _notifications['absent']!,
                  onChanged: (v) => setState(() => _notifications['absent'] = v),
                ),
                const SizedBox(height: 16),
                _SwitchRow(
                  label: 'Low battery warning',
                  value: _notifications['lowBattery']!,
                  onChanged: (v) => setState(() => _notifications['lowBattery'] = v),
                ),
                const SizedBox(height: 16),
                _SwitchRow(
                  label: 'Sync failure alerts',
                  value: _notifications['syncFail']!,
                  onChanged: (v) => setState(() => _notifications['syncFail'] = v),
                ),
                const SizedBox(height: 16),
                _SwitchRow(
                  label: 'Unknown fingerprint scans',
                  value: _notifications['unknown']!,
                  onChanged: (v) => setState(() => _notifications['unknown'] = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // System
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
                    Icon(Icons.security, size: 16, color: AppTheme.slate400),
                    SizedBox(width: 8),
                    Text('SYSTEM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.slate500, letterSpacing: 1)),
                  ],
                ),
                const SizedBox(height: 12),
                const _SettingsRow(label: 'App Version', value: 'v2.4.1'),
                const SizedBox(height: 12),
                const _SettingsRow(label: 'GATE-01 FW', value: 'v2.4.1'),
                const SizedBox(height: 12),
                const _SettingsRow(label: 'Supabase', value: 'vidyodaya-prod'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Help
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Column(
              children: const [
                _MenuRow(icon: Icons.help_outline, label: 'Help & Documentation'),
                Divider(height: 1, color: AppTheme.slate100),
                _MenuRow(icon: Icons.public, label: 'Contact Support'),
              ],
            ),
          ),
          // Danger Zone (Admin Only)
          if (_profile?.role == 'admin') ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.red100),
                boxShadow: [BoxShadow(color: AppTheme.red50.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.warning_amber_rounded, size: 16, color: AppTheme.red500),
                      SizedBox(width: 8),
                      Text('DANGER ZONE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.red600, letterSpacing: 1)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _handleWipeData,
                      icon: const Icon(Icons.delete_forever, size: 16),
                      label: const Text('Reset Test Data', style: TextStyle(fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.red600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Wipes all students, attendance, and teachers (keeps admin account).', style: TextStyle(fontSize: 11, color: AppTheme.slate400)),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Sign Out
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout, size: 16),
              label: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.w500)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.red50,
                foregroundColor: AppTheme.red600,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _QuickAccessBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  const _QuickAccessBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final String value;

  const _SettingsRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: AppTheme.slate500)),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.slate700)),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: AppTheme.slate700)),
        SizedBox(
          width: 44,
          height: 24,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: AppTheme.sky500,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: AppTheme.slate200,
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.slate400),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: AppTheme.slate700))),
            const Icon(Icons.chevron_right, size: 16, color: AppTheme.slate300),
          ],
        ),
      ),
    );
  }
}
