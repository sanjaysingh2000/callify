/// Represents a live audio panel room.
class Panel {
  const Panel({
    required this.id,
    required this.title,
    required this.hostId,
    this.hostDisplayName = '',
    required this.status,
    required this.createdAt,
    required this.participantCount,
    this.durationMinutes = defaultDurationMinutes,
    this.kickedUserIds = const [],
    this.rejoinRequestUserIds = const [],
  });

  static const int defaultDurationMinutes = 60;

  final String id;
  final String title;
  final String hostId;
  final String hostDisplayName;

  /// 'live' or 'ended'.
  final String status;
  final DateTime createdAt;
  final int participantCount;
  final int durationMinutes;
  final List<String> kickedUserIds;
  final List<String> rejoinRequestUserIds;

  Duration get duration => Duration(minutes: durationMinutes);

  bool get isLive => status == 'live';

  Panel copyWith({
    String? id,
    String? title,
    String? hostId,
    String? hostDisplayName,
    String? status,
    DateTime? createdAt,
    int? participantCount,
    int? durationMinutes,
    List<String>? kickedUserIds,
    List<String>? rejoinRequestUserIds,
  }) {
    return Panel(
      id: id ?? this.id,
      title: title ?? this.title,
      hostId: hostId ?? this.hostId,
      hostDisplayName: hostDisplayName ?? this.hostDisplayName,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      participantCount: participantCount ?? this.participantCount,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      kickedUserIds: kickedUserIds ?? this.kickedUserIds,
      rejoinRequestUserIds: rejoinRequestUserIds ?? this.rejoinRequestUserIds,
    );
  }
}
