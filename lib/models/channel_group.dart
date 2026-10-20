class ChannelGroup {
  final int? id;
  final int playlistId;
  final String name;
  final int sortOrder;
  final bool isHidden;
  final int channelCount;

  ChannelGroup({
    this.id,
    required this.playlistId,
    required this.name,
    this.sortOrder = 0,
    this.isHidden = false,
    this.channelCount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'playlist_id': playlistId,
      'name': name,
      'sort_order': sortOrder,
      'is_hidden': isHidden ? 1 : 0,
    };
  }

  factory ChannelGroup.fromMap(
    Map<String, dynamic> map, {
    int channelCount = 0,
  }) {
    return ChannelGroup(
      id: map['id'] as int?,
      playlistId: map['playlist_id'] as int,
      name: map['name'] as String,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      isHidden: (map['is_hidden'] as int?) == 1,
      channelCount: channelCount,
    );
  }

  ChannelGroup copyWith({
    int? id,
    int? playlistId,
    String? name,
    int? sortOrder,
    bool? isHidden,
    int? channelCount,
  }) {
    return ChannelGroup(
      id: id ?? this.id,
      playlistId: playlistId ?? this.playlistId,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      isHidden: isHidden ?? this.isHidden,
      channelCount: channelCount ?? this.channelCount,
    );
  }
}
