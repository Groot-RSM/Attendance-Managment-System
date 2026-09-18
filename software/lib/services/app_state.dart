import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AppState {
  // Global notifier that increments whenever data changes
  static final ValueNotifier<int> refreshNotifier = ValueNotifier<int>(0);
  static bool _isInitialized = false;
  
  // Call this manually if a local change happens (like BLE sync)
  static void triggerRefresh() {
    refreshNotifier.value++;
  }
  
  // Call this once on app boot
  static void initFirebaseListener() {
    if (_isInitialized) return;
    _isInitialized = true;
    
    // Listen to Firebase. When network connects and syncs, these streams fire!
    FirebaseFirestore.instance.collection('attendance').snapshots().listen((snapshot) {
      triggerRefresh();
    }, onError: (e) {
      print('AppState attendance listener offline error ignored');
    });
    
    FirebaseFirestore.instance.collection('students').snapshots().listen((snapshot) {
      triggerRefresh();
    }, onError: (e) {
      print('AppState students listener offline error ignored');
    });
  }
}
