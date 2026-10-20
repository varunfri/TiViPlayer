class Channel {
  final int? id;
  final int playlistId;
  final int groupId;
  final String? groupName;
  final int channelNumber;
  final String name;
  final String streamUrl;
  final String? logoUrl;
  final String? tvgId;
  final bool isFavorite;
  final bool isHidden;
  final int catchupDays;
  final int sortOrder;
  final String? drmType; // e.g. 'widevine', 'playready', 'clearkey'
  final String? drmLicenseUrl;
  final String? drmHeaders; // JSON-encoded key-value headers
  final bool isLive;
  final int? durationSeconds;

  Channel({
    this.id,
    required this.playlistId,
    required this.groupId,
    this.groupName,
    required this.channelNumber,
    required this.name,
    required this.streamUrl,
    this.logoUrl,
    this.tvgId,
    this.isFavorite = false,
    this.isHidden = false,
    this.catchupDays = 0,
    this.sortOrder = 0,
    this.drmType,
    this.drmLicenseUrl,
    this.drmHeaders,
    this.isLive = true,
    this.durationSeconds,
  });

  bool get isVod => !isLive;
  bool get hasDrm => drmType != null && drmType!.isNotEmpty;

  /// Returns in-app player URL (e.g. https://server:5000/mpd/760?q=auto)
  /// which renders the pure, borderless HTML5 player with Widevine DRM and Shaka Player.
  String? get inAppWebPlayerUrl {
    try {
      final u = Uri.parse(streamUrl);
      if (u.host.isEmpty) return null;

      String? id;
      if (tvgId != null && RegExp(r'^\d+$').hasMatch(tvgId!)) {
        id = tvgId;
      } else {
        final match = RegExp(
          r'/(?:live/)?(?:mpd/)?(\d+)(?:\.m3u8|\.mpd)?(?:\?|$)',
        ).firstMatch(streamUrl);
        id = match?.group(1);
      }

      if (id != null) {
        return '${u.origin}/mpd/$id?q=auto&pm=hd';
      }

      // Never treat raw media stream manifests (.m3u8, .ts, .mpd) as an HTML web player page
      final lower = streamUrl.toLowerCase();
      if (lower.contains('.m3u8') ||
          lower.contains('.ts') ||
          lower.contains('.mpd')) {
        return null;
      }

      if (u.scheme.startsWith('http') &&
          (lower.contains('/player') ||
              lower.contains('/play') ||
              lower.contains('.html'))) {
        return streamUrl;
      }
    } catch (_) {}
    return null;
  }

  /// Returns web player URL (e.g. https://server:5000/play/760) if this stream originates from JioTV Go or provides a web stream
  String? get webPlayerUrl {
    try {
      final u = Uri.parse(streamUrl);
      if (u.host.isEmpty) return null;

      String? id;
      if (tvgId != null && RegExp(r'^\d+$').hasMatch(tvgId!)) {
        id = tvgId;
      } else {
        final match = RegExp(
          r'/(?:live/)?(?:mpd/)?(\d+)(?:\.m3u8|\.mpd)?(?:\?|$)',
        ).firstMatch(streamUrl);
        id = match?.group(1);
      }

      if (id != null) {
        return '${u.origin}/play/$id';
      }

      // Never treat raw media stream manifests (.m3u8, .ts, .mpd) as an HTML web player page
      final lower = streamUrl.toLowerCase();
      if (lower.contains('.m3u8') ||
          lower.contains('.ts') ||
          lower.contains('.mpd')) {
        return null;
      }

      if (u.scheme.startsWith('http') &&
          (lower.contains('/player') ||
              lower.contains('/play') ||
              lower.contains('.html'))) {
        return streamUrl;
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'playlist_id': playlistId,
      'group_id': groupId,
      'channel_number': channelNumber,
      'name': name,
      'stream_url': streamUrl,
      'logo_url': logoUrl,
      'tvg_id': tvgId,
      'is_favorite': isFavorite ? 1 : 0,
      'is_hidden': isHidden ? 1 : 0,
      'catchup_days': catchupDays,
      'sort_order': sortOrder,
      'drm_type': drmType,
      'drm_license_url': drmLicenseUrl,
      'drm_headers': drmHeaders,
      'is_live': isLive ? 1 : 0,
      'duration_seconds': durationSeconds,
    };
  }

  factory Channel.fromMap(Map<String, dynamic> map, {String? groupName}) {
    return Channel(
      id: map['id'] as int?,
      playlistId: map['playlist_id'] as int,
      groupId: map['group_id'] as int,
      groupName: groupName ?? map['group_name'] as String?,
      channelNumber: (map['channel_number'] as int?) ?? 1,
      name: map['name'] as String,
      streamUrl: map['stream_url'] as String,
      logoUrl: map['logo_url'] as String?,
      tvgId: map['tvg_id'] as String?,
      isFavorite: (map['is_favorite'] as int?) == 1,
      isHidden: (map['is_hidden'] as int?) == 1,
      catchupDays: (map['catchup_days'] as int?) ?? 0,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      drmType: map['drm_type'] as String?,
      drmLicenseUrl: map['drm_license_url'] as String?,
      drmHeaders: map['drm_headers'] as String?,
      isLive: map['is_live'] == null ? true : (map['is_live'] as int) == 1,
      durationSeconds: map['duration_seconds'] as int?,
    );
  }

  Channel copyWith({
    int? id,
    int? playlistId,
    int? groupId,
    String? groupName,
    int? channelNumber,
    String? name,
    String? streamUrl,
    String? logoUrl,
    String? tvgId,
    bool? isFavorite,
    bool? isHidden,
    int? catchupDays,
    int? sortOrder,
    String? drmType,
    String? drmLicenseUrl,
    String? drmHeaders,
    bool? isLive,
    int? durationSeconds,
  }) {
    return Channel(
      id: id ?? this.id,
      playlistId: playlistId ?? this.playlistId,
      groupId: groupId ?? this.groupId,
      groupName: groupName ?? this.groupName,
      channelNumber: channelNumber ?? this.channelNumber,
      name: name ?? this.name,
      streamUrl: streamUrl ?? this.streamUrl,
      logoUrl: logoUrl ?? this.logoUrl,
      tvgId: tvgId ?? this.tvgId,
      isFavorite: isFavorite ?? this.isFavorite,
      isHidden: isHidden ?? this.isHidden,
      catchupDays: catchupDays ?? this.catchupDays,
      sortOrder: sortOrder ?? this.sortOrder,
      drmType: drmType ?? this.drmType,
      drmLicenseUrl: drmLicenseUrl ?? this.drmLicenseUrl,
      drmHeaders: drmHeaders ?? this.drmHeaders,
      isLive: isLive ?? this.isLive,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }
}
