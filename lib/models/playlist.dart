enum PlaylistType { m3u, xtream }

class Playlist {
  final int? id;
  final String name;
  final PlaylistType type;
  final String url;
  final String? username;
  final String? password;
  final String? epgUrl;
  final DateTime lastUpdated;
  final DateTime? lastEpgSync;
  final Map<String, String>? headers;
  final int channelCount;

  Playlist({
    this.id,
    required this.name,
    required this.type,
    required this.url,
    this.username,
    this.password,
    this.epgUrl,
    DateTime? lastUpdated,
    this.lastEpgSync,
    this.headers,
    this.channelCount = 0,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  bool get isEpgStale {
    if (epgUrl == null || epgUrl!.trim().isEmpty) return false;
    if (lastEpgSync == null) return true;
    final age = DateTime.now().difference(lastEpgSync!);
    return age.inHours >= 12;
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'type': type.name,
      'url': url,
      'username': username,
      'password': password,
      'epg_url': epgUrl,
      'last_updated': lastUpdated.millisecondsSinceEpoch,
      'last_epg_sync': lastEpgSync?.millisecondsSinceEpoch,
    };
  }

  factory Playlist.fromMap(Map<String, dynamic> map) {
    return Playlist(
      id: map['id'] as int?,
      name: map['name'] as String,
      type: PlaylistType.values.byName(map['type'] as String),
      url: map['url'] as String,
      username: map['username'] as String?,
      password: map['password'] as String?,
      epgUrl: map['epg_url'] as String?,
      lastUpdated: DateTime.fromMillisecondsSinceEpoch(
        map['last_updated'] as int,
      ),
      lastEpgSync: map['last_epg_sync'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_epg_sync'] as int)
          : null,
      channelCount: (map['channel_count'] as int?) ?? 0,
    );
  }

  Playlist copyWith({
    int? id,
    String? name,
    PlaylistType? type,
    String? url,
    String? username,
    String? password,
    String? epgUrl,
    DateTime? lastUpdated,
    DateTime? lastEpgSync,
    Map<String, String>? headers,
    int? channelCount,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
      epgUrl: epgUrl ?? this.epgUrl,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      lastEpgSync: lastEpgSync ?? this.lastEpgSync,
      headers: headers ?? this.headers,
      channelCount: channelCount ?? this.channelCount,
    );
  }
}
