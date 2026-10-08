/// Represents the lifecycle states of an audio call.
enum CallState {
  /// No call is active.
  idle,

  /// User is in the matchmaking queue, looking for a partner.
  searching,

  /// A partner has been found — about to connect.
  matched,

  /// Connecting to the LiveKit room.
  connecting,

  /// Call is active and audio is flowing.
  connected,

  /// Call has ended normally.
  ended,

  /// An error occurred during the call.
  error,
}
