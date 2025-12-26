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
    // Note: We don't have a unique constraint on (CowID, Date, Time) in the schema,
    // so we handle the uniqueness logic in the Dart code below.
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
  }

  // --- CRUD OPERATIONS ---

  // Add a Cow
  Future<int> addCow(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('Cows', row);
  }

  // Find Cow by RFID
  Future<Map<String, dynamic>?> getCowByRFID(String rfid) async {
    final db = await instance.database;
    final maps = await db.query('Cows', where: 'RFID = ?', whereArgs: [rfid]);
    if (maps.isNotEmpty) return maps.first;
    return null;
  }

  // --- CRITICAL UPDATE: LOGIC TO PREVENT DUPLICATES ---
  Future<int> insertMilkRecord(Map<String, dynamic> row) async {
    final db = await instance.database;

    // 1. CHECK IF RECORD EXISTS
    // We look for a row with the same CowID, Date, and Time (Morning/Evening)
    final existingRows = await db.query(
      'Milking',
      where: 'CowID = ? AND Date = ? AND Time = ?',
      whereArgs: [row['CowID'], row['Date'], row['Time']],
    );

    if (existingRows.isNotEmpty) {
      // 2. UPDATE EXISTING RECORD
      // If found, we update the weight (overwrite the old value)
      // We also reset 'IsSynced' to 0 so the updated value gets sent to the cloud.
      final id = existingRows.first['MilkingID'];

      return await db.update(
        'Milking',
        row, // The new data overwrites the old data
        where: 'MilkingID = ?',
        whereArgs: [id],
      );
    } else {
      // 3. INSERT NEW RECORD
      // If not found, create a fresh entry
      return await db.insert('Milking', row);
    }
  }

  // Get Weekly Data for Graphs
  Future<List<Map<String, dynamic>>> getWeeklyData() async {
    final db = await instance.database;
    return await db.rawQuery(
      'SELECT * FROM Milking ORDER BY Date DESC LIMIT 7',
    );
  }

  // --- REPORTING QUERIES ---

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

  // --- UPDATE OPERATIONS ---

  Future<int> updateCow(Map<String, dynamic> cow) async {
    final db = await instance.database;
    int id = cow['CowID'];
    return await db.update('Cows', cow, where: 'CowID = ?', whereArgs: [id]);
  }
}
