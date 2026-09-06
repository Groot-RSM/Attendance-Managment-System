import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'local_db_service.dart';
import 'database_service.dart';
import '../models/models.dart';

class BleService {
  // Singleton pattern
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  final LocalDbService _localDbService = LocalDbService();
  
  // Standard Nordic UART Service UUIDs
  static const String UART_SERVICE_UUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  static const String UART_RX_CHARACTERISTIC_UUID = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"; // App sends to ESP32
  static const String UART_TX_CHARACTERISTIC_UUID = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"; // ESP32 sends to App
  
  // Persistent connection state
  BluetoothDevice? connectedDevice;
  final StreamController<bool> _connectionStateController = StreamController<bool>.broadcast();
  Stream<bool> get isConnectedStream => _connectionStateController.stream;
  StreamSubscription? _deviceConnectionSub;

  // Expose standard flutter_blue_plus streams
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;
  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  BluetoothCharacteristic? _rxCharacteristic;
  StreamSubscription? _txSubscription;
  final StreamController<String> _linesController = StreamController<String>.broadcast();

  Future<void> startScan() async {
    // Make sure Bluetooth is on and supported before scanning
    if (await FlutterBluePlus.isSupported == false) {
      print("Bluetooth not supported");
      return;
    }
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }
  
  bool _intentionalDisconnect = false;

