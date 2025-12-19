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
      Time TEXT NOT NULL, -- Added Time to track Morning vs Evening exactly
      CycleNumber INTEGER NOT NULL,
      MorningMilk REAL DEFAULT 0,
      EveningMilk REAL DEFAULT 0,
      TotalMilk REAL DEFAULT 0,
      IsSynced INTEGER DEFAULT 0,
      FOREIGN KEY (CowID) REFERENCES Cows(CowID) ON DELETE CASCADE
    )
    ''');
  }

  // --- CRUD OPERATIONS ---

  // Add a Cow
  Future<int> addCow(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('Cows', row);
  }

  // Find Cow by RFID (Used by Home Page Listener)
  Future<Map<String, dynamic>?> getCowByRFID(String rfid) async {
    final db = await instance.database;
    final maps = await db.query('Cows', where: 'RFID = ?', whereArgs: [rfid]);
    if (maps.isNotEmpty) return maps.first;
    return null;
  }

  // Save Milk Record
  Future<int> insertMilkRecord(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('Milking', row);
  }

  // Get Weekly Data for Graphs
  Future<List<Map<String, dynamic>>> getWeeklyData() async {
    final db = await instance.database;
    // Simple query to get last 7 entries
    return await db.rawQuery(
      'SELECT * FROM Milking ORDER BY Date DESC LIMIT 7',
    );
  }

  // Check if cow was already milked this session (Morning/Evening)
  Future<bool> isCowMilkedToday(int cowID, String date, String session) async {
    final db = await instance.database;
    // We define "Session" based on time, but for now let's assume
    // we pass 'Morning' or 'Evening' to check logic later.
    // Simpler rule: Check if entry exists for this Cow + Date + Time(Morning/Evening)
    // Note: Our table stores 'Time' as string. Let's strict check that.

    final result = await db.query(
      'Milking',
      where: 'CowID = ? AND Date = ? AND Time = ?',
      whereArgs: [cowID, date, session],
    );
    return result.isNotEmpty;
  }

  // --- REPORTING QUERIES ---

  // Get data for the last X days (7 or 30)
  Future<List<Map<String, dynamic>>> getMilkDataForReport(int days) async {
    final db = await instance.database;
    // Get date X days ago
    final dateThreshold = DateTime.now().subtract(Duration(days: days));
    final dateStr = dateThreshold.toIso8601String().substring(0, 10);

    return await db.query(
      'Milking',
      where: 'Date >= ?',
      whereArgs: [dateStr],
      orderBy: 'Date ASC', // Oldest first for the Bar Chart
    );
  }

  // --- UPDATE OPERATIONS ---

  Future<int> updateCow(Map<String, dynamic> cow) async {
    final db = await instance.database;
    int id = cow['CowID'];
    return await db.update('Cows', cow, where: 'CowID = ?', whereArgs: [id]);
  }
}
