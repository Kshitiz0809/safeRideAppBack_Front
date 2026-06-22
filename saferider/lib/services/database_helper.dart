import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../models/telemetry_window.dart';
import '../models/ride_session.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() {
    return _instance;
  }

  DatabaseHelper._internal();

  Future<Database> get database async {
    _database ??= await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final dbPath = path.join(documentsDirectory.path, 'saferider.db');

    return openDatabase(
      dbPath,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // TelemetryWindow table
    await db.execute('''
      CREATE TABLE telemetry_windows (
        id TEXT PRIMARY KEY,
        ride_id TEXT,
        timestamp TEXT NOT NULL,
        speed REAL NOT NULL,
        max_roll REAL NOT NULL,
        max_cornering_intensity REAL NOT NULL,
        jerk_variance REAL NOT NULL,
        window_score REAL NOT NULL,
        is_synced INTEGER DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // RideSession table
    await db.execute('''
      CREATE TABLE ride_sessions (
        ride_id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT,
        total_distance REAL NOT NULL,
        final_score REAL NOT NULL,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Index for faster queries
    await db.execute('''
      CREATE INDEX idx_ride_id ON telemetry_windows(ride_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_is_synced ON telemetry_windows(is_synced)
    ''');

    await db.execute('''
      CREATE INDEX idx_user_id ON ride_sessions(user_id)
    ''');
  }

  // TelemetryWindow operations
  Future<void> insertTelemetryWindow(TelemetryWindow window) async {
    final db = await database;
    await db.insert(
      'telemetry_windows',
      window.toSQLiteMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<TelemetryWindow>> getTelemetryWindowsByRideId(String rideId) async {
    final db = await database;
    final maps = await db.query(
      'telemetry_windows',
      where: 'ride_id = ?',
      whereArgs: [rideId],
      orderBy: 'timestamp ASC',
    );
    return maps.map((m) => TelemetryWindow.fromSQLiteMap(m)).toList();
  }

  Future<List<TelemetryWindow>> getUnSyncedTelemetryWindows() async {
    final db = await database;
    final maps = await db.query(
      'telemetry_windows',
      where: 'is_synced = ?',
      whereArgs: [0],
      orderBy: 'timestamp ASC',
    );
    return maps.map((m) => TelemetryWindow.fromSQLiteMap(m)).toList();
  }

  Future<void> markTelemetryWindowsAsSynced(List<String> windowIds) async {
    final db = await database;
    for (final id in windowIds) {
      await db.update(
        'telemetry_windows',
        {'is_synced': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> deleteTelemetryWindow(String id) async {
    final db = await database;
    await db.delete(
      'telemetry_windows',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteTelemetryWindowsByRideId(String rideId) async {
    final db = await database;
    await db.delete(
      'telemetry_windows',
      where: 'ride_id = ?',
      whereArgs: [rideId],
    );
  }

  // RideSession operations
  Future<void> insertRideSession(RideSession session) async {
    final db = await database;
    await db.insert(
      'ride_sessions',
      session.toSQLiteMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<RideSession?> getRideSessionById(String rideId) async {
    final db = await database;
    final maps = await db.query(
      'ride_sessions',
      where: 'ride_id = ?',
      whereArgs: [rideId],
    );

    if (maps.isNotEmpty) {
      return RideSession.fromSQLiteMap(maps.first);
    }
    return null;
  }

  Future<List<RideSession>> getRideSessionsByUserId(String userId) async {
    final db = await database;
    final maps = await db.query(
      'ride_sessions',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'start_time DESC',
    );
    return maps.map((m) => RideSession.fromSQLiteMap(m)).toList();
  }

  Future<void> updateRideSession(RideSession session) async {
    final db = await database;
    await db.update(
      'ride_sessions',
      session.toSQLiteMap(),
      where: 'ride_id = ?',
      whereArgs: [session.rideId],
    );
  }

  Future<void> deleteRideSession(String rideId) async {
    final db = await database;
    await db.delete(
      'ride_sessions',
      where: 'ride_id = ?',
      whereArgs: [rideId],
    );
  }

  Future<void> deleteAllRideDataForUser(String userId) async {
    final db = await database;
    final rides = await db.query(
      'ride_sessions',
      columns: ['ride_id'],
      where: 'user_id = ?',
      whereArgs: [userId],
    );

    for (final ride in rides) {
      final rideId = ride['ride_id'] as String;
      await db.delete(
        'telemetry_windows',
        where: 'ride_id = ?',
        whereArgs: [rideId],
      );
    }

    await db.delete(
      'ride_sessions',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  Future<int> getTelemetryWindowCount({String? rideId}) async {
    final db = await database;
    final result = await db.rawQuery(
      rideId != null
          ? 'SELECT COUNT(*) as count FROM telemetry_windows WHERE ride_id = ?'
          : 'SELECT COUNT(*) as count FROM telemetry_windows',
      rideId != null ? [rideId] : [],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> closeDatabase() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
