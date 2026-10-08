import '../../../call/data/services/livekit_service.dart';

/// LiveKit connection used by panel rooms.
///
/// It deliberately connects with the microphone disabled. A panel listener
/// only starts publishing after they have been promoted and choose to unmute.
/// Keeping this as a thin extension means both call types share one LiveKit
/// token/connection implementation.
class PanelLiveKitService extends LiveKitService {
  @override
  Future<void> connect({
    required String roomName,
    required String identity,
    bool enableMicrophone = false,
  }) {
    return super.connect(
      roomName: roomName,
      identity: identity,
      enableMicrophone: enableMicrophone,
    );
  }
}
