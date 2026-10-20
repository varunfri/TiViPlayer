class RecordingItem {
  final int? id;
  final int channelId;
  final String channelName;
  final String? channelLogo;
  final String streamUrl;
  final String programTitle;
  final String? programDescription;
  final DateTime startTime;
  final DateTime endTime;
  final int preRollMinutes;
  final int postRollMinutes;
  final String filePath;
  final String
  status; // 'scheduled', 'recording', 'completed', 'cancelled', 'failed'
  final int bytesRecorded;
  final DateTime createdAt;

  const RecordingItem({
    this.id,
    required this.channelId,
    required this.channelName,
    this.channelLogo,
    required this.streamUrl,
    required this.programTitle,
    this.programDescription,
    required this.startTime,
    required this.endTime,
    this.preRollMinutes = 2,
    this.postRollMinutes = 5,
    required this.filePath,
    this.status = 'scheduled',
    this.bytesRecorded = 0,
    required this.createdAt,
  });

  Duration get duration => endTime.difference(startTime);

  bool get isRecording => status == 'recording';
  bool get isScheduled => status == 'scheduled';
  bool get isCompleted => status == 'completed';

  DateTime get effectiveStartTime =>
      startTime.subtract(Duration(minutes: preRollMinutes));

  DateTime get effectiveEndTime =>
      endTime.add(Duration(minutes: postRollMinutes));

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'channel_id': channelId,
      'channel_name': channelName,
      'channel_logo': channelLogo,
      'stream_url': streamUrl,
      'program_title': programTitle,
      'program_description': programDescription,
      'start_time': startTime.millisecondsSinceEpoch,
      'end_time': endTime.millisecondsSinceEpoch,
      'pre_roll_minutes': preRollMinutes,
      'post_roll_minutes': postRollMinutes,
      'file_path': filePath,
      'status': status,
      'bytes_recorded': bytesRecorded,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory RecordingItem.fromMap(Map<String, dynamic> map) {
    return RecordingItem(
      id: map['id'] as int?,
      channelId: map['channel_id'] as int,
      channelName: map['channel_name'] as String,
      channelLogo: map['channel_logo'] as String?,
      streamUrl: map['stream_url'] as String,
      programTitle: map['program_title'] as String,
      programDescription: map['program_description'] as String?,
      startTime: DateTime.fromMillisecondsSinceEpoch(map['start_time'] as int),
      endTime: DateTime.fromMillisecondsSinceEpoch(map['end_time'] as int),
      preRollMinutes: (map['pre_roll_minutes'] as int?) ?? 2,
      postRollMinutes: (map['post_roll_minutes'] as int?) ?? 5,
      filePath: map['file_path'] as String,
      status: map['status'] as String,
      bytesRecorded: (map['bytes_recorded'] as int?) ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  RecordingItem copyWith({
    int? id,
    int? channelId,
    String? channelName,
    String? channelLogo,
    String? streamUrl,
    String? programTitle,
    String? programDescription,
    DateTime? startTime,
    DateTime? endTime,
    int? preRollMinutes,
    int? postRollMinutes,
    String? filePath,
    String? status,
    int? bytesRecorded,
    DateTime? createdAt,
  }) {
    return RecordingItem(
      id: id ?? this.id,
      channelId: channelId ?? this.channelId,
      channelName: channelName ?? this.channelName,
      channelLogo: channelLogo ?? this.channelLogo,
      streamUrl: streamUrl ?? this.streamUrl,
      programTitle: programTitle ?? this.programTitle,
      programDescription: programDescription ?? this.programDescription,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      preRollMinutes: preRollMinutes ?? this.preRollMinutes,
      postRollMinutes: postRollMinutes ?? this.postRollMinutes,
      filePath: filePath ?? this.filePath,
      status: status ?? this.status,
      bytesRecorded: bytesRecorded ?? this.bytesRecorded,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
