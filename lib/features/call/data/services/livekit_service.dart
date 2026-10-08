import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../core/config/livekit_config.dart';

/// Callback typedefs for LiveKit events.
typedef VoidEventCallback = void Function();

/// Manages a LiveKit room connection for audio-only calls.
///
/// Replaces the raw WebRTC implementation — LiveKit handles TURN/STUN,
/// signaling, ICE candidates, and reconnection automatically.
class LiveKitService {
  static const MethodChannel _callForegroundChannel = MethodChannel(
    'quick_call/call_foreground_service',
  );

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  bool _isDisposed = false;

  bool _isMuted = false;
  bool _isSpeakerOn = true;

  /// Whether the local microphone is muted.
  bool get isMuted => _isMuted;

  /// Whether the local microphone is currently publishing audio.
  bool get isMicEnabled => !_isMuted;

  /// Whether the speaker (loudspeaker) is on.
  bool get isSpeakerOn => _isSpeakerOn;

  /// Whether the service is connected to a room.
  bool get isConnected => _room?.connectionState == ConnectionState.connected;

  // Callbacks
  VoidEventCallback? onPartnerJoined;
  VoidEventCallback? onPartnerLeft;
  VoidEventCallback? onDisconnected;
  void Function(String reason)? onError;

  // ---------------------------------------------------------------------------
  // LiveKit Cloud Configuration
  // ---------------------------------------------------------------------------

  static String get _serverUrl => LiveKitConfig.serverUrl;

  // ---------------------------------------------------------------------------
  // Token generation is intentionally handled by a backend service.
  // ---------------------------------------------------------------------------

  static Future<String> _generateToken({
    required String roomName,
    required String identity,
  }) {
    return LiveKitConfig.requestToken(roomName: roomName, identity: identity);
  }

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  /// Connects to a LiveKit room.
  ///
  /// [roomName] is the matchmaking room ID.
  /// [identity] is the user's unique ID.
  /// Throws on failure.
  Future<void> connect({
    required String roomName,
    required String identity,
    bool enableMicrophone = true,
  }) async {
    // Guard against connecting after disposal.
    if (_isDisposed) {
      throw StateError('Cannot connect: LiveKitService is disposed');
    }

    final token = await _generateToken(roomName: roomName, identity: identity);

    // Create the room with audio-optimised options.
    _room = Room(
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultAudioPublishOptions: AudioPublishOptions(
          dtx: true, // Save bandwidth during silence.
        ),
      ),
    );

    // Set up event listeners before connecting.
    _listener = _room!.createListener();
    _setupEventListeners();

    try {
      // Connect to LiveKit Cloud with a timeout.
      await _room!
          .connect(
            _serverUrl,
            token,
            connectOptions: const ConnectOptions(autoSubscribe: true),
          )
          .timeout(const Duration(seconds: 15));

      // Listeners in a panel must not publish until a host promotes them.
      _isMuted = !enableMicrophone;
      await _room!.localParticipant?.setMicrophoneEnabled(enableMicrophone);
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _callForegroundChannel.invokeMethod<void>('start');
      }

      debugPrint('[LiveKit] Connected to room: $roomName as $identity');
    } catch (e) {
      // Clean up on connection failure.
      _listener?.dispose();
      _listener = null;
      await _room?.dispose();
      _room = null;
      await _stopAndroidCallForegroundService();
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Event Handling
  // ---------------------------------------------------------------------------

  void _setupEventListeners() {
    _listener
      ?..on<ParticipantConnectedEvent>((event) {
        debugPrint('[LiveKit] Partner joined: ${event.participant.identity}');
        if (!_isDisposed) onPartnerJoined?.call();
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        debugPrint('[LiveKit] Partner left: ${event.participant.identity}');
        if (!_isDisposed) onPartnerLeft?.call();
      })
      ..on<RoomDisconnectedEvent>((event) {
        debugPrint('[LiveKit] Disconnected: ${event.reason}');
        if (!_isDisposed) onDisconnected?.call();
      })
      ..on<TrackSubscribedEvent>((event) {
        debugPrint(
          '[LiveKit] Subscribed to ${event.track.kind} from '
          '${event.participant.identity}',
        );
      })
      ..on<RoomReconnectingEvent>((_) {
        debugPrint('[LiveKit] Reconnecting...');
      })
      ..on<RoomReconnectedEvent>((_) {
        debugPrint('[LiveKit] Reconnected!');
      });
  }

  /// Returns true if a remote participant (partner) is in the room.
  bool get hasPartner => (_room?.remoteParticipants.length ?? 0) > 0;

  // ---------------------------------------------------------------------------
  // Audio Controls
  // ---------------------------------------------------------------------------

  /// Toggles the local microphone mute state.
  Future<void> toggleMute() async {
    if (_isMuted) {
      await enableMic();
    } else {
      await disableMic();
    }
  }

  /// Starts publishing microphone audio for the local participant.
  Future<void> enableMic() => _setMicrophoneEnabled(true);

  /// Stops publishing microphone audio for the local participant.
  Future<void> disableMic() => _setMicrophoneEnabled(false);

  Future<void> _setMicrophoneEnabled(bool enabled) async {
    if (_room == null || _isDisposed) return;
    final previousMuted = _isMuted;
    _isMuted = !enabled;
    try {
      await _room!.localParticipant?.setMicrophoneEnabled(enabled);
    } catch (e) {
      _isMuted = previousMuted;
      debugPrint('[LiveKit] set microphone state failed: $e');
    }
  }

  /// Toggles between earpiece and loudspeaker.
  Future<void> toggleSpeaker() async {
    if (_isDisposed) return;
    _isSpeakerOn = !_isSpeakerOn;
    try {
      await Hardware.instance.setSpeakerphoneOn(_isSpeakerOn);
    } catch (e) {
      // Revert state on failure.
      _isSpeakerOn = !_isSpeakerOn;
      debugPrint('[LiveKit] toggleSpeaker failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Disconnects from the room and disposes all resources.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    // Clear callbacks to prevent late-firing events.
    onPartnerJoined = null;
    onPartnerLeft = null;
    onDisconnected = null;
    onError = null;

    _listener?.dispose();
    _listener = null;

    try {
      await _room?.disconnect();
    } catch (e) {
      debugPrint('[LiveKit] disconnect error (ignored): $e');
    }
    try {
      await _room?.dispose();
    } catch (e) {
      debugPrint('[LiveKit] room dispose error (ignored): $e');
    }
    _room = null;
    await _stopAndroidCallForegroundService();

    _isMuted = false;
    _isSpeakerOn = true;

    debugPrint('[LiveKit] Disposed');
  }

  Future<void> _stopAndroidCallForegroundService() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _callForegroundChannel.invokeMethod<void>('stop');
    } catch (e) {
      debugPrint('[LiveKit] foreground service stop failed: $e');
    }
  }
}
