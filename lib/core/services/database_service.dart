import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/clip_item.dart';
import '../../models/peer_device.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._();
  factory DatabaseService() => _instance;
  DatabaseService._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
      return await databaseFactory.openDatabase(
        'clipsync.db',
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, version) async => await _createTables(db),
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 2) {
              await db.execute('DROP TABLE IF EXISTS clips');
            }
            await _createTables(db);
          },
        ),
      );
    } else if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      // Desktop: use FFI factory; store in ApplicationSupport (%LOCALAPPDATA%\ClipSync)
      // This folder IS removed when the Inno Setup uninstaller runs.
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final supportDir = await getApplicationSupportDirectory();
      final path = join(supportDir.path, 'clipsync.db');
      return await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, version) async => await _createTables(db),
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 2) {
              await db.execute('DROP TABLE IF EXISTS clips');
            }
            if (oldVersion < 3) {
              await _createPeersTable(db);
            }
            await _createTables(db);
          },
        ),
      );
    } else {
      // Android / iOS: use app-private support dir (wiped on uninstall)
      final supportDir = await getApplicationSupportDirectory();
      final path = join(supportDir.path, 'clipsync.db');

      return openDatabase(
        path,
        version: 3,
        onCreate: (db, version) async => await _createTables(db),
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('DROP TABLE IF EXISTS clips');
          }
          if (oldVersion < 3) {
            await _createPeersTable(db);
          }
        },
      );
    }
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS clips (
        id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        type TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        device_name TEXT NOT NULL,
        is_pinned INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS config (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await _createPeersTable(db);
  }

  Future<void> _createPeersTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS peers (
        peer_id   TEXT PRIMARY KEY,
        peer_name TEXT NOT NULL,
        public_key TEXT NOT NULL,
        last_seen INTEGER NOT NULL
      )
    ''');
  }

  // ── Clips ──────────────────────────────────────────────────────────────────

  Future<void> insertClip(ClipItem clip) async {
    final dbClient = await db;

    // ── Dedup 1: ID-based (handles re-sends of the exact same object) ─────────
    final existingById = await dbClient.query(
      'clips', where: 'id = ?', whereArgs: [clip.id], limit: 1,
    );
    if (existingById.isNotEmpty) {
      final existingTs = existingById.first['timestamp'] as int;
      if (clip.timestamp.millisecondsSinceEpoch <= existingTs) return;
    }

    // ── Dedup 2: Content+time window (handles MQTT QoS re-delivery & rapid copy)
    // If the SAME content from the SAME device arrived within the last 5 seconds,
    // skip — it is almost certainly a duplicate, not a new copy action.
    final fiveSecondsAgo = DateTime.now()
        .subtract(const Duration(seconds: 5))
        .millisecondsSinceEpoch;
    final existingByContent = await dbClient.query(
      'clips',
      where: 'content = ? AND device_name = ? AND timestamp > ?',
      whereArgs: [clip.content, clip.deviceName, fiveSecondsAgo],
      limit: 1,
    );
    if (existingByContent.isNotEmpty) return;

    await dbClient.insert('clips', clip.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    await _enforceSlidingWindow();
  }
  Future<void> updateSourceDeviceName(String oldName, String newName) async {
    final dbClient = await db;
    await dbClient.update(
      'clips',
      {'sourceDeviceName': newName},
      where: 'sourceDeviceName = ?',
      whereArgs: [oldName],
    );
  }

  // ── Configurable limit (driven by settings) ────────────────────────────────
  static int maxClips = 50; // default; only 50 active in v0.1.0

  Future<void> _enforceSlidingWindow() async {
    final dbClient = await db;
    final count = Sqflite.firstIntValue(
        await dbClient.rawQuery('SELECT COUNT(*) FROM clips'));
    if (count != null && count > maxClips) {
      final extraCount = count - maxClips;
      await dbClient.rawDelete('''
        DELETE FROM clips
        WHERE id IN (
          SELECT id FROM clips
          WHERE is_pinned = 0
          ORDER BY timestamp ASC
          LIMIT ?
        )
      ''', [extraCount]);
    }
  }

  Future<List<ClipItem>> getClips() async {
    final dbClient = await db;
    final maps = await dbClient.query('clips', orderBy: 'timestamp DESC');
    return maps.map((e) => ClipItem.fromMap(e)).toList();
  }

  Future<void> deleteClip(String id) async {
    final dbClient = await db;
    await dbClient.delete('clips', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> togglePinById(String id, bool isPinned) async {
    final dbClient = await db;
    await dbClient.update(
      'clips',
      {'is_pinned': isPinned ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteAllClips() async {
    final dbClient = await db;
    await dbClient.delete('clips'); // Drops all rows
  }

  // ── Config ─────────────────────────────────────────────────────────────────

  Future<void> setConfig(String key, String value) async {
    final dbClient = await db;
    await dbClient.insert('config', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getConfig(String key) async {
    final dbClient = await db;
    final results =
        await dbClient.query('config', where: 'key = ?', whereArgs: [key]);
    if (results.isNotEmpty) return results.first['value'] as String;
    return null;
  }

  // ── Peers ──────────────────────────────────────────────────────────────────

  Future<void> upsertPeer(PeerDevice peer) async {
    final dbClient = await db;
    await dbClient.insert('peers', peer.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<PeerDevice>> getPeers() async {
    final dbClient = await db;
    final maps = await dbClient.query('peers', orderBy: 'last_seen DESC');
    return maps.map((e) => PeerDevice.fromMap(e)).toList();
  }

  Future<void> removePeer(String peerId) async {
    final dbClient = await db;
    await dbClient.delete('peers', where: 'peer_id = ?', whereArgs: [peerId]);
  }

  Future<void> updatePeerLastSeen(String peerId) async {
    final dbClient = await db;
    await dbClient.update(
      'peers',
      {'last_seen': DateTime.now().millisecondsSinceEpoch},
      where: 'peer_id = ?',
      whereArgs: [peerId],
    );
  }

  /// Updates only the peer_name of an existing record, keyed by peer_id.
  /// Safe to call after a name change — never creates a duplicate row.
  Future<void> updatePeerName(String peerId, String newName) async {
    final dbClient = await db;
    await dbClient.update(
      'peers',
      {'peer_name': newName},
      where: 'peer_id = ?',
      whereArgs: [peerId],
    );
  }
}
