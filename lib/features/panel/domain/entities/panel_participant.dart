/// Roles within a panel room, ordered by hierarchy.
enum PanelRole {
  host,
  coHost,
  speaker,
  audience;

  /// Converts a Firestore string to a [PanelRole].
  static PanelRole fromString(String value) {
    switch (value) {
      case 'host':
        return PanelRole.host;
      case 'co-host':
        return PanelRole.coHost;
      case 'speaker':
        return PanelRole.speaker;
      case 'audience':
        return PanelRole.audience;
      default:
        return PanelRole.audience;
    }
  }

  /// Converts to a Firestore-storable string.
  String toFirestoreString() {
    switch (this) {
      case PanelRole.host:
        return 'host';
      case PanelRole.coHost:
        return 'co-host';
      case PanelRole.speaker:
        return 'speaker';
      case PanelRole.audience:
        return 'audience';
    }
  }
}

/// Represents a participant in a panel room.
class PanelParticipant {
  const PanelParticipant({
    required this.userId,
    required this.displayName,
    required this.role,
    this.isOnline = true,
    this.isMuted = true,
    this.micRequested = false,
    this.lastSeen,
    this.profileImageBase64,
  });

  final String userId;
  final String displayName;
  final PanelRole role;
  final bool isOnline;
  final bool isMuted;
  final bool micRequested;
  final DateTime? lastSeen;
  final String? profileImageBase64;

  bool get isHost => role == PanelRole.host;
  bool get isCoHost => role == PanelRole.coHost;
  bool get isSpeaker => role == PanelRole.speaker;
  bool get isAudience => role == PanelRole.audience;

  /// Whether this participant is allowed to speak (host, co-host, or speaker).
  bool get canSpeak =>
      role == PanelRole.host ||
      role == PanelRole.coHost ||
      role == PanelRole.speaker;

  /// Whether this participant's heartbeat is stale (>45 seconds old).
  bool get isStale {
    if (lastSeen == null) return false;
    return DateTime.now().difference(lastSeen!) > const Duration(seconds: 45);
  }

  bool get isActive => isOnline && !isStale;

  PanelParticipant copyWith({
    String? userId,
    String? displayName,
    PanelRole? role,
    bool? isOnline,
    bool? isMuted,
    bool? micRequested,
    DateTime? lastSeen,
    String? profileImageBase64,
  }) {
    return PanelParticipant(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      isOnline: isOnline ?? this.isOnline,
      isMuted: isMuted ?? this.isMuted,
      micRequested: micRequested ?? this.micRequested,
      lastSeen: lastSeen ?? this.lastSeen,
      profileImageBase64: profileImageBase64 ?? this.profileImageBase64,
    );
  }
}
