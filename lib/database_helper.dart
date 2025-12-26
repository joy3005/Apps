import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('jeyam_dairy.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    // 1. Cows Table
    await db.execute('''
    CREATE TABLE Cows (
      CowID INTEGER PRIMARY KEY AUTOINCREMENT,
      RFID TEXT NOT NULL UNIQUE,
      CowPicturePath TEXT,
      PurchaseDate TEXT NOT NULL,
      BirthYear TEXT NOT NULL,
      CurrentMilkingCycle INTEGER NOT NULL,
      CurrentStage TEXT NOT NULL,
      CalfBirthDate TEXT,
      LastInjectionDate TEXT
    )
    ''');

    // 2. Milking Data Table
    await db.execute('''
    CREATE TABLE Milking (
      MilkingID INTEGER PRIMARY KEY AUTOINCREMENT,
      CowID INTEGER NOT NULL,
      Date TEXT NOT NULL, 
      Time TEXT NOT NULL, 
      CycleNumber INTEGER NOT NULL,
      MorningMilk REAL DEFAULT 0,
      EveningMilk REAL DEFAULT 0,
      TotalMilk REAL DEFAULT 0,
      IsSynced INTEGER DEFAULT 0,
      FOREIGN KEY (CowID) REFERENCES Cows(CowID) ON DELETE CASCADE
    )
    ''');

    // 3. NEW: Cow Events Table (For History like Gestation)
    await db.execute('''
    CREATE TABLE Cow_Events (
      EventID INTEGER PRIMARY KEY AUTOINCREMENT,
      CowID INTEGER NOT NULL,
      CycleNumber INTEGER NOT NULL,
      EventType TEXT NOT NULL, -- "Injection", "Birth"
      EventDate TEXT NOT NULL,
      Notes TEXT,
      FOREIGN KEY (CowID) REFERENCES Cows(CowID) ON DELETE CASCADE
    )
    ''');

    // 4. Indexes
    await db.execute('CREATE INDEX idx_milking_cow_id ON Milking(CowID)');
    await db.execute('CREATE INDEX idx_milking_date ON Milking(Date)');
    await db.execute('CREATE INDEX idx_milking_synced ON Milking(IsSynced)');
  }

  // --- CRUD OPERATIONS ---
  Future<int> addCow(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('Cows', row);
  }

  Future<Map<String, dynamic>?> getCowByRFID(String rfid) async {
    final db = await instance.database;
    final maps = await db.query('Cows', where: 'RFID = ?', whereArgs: [rfid]);
    if (maps.isNotEmpty) return maps.first;
    return null;
  }

  Future<Map<String, dynamic>?> getCowById(int id) async {
    final db = await instance.database;
    final maps = await db.query('Cows', where: 'CowID = ?', whereArgs: [id]);
    if (maps.isNotEmpty) return maps.first;
    return null;
  }

  Future<int> updateCow(Map<String, dynamic> cow) async {
    final db = await instance.database;
    int id = cow['CowID'];
    return await db.update('Cows', cow, where: 'CowID = ?', whereArgs: [id]);
  }

  Future<int> insertMilkRecord(Map<String, dynamic> row) async {
    final db = await instance.database;
    final existingRows = await db.query(
      'Milking',
      where: 'CowID = ? AND Date = ? AND Time = ?',
      whereArgs: [row['CowID'], row['Date'], row['Time']],
    );

    if (existingRows.isNotEmpty) {
      final id = existingRows.first['MilkingID'];
      return await db.update(
        'Milking',
        row,
        where: 'MilkingID = ?',
        whereArgs: [id],
      );
    } else {
      return await db.insert('Milking', row);
    }
  }

  Future<List<Map<String, dynamic>>> getMilkDataForReport(int days) async {
    final db = await instance.database;
    final dateThreshold = DateTime.now().subtract(Duration(days: days));
    final dateStr = dateThreshold.toIso8601String().substring(0, 10);
    return await db.query(
      'Milking',
      where: 'Date >= ?',
      whereArgs: [dateStr],
      orderBy: 'Date ASC',
    );
  }

  // --- METRICS & INSIGHTS ---

  // 1. Summary Card Data
  Future<Map<String, dynamic>> getCowInsights(
    int cowID,
    int currentCycle,
  ) async {
    final db = await instance.database;
    Map<String, dynamic> insights = {};

    // Current Cycle Stats
    final currentStats = await db.rawQuery(
      '''
      SELECT AVG(TotalMilk) as AvgMilk, MAX(TotalMilk) as MaxMilk, MIN(TotalMilk) as MinMilk, COUNT(*) as DaysMilked
      FROM Milking WHERE CowID = ? AND CycleNumber = ?
    ''',
      [cowID, currentCycle],
    );

    if (currentStats.isNotEmpty) insights['Current'] = currentStats.first;

    // Simple History List
    final historyStats = await db.rawQuery(
      '''
      SELECT CycleNumber, AVG(TotalMilk) as AvgMilk, COUNT(*) as DaysMilked
      FROM Milking WHERE CowID = ? GROUP BY CycleNumber ORDER BY CycleNumber ASC
    ''',
      [cowID],
    );
    insights['History'] = historyStats;

    // Current Dry/Gestation Status (from Cows table)
    final cowProfile = await db.query(
      'Cows',
      where: 'CowID = ?',
      whereArgs: [cowID],
    );
    if (cowProfile.isNotEmpty) {
      var c = cowProfile.first;
      String purchaseDateStr = c['PurchaseDate'] as String;
      String? injectionDateStr = c['LastInjectionDate'] as String?;
      String? calfDateStr = c['CalfBirthDate'] as String?;

      DateTime purchaseDate = DateTime.parse(purchaseDateStr);
      DateTime now = DateTime.now();
      int totalDaysOwned = now.difference(purchaseDate).inDays;

      final totalMilkedResult = await db.rawQuery(
        'SELECT COUNT(*) as Count FROM Milking WHERE CowID = ?',
        [cowID],
      );
      int totalMilkedDays = Sqflite.firstIntValue(totalMilkedResult) ?? 0;

      insights['DryDays'] = (totalDaysOwned - totalMilkedDays).clamp(0, 9999);

      if (injectionDateStr != null &&
          injectionDateStr.isNotEmpty &&
          calfDateStr != null &&
          calfDateStr.isNotEmpty) {
        DateTime injectionDate = DateTime.parse(injectionDateStr);
        DateTime calfDate = DateTime.parse(calfDateStr);
        insights['GestationDays'] = calfDate.difference(injectionDate).inDays;
      } else {
        insights['GestationDays'] = null;
      }
    }
    return insights;
  }

  // 2. NEW: History Graph Data
  Future<Map<String, List<Map<String, dynamic>>>> getCowHistoryMetrics(
    int cowID,
  ) async {
    final db = await instance.database;

    // A. MILK HISTORY
    final milkRes = await db.rawQuery(
      '''
      SELECT CycleNumber as x, AVG(TotalMilk) as y 
      FROM Milking WHERE CowID = ? GROUP BY CycleNumber ORDER BY CycleNumber ASC
    ''',
      [cowID],
    );

    // B. DRY DAYS HISTORY (Calculated from Gaps in Milking)
    // Logic: Find Last Date of Cycle N and First Date of Cycle N+1
    List<Map<String, dynamic>> dryDaysData = [];
    final cycleDates = await db.rawQuery(
      '''
      SELECT CycleNumber, MIN(Date) as StartDate, MAX(Date) as EndDate
      FROM Milking WHERE CowID = ? GROUP BY CycleNumber ORDER BY CycleNumber ASC
    ''',
      [cowID],
    );

    for (int i = 0; i < cycleDates.length - 1; i++) {
      // Compare Cycle 1 EndDate to Cycle 2 StartDate
      DateTime endCurr = DateTime.parse(cycleDates[i]['EndDate'] as String);
      DateTime startNext = DateTime.parse(
        cycleDates[i + 1]['StartDate'] as String,
      );
      int gap = startNext.difference(endCurr).inDays;

      // "Cycle 2" dry days corresponds to the gap BEFORE Cycle 2 started
      dryDaysData.add({
        "x": cycleDates[i + 1]['CycleNumber'],
        "y": gap.toDouble(),
      });
    }

    // C. GESTATION HISTORY (From Events Table)
    // We look for pairs of "Injection" and "Birth" in the same cycle
    List<Map<String, dynamic>> gestationData = [];
    final events = await db.query(
      'Cow_Events',
      where: 'CowID = ?',
      orderBy: 'EventDate ASC',
      whereArgs: [cowID],
    );

    // Group by Cycle
    Map<int, Map<String, String>> cycleEvents = {};
    for (var e in events) {
      int c = e['CycleNumber'] as int;
      if (!cycleEvents.containsKey(c)) cycleEvents[c] = {};
      cycleEvents[c]![e['EventType'] as String] = e['EventDate'] as String;
    }

    cycleEvents.forEach((cycle, dates) {
      if (dates.containsKey('Injection') && dates.containsKey('Birth')) {
        DateTime inj = DateTime.parse(dates['Injection']!);
        DateTime birth = DateTime.parse(dates['Birth']!);
        int days = birth.difference(inj).inDays;
        gestationData.add({"x": cycle, "y": days.toDouble()});
      }
    });

    return {"milk": milkRes, "dry": dryDaysData, "gestation": gestationData};
  }
}
