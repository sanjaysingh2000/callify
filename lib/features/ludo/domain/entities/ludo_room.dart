class LudoSeat {
  const LudoSeat({
    required this.userId,
    required this.displayName,
    required this.isMuted,
  });

  final String? userId;
  final String? displayName;
  final bool isMuted;

  bool get isOccupied => userId != null;

  factory LudoSeat.fromMap(Map<String, dynamic>? data) {
    final userId = data?['userId'];
    final displayName = data?['displayName'];
    final isMuted = data?['isMuted'];
    return LudoSeat(
      userId: userId is String && userId.isNotEmpty ? userId : null,
      displayName: displayName is String ? displayName : null,
      isMuted: isMuted is bool ? isMuted : true,
    );
  }

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'displayName': displayName,
    'isMuted': isMuted,
  };
}

class LudoRoom {
  const LudoRoom({
    required this.id,
    required this.title,
    required this.hostId,
    required this.status,
    required this.seats,
    required this.gameState,
    required this.gameUserIds,
  });

  final String id;
  final String title;
  final String hostId;
  final String status;
  final List<LudoSeat> seats;
  final Map<String, Object?>? gameState;
  final List<String> gameUserIds;

  int get playerCount => seats.where((seat) => seat.isOccupied).length;
  int get vacantSeats => seats.length - playerCount;
  bool get isLive => status == 'live';

  factory LudoRoom.fromDocument(String id, Map<String, dynamic> data) {
    final rawSeats = data['seats'];
    final seatValues = rawSeats is List ? rawSeats : const <Object?>[];
    final rawGameState = data['gameState'];
    final rawGameUserIds = data['gameUserIds'];
    return LudoRoom(
      id: id,
      title: data['title'] is String ? data['title'] as String : 'Ludo table',
      hostId: data['hostId'] is String ? data['hostId'] as String : '',
      status: data['status'] is String ? data['status'] as String : 'ended',
      seats: List.unmodifiable(
        List.generate(
          4,
          (index) =>
              _parseSeat(index < seatValues.length ? seatValues[index] : null),
        ),
      ),
      gameState: rawGameState is Map
          ? rawGameState.cast<String, Object?>()
          : null,
      gameUserIds: rawGameUserIds is List
          ? List.unmodifiable(rawGameUserIds.whereType<String>())
          : const [],
    );
  }

  static LudoSeat _parseSeat(Object? value) {
    if (value is! Map)
      return const LudoSeat(userId: null, displayName: null, isMuted: true);
    final data = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is String) data[entry.key as String] = entry.value;
    }
    return LudoSeat.fromMap(data);
  }
}
