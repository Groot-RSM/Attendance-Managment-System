import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/models.dart';

class LocalDbService {
  static const String rosterBoxName = 'student_roster';
  static const String bufferBoxName = 'attendance_buffer';
  static const String syncBoxName = 'sync_queue';
  static const String settingsBoxName = 'app_settings';

  Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(rosterBoxName);
    await Hive.openBox(bufferBoxName);
    await Hive.openBox(syncBoxName);
    await Hive.openBox(settingsBoxName);
  }

  // --- Session Management ---
  Future<void> updateLastActiveTime() async {
    final box = Hive.box(settingsBoxName);
    await box.put('last_active', DateTime.now().toIso8601String());
  }

  DateTime? getLastActiveTime() {
    final box = Hive.box(settingsBoxName);
    final isoStr = box.get('last_active');
    if (isoStr != null) {
      return DateTime.tryParse(isoStr);
    }
    return null;
  }

  Future<void> saveUserProfile(UserProfile profile) async {
    final box = Hive.box(settingsBoxName);
    await box.put('cached_profile', jsonEncode({
      'uid': profile.uid,
      'name': profile.name,
      'email': profile.email,
      'phone': profile.phone,
      'role': profile.role,
      'classId': profile.classId,
      'section': profile.section,
      'hasSetPassword': profile.hasSetPassword,
      'teacherId': profile.teacherId,
    }));
  }

  UserProfile? getCachedUserProfile() {
    final box = Hive.box(settingsBoxName);
    final jsonStr = box.get('cached_profile');
    if (jsonStr != null) {
      final map = jsonDecode(jsonStr);
      return UserProfile.fromMap(map['uid'] ?? '', map);
    }
    return null;
  }

  // --- Student Roster Mapping ---

  Future<void> saveStudentRoster(List<Student> students) async {
    final box = Hive.box(rosterBoxName);
    await box.clear(); // Clear old cache
    for (var student in students) {
      // Store by fingerprintId for ultra-fast BLE lookup
      final studentMap = {
        'studentId': student.studentId,
        'name': student.name,
        'rollNo': student.rollNo,
        'fingerprintId': student.fingerprintId,
        'classId': student.classId,
        'section': student.section,
        'dob': student.dob,
        'enrollDate': student.enrollDate,
        'photo': student.photo,
        'attendancePct': student.attendancePct,
        'templateQuality': student.templateQuality,
        'templateDay': student.templateDay,
        'teacherId': student.teacherId,
        'schoolId': student.schoolId,
        'status': student.status,
        'parentName': student.parentName,
        'parentPhone': student.parentPhone,
      };
      await box.put(student.studentId, jsonEncode(studentMap));
    }
  }

  Future<void> addStudentLocal(Student student) async {
    final box = Hive.box(rosterBoxName);
    final studentMap = {
      'studentId': student.studentId,
      'name': student.name,
      'rollNo': student.rollNo,
      'fingerprintId': student.fingerprintId,
      'classId': student.classId,
      'section': student.section,
      'dob': student.dob,
      'enrollDate': student.enrollDate,
      'photo': student.photo,
      'attendancePct': student.attendancePct,
      'templateQuality': student.templateQuality,
      'templateDay': student.templateDay,
      'teacherId': student.teacherId,
      'schoolId': student.schoolId,
      'status': student.status,
      'parentName': student.parentName,
      'parentPhone': student.parentPhone,
    };
    await box.put(student.studentId, jsonEncode(studentMap));
  }

  Student? getStudentByFingerprint(int fingerprintId) {
    if (fingerprintId <= 0) return null; // 0 or less are not valid assigned fingerprints
    
    final box = Hive.box(rosterBoxName);
    for (var key in box.keys) {
      final data = box.get(key);
      if (data != null) {
        final map = jsonDecode(data as String);
        if (map['fingerprintId'] == fingerprintId) {
          return Student(
            studentId: map['studentId'],
            name: map['name'],
            rollNo: map['rollNo'],
            fingerprintId: map['fingerprintId'],
            classId: map['classId'],
            section: map['section'],
            dob: map['dob'],
            enrollDate: map['enrollDate'],
            photo: map['photo'],
            attendancePct: map['attendancePct'],
            templateQuality: map['templateQuality'],
            templateDay: map['templateDay'],
            teacherId: map['teacherId'] ?? '',
            schoolId: map['schoolId'] ?? '',
            status: map['status'] ?? 'active',
            parentName: map['parentName'] ?? '',
            parentPhone: map['parentPhone'] ?? '',
          );
        }
      }
    }
    return null;
  }

  Student? getStudentByRollNo(int rollNo, String classId, String? section) {
    if (rollNo <= 0 || classId.isEmpty) return null;
    
    final box = Hive.box(rosterBoxName);
    for (var key in box.keys) {
      final data = box.get(key);
      if (data != null) {
        final map = jsonDecode(data as String);
        if (map['rollNo'] == rollNo && map['classId'] == classId) {
          // If section is provided, match it too
          if (section != null && section != 'ALL' && map['section'] != section) {
            continue;
          }
          return Student(
            studentId: map['studentId'],
            name: map['name'],
            rollNo: map['rollNo'],
            fingerprintId: map['fingerprintId'],
            classId: map['classId'],
            section: map['section'],
            dob: map['dob'],
            enrollDate: map['enrollDate'],
            photo: map['photo'],
            attendancePct: map['attendancePct'],
            templateQuality: map['templateQuality'],
            templateDay: map['templateDay'],
            teacherId: map['teacherId'] ?? '',
            schoolId: map['schoolId'] ?? '',
            status: map['status'] ?? 'active',
            parentName: map['parentName'] ?? '',
            parentPhone: map['parentPhone'] ?? '',
          );
        }
      }
    }
    return null;
  }

  Student? getStudentById(String studentId) {
    if (studentId.isEmpty || studentId == 'UNKNOWN') return null;
    
    final box = Hive.box(rosterBoxName);
    final data = box.get(studentId);
    if (data != null) {
      final map = jsonDecode(data as String);
      return Student(
        studentId: map['studentId'],
        name: map['name'],
        rollNo: map['rollNo'],
        fingerprintId: map['fingerprintId'],
        classId: map['classId'],
        section: map['section'],
        dob: map['dob'],
        enrollDate: map['enrollDate'],
        photo: map['photo'],
        attendancePct: map['attendancePct'],
        templateQuality: map['templateQuality'],
        templateDay: map['templateDay'],
        teacherId: map['teacherId'] ?? '',
        schoolId: map['schoolId'] ?? '',
        status: map['status'] ?? 'active',
        parentName: map['parentName'] ?? '',
        parentPhone: map['parentPhone'] ?? '',
      );
    }
    return null;
  }

  int getStudentCount() {
    return Hive.box(rosterBoxName).length;
  }

  List<Student> getAllStudents() {
    final box = Hive.box(rosterBoxName);
    final List<Student> students = [];
    
    for (var key in box.keys) {
      final data = box.get(key);
      if (data != null) {
        final map = jsonDecode(data as String);
        students.add(Student(
          studentId: map['studentId'],
          name: map['name'],
          rollNo: map['rollNo'],
          fingerprintId: map['fingerprintId'],
          classId: map['classId'],
          section: map['section'],
          dob: map['dob'],
          enrollDate: map['enrollDate'],
          photo: map['photo'],
          attendancePct: map['attendancePct'],
          templateQuality: map['templateQuality'],
          templateDay: map['templateDay'],
          teacherId: map['teacherId'] ?? '',
          schoolId: map['schoolId'] ?? '',
          status: map['status'] ?? 'active',
          parentName: map['parentName'] ?? '',
          parentPhone: map['parentPhone'] ?? '',
        ));
      }
    }
    
    // Sort students by roll number
    students.sort((a, b) => a.rollNo.compareTo(b.rollNo));
    return students;
  }

  // --- Attendance Buffer (BLE Received) ---

  Future<void> saveReceivedAttendance(AttendanceRecord record) async {
    final box = Hive.box(bufferBoxName);
    
    final recordMap = {
      'eventId': record.eventId,
      'deviceId': record.deviceId,
      'fingerprintId': record.fingerprintId,
      'studentId': record.studentId,
      'studentName': record.studentName,
      'photo': record.photo,
      'classId': record.classId,
      'timestamp': record.timestamp.toIso8601String(),
      'status': record.status,
      'schoolId': record.schoolId,
      'confidence': record.confidence,
    };
    
    // Key by eventId to naturally prevent duplicates from multiple syncs
    await box.put(record.eventId, jsonEncode(recordMap));
  }

  List<AttendanceRecord> getAllReceivedAttendance() {
    final box = Hive.box(bufferBoxName);
    final List<AttendanceRecord> records = [];
    
    for (var key in box.keys) {
      final data = box.get(key);
      if (data != null) {
        final map = jsonDecode(data as String);
        records.add(AttendanceRecord(
          eventId: map['eventId'],
          deviceId: map['deviceId'],
          fingerprintId: map['fingerprintId'],
          studentId: map['studentId'],
          studentName: map['studentName'],
          photo: map['photo'],
          classId: map['classId'],
          timestamp: DateTime.parse(map['timestamp']),
          status: map['status'],
          schoolId: map['schoolId'],
          confidence: map['confidence'],
        ));
      }
    }
    
    // Sort descending by timestamp
    records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return records;
  }

  Future<void> wipeAllLocalData() async {
    await Hive.box(rosterBoxName).clear();
    await Hive.box(bufferBoxName).clear();
    await Hive.box(syncBoxName).clear();
  }
}
