import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/models.dart';
import 'dart:math' as math;
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import '../services/database_service.dart';
import '../services/local_db_service.dart';
import '../services/app_state.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({Key? key}) : super(key: key);

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final DatabaseService _dbService = DatabaseService();
  final LocalDbService _localDbService = LocalDbService();
  
  List<String> _classes = ['All'];
  String _classFilter = 'All';
  
  DateTimeRange _dateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );
  
  bool _isLoading = true;
  int _presentCount = 0;
  int _absentCount = 0;
  int _totalStudents = 0;
  
  List<Student> _needsAttention = [];
  List<AttendanceRecord> _filteredRecords = [];
  
  List<DayTrend> _dailyTrends = [];
  List<double> _lineChartData = [0, 0, 0, 0, 0];
  List<String> _lineChartLabels = ['', '', '', '', ''];
  late VoidCallback _refreshListener;

  @override
  void initState() {
    super.initState();
    _loadProfileAndData();
    
    _refreshListener = () {
      if (mounted) _fetchReportData();
    };
    AppState.refreshNotifier.addListener(_refreshListener);
  }

  @override
  void dispose() {
    AppState.refreshNotifier.removeListener(_refreshListener);
    super.dispose();
  }

  Future<void> _loadProfileAndData() async {
    await _loadProfile();
    await _fetchReportData();
  }

  Future<void> _loadProfile() async {
    final profile = await _dbService.getCurrentUserProfile();
    if (mounted) {
      setState(() {
        if (profile?.role == 'teacher') {
          if (profile?.classId != null && profile?.classId != 'ALL') {
            final cls = '${profile!.classId} ${profile.section ?? 'A'}';
            _classes = [cls];
            _classFilter = cls;
          } else {
            // Security fix: If class ID is unknown, do NOT show all classes
            _classes = ['None'];
            _classFilter = 'None';
          }
        } else {
          // Admin: show all unique classes from local db
          final students = _localDbService.getAllStudents();
          final uniqueClasses = students.map((s) => '${s.classId} ${s.section}').toSet().toList();
          uniqueClasses.sort();
          _classes = ['All', ...uniqueClasses];
          _classFilter = 'All';
        }
      });
    }
  }

  Future<void> _fetchReportData() async {
    setState(() => _isLoading = true);
    try {
      final records = await _dbService.getAttendanceForDateRange(
        _dateRange.start, 
        _dateRange.end,
        classFilter: _classFilter, // This pulls all records for class number (e.g. 8)
      );
      
      // Also get local records for this time period just in case
      final localRecords = _localDbService.getAllReceivedAttendance().where((r) {
        return r.timestamp.isAfter(_dateRange.start.subtract(const Duration(days: 1))) &&
               r.timestamp.isBefore(_dateRange.end.add(const Duration(days: 1)));
      });
      
      List<AttendanceRecord> rawRecords = [...records, ...localRecords].toSet().toList();
      
      final allStudents = _localDbService.getAllStudents();
      List<Student> relevantStudents = allStudents;
      Set<String> validStudentIds = {};
      Set<String> validFingerprints = {};
      
      if (_classFilter != 'All') {
        // Correctly filter to ONLY this specific class and section (e.g. 8 A)
        relevantStudents = allStudents.where((s) => '${s.classId} ${s.section}' == _classFilter).toList();
        
        for (var s in relevantStudents) {
          validStudentIds.add(s.studentId);
          validFingerprints.add(s.fingerprintId.toString());
        }
        
        // Filter the raw records to only include students actually in this section
        _filteredRecords = rawRecords.where((r) {
          return validStudentIds.contains(r.studentId) || validFingerprints.contains(r.fingerprintId.toString());
        }).toList();
      } else {
        _filteredRecords = rawRecords;
      }

      int present = 0;
      int absent = 0;
      Set<String> uniqueStudents = {};
      
      // Calculate daily trends for the bar chart (last 5 days)
      Map<String, Map<String, int>> dailyCounts = {};
      
      // Group by Day + Student ID to prevent duplicates (if a sync happened multiple times in one day)
      Map<String, AttendanceRecord> uniqueDailyRecords = {};
      
      for (var r in _filteredRecords) {
        String dayKey = '${r.timestamp.year}-${r.timestamp.month.toString().padLeft(2, '0')}-${r.timestamp.day.toString().padLeft(2, '0')}';
        String studentKey = r.studentId.isNotEmpty ? r.studentId : r.fingerprintId.toString();
        String uniqueKey = '$dayKey-$studentKey';
        
        if (!uniqueDailyRecords.containsKey(uniqueKey) || r.timestamp.isAfter(uniqueDailyRecords[uniqueKey]!.timestamp)) {
          uniqueDailyRecords[uniqueKey] = r;
        }
      }
      
      for (var r in uniqueDailyRecords.values) {
        if (r.status != 'ABSENT') {
          present++;
        } else {
          absent++;
        }
        if (r.studentId.isNotEmpty) {
          uniqueStudents.add(r.studentId);
        }
        
        String dayKey = '${r.timestamp.year}-${r.timestamp.month.toString().padLeft(2, '0')}-${r.timestamp.day.toString().padLeft(2, '0')}';
        dailyCounts.putIfAbsent(dayKey, () => {'present': 0, 'absent': 0});
        if (r.status != 'ABSENT') {
          dailyCounts[dayKey]!['present'] = dailyCounts[dayKey]!['present']! + 1;
        } else {
          dailyCounts[dayKey]!['absent'] = dailyCounts[dayKey]!['absent']! + 1;
        }
      }
      
      // Generate last 5 days trend
      List<DayTrend> trends = [];
      List<String> days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      for (int i = 4; i >= 0; i--) {
        DateTime d = DateTime.now().subtract(Duration(days: i));
        String dayKey = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        int p = dailyCounts[dayKey]?['present'] ?? 0;
        int a = dailyCounts[dayKey]?['absent'] ?? 0;
        trends.add(DayTrend(day: days[d.weekday - 1], present: p, absent: a));
      }
      _dailyTrends = trends;
      
      // Generate line chart data (e.g. weekly averages)
      // For simplicity, just plot the 5 days percentage
      List<double> lineData = [];
      List<String> lineLabels = [];
      for (var t in trends) {
        double total = (t.present + t.absent).toDouble();
        double pct = total > 0 ? (t.present / total) * 100 : 0;
        lineData.add(pct);
        lineLabels.add(t.day);
      }
      // if everything is 0, give dummy data so chart doesn't crash
      if (lineData.every((e) => e == 0)) {
        lineData = [100, 100, 100, 100, 100];
      }
      _lineChartData = lineData;
      _lineChartLabels = lineLabels;
      
      // Calculate needs attention (bottom 5 attendance)
      // relevantStudents is already filtered based on _classFilter at the top
      
      _needsAttention = relevantStudents.toList();
      _needsAttention.sort((a, b) => a.attendancePct.compareTo(b.attendancePct));
      if (_needsAttention.length > 5) {
        _needsAttention = _needsAttention.sublist(0, 5);
      }

      if (mounted) {
        setState(() {
          _presentCount = present;
          _absentCount = absent;
          _totalStudents = relevantStudents.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _dateRange,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.sky500,
              onPrimary: Colors.white,
              onSurface: AppTheme.slate800,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _dateRange = picked);
      _fetchReportData();
    }
  }
  
  Future<void> _exportCsv() async {
    if (_filteredRecords.isEmpty) return;
    
    try {
      List<List<dynamic>> rows = [
        ['Event ID', 'Date', 'Time', 'Student ID', 'Student Name', 'Class', 'Status', 'Device ID', 'Confidence']
      ];

      for (var r in _filteredRecords) {
        rows.add([
          r.eventId,
          '${r.timestamp.year}-${r.timestamp.month}-${r.timestamp.day}',
          '${r.timestamp.hour}:${r.timestamp.minute.toString().padLeft(2, '0')}',
          r.studentId,
          r.studentName,
          r.classId,
          r.status,
          r.deviceId,
          r.confidence,
        ]);
      }

      String csv = const ListToCsvConverter().convert(rows);
      final directory = await getApplicationDocumentsDirectory();
      final path = '${directory.path}/attendance_report_${DateTime.now().millisecondsSinceEpoch}.csv';
      final file = File(path);
      await file.writeAsString(csv);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Report saved to $path', style: TextStyle(color: Colors.white)), backgroundColor: AppTheme.emerald500));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to export CSV: $e', style: TextStyle(color: Colors.white)), backgroundColor: AppTheme.red500));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.slate50,
      appBar: AppBar(
        title: const Text('Reports', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.slate800,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppTheme.slate100, height: 1),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _classes.map((c) {
                bool isSelected = _classFilter == c;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: InkWell(
                    onTap: () {
                      setState(() => _classFilter = c);
                      _fetchReportData();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.sky500 : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: isSelected
                            ? []
                            : [
                                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
                              ],
                      ),
                      child: Text(
                        c == 'All' ? 'Select Class' : 'Class $c',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isSelected ? Colors.white : AppTheme.slate500,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDateRange,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 16, color: AppTheme.slate400),
                  const SizedBox(width: 8),
                  Text(
                    '${_dateRange.start.day}/${_dateRange.start.month}/${_dateRange.start.year} – ${_dateRange.end.day}/${_dateRange.end.month}/${_dateRange.end.year}', 
                    style: const TextStyle(fontSize: 12, color: AppTheme.slate600, fontWeight: FontWeight.w600)
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Summary
          _isLoading 
          ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
          : Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _SumCard(label: 'Present', value: _presentCount > 0 ? '${((_presentCount / (_presentCount + _absentCount)) * 100).toStringAsFixed(1)}%' : '0%', color: AppTheme.emerald500),
                _SumCard(label: 'Absent', value: _absentCount > 0 ? '${((_absentCount / (_presentCount + _absentCount)) * 100).toStringAsFixed(1)}%' : '0%', color: AppTheme.red500),
                _SumCard(label: 'Total Students', value: '$_totalStudents', color: AppTheme.sky500),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Attendance Overview (Line Chart Placeholder)
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
                    const Text('Attendance Overview', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.slate700)),
                    InkWell(
                      onTap: _exportCsv,
                      child: Row(
                        children: const [
                          Icon(Icons.download, size: 14, color: AppTheme.sky500),
                          SizedBox(width: 4),
                          Text('Export', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.sky500)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(width: 12, height: 4, decoration: BoxDecoration(color: AppTheme.sky500, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 6),
                    const Text('Attendance %', style: TextStyle(fontSize: 12, color: AppTheme.slate400)),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 140,
                  width: double.infinity,
                  child: CustomPaint(painter: _LineChartPainter(data: _lineChartData, labels: _lineChartLabels)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Daily Breakdown
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
                const Text('Daily Breakdown (This Week)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.slate700)),
                const SizedBox(height: 24),
                SizedBox(
                  height: 150,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _dailyTrends.map((t) {
                      double total = (t.present + t.absent).toDouble();
                      if (total == 0) total = 1;
                      double maxH = 120;
                      // Max value dynamically scales, assume max 50 for display
                      double maxStudents = math.max(50, _totalStudents.toDouble());
                      double presentH = (t.present / maxStudents) * maxH; 
                      double absentH = (t.absent / maxStudents) * maxH;
                      
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                width: 12,
                                height: presentH,
                                decoration: const BoxDecoration(
                                  color: AppTheme.emerald500,
                                  borderRadius: BorderRadius.only(topLeft: Radius.circular(3), topRight: Radius.circular(3)),
                                ),
                              ),
                              const SizedBox(width: 2),
                              Container(
                                width: 12,
                                height: absentH,
                                decoration: BoxDecoration(
                                  color: AppTheme.red400.withOpacity(0.6),
                                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(3), topRight: Radius.circular(3)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(t.day, style: const TextStyle(fontSize: 10, color: AppTheme.slate400)),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Needs Attention
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
                const Text('Needs Attention', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.slate700)),
                const SizedBox(height: 16),
                if (_needsAttention.isEmpty)
                  const Text("No students require attention.", style: TextStyle(color: AppTheme.slate400, fontSize: 12)),
                ..._needsAttention.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: _NeedsAttentionRow(name: s.name, cls: '${s.classId} ${s.section}', pct: s.attendancePct),
                )).toList(),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SumCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SumCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.slate400)),
      ],
    );
  }
}

class _NeedsAttentionRow extends StatelessWidget {
  final String name;
  final String cls;
  final int pct;

  const _NeedsAttentionRow({required this.name, required this.cls, required this.pct});

  @override
  Widget build(BuildContext context) {
    Color color = pct < 75 ? AppTheme.red500 : AppTheme.amber500;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.slate700)),
              Text('Class $cls', style: const TextStyle(fontSize: 12, color: AppTheme.slate400)),
            ],
          ),
        ),
        SizedBox(
          width: 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct / 100,
                  backgroundColor: AppTheme.slate100,
                  color: color,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 4),
              Text('$pct%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> data;
  final List<String> labels;

  _LineChartPainter({required this.data, required this.labels});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppTheme.slate100
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    
    // Draw grid
    for(int i=0; i<4; i++) {
      double y = size.height * (i / 3) * 0.8;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final linePaint = Paint()
      ..color = AppTheme.sky500
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    final dotPaint = Paint()
      ..color = AppTheme.sky500
      ..style = PaintingStyle.fill;

    final path = Path();
    
    double minVal = 0;
    double maxVal = 100;
    
    // Scale minVal to make chart look dynamic if all data is grouped tightly
    double dataMin = data.reduce(math.min);
    if (dataMin > 50) minVal = 50;
    if (dataMin > 75) minVal = 70;
    
    for (int i = 0; i < data.length; i++) {
      double x = size.width * (i / (data.length - 1));
      double y = size.height * 0.8 * (1 - ((data[i] - minVal) / (maxVal - minVal)));
      
      // Clamp y
      if (y < 0) y = 0;
      if (y > size.height * 0.8) y = size.height * 0.8;
      
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    
    canvas.drawPath(path, linePaint);
    
    for (int i = 0; i < data.length; i++) {
      double x = size.width * (i / (data.length - 1));
      double y = size.height * 0.8 * (1 - ((data[i] - minVal) / (maxVal - minVal)));
      if (y < 0) y = 0;
      if (y > size.height * 0.8) y = size.height * 0.8;
      
      canvas.drawCircle(Offset(x, y), 4, dotPaint);
      
      final textSpan = TextSpan(
        text: labels[i],
        style: const TextStyle(color: AppTheme.slate400, fontSize: 10),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, size.height - 15));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
