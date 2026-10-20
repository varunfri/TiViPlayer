import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'app_platform.dart';
import '../models/playlist.dart';
import '../models/channel_group.dart';
import '../models/channel.dart';
import '../models/epg_program.dart';
import '../models/recording_item.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('tv_player.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    String path;
    if (AppPlatform.isWeb) {
      databaseFactory = databaseFactoryFfiWebNoWebWorker;
      path = filePath;
    } else {
      try {
        databaseFactory;
      } catch (_) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
      final dbPath = await getApplicationDocumentsDirectory();
      path = join(dbPath.path, filePath);
    }

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onOpen: (db) async {
        try {
          await db.execute('ALTER TABLE channels ADD COLUMN drm_type TEXT;');
        } catch (_) {}
        try {
          await db.execute(
            'ALTER TABLE channels ADD COLUMN drm_license_url TEXT;',
          );
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE channels ADD COLUMN drm_headers TEXT;');
        } catch (_) {}
        try {
          await db.execute(
            'ALTER TABLE playlists ADD COLUMN last_epg_sync INTEGER DEFAULT 0;',
          );
        } catch (_) {}
        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS recordings (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              channel_id INTEGER NOT NULL,
              channel_name TEXT NOT NULL,
              channel_logo TEXT,
              stream_url TEXT NOT NULL,
              program_title TEXT NOT NULL,
              program_description TEXT,
              start_time INTEGER NOT NULL,
              end_time INTEGER NOT NULL,
              pre_roll_minutes INTEGER DEFAULT 2,
              post_roll_minutes INTEGER DEFAULT 5,
              file_path TEXT NOT NULL,
              status TEXT NOT NULL,
              bytes_recorded INTEGER DEFAULT 0,
              created_at INTEGER NOT NULL,
              FOREIGN KEY (channel_id) REFERENCES channels (id) ON DELETE CASCADE
            );
          ''');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_recordings_status ON recordings(status, start_time);',
          );
        } catch (_) {}
        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS app_settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            );
          ''');
        } catch (_) {}
        try {
          await db.execute(
            'ALTER TABLE channels ADD COLUMN is_live INTEGER DEFAULT 1;',
          );
        } catch (_) {}
        try {
          await db.execute(
            'ALTER TABLE channels ADD COLUMN duration_seconds INTEGER DEFAULT -1;',
          );
        } catch (_) {}
      },
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Playlists Table
    await db.execute('''
      CREATE TABLE playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        url TEXT NOT NULL,
        username TEXT,
        password TEXT,
        epg_url TEXT,
        last_updated INTEGER NOT NULL,
        last_epg_sync INTEGER DEFAULT 0
      )
    ''');

    // 2. Channel Groups
    await db.execute('''
      CREATE TABLE channel_groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        sort_order INTEGER DEFAULT 0,
        is_hidden INTEGER DEFAULT 0,
        FOREIGN KEY (playlist_id) REFERENCES playlists (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_groups_playlist ON channel_groups(playlist_id, sort_order);',
    );

    // 3. Channels Table
    await db.execute('''
      CREATE TABLE channels (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id INTEGER NOT NULL,
        group_id INTEGER NOT NULL,
        channel_number INTEGER DEFAULT 1,
        name TEXT NOT NULL,
        stream_url TEXT NOT NULL,
        logo_url TEXT,
        tvg_id TEXT,
        is_favorite INTEGER DEFAULT 0,
        is_hidden INTEGER DEFAULT 0,
        catchup_days INTEGER DEFAULT 0,
        sort_order INTEGER DEFAULT 0,
        drm_type TEXT,
        drm_license_url TEXT,
        drm_headers TEXT,
        is_live INTEGER DEFAULT 1,
        duration_seconds INTEGER DEFAULT -1,
        FOREIGN KEY (playlist_id) REFERENCES playlists (id) ON DELETE CASCADE,
        FOREIGN KEY (group_id) REFERENCES channel_groups (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_channels_group ON channels(group_id, is_hidden, sort_order);',
    );
    await db.execute('CREATE INDEX idx_channels_tvg_id ON channels(tvg_id);');

    // 4. EPG Programs Table
    await db.execute('''
      CREATE TABLE epg_programs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        channel_tvg_id TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        start_time INTEGER NOT NULL,
        end_time INTEGER NOT NULL,
        category TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_epg_timeline ON epg_programs(channel_tvg_id, start_time, end_time);',
    );

    // 5. App Settings & Playback Resume State Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  // --- PLAYLIST OPERATIONS ---
  Future<List<Playlist>> getPlaylists() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT p.*, COUNT(c.id) as channel_count
      FROM playlists p
      LEFT JOIN channels c ON c.playlist_id = p.id
      GROUP BY p.id
      ORDER BY p.id ASC
    ''');
    return result.map((m) => Playlist.fromMap(m)).toList();
  }

  Future<int> insertPlaylist(Playlist playlist) async {
    final db = await database;
    return await db.insert('playlists', playlist.toMap());
  }

  Future<void> deletePlaylist(int id) async {
    final db = await database;
    await db.delete('epg_programs');
    await db.delete('channels', where: 'playlist_id = ?', whereArgs: [id]);
    await db.delete(
      'channel_groups',
      where: 'playlist_id = ?',
      whereArgs: [id],
    );
    await db.delete('playlists', where: 'id = ?', whereArgs: [id]);
    await db.delete(
      'app_settings',
      where: 'key LIKE ?',
      whereArgs: ['playlist_${id}_%'],
    );
    final lastPid = await getSetting('last_playlist_id');
    if (lastPid == id.toString()) {
      await deleteSetting('last_playlist_id');
      await deleteSetting('last_playlist_name');
      await deleteSetting('last_playlist_url');
    }
  }

  Future<void> renamePlaylist(int id, String newName) async {
    final db = await database;
    await db.update(
      'playlists',
      {'name': newName, 'last_updated': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updatePlaylistEpgUrl(int id, String? epgUrl) async {
    final db = await database;
    await db.update(
      'playlists',
      {
        'epg_url': epgUrl,
        'last_updated': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updatePlaylistEpgSyncTime(int id, int timestamp) async {
    final db = await database;
    await db.update(
      'playlists',
      {'last_epg_sync': timestamp},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> getFutureEpgProgramCountForPlaylist(int playlistId) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = await db.rawQuery(
      '''
      SELECT COUNT(p.id) as count
      FROM epg_programs p
      WHERE p.end_time >= ?
        AND (
          p.channel_tvg_id IN (
            SELECT DISTINCT tvg_id FROM channels WHERE playlist_id = ? AND tvg_id IS NOT NULL AND tvg_id != ''
          )
          OR LOWER(p.channel_tvg_id) IN (
            SELECT DISTINCT LOWER(name) FROM channels WHERE playlist_id = ?
          )
        )
    ''',
      [now, playlistId, playlistId],
    );

    if (result.isNotEmpty && result.first['count'] != null) {
      return (result.first['count'] as int?) ?? 0;
    }
    return 0;
  }

  Future<int> getChannelCount(int playlistId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM channels WHERE playlist_id = ?',
      [playlistId],
    );
    if (result.isNotEmpty && result.first['count'] != null) {
      return (result.first['count'] as int?) ?? 0;
    }
    return 0;
  }

  // --- CHANNEL GROUP OPERATIONS ---
  Future<List<ChannelGroup>> getGroups(int playlistId) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT g.*, COUNT(c.id) as channel_count
      FROM channel_groups g
      LEFT JOIN channels c ON c.group_id = g.id AND c.is_hidden = 0
      WHERE g.playlist_id = ? AND g.is_hidden = 0
      GROUP BY g.id
      ORDER BY g.sort_order ASC, g.name ASC
    ''',
      [playlistId],
    );

    return result
        .map(
          (m) => ChannelGroup.fromMap(
            m,
            channelCount: (m['channel_count'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  // --- CHANNEL OPERATIONS ---
  Future<List<Channel>> getChannels({
    required int playlistId,
    int? groupId,
    bool favoritesOnly = false,
    String? searchQuery,
  }) async {
    final db = await database;
    String whereClause = 'c.playlist_id = ? AND c.is_hidden = 0';
    List<dynamic> whereArgs = [playlistId];

    if (favoritesOnly) {
      whereClause += ' AND c.is_favorite = 1';
    } else if (groupId != null) {
      whereClause += ' AND c.group_id = ?';
      whereArgs.add(groupId);
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      whereClause += ' AND c.name LIKE ?';
      whereArgs.add('%${searchQuery.trim()}%');
    }

    final result = await db.rawQuery('''
      SELECT c.*, g.name as group_name
      FROM channels c
      LEFT JOIN channel_groups g ON g.id = c.group_id
      WHERE $whereClause
      ORDER BY c.sort_order ASC, c.channel_number ASC, c.name ASC
    ''', whereArgs);

    return result.map((m) => Channel.fromMap(m)).toList();
  }

  Future<void> toggleFavorite(int channelId, bool isFavorite) async {
    final db = await database;
    await db.update(
      'channels',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [channelId],
    );
  }

  // --- EPG OPERATIONS ---
  Future<EpgProgram?> getCurrentProgram(String tvgId) async {
    if (tvgId.isEmpty) return null;
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final lower = tvgId.toLowerCase();

    final result = await db.query(
      'epg_programs',
      where:
          '(channel_tvg_id = ? OR LOWER(channel_tvg_id) = ?) AND start_time <= ? AND end_time >= ?',
      whereArgs: [tvgId, lower, now, now],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return EpgProgram.fromMap(result.first);
    }
    return null;
  }

  Future<Map<String, EpgProgram>> getLivePrograms() async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = await db.query(
      'epg_programs',
      where: 'start_time <= ? AND end_time >= ?',
      whereArgs: [now, now],
    );

    final Map<String, EpgProgram> map = {};
    for (final row in result) {
      final prog = EpgProgram.fromMap(row);
      final key = prog.channelTvgId.trim().toLowerCase();
      if (key.isNotEmpty) {
        map[key] = prog;
      }
    }
    return map;
  }

  Future<List<EpgProgram>> getUpcomingPrograms(
    String tvgId, {
    int limit = 5,
  }) async {
    if (tvgId.isEmpty) return [];
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final lower = tvgId.toLowerCase();

    final result = await db.query(
      'epg_programs',
      where:
          '(channel_tvg_id = ? OR LOWER(channel_tvg_id) = ?) AND end_time >= ?',
      whereArgs: [tvgId, lower, now],
      orderBy: 'start_time ASC',
      limit: limit,
    );

    return result.map((m) => EpgProgram.fromMap(m)).toList();
  }

  Future<int> getEpgProgramsCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM epg_programs',
    );
    if (result.isNotEmpty && result.first['count'] != null) {
      return (result.first['count'] as int?) ?? 0;
    }
    return 0;
  }

  Future<void> saveEpgPrograms(
    List<EpgProgram> epgList, {
    bool clearExisting = false,
  }) async {
    if (epgList.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      if (clearExisting) {
        await txn.delete('epg_programs');
      } else {
        // Clean expired programs older than 24 hours
        final cutoff = DateTime.now()
            .subtract(const Duration(hours: 24))
            .millisecondsSinceEpoch;
        await txn.delete(
          'epg_programs',
          where: 'end_time < ?',
          whereArgs: [cutoff],
        );
      }

      const chunkSize = 500;
      for (var i = 0; i < epgList.length; i += chunkSize) {
        final end = (i + chunkSize < epgList.length)
            ? i + chunkSize
            : epgList.length;
        final chunk = epgList.sublist(i, end);
        final batch = txn.batch();
        for (final prog in chunk) {
          batch.insert('epg_programs', prog.toMap());
        }
        await batch.commit(noResult: true);
      }
    });
  }

  // --- BATCH INSERTS ---
  Future<void> saveParsedPlaylistData({
    required int playlistId,
    required Map<String, List<Channel>> groupedChannels,
    List<EpgProgram>? epgList,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      int groupOrder = 0;
      int globalChannelNum = 1;

      for (final entry in groupedChannels.entries) {
        final groupName = entry.key;
        final channels = entry.value;

        // Insert group
        final groupId = await txn.insert('channel_groups', {
          'playlist_id': playlistId,
          'name': groupName,
          'sort_order': groupOrder++,
          'is_hidden': 0,
        });

        // Insert channels in batch
        final batch = txn.batch();
        for (final ch in channels) {
          batch.insert('channels', {
            'playlist_id': playlistId,
            'group_id': groupId,
            'channel_number': globalChannelNum++,
            'name': ch.name,
            'stream_url': ch.streamUrl,
            'logo_url': ch.logoUrl,
            'tvg_id': ch.tvgId,
            'is_favorite': 0,
            'is_hidden': 0,
            'catchup_days': ch.catchupDays,
            'sort_order': ch.sortOrder,
          });
        }
        await batch.commit(noResult: true);
      }

      // Insert EPG programs
      if (epgList != null && epgList.isNotEmpty) {
        final epgBatch = txn.batch();
        for (final prog in epgList) {
          epgBatch.insert('epg_programs', prog.toMap());
        }
        await epgBatch.commit(noResult: true);
      }
    });
  }

  // --- RECORDINGS OPERATIONS ---
  Future<int> insertRecording(RecordingItem item) async {
    final db = await database;
    return await db.insert('recordings', item.toMap());
  }

  Future<void> updateRecordingStatus(int id, String status) async {
    final db = await database;
    await db.update(
      'recordings',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateRecordingProgress(int id, int bytesRecorded) async {
    final db = await database;
    await db.update(
      'recordings',
      {'bytes_recorded': bytesRecorded},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateRecordingFileAndStatus(
    int id,
    String filePath,
    String status,
    int bytesRecorded,
  ) async {
    final db = await database;
    await db.update(
      'recordings',
      {
        'file_path': filePath,
        'status': status,
        'bytes_recorded': bytesRecorded,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<RecordingItem>> getAllRecordings() async {
    final db = await database;
    final result = await db.query('recordings', orderBy: 'start_time DESC');
    return result.map((m) => RecordingItem.fromMap(m)).toList();
  }

  Future<List<RecordingItem>> getActiveOrScheduledRecordings() async {
    final db = await database;
    final result = await db.query(
      'recordings',
      where: "status IN ('scheduled', 'recording')",
      orderBy: 'start_time ASC',
    );
    return result.map((m) => RecordingItem.fromMap(m)).toList();
  }

  Future<RecordingItem?> getRecordingById(int id) async {
    final db = await database;
    final result = await db.query(
      'recordings',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return RecordingItem.fromMap(result.first);
    }
    return null;
  }

  Future<void> deleteRecording(int id) async {
    final db = await database;
    await db.delete('recordings', where: 'id = ?', whereArgs: [id]);
  }

  // --- APP SETTINGS & RESUME STATE OPERATIONS ---
  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveSettings(Map<String, String> entries) async {
    if (entries.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final entry in entries.entries) {
        batch.insert('app_settings', {
          'key': entry.key,
          'value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final result = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return result.first['value'] as String?;
    }
    return null;
  }

  Future<Map<String, String>> getAllSettings() async {
    final db = await database;
    final result = await db.query('app_settings');
    final map = <String, String>{};
    for (final row in result) {
      final k = row['key'] as String?;
      final v = row['value'] as String?;
      if (k != null && v != null) {
        map[k] = v;
      }
    }
    return map;
  }

  Future<void> deleteSetting(String key) async {
    final db = await database;
    await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
  }

  Future<void> deleteSettingsWithPrefix(String prefix) async {
    final db = await database;
    await db.delete(
      'app_settings',
      where: 'key LIKE ?',
      whereArgs: ['$prefix%'],
    );
  }
}
