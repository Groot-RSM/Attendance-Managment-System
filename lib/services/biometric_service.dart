import 'dart:io';
import 'package:path_provider/path_provider.dart';

class BiometricService {
  // Helper to compute a mock "similarity score" between two hex strings
  // Note: Real minutiae matching is proprietary to the R307 sensor. 
  // This uses byte-by-byte similarity as a functional approximation for the Dart side.
  static double _computeSimilarity(String hex1, String hex2) {
    if (hex1.isEmpty || hex2.isEmpty) return 0.0;
    
    int matches = 0;
    int minLen = hex1.length < hex2.length ? hex1.length : hex2.length;
    
    for (int i = 0; i < minLen; i += 2) {
      if (hex1.substring(i, i + 2) == hex2.substring(i, i + 2)) {
        matches++;
      }
    }
    
    return (matches / (minLen / 2)) * 100.0; // Percentage similarity 0-100
  }

  // Parses template.csv (T0) and all_scanned_templates.csv, runs medoid selection
  static Future<Map<int, String>> findBestTemplates(String scansCsvPath, String t0CsvPath, {double acceptThreshold = 50.0}) async {
    final scansFile = File(scansCsvPath);
    final t0File = File(t0CsvPath);
    
    if (!await scansFile.exists() || !await t0File.exists()) {
      throw Exception("Required files not found. Ensure both 'template.csv' and 'all_scanned_templates.csv' are synced.");
    }

    // Map: userId -> List of all templates (T0 + Scans)
    final Map<int, List<String>> userGalleries = {};

    // 1. Load Original T0 Templates
    final t0Lines = await t0File.readAsLines();
    for (int i = 1; i < t0Lines.length; i++) {
      final parts = t0Lines[i].split(',');
      if (parts.length >= 2) {
        final userId = int.tryParse(parts[0]) ?? -1;
        final hex = parts[1].trim();
        if (userId != -1 && hex.isNotEmpty) {
          userGalleries[userId] = [hex]; // T0 is the first entry
        }
      }
    }

    // 2. Load Scanned Templates
    final scanLines = await scansFile.readAsLines();
    for (int i = 1; i < scanLines.length; i++) {
      final parts = scanLines[i].split(',');
      if (parts.length >= 2) {
        final userId = int.tryParse(parts[0]) ?? -1;
        final hex = parts[1].trim();
        
        if (userId != -1 && hex.isNotEmpty) {
          if (!userGalleries.containsKey(userId)) {
            userGalleries[userId] = [];
          }
          
          // Verify scan quality against T0 (Sanity Check / Accept Threshold)
          if (userGalleries[userId]!.isNotEmpty) {
            double scoreVsT0 = _computeSimilarity(userGalleries[userId]!.first, hex);
            if (scoreVsT0 >= acceptThreshold) {
              userGalleries[userId]!.add(hex);
            }
          } else {
            userGalleries[userId]!.add(hex); // No T0 exists, just add it
          }
        }
      }
    }

    final Map<int, String> finalTemplates = {};

    // 3. Find Best Template (Medoid Selection)
    userGalleries.forEach((userId, gallery) {
      if (gallery.isEmpty) return;
      if (gallery.length == 1) {
        finalTemplates[userId] = gallery.first;
        return;
      }

      int bestIndex = 0;
      double highestAvgSim = -1.0;

      // Compare all pairs to find the template with highest average similarity to others
      for (int i = 0; i < gallery.length; i++) {
        double totalSim = 0;
        for (int j = 0; j < gallery.length; j++) {
          if (i != j) {
            totalSim += _computeSimilarity(gallery[i], gallery[j]);
          }
        }
        
        double avgSim = totalSim / (gallery.length - 1);
        if (avgSim > highestAvgSim) {
          highestAvgSim = avgSim;
          bestIndex = i;
        }
      }

      finalTemplates[userId] = gallery[bestIndex];
    });

    return finalTemplates;
  }

  // Generates a new CSV file containing the optimized templates
  static Future<File> generateOptimizedCsv(Map<int, String> bestTemplates) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/optimized_templates.csv');

    final sink = file.openWrite();
    sink.writeln("User ID,Scanned Template"); // Header
    
    final sortedKeys = bestTemplates.keys.toList()..sort();
    
    for (var id in sortedKeys) {
      sink.writeln("$id,${bestTemplates[id]}");
    }

    await sink.close();
    return file;
  }
}
