import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:jeyam_dairy/database_helper.dart';

class SyncService {
  // MAKE SURE THIS ENDS IN /exec, NOT /dev
  static const String _googleScriptUrl =
      "https://script.google.com/macros/s/AKfycbyZrPhP8lron-Jh-rJLFERdNd4Fs4U5RVOg4iJcI1WT_nxw2odARLOszITtKreTPx4JKw/exec";

  // Returns "Success" or the Error Message
  static Future<String> syncToCloud() async {
    final db = await DatabaseHelper.instance.database;
    String statusLog = "";

    try {
      // 1. CHECK DATA EXISTENCE
      final List<Map<String, dynamic>> allCows = await db.query('Cows');
      final List<Map<String, dynamic>> unsyncedMilk = await db.query(
        'Milking',
        where: 'IsSynced = ?',
        whereArgs: [0],
      );

      print(
        "DEBUG: Found ${allCows.length} Cows and ${unsyncedMilk.length} Unsynced Milk records.",
      );

      if (allCows.isEmpty && unsyncedMilk.isEmpty) {
        return "No data to sync.";
      }

      // 2. SYNC COWS
      if (allCows.isNotEmpty) {
        print("DEBUG: Sending Cows...");
        List<Map<String, dynamic>> processedCows = allCows.map((c) {
          Map<String, dynamic> row = Map.from(c);
          int birthYear = int.parse(row['BirthYear'].toString());
          row['Age'] = DateTime.now().year - birthYear;
          return row;
        }).toList();

        final cowResponse = await http.post(
          Uri.parse(_googleScriptUrl),
          body: jsonEncode({"type": "cows", "data": processedCows}),
        );

        print(
          "DEBUG: Cow Response: ${cowResponse.statusCode} - ${cowResponse.body}",
        );

        if (cowResponse.statusCode == 302) {
          // Redirects are fine, usually handled automatically by http package
          // If we got here manually, it might mean the followRedirects failed?
          // Usually 200 is expected for Google Scripts.
        }

        if (cowResponse.statusCode != 200 && cowResponse.statusCode != 302) {
          return "Cow Sync Failed: HTTP ${cowResponse.statusCode}";
        }
      }

      // 3. SYNC MILK
      if (unsyncedMilk.isNotEmpty) {
        print("DEBUG: Sending Milk...");
        final milkResponse = await http.post(
          Uri.parse(_googleScriptUrl),
          body: jsonEncode({"type": "milk", "data": unsyncedMilk}),
        );

        print(
          "DEBUG: Milk Response: ${milkResponse.statusCode} - ${milkResponse.body}",
        );

        if (milkResponse.statusCode == 200 || milkResponse.statusCode == 302) {
          await _markAsSynced(unsyncedMilk);
          statusLog += "Milk Synced. ";
        } else {
          return "Milk Sync Failed: HTTP ${milkResponse.statusCode}";
        }
      }

      return "Success";
    } catch (e) {
      print("CRITICAL ERROR: $e");
      return "Error: $e";
    }
  }

  static Future<void> _markAsSynced(List<Map<String, dynamic>> rows) async {
    final db = await DatabaseHelper.instance.database;
    var batch = db.batch();
    for (var row in rows) {
      batch.update(
        'Milking',
        {'IsSynced': 1},
        where: 'MilkingID = ?',
        whereArgs: [row['MilkingID']],
      );
    }
    await batch.commit(noResult: true);
  }
}
