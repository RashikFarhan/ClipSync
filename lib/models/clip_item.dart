class ClipItem {
  final String id;
  final String content;
  final String type;
  final DateTime timestamp;
  final String deviceName;
  final bool isPinned;

  ClipItem({
    required this.id,
    required this.content,
    required this.type,
    required this.timestamp,
    required this.deviceName,
    required this.isPinned,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'content': content,
      'type': type,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'device_name': deviceName,
      'is_pinned': isPinned ? 1 : 0,
    };
  }

  factory ClipItem.fromMap(Map<String, dynamic> map) {
    return ClipItem(
      id: map['id'] as String,
      content: map['content'] as String,
      type: map['type'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      deviceName: map['device_name'] as String,
      isPinned: (map['is_pinned'] as int) == 1,
    );
  }

  ClipItem copyWith({
    String? id,
    String? content,
    String? type,
    DateTime? timestamp,
    String? deviceName,
    bool? isPinned,
  }) {
    return ClipItem(
      id: id ?? this.id,
      content: content ?? this.content,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      deviceName: deviceName ?? this.deviceName,
      isPinned: isPinned ?? this.isPinned,
    );
  }
}
