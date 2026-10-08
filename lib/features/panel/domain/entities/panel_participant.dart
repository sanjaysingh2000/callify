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
    this.isMuted = true,
    this.micRequested = false,
  });

  final String userId;
  final String displayName;
  final PanelRole role;
  final bool isMuted;
  final bool micRequested;

  bool get isHost => role == PanelRole.host;
  bool get isCoHost => role == PanelRole.coHost;
  bool get isSpeaker => role == PanelRole.speaker;
  bool get isAudience => role == PanelRole.audience;

  /// Whether this participant is allowed to speak (host, co-host, or speaker).
  bool get canSpeak =>
      role == PanelRole.host ||
      role == PanelRole.coHost ||
      role == PanelRole.speaker;

  PanelParticipant copyWith({
    String? userId,
    String? displayName,
    PanelRole? role,
    bool? isMuted,
    bool? micRequested,
  }) {
    return PanelParticipant(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      isMuted: isMuted ?? this.isMuted,
      micRequested: micRequested ?? this.micRequested,
    );
  }
}
