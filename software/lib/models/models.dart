class UserProfile {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String role;
  final String? classId;
  final String? section;
  final bool? hasSetPassword;
  final String? teacherId;

  UserProfile({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.classId,
    this.section,
    this.hasSetPassword,
    this.teacherId,
  });

  factory UserProfile.fromMap(String uid, Map<String, dynamic> data) {
    return UserProfile(
      uid: uid,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      role: data['role'] ?? 'teacher',
      classId: data['classId'],
      section: data['section'],
      hasSetPassword: data['hasSetPassword'],
      teacherId: data['teacherId'],
    );
  }
}

class Student {
  final String studentId;
  final String name;
  final int rollNo;
  final int fingerprintId;
  final String classId; // replaces className
  final String section;
  final String dob;
  final String enrollDate;
  final String photo;
  final int attendancePct;
  final int templateQuality;
  final int templateDay;
  final String teacherId;
  final String schoolId;
  final String status;
  final String parentName;
  final String parentPhone;

  Student({
    required this.studentId,
    required this.name,
    required this.rollNo,
    required this.fingerprintId,
    required this.classId,
    required this.section,
    required this.dob,
    required this.enrollDate,
    required this.photo,
    required this.attendancePct,
    required this.templateQuality,
    required this.templateDay,
    required this.teacherId,
    required this.schoolId,
    required this.status,
    this.parentName = '',
    this.parentPhone = '',
  });
}

class AttendanceRecord {
  final String eventId;
  final String deviceId;
  final int fingerprintId;
  final String studentId;
  final String studentName; // Still useful for quick UI rendering if joined
  final String photo;       // UI helper
  final String classId;
  final DateTime timestamp;
  final String status;      // "IN" or "OUT"
  final String schoolId;
  final int confidence;

  AttendanceRecord({
    required this.eventId,
    required this.deviceId,
    required this.fingerprintId,
    required this.studentId,
    required this.studentName,
    required this.photo,
    required this.classId,
    required this.timestamp,
    required this.status,
    required this.schoolId,
    required this.confidence,
  });
}

class SyncRecord {
  final String id;
  final String type;
  final String timestamp;
  final bool synced;

  SyncRecord({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.synced,
  });
}

class DayTrend {
  final String day;
  final int present;
  final int absent;

  DayTrend({
    required this.day,
    required this.present,
    required this.absent,
  });
}

class MonthAttendance {
  final String month;
  final int pct;

  MonthAttendance({
    required this.month,
    required this.pct,
  });
}

// Mock Data
final List<Student> students = [];

final List<DayTrend> weekTrend = [];

final List<MonthAttendance> attendanceHistory = [];

final List<SyncRecord> pendingSyncRecords = [];