  Future<void> connectToDevice(BluetoothDevice device) async {
    _intentionalDisconnect = false;
    await device.connect(autoConnect: false);
    connectedDevice = device;
    _connectionStateController.add(true);
    
    _deviceConnectionSub?.cancel();
    _deviceConnectionSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        if (!_intentionalDisconnect) {
          // Unexpected drop! Attempt to automatically reconnect in the background
          _attemptReconnect(device);
        } else {
          _handleDisconnect();
        }
      }
    });
  }

  Future<void> _attemptReconnect(BluetoothDevice device) async {
    while (!_intentionalDisconnect) {
      try {
        await Future.delayed(const Duration(seconds: 3));
        if (_intentionalDisconnect) break; // Check again after delay
        await device.connect(autoConnect: false);
        // If we reach here, we are reconnected!
        connectedDevice = device;
        _connectionStateController.add(true);
        // We might need to re-initialize UART if characteristics were lost,
        // but for now, just marking connected.
        break; // Break the loop on success
      } catch (e) {
        print("Reconnection attempt failed: $e");
        // Loop will continue and try again
      }
    }
  }

  void _handleDisconnect() {
    connectedDevice = null;
    _connectionStateController.add(false);
    _txSubscription?.cancel();
    _txSubscription = null;
    _rxCharacteristic = null;
    _deviceConnectionSub?.cancel();
  }

  Future<void> disconnectFromDevice() async {
    _intentionalDisconnect = true;
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      _handleDisconnect();
    }
  }

  // Initializes the UART connection, finds the TX/RX characteristics, and sets up the line buffer
  Future<bool> initializeUart(BluetoothDevice device) async {
    List<BluetoothService> services = await device.discoverServices();
    
    BluetoothService? uartService;
    BluetoothCharacteristic? txCharacteristic;

    for (var service in services) {
      if (service.uuid.toString().toUpperCase() == UART_SERVICE_UUID) {
        uartService = service;
        break;
      }
    }

    if (uartService == null) return false;

    for (var characteristic in uartService.characteristics) {
      final uuid = characteristic.uuid.toString().toUpperCase();
      if (uuid == UART_TX_CHARACTERISTIC_UUID) {
        txCharacteristic = characteristic; // Device to App
      } else if (uuid == UART_RX_CHARACTERISTIC_UUID) {
        _rxCharacteristic = characteristic; // App to Device
      }
    }

    if (txCharacteristic == null || _rxCharacteristic == null) return false;

    await txCharacteristic.setNotifyValue(true);
    
    String buffer = "";

    _txSubscription?.cancel();
    // Listen to incoming data stream and split by newline
    _txSubscription = txCharacteristic.onValueReceived.listen((value) {
      String chunk = utf8.decode(value, allowMalformed: true);
      buffer += chunk;
      
      while (buffer.contains('\n')) {
        int index = buffer.indexOf('\n');
        String line = buffer.substring(0, index).trim();
        buffer = buffer.substring(index + 1);
        if (line.isNotEmpty) {
          _linesController.add(line);
        }
      }
    });

    return true;
  }

  // Sends the list files command and waits for the response
  Future<List<String>> listFiles() async {
    if (_rxCharacteristic == null) return [];
    
    List<String> files = [];
    Completer<List<String>> completer = Completer();
    
    StreamSubscription? sub;
    sub = _linesController.stream.listen((line) {
      print("BLE Line Received: $line"); // DEBUG
      if (line.startsWith("FILE:")) {
        String filename = line.substring(5);
        print("BLE Parsed File: $filename"); // DEBUG
        files.add(filename);
      } else if (line == "EOF:LIST") {
        print("BLE EOF Received! Completing with ${files.length} files."); // DEBUG
        sub?.cancel();
        if (!completer.isCompleted) completer.complete(files);
      }
    });

    await _rxCharacteristic!.write(utf8.encode("CMD:LIST_FILES\n"));
    
    // Timeout fallback just in case ESP32 gets stuck
    Future.delayed(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        sub?.cancel();
        completer.complete(files);
      }
    });

    return completer.future;
  }

  // Commands ESP32 to send a file and parses the lines dynamically
  Future<void> downloadFile(BluetoothDevice device, String filename, Function(String) onProgress) async {
    if (_rxCharacteristic == null) return;
    
    Completer<void> completer = Completer();
    int lineCount = 0;
    
    bool isAttendance = false;
    bool isTemplates = false;
    DateTime fileDate = _extractDateFromFilename(filename);

    StreamSubscription? sub;
    File? localFile;
    IOSink? sink;
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      String cleanFilename = filename;
      if (cleanFilename.startsWith('/')) cleanFilename = cleanFilename.substring(1);
      
      final filePath = '${directory.path}/$cleanFilename';
      localFile = File(filePath);
      sink = localFile.openWrite();
      print("Saving BLE data to: $filePath");
    } catch (e) {
      print("Error creating local file: $e");
    }

    sub = _linesController.stream.listen((line) async {
      if (line == "EOF:FILE") {
        sub?.cancel();
        await sink?.close();
        
        if (isAttendance) {
          await _generateAbsentRecordsForDate(fileDate, device.remoteId.toString());
        }
        
        if (!completer.isCompleted) completer.complete();
        return;
      }
      
      // Write line to local physical CSV file
      sink?.writeln(line);

      // Check header row to determine parsing strategy
      if (line.contains("User ID") && line.contains("Scanned Template")) {
        isTemplates = true;
        isAttendance = false;
        return;
      } else if (line.contains("User ID") && line.contains("Time")) {
        isAttendance = true;
        isTemplates = false;
        return;
      }

      lineCount++;
      onProgress("Received $lineCount records...");

      // Parse data rows for local database
      if (isAttendance) {
        await _parseAttendanceLine(line, device.remoteId.toString(), fileDate);
      } else if (isTemplates) {
        await _parseTemplateLine(line);
      }
    });

    await _rxCharacteristic!.write(utf8.encode("CMD:GET_FILE:$filename\n"));
    return completer.future;
  }

  // Uploads a CSV file to the ESP32 chunk by chunk
  Future<void> uploadCsvToGate(BluetoothDevice device, File file, Function(String) onProgress) async {
    if (_rxCharacteristic == null) throw Exception("UART not initialized");
    
    Completer<void> handshakeCompleter = Completer();
    Completer<void> uploadCompleter = Completer();
    
    StreamSubscription? sub;
    sub = _linesController.stream.listen((line) {
      if (line == "READY_TO_RECEIVE") {
        if (!handshakeCompleter.isCompleted) handshakeCompleter.complete();
      } else if (line == "UPLOAD_DONE") {
        if (!uploadCompleter.isCompleted) uploadCompleter.complete();
      } else if (line == "ERR:FILE_OPEN") {
        if (!handshakeCompleter.isCompleted) handshakeCompleter.completeError("ESP32 failed to open file for writing.");
      }
    });

    onProgress("Initiating upload handshake...");
    await _rxCharacteristic!.write(utf8.encode("CMD:PUT_FILE\n"));
    
    // Wait for handshake
    await handshakeCompleter.future.timeout(const Duration(seconds: 5), onTimeout: () {
      sub?.cancel();
      throw Exception("ESP32 did not respond to PUT_FILE command");
    });
    
    // Read file bytes
    List<int> fileBytes = await file.readAsBytes();
    int totalBytes = fileBytes.length;
    int bytesSent = 0;
    
    onProgress("Sending 0 of $totalBytes bytes...");
    
    // Send in 20 byte chunks
    for (int i = 0; i < fileBytes.length; i += 20) {
      int end = (i + 20 < fileBytes.length) ? i + 20 : fileBytes.length;
      List<int> chunk = fileBytes.sublist(i, end);
      
      await _rxCharacteristic!.write(chunk);
      await Future.delayed(const Duration(milliseconds: 30));
      
      bytesSent += chunk.length;
      if (i % 100 == 0) { // Update progress every 5 chunks
        onProgress("Sending $bytesSent of $totalBytes bytes...");
      }
    }
    
    onProgress("Finalizing upload...");
    await _rxCharacteristic!.write(utf8.encode("CMD:EOF\n"));
    
    // Wait for completion
    await uploadCompleter.future.timeout(const Duration(seconds: 10), onTimeout: () {
      sub?.cancel();
      throw Exception("ESP32 did not confirm upload completion");
    });
    
    sub?.cancel();
  }

  DateTime _extractDateFromFilename(String filename) {
    // Attempt to parse dates like 19-08-2026.csv or 2026-08-19.csv
    RegExp dateRegex = RegExp(r'(\d{2,4}[-_]\d{2}[-_]\d{2,4})');
    var match = dateRegex.firstMatch(filename);
    
    if (match != null) {
      try {
        String ds = match.group(0)!;
        if (ds.length == 10) { 
           if (ds.startsWith(RegExp(r'\d{4}'))) {
             // format 2026-08-19
             return DateTime.parse(ds.replaceAll('_', '-'));
           } else {
             // format 19-08-2026 -> convert to 2026-08-19
             var parts = ds.split(RegExp(r'[-_]'));
             if (parts.length == 3) {
               return DateTime.parse('${parts[2]}-${parts[1]}-${parts[0]}');
             }
           }
        }
      } catch(e) {
        print("Date parse error: $e");
      }
    }
    // Fallback to today if parsing fails or no date in filename
    return DateTime.now();
  }

  Future<void> _parseAttendanceLine(String csvLine, String deviceId, DateTime baseDate) async {
    // Format: User ID,Time
    // 101,19:43:28
    try {
      List<String> parts = csvLine.split(',');
      if (parts.length >= 2) {
        int rollNo = int.tryParse(parts[0]) ?? 0;
        String timeStr = parts[1]; // "19:43:28"
        
        List<String> timeParts = timeStr.split(':');
        if (timeParts.length == 3) {
          DateTime timestamp = DateTime(
            baseDate.year, baseDate.month, baseDate.day,
            int.parse(timeParts[0]), int.parse(timeParts[1]), int.parse(timeParts[2])
          );

          String eventId = "BLE-${deviceId}-${timestamp.millisecondsSinceEpoch}-$rollNo";
          
          // Since Roll No is globally unique across all classes, we can just look them up globally!
          // (Remember we mapped fingerprintId = rollNo during registration)
          final student = _localDbService.getStudentByFingerprint(rollNo);
          
          final record = AttendanceRecord(
            eventId: eventId,
            deviceId: deviceId,
            fingerprintId: rollNo, // We treat the hardware ID as the Roll No!
            studentId: student?.studentId ?? 'UNREGISTERED',
            studentName: student?.name ?? 'ID: $rollNo',
            photo: student?.photo ?? '',
            classId: student?.classId ?? '',
            timestamp: timestamp,
            status: 'IN', // Using default status, since it's an entrance gate
            schoolId: student?.schoolId ?? 'SCH_01', 
            confidence: 99,
          );

          await _localDbService.saveReceivedAttendance(record);
          
          // Also push this record directly to Firebase Cloud! (Fire-and-forget so it doesn't block offline)
          try {
            DatabaseService().addAttendance(record);
          } catch (e) {
            print("Failed to sync attendance record to cloud: $e");
          }
        }
      }
    } catch (e) {
      print("Failed to parse attendance record: $csvLine Error: $e");
    }
  }

  Future<void> _parseTemplateLine(String csvLine) async {
    // Format: User ID,Time,Scanned Template OR User ID,Scanned Template
    // 101,20:00:51,EF01FFFFFFFF02...
    // 101,EF01FFFFFFFF02...
    try {
      List<String> parts = csvLine.split(',');
      if (parts.length >= 2) {
        int fingerprintId = int.tryParse(parts[0]) ?? 0;
        String hexString = parts.last; // Template is always the last item
        
        final student = _localDbService.getStudentByFingerprint(fingerprintId);
        if (student != null) {
          print("Successfully parsed template backup for student ${student.name} (${hexString.length} chars)");
          // In a full implementation, you'd save this hex string to Hive or Firestore so the cloud has a backup of the fingerprint!
        }
      }
    } catch (e) {
      print("Failed to parse template record: $csvLine Error: $e");
    }
  }

  Future<void> _generateAbsentRecordsForDate(DateTime baseDate, String deviceId) async {
    try {
      var allRecords = _localDbService.getAllReceivedAttendance();
      var allStudents = _localDbService.getAllStudents();
      
      // Get all students who were present on this date
      final presentFingerprints = allRecords.where((record) {
        return record.timestamp.year == baseDate.year &&
               record.timestamp.month == baseDate.month &&
               record.timestamp.day == baseDate.day &&
               record.status == 'IN';
      }).map((r) => r.fingerprintId).toSet();

      // Create a specific 00:00:00 timestamp for absent records so they can be overridden by any actual scan today
      DateTime absentTimestamp = DateTime(baseDate.year, baseDate.month, baseDate.day, 0, 0, 0);

      for (var student in allStudents) {
        if (!presentFingerprints.contains(student.fingerprintId)) {
          // If a student's fingerprint is -1, use their studentId in the eventId to avoid collisions
          String uniqueIdentifier = student.fingerprintId > 0 ? student.fingerprintId.toString() : student.studentId;
          String eventId = "BLE-ABSENT-${deviceId}-${absentTimestamp.millisecondsSinceEpoch}-$uniqueIdentifier";
          
          final record = AttendanceRecord(
            eventId: eventId,
            deviceId: deviceId,
            fingerprintId: student.fingerprintId,
            studentId: student.studentId,
            studentName: student.name,
            photo: student.photo,
            classId: student.classId,
            timestamp: absentTimestamp,
            status: 'ABSENT',
            schoolId: student.schoolId,
            confidence: 0,
          );

          await _localDbService.saveReceivedAttendance(record);
          
          try {
            DatabaseService().addAttendance(record); // Fire-and-forget
          } catch (e) {
            print("Failed to sync absent record to cloud: $e");
          }
        }
      }
      print("Successfully generated and synced absent records for ${baseDate.toIso8601String()}");
    } catch (e) {
      print("Error generating absent records: $e");
    }
  }

  Future<void> simulateEsp32Sync() async {
    // Simulate a BLE sync operation
    await Future.delayed(const Duration(seconds: 2));
  }
}
