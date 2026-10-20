class EpgProgram {
  final int? id;
  final String channelTvgId;
  final String title;
  final String? description;
  final DateTime startTime;
  final DateTime endTime;
  final String? category;

  EpgProgram({
    this.id,
    required this.channelTvgId,
    required this.title,
    this.description,
    required this.startTime,
    required this.endTime,
    this.category,
  });

  bool get isLiveNow {
    final now = DateTime.now();
    return now.isAfter(startTime) && now.isBefore(endTime);
  }

  double get progress {
    final now = DateTime.now();
    if (now.isBefore(startTime)) return 0.0;
    if (now.isAfter(endTime)) return 1.0;
    final total = endTime.difference(startTime).inSeconds;
    if (total <= 0) return 0.0;
    final elapsed = now.difference(startTime).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  int get durationMinutes => endTime.difference(startTime).inMinutes;

  int get remainingMinutes {
    final now = DateTime.now();
    if (now.isAfter(endTime)) return 0;
    return endTime.difference(now).inMinutes;
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'channel_tvg_id': channelTvgId,
      'title': title,
      'description': description,
      'start_time': startTime.millisecondsSinceEpoch,
      'end_time': endTime.millisecondsSinceEpoch,
      'category': category,
    };
  }

  factory EpgProgram.fromMap(Map<String, dynamic> map) {
    return EpgProgram(
      id: map['id'] as int?,
      channelTvgId: map['channel_tvg_id'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      startTime: DateTime.fromMillisecondsSinceEpoch(map['start_time'] as int),
      endTime: DateTime.fromMillisecondsSinceEpoch(map['end_time'] as int),
      category: map['category'] as String?,
    );
  }
}
