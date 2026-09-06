import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'firebase_options.dart';
import 'theme.dart';
import 'models/models.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'services/auth_service.dart';
import 'screens/live_attendance_screen.dart';
import 'screens/students_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/student_details_screen.dart';
import 'screens/register_student_screen.dart';
import 'screens/my_class_screen.dart';
import 'screens/device_management_screen.dart';
import 'screens/sync_status_screen.dart';
import 'screens/register_teacher_screen.dart';
import 'screens/teacher_assignment_screen.dart';
import 'screens/set_password_screen.dart';
import 'services/local_db_service.dart';
import 'services/database_service.dart';
import 'services/app_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await LocalDbService().init();
  
  // TEMP: Fix existing students where fingerprintId is -1
  final rosterBox = Hive.box(LocalDbService.rosterBoxName);
  final allData = rosterBox.toMap();
  for (var key in allData.keys) {
    var map = jsonDecode(allData[key] as String);
    if (map['fingerprintId'] == -1 || map['fingerprintId'] == 0) {
      map['fingerprintId'] = map['rollNo']; // Fix the ID!
      await rosterBox.put(key, jsonEncode(map));
      
      // Also update Firebase so it stays fixed
      try {
        await FirebaseFirestore.instance
            .collection('students')
            .doc(map['studentId'])
            .update({'fingerprintId': map['rollNo']});
      } catch (e) {}
    }
  }
  
  // TEMP: Wipe FIREBASE attendance collection to clear ghost data from earlier today
  try {
    final docs = await FirebaseFirestore.instance.collection('attendance').get();
    for (var doc in docs.docs) {
      await doc.reference.delete();
    }
    print("Wiped ${docs.docs.length} ghost attendance records from Firebase!");
  } catch (e) {
    print("Failed to wipe Firebase attendance: $e");
  }

  // Initial Session Timeout Check
  final lastActive = LocalDbService().getLastActiveTime();
  if (lastActive != null) {
    if (DateTime.now().difference(lastActive).inMinutes >= 60) {
      await FirebaseAuth.instance.signOut();
    }
  }
  await LocalDbService().updateLastActiveTime();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Check timeout on resume
      final lastActive = LocalDbService().getLastActiveTime();
      if (lastActive != null && DateTime.now().difference(lastActive).inMinutes >= 60) {
        AuthService().signOut();
      }
      LocalDbService().updateLastActiveTime();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden || state == AppLifecycleState.detached) {
      // Update time when leaving app
      LocalDbService().updateLastActiveTime();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Attendance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: StreamBuilder<User?>(
        stream: AuthService().authStateChanges,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: AppTheme.sky500),
              ),
            );
          }
          if (snapshot.hasData) {
            return MainLayout(onLogout: () async {
              await AuthService().signOut();
            });
          }
          return LoginScreen(onLogin: () {});
        },
      ),
    );
  }
}

class MainLayout extends StatefulWidget {
  final VoidCallback onLogout;

  const MainLayout({Key? key, required this.onLogout}) : super(key: key);

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;
  bool _isLoading = true;
  bool _needsPassword = false;

  @override
  void initState() {
    super.initState();
    AppState.initFirebaseListener();
    _checkPasswordRequirement();
  }

  Future<void> _checkPasswordRequirement() async {
    final profile = await DatabaseService().getCurrentUserProfile();
    if (profile != null && profile.role == 'teacher' && profile.hasSetPassword != true) {
      if (mounted) {
        setState(() {
          _needsPassword = true;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _needsPassword = false;
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToInternal(String screenName) {
    Widget? screen;
    switch (screenName) {
      case 'register':
        screen = const RegisterStudentScreen();
        break;
      case 'register_teacher':
        screen = const RegisterTeacherScreen();
        break;
      case 'assign_teachers':
        screen = const TeacherAssignmentScreen();
        break;
      case 'device':
        screen = const DeviceManagementScreen();
        break;
      case 'my_class':
        screen = const MyClassScreen();
        break;
      case 'sync':
        screen = const SyncStatusScreen();
        break;
      case 'student_details':
        // For testing, just default to first student id
        screen = StudentDetailsScreen(
          studentId: 'STU0347',
          onBack: () => Navigator.pop(context),
        );
        break;
    }

    if (screen != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => screen!),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.sky500)),
      );
    }

    if (_needsPassword) {
      return SetPasswordScreen(
        onComplete: () {
          setState(() {
            _needsPassword = false;
          });
        },
      );
    }

    final List<Widget> screens = [
      // Pass the navigate callback to dashboard for its deep links
      DashboardScreen(), 
      // Assuming StudentsScreen exists and might need updates later, wrapping it for now
      const StudentsScreen(),
      const LiveAttendanceScreen(),
      const ReportsScreen(),
      SettingsScreen(onLogout: widget.onLogout, onNavigate: _navigateToInternal),
    ];

    return Scaffold(
      backgroundColor: AppTheme.slate50,
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: _currentIndex,
          children: screens,
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.slate100, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: Colors.white,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppTheme.sky500,
          unselectedItemColor: AppTheme.slate400,
          selectedFontSize: 10,
          unselectedFontSize: 10,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.people_outline), activeIcon: Icon(Icons.people), label: 'Students'),
            BottomNavigationBarItem(icon: Icon(Icons.calendar_today_outlined), activeIcon: Icon(Icons.calendar_today), label: 'Attendance'),
            BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), activeIcon: Icon(Icons.bar_chart), label: 'Reports'),
            BottomNavigationBarItem(icon: Icon(Icons.more_horiz_outlined), activeIcon: Icon(Icons.more_horiz), label: 'More'),
          ],
        ),
      ),
    );
  }
}
