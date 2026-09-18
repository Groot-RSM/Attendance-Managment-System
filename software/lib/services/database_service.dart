import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/models.dart';
import 'local_db_service.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final LocalDbService _localDbService = LocalDbService();

  String? get currentUserUid => FirebaseAuth.instance.currentUser?.uid;

  Stream<DocumentSnapshot> getCurrentUserProfileStream(String uid) {
    return _db.collection('users').doc(uid).snapshots();
  }

  Stream<List<Student>> getStudentsStream() {
    return _db.collection('students').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return Student(
          studentId: data['studentId'] ?? doc.id,
          name: data['name'] ?? '',
          rollNo: data['rollNo'] ?? 0,
          fingerprintId: data['fingerprintId'] ?? 0,
          classId: data['classId'] ?? '',
          section: data['section'] ?? '',
          dob: data['dob'] ?? '',
          enrollDate: data['enrollDate'] ?? '',
          photo: data['photo'] ?? '',
          attendancePct: data['attendancePct'] ?? 0,
          templateQuality: data['templateQuality'] ?? 0,
          templateDay: data['templateDay'] ?? 0,
          teacherId: data['teacherId'] ?? '',
          schoolId: data['schoolId'] ?? '',
          status: data['status'] ?? 'active',
        );
      }).toList();
    });
  }

  Stream<List<AttendanceRecord>> getTodayFeedStream() {
    return _db.collection('attendance').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return AttendanceRecord(
          eventId: data['eventId'] ?? doc.id,
          deviceId: data['deviceId'] ?? '',
          fingerprintId: data['fingerprintId'] ?? 0,
          studentId: data['studentId'] ?? '',
          studentName: data['studentName'] ?? '',
          photo: data['photo'] ?? '',
          classId: data['classId'] ?? '',
          timestamp: data['timestamp'] != null ? (data['timestamp'] as Timestamp).toDate() : DateTime.now(),
          status: data['status'] ?? '',
          schoolId: data['schoolId'] ?? '',
          confidence: data['confidence'] ?? 0,
        );
      }).toList();
    });
  }

  Future<List<AttendanceRecord>> getStudentAttendanceHistory(String studentId) async {
    final snapshot = await _db.collection('attendance')
        .where('studentId', isEqualTo: studentId)
        .get();
        
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return AttendanceRecord(
        eventId: data['eventId'] ?? doc.id,
        deviceId: data['deviceId'] ?? '',
        fingerprintId: data['fingerprintId'] ?? 0,
        studentId: data['studentId'] ?? '',
        studentName: data['studentName'] ?? '',
        photo: data['photo'] ?? '',
        classId: data['classId'] ?? '',
        timestamp: data['timestamp'] != null ? (data['timestamp'] as Timestamp).toDate() : DateTime.now(),
        status: data['status'] ?? '',
        schoolId: data['schoolId'] ?? '',
        confidence: data['confidence'] ?? 0,
      );
    }).toList();
  }

  Future<List<AttendanceRecord>> getAttendanceForDateRange(DateTime start, DateTime end, {String? classFilter}) async {
    // For now, since Firebase queries with ranges + equality can require complex indexes,
    // and this is a prototype, we'll fetch all within range and filter locally if needed.
    // In production, we'd use a composite index.
    
    // Set start to beginning of day and end to end of day
    final startOfDay = DateTime(start.year, start.month, start.day, 0, 0, 0);
    final endOfDay = DateTime(end.year, end.month, end.day, 23, 59, 59);
    
    Query query = _db.collection('attendance')
        .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
        .where('timestamp', isLessThanOrEqualTo: endOfDay);
        
    // We will NOT filter by classId in the query to avoid needing a Firebase Composite Index.
    // We'll fetch all records for the date range and filter locally.
        
    final snapshot = await query.get();
    
    var records = snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return AttendanceRecord(
        eventId: data['eventId'] ?? doc.id,
        deviceId: data['deviceId'] ?? '',
        fingerprintId: data['fingerprintId'] ?? 0,
        studentId: data['studentId'] ?? '',
        studentName: data['studentName'] ?? '',
        photo: data['photo'] ?? '',
        classId: data['classId'] ?? '',
        timestamp: data['timestamp'] != null ? (data['timestamp'] as Timestamp).toDate() : DateTime.now(),
        status: data['status'] ?? '',
        schoolId: data['schoolId'] ?? '',
        confidence: data['confidence'] ?? 0,
      );
    }).toList();
    
    // Filter locally
    if (classFilter != null && classFilter != 'All') {
      final clsId = classFilter.split(' ')[0];
      records = records.where((r) => r.classId == clsId).toList();
    }
    
    return records;
  }

  Future<void> addStudent(Student student) async {
    final docRef = _db.collection('students').doc(student.studentId);
    await docRef.set({
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
    });
  }

  Future<void> updateStudent(Student student) async {
    final docRef = _db.collection('students').doc(student.studentId);
    await docRef.update({
      'name': student.name,
      'rollNo': student.rollNo,
      'fingerprintId': student.fingerprintId,
      'classId': student.classId,
      'section': student.section,
      'dob': student.dob,
      'photo': student.photo,
      'attendancePct': student.attendancePct,
      'templateQuality': student.templateQuality,
      'templateDay': student.templateDay,
      'teacherId': student.teacherId,
      'status': student.status,
      'parentName': student.parentName,
      'parentPhone': student.parentPhone,
    });
  }

  Future<List<Student>> fetchAllStudents() async {
    final snapshot = await _db.collection('students').get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return Student(
        studentId: data['studentId'] ?? doc.id,
        name: data['name'] ?? '',
        rollNo: data['rollNo'] ?? 0,
        fingerprintId: data['fingerprintId'] ?? 0,
        classId: data['classId'] ?? '',
        section: data['section'] ?? '',
        dob: data['dob'] ?? '',
        enrollDate: data['enrollDate'] ?? '',
        photo: data['photo'] ?? '',
        attendancePct: data['attendancePct'] ?? 0,
        templateQuality: data['templateQuality'] ?? 0,
        templateDay: data['templateDay'] ?? 0,
        teacherId: data['teacherId'] ?? '',
        schoolId: data['schoolId'] ?? '',
        status: data['status'] ?? 'active',
        parentName: data['parentName'] ?? '',
        parentPhone: data['parentPhone'] ?? '',
      );
    }).toList();
  }


  Future<UserProfile?> getCurrentUserProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    
    // FAST PATH: Instantly return cached profile if it belongs to the CURRENT user
    final cachedProfile = _localDbService.getCachedUserProfile();
    if (cachedProfile != null && cachedProfile.uid == uid) {
      // Silently sync with server in the background to keep profile fresh
      final email = FirebaseAuth.instance.currentUser?.email;
      getUserProfile(uid, email: email).then((p) {
        if (p != null) {
          _localDbService.saveUserProfile(p); // Update cache silently
        }
      });
      return cachedProfile;
    }
    
    // No valid cache for this user — fetch from Firebase
    final email = FirebaseAuth.instance.currentUser?.email;
    return getUserProfile(uid, email: email);
  }

  Future<UserProfile?> getUserProfile(String uid, {String? email}) async {
    try {
      if (email != null) {
        final emailDoc = await _db.collection('users').doc(email.toLowerCase()).get();
        if (emailDoc.exists && emailDoc.data() != null) {
          final profile = UserProfile.fromMap(emailDoc.id, emailDoc.data()!);
          await _localDbService.saveUserProfile(profile);
          return profile;
        }
      }

      final doc = await _db.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        final profile = UserProfile.fromMap(doc.id, doc.data()!);
        await _localDbService.saveUserProfile(profile);
        return profile;
      }
    } catch (e) {
      // Only return cached profile if it belongs to the same user (UID match)
      final cached = _localDbService.getCachedUserProfile();
      if (cached != null && cached.uid == uid) return cached;
      return null; // Don't return a different user's cached profile!
    }
    return null;
  }

  Future<UserProfile?> getUserProfileByTeacherId(String teacherId) async {
    try {
      final query = await _db.collection('users').where('teacherId', isEqualTo: teacherId).limit(1).get();
      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        return UserProfile.fromMap(doc.id, doc.data());
      }
    } catch (e) {
      print("Failed to get user by teacher ID (likely offline): $e");
    }
    return null;
  }

  Future<void> addAttendance(AttendanceRecord record) async {
    final docRef = _db.collection('attendance').doc(record.eventId);
    await docRef.set({
      'eventId': record.eventId,
      'deviceId': record.deviceId,
      'fingerprintId': record.fingerprintId,
      'studentId': record.studentId,
      'studentName': record.studentName,
      'photo': record.photo,
      'classId': record.classId,
      'timestamp': record.timestamp,
      'status': record.status,
      'schoolId': record.schoolId,
      'confidence': record.confidence,
    });
  }

  // Teacher Management
  Stream<List<UserProfile>> getTeachersStream() {
    return _db.collection('users').where('role', isEqualTo: 'teacher').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => UserProfile.fromMap(doc.id, doc.data())).toList();
    });
  }

  Future<List<UserProfile>> getAllTeachers() async {
    final snapshot = await _db.collection('users').where('role', isEqualTo: 'teacher').get();
    return snapshot.docs.map((doc) => UserProfile.fromMap(doc.id, doc.data())).toList();
  }

  Future<void> addTeacherWhitelist(String email, String name, String phone) async {
    final String teacherId = 'TCH${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    
    await _db.collection('users').doc(email.toLowerCase()).set({
      'name': name,
      'email': email.toLowerCase(),
      'phone': phone,
      'role': 'teacher',
      'classId': null, // Starts unassigned
      'section': null,
      'hasSetPassword': false,
      'teacherId': teacherId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markPasswordAsSet(String uidOrEmail) async {
    await _db.collection('users').doc(uidOrEmail.toLowerCase()).update({
      'hasSetPassword': true,
    });
  }

  Future<void> assignTeacher(String uid, String classId, String section) async {
    await _db.collection('users').doc(uid).update({
      'classId': classId,
      'section': section,
    });
  }

  Future<void> wipeTestData() async {
    // 1. Delete all students
    final studentsSnapshot = await _db.collection('students').get();
    for (var doc in studentsSnapshot.docs) {
      await doc.reference.delete();
    }
    
    // 2. Delete all attendance
    final attendanceSnapshot = await _db.collection('attendance').get();
    for (var doc in attendanceSnapshot.docs) {
      await doc.reference.delete();
    }

    // 3. Delete all users EXCEPT the admin account
    final usersSnapshot = await _db.collection('users').get();
    for (var doc in usersSnapshot.docs) {
      final data = doc.data();
      final email = data['email']?.toString().toLowerCase();
      // Keep the main admin account
      if (email != 'manneysatheesh@gmail.com') {
        await doc.reference.delete();
      }
    }
  }
}
