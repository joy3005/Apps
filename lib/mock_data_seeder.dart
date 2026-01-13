import 'dart:math';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class MockDataSeeder {
  static final Random _random = Random();

  static Future<void> seedDatabase() async {
    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();

    print("--- STARTING SEEDING (6 Months: July 29 - Dec 29) ---");

    // Clear existing data first to avoid conflicts
    await db.delete('Cows');
    await db.delete('Milking');
    await db.delete('Cow_Events');

    // Define Time Window
    DateTime endDate = DateTime(2025, 12, 29); // Dec 29
    DateTime startDate = DateTime(2025, 07, 29); // July 29

    // 1. GENERATE 20 COWS
    for (int i = 1; i <= 20; i++) {
      String rfid = (1000 + i).toString();
      bool isMultiCycleGroup = i <= 10; // First 10 cows are complex

      // Cow Profile
      batch.insert('Cows', {
        'RFID': rfid,
        'PurchaseDate': '2023-01-01',
        'BirthYear': '2020',
        'CurrentMilkingCycle': isMultiCycleGroup
            ? 2
            : 1, // Group A is in Cycle 2 by Dec
        'CurrentStage': 'Milking',
        'CalfBirthDate': isMultiCycleGroup ? '2025-10-30' : '2024-05-20',
        'LastInjectionDate': '2025-08-30',
        'CowPicturePath': '',
      });

      // 2. GENERATE MILKING & EVENTS

      if (isMultiCycleGroup) {
        // --- GROUP A: MULTI-CYCLE (Complex) ---
        // Scenario: Milking (July-Aug) -> Dry (Sept-Oct) -> Birth -> Milking (Nov-Dec)

        // CYCLE 1 DATA (July 29 - Aug 30)
        // Add Multiple Injections for Cycle 1 (The scenario: trying to get pregnant for Cycle 2)
        _addEvent(batch, i, 1, 'Injection', '2025-07-05', 'Failed Attempt 1');
        _addEvent(batch, i, 1, 'Injection', '2025-07-25', 'Failed Attempt 2');
        _addEvent(
          batch,
          i,
          1,
          'Injection',
          '2025-08-15',
          'Successful',
        ); // Conception

        // Birth (Conception Aug 15 + 2.5 months "test gestation" = Oct 30)
        _addEvent(
          batch,
          i,
          1,
          'Birth',
          '2025-10-30',
          'Calf Born (Cycle 2 Start)',
        );

        // Loop Days
        int daysCount = endDate.difference(startDate).inDays;
        for (int day = 0; day <= daysCount; day++) {
          DateTime date = startDate.add(Duration(days: day));
          String dateStr = DateFormat('yyyy-MM-dd').format(date);

          // LOGIC:
          // Milking: July 29 - Aug 30
          // Dry: Aug 31 - Oct 30 (No Data)
          // Milking: Oct 31 - Dec 29

          bool isCycle1Milking = date.isBefore(DateTime(2025, 08, 31));
          bool isCycle2Milking = date.isAfter(DateTime(2025, 10, 30));

          if (isCycle1Milking) {
            _addMilkRecord(batch, i, dateStr, 1);
          } else if (isCycle2Milking) {
            _addMilkRecord(batch, i, dateStr, 2);
          }
          // Else: Dry Period (No rows inserted)
        }
      } else {
        // --- GROUP B: SINGLE CYCLE (Simple) ---
        // Continuous milking July 29 - Dec 29

        // History: One injection, One birth earlier in the year
        _addEvent(batch, i, 1, 'Injection', '2024-02-15', 'Success');
        _addEvent(
          batch,
          i,
          1,
          'Birth',
          '2024-11-20',
          'Calf Born',
        ); // Wait, birth inside window?
        // Let's just make them standard milking cycle 1

        int daysCount = endDate.difference(startDate).inDays;
        for (int day = 0; day <= daysCount; day++) {
          DateTime date = startDate.add(Duration(days: day));
          String dateStr = DateFormat('yyyy-MM-dd').format(date);
          _addMilkRecord(batch, i, dateStr, 1);
        }
      }
    }

    await batch.commit(noResult: true);
    print("--- SEEDING COMPLETE ---");
  }

  // Helper to insert Milk
  static void _addMilkRecord(Batch batch, int cowId, String date, int cycle) {
    double base = 12.0 + _random.nextInt(5);
    double m = base + _random.nextDouble();
    double e = base - 1.0 + _random.nextDouble();

    batch.insert('Milking', {
      'CowID': cowId,
      'Date': date,
      'Time': 'Morning',
      'CycleNumber': cycle,
      'MorningMilk': double.parse(m.toStringAsFixed(2)),
      'EveningMilk': 0,
      'TotalMilk': double.parse(m.toStringAsFixed(2)),
      'IsSynced': 0,
    });

    batch.insert('Milking', {
      'CowID': cowId,
      'Date': date,
      'Time': 'Evening',
      'CycleNumber': cycle,
      'MorningMilk': 0,
      'EveningMilk': double.parse(e.toStringAsFixed(2)),
      'TotalMilk': double.parse(e.toStringAsFixed(2)),
      'IsSynced': 0,
    });
  }

  // Helper to insert Event
  static void _addEvent(
    Batch batch,
    int cowId,
    int cycle,
    String type,
    String date,
    String note,
  ) {
    batch.insert('Cow_Events', {
      'CowID': cowId,
      'CycleNumber': cycle,
      'EventType': type,
      'EventDate': date,
      'Notes': note,
    });
  }

  static Future<void> clearDatabase() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('Cows');
    await db.delete('Milking');
    await db.delete('Cow_Events');
    print("DATABASE CLEARED");
  }
}
