import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/device_id_store.dart';
import '../../data/datasources/last_call_store.dart';
import '../../data/datasources/matchmaking_data_source.dart';
import '../../data/services/livekit_service.dart';
import '../../data/services/matchmaking_waiting_audio.dart';
import '../../domain/entities/call_state.dart';

/// Orchestrates the random matchmaking + LiveKit audio call flow.
///
/// Flow:
///  1. [startRandomCall] → join queue → search for match
///  2. Match found → show "Partner Found" popup
///  3. Both users connect to the same LiveKit room
///  4. Audio call active
///  5. [hangUp] → clean up everything
///
/// Robustness features:
///  - **Heartbeat**: Updates Firestore every 10s so offline users aren't matched.
///  - **Retry loop**: Periodically retries [findMatch] to handle high contention.
///  - **Connecting timeout**: If partner doesn't join LiveKit within 20s, retries.
class CallController extends ChangeNotifier {
  CallController({
    MatchmakingDataSource? matchmakingDataSource,
    LastCallStore? lastCallStore,
    LiveKitService? liveKitService,
    DeviceIdStore? deviceIdStore,
    MatchmakingWaitingAudio? waitingAudio,
  }) : _matchmaking = matchmakingDataSource ?? MatchmakingDataSource(),
       _lastCallStore = lastCallStore ?? LastCallStore(),
       _liveKit = liveKitService ?? LiveKitService(),
       _deviceIdStore = deviceIdStore ?? DeviceIdStore(),
       _waitingAudio = waitingAudio ?? AssetMatchmakingWaitingAudio();

  final MatchmakingDataSource _matchmaking;
  final LastCallStore _lastCallStore;
  LiveKitService _liveKit;
  final DeviceIdStore _deviceIdStore;
  final MatchmakingWaitingAudio _waitingAudio;

  // ---------------------------------------------------------------------------
  // Observable state
  // ---------------------------------------------------------------------------

  CallState _state = CallState.idle;
  CallState get state => _state;

  String? _roomId;
  String? get roomId => _roomId;

  bool get isMuted => _liveKit.isMuted;
  bool get isSpeakerOn => _liveKit.isSpeakerOn;

  Duration _callDuration = Duration.zero;
  Duration get callDuration => _callDuration;

  Duration _searchDuration = Duration.zero;
  Duration get searchDuration => _searchDuration;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  Timer? _durationTimer;
  Timer? _searchTimer;
  Timer? _heartbeatTimer;
  Timer? _retryTimer;
  Timer? _connectingTimeoutTimer;
  final List<StreamSubscription> _subscriptions = [];

  String? _userId;
  String? _partnerId;
  bool _isReconnecting = false;
  bool _isHangingUp = false;
  bool _isDisposed = false;
  bool _matchHandled = false;

  /// Max retries when connecting timeout fires before giving up.
  static const int _maxConnectRetries = 2;
  int _connectRetryCount = 0;

  /// Maximum call duration (15 minutes).
  static const Duration maxCallDuration = Duration(minutes: 15);

  /// Time remaining before the call is auto-ended.
  Duration get remainingDuration {
    final remaining = maxCallDuration - _callDuration;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Whether the call is in the last 60 seconds.
  bool get isNearTimeLimit =>
      _state == CallState.connected &&
      remainingDuration <= const Duration(minutes: 1);

  // ---------------------------------------------------------------------------
  // Random matching flow
  // ---------------------------------------------------------------------------

  /// Starts the random matching process.
  Future<void> startRandomCall() async {
    if (_isDisposed) return;
    try {
      _isReconnecting = false;
      _partnerId = null;
      final userId = await _deviceIdStore.getOrCreateDeviceId();
      _userId = userId;
      _matchHandled = false;
      _connectRetryCount = 0;
      _setState(CallState.searching);
      _startSearchTimer();
      _startHeartbeat();

      // Join the matchmaking queue.
      await _matchmaking.joinQueue(userId);

      // Try to find a match immediately.
      await _attemptMatch();
    } catch (e) {
      if (_isDisposed) return;
      _errorMessage = e.toString();
      _setState(CallState.error);
    }
  }

  /// Rejoins the last shared room. The other user must also choose reconnect.
  Future<void> reconnectToLastUser({
    required String partnerId,
    required String roomId,
  }) async {
    if (_isDisposed) return;
    try {
      _isReconnecting = true;
      _partnerId = partnerId;
      _userId = await _deviceIdStore.getOrCreateDeviceId();
      if (_isDisposed) return;
      _connectRetryCount = 0;
      _matchHandled = false;
      _setState(CallState.searching);
      await _onMatchFound(
        MatchResult(partnerId: partnerId, roomId: roomId, role: 'caller'),
      );
    } catch (e) {
      if (_isDisposed) return;
      _errorMessage = 'Could not reconnect. Please try again.';
      _setState(CallState.error);
    }
  }

  /// Attempts to find a match. If none found, sets up passive listener
  /// AND a periodic retry loop.
  Future<void> _attemptMatch() async {
    if (_isDisposed || _matchHandled) return;
    if (_state != CallState.searching) return;

    final userId = _userId;
    if (userId == null) return;

    try {
      final match = await _matchmaking.findMatch(userId);

      if (_isDisposed || _matchHandled) return;

      if (match != null) {
        await _onMatchFound(match);
      } else {
        _startPassiveMatchHandling(userId);
      }
    } catch (e) {
      debugPrint('[CallController] findMatch error: $e');
      // Keep listening and retrying after transient Firestore failures.
      _startPassiveMatchHandling(userId);
    }
  }

  void _startPassiveMatchHandling(String userId) {
    if (_subscriptions.isEmpty) {
      _subscriptions.add(
        _matchmaking
            .onMatchFound(userId)
            .listen(
              (match) async {
                await _onMatchFound(match);
              },
              onError: (e) {
                debugPrint('[CallController] Match stream error: $e');
                if (!_isDisposed && _state == CallState.searching) {
                  _errorMessage = 'Connection error. Please try again.';
                  _setState(CallState.error);
                }
              },
            ),
      );
    }

    _retryTimer ??= Timer.periodic(
      const Duration(seconds: 3),
      (_) => _retryFindMatch(),
    );
  }

  /// Periodic retry of findMatch to handle contention with many users.
  Future<void> _retryFindMatch() async {
    if (_isDisposed || _matchHandled) {
      _retryTimer?.cancel();
      _retryTimer = null;
      return;
    }
    if (_state != CallState.searching) {
      _retryTimer?.cancel();
      _retryTimer = null;
      return;
    }

    final userId = _userId;
    if (userId == null) return;

    try {
      // Add a small random jitter to spread out concurrent retries.
      await Future.delayed(Duration(milliseconds: Random().nextInt(1000)));

      if (_isDisposed || _matchHandled) return;

      final match = await _matchmaking.findMatch(userId);

      if (_isDisposed || _matchHandled) return;

      if (match != null) {
        _retryTimer?.cancel();
        _retryTimer = null;
        await _onMatchFound(match);
      }
    } catch (e) {
      debugPrint('[CallController] Retry findMatch error: $e');
      // Silently retry next time.
    }
  }

  /// Cancels the search and removes from queue.
  Future<void> cancelSearch() async {
    await _waitingAudio.stop();
    _stopSearchTimers();

    await _cancelSubscriptions();

    final userId = _userId;
    if (userId != null) {
      try {
        await _matchmaking.leaveQueue(userId);
      } catch (_) {}
    }
    if (!_isDisposed) _setState(CallState.idle);
  }

  // ---------------------------------------------------------------------------
  // Match handling
  // ---------------------------------------------------------------------------

  Future<void> _onMatchFound(MatchResult match) async {
    // Guard: only handle the first match event.
    if (_matchHandled || _isDisposed) return;
    if (_state != CallState.searching) return;
    _matchHandled = true;

    _stopSearchTimers();
    await _cancelSubscriptions();

    _roomId = match.roomId;
    _partnerId = match.partnerId;

    // Show "Partner Found" state briefly.
    _setState(CallState.matched);

    // Small delay so the user sees the "Partner Found" popup.
    await Future.delayed(const Duration(seconds: 2));

    if (_isDisposed) return;
    if (_state != CallState.matched) return; // User may have cancelled.

    try {
      _setState(CallState.connecting);

      // Set up LiveKit callbacks before connecting.
      _setupLiveKitCallbacks();

      // Both users simply connect to the same LiveKit room.
      await _liveKit.connect(roomName: match.roomId, identity: _userId!);

      if (_isDisposed) return;

      // If partner is already in the room, we're connected.
      if (_liveKit.hasPartner) {
        _markConnected();
      } else {
        // Start connecting timeout — if partner doesn't join within 20s,
        // they're probably offline. Auto-retry matching.
        _startConnectingTimeout();
      }
    } catch (e) {
      if (_isDisposed) return;
      debugPrint('[CallController] LiveKit connect failed: $e');
      _errorMessage = 'Failed to connect. Please try again.';
      _setState(CallState.error);
    }
  }

  // ---------------------------------------------------------------------------
  // Connecting timeout — handles offline partner
  // ---------------------------------------------------------------------------

  /// Starts a 20-second timer. If partner doesn't join LiveKit by then,
  /// disconnects and goes back to searching.
  void _startConnectingTimeout() {
    _connectingTimeoutTimer?.cancel();
    _connectingTimeoutTimer = Timer(const Duration(seconds: 20), () {
      if (_isDisposed) return;
      if (_state != CallState.connecting) return;

      debugPrint('[CallController] Connecting timeout — partner is offline');
      _handlePartnerNoShow();
    });
  }

  /// Handles the case where the matched partner never showed up.
  /// Disconnects from LiveKit and goes back to searching.
  Future<void> _handlePartnerNoShow() async {
    if (_isDisposed) return;

    _connectingTimeoutTimer?.cancel();
    _connectingTimeoutTimer = null;

    // Clean up the failed connection.
    await _liveKit.dispose();

    final userId = _userId;
    if (userId == null || _isDisposed) return;

    if (_isReconnecting) {
      _isReconnecting = false;
      _errorMessage =
          'Your last partner is not available to reconnect right now.';
      _setState(CallState.error);
      return;
    }

    _connectRetryCount++;
    if (_connectRetryCount > _maxConnectRetries) {
      _errorMessage = 'Could not find an active partner. Please try again.';
      _setState(CallState.error);
      return;
    }

    debugPrint(
      '[CallController] Retrying matchmaking (attempt $_connectRetryCount)',
    );

    // Reset state and go back to searching with a fresh LiveKit instance.
    _matchHandled = false;
    _roomId = null;
    _liveKit = LiveKitService();
    _setState(CallState.searching);
    _startSearchTimer();
    _startHeartbeat();

    try {
      await _matchmaking.joinQueue(userId);
      await _attemptMatch();
    } catch (e) {
      if (_isDisposed) return;
      _errorMessage = e.toString();
      _setState(CallState.error);
    }
  }

  // ---------------------------------------------------------------------------
  // LiveKit callbacks
  // ---------------------------------------------------------------------------

  void _setupLiveKitCallbacks() {
    _liveKit.onPartnerJoined = () {
      if (_isDisposed) return;
      if (_state == CallState.connecting || _state == CallState.matched) {
        // Partner showed up — cancel the timeout.
        _markConnected();
      }
    };

    _liveKit.onPartnerLeft = () {
      if (_isDisposed) return;
      debugPrint('[CallController] Partner left the room');
      if (_state == CallState.connected) {
        hangUp();
      }
      // If still connecting, let the connecting timeout handle it — don't
      // hang up immediately as we might be waiting for a partner who hasn't
      // joined yet.
    };

    _liveKit.onDisconnected = () {
      if (_isDisposed) return;
      debugPrint('[CallController] Disconnected from room');
      if (_state == CallState.connected) {
        hangUp();
      } else if (_state == CallState.connecting) {
        // During connecting phase, a disconnect likely means the LiveKit room
        // was cleaned up server-side (empty room timeout). Retry matching
        // instead of showing an error.
        debugPrint(
          '[CallController] Disconnected during connecting — retrying',
        );
        _handlePartnerNoShow();
      }
    };
  }

  void _markConnected() {
    if (_isDisposed || _state == CallState.connected) return;
    _connectingTimeoutTimer?.cancel();
    _connectingTimeoutTimer = null;
    _setState(CallState.connected);
    _startDurationTimer();
    final roomId = _roomId;
    final partnerId = _partnerId;
    if (roomId != null && partnerId != null) {
      unawaited(() async {
        try {
          await _lastCallStore.save(partnerId: partnerId, roomId: roomId);
        } catch (e) {
          debugPrint('[CallController] Could not save last call: $e');
        }
      }());
    }
    unawaited(HapticFeedback.vibrate().catchError((_) {}));
  }

  // ---------------------------------------------------------------------------
  // Controls
  // ---------------------------------------------------------------------------

  /// Toggles the microphone mute state.
  Future<void> toggleMute() async {
    if (_isDisposed || _state != CallState.connected) return;
    await _liveKit.toggleMute();
    if (!_isDisposed) notifyListeners();
  }

  /// Toggles between earpiece and loudspeaker.
  Future<void> toggleSpeaker() async {
    if (_isDisposed || _state != CallState.connected) return;
    await _liveKit.toggleSpeaker();
    if (!_isDisposed) notifyListeners();
  }

  /// Ends the call and cleans up all resources.
  Future<void> hangUp() async {
    // Guard against being called multiple times.
    if (_isHangingUp) return;
    _isHangingUp = true;
    await _waitingAudio.stop();

    _stopAllTimers();
    await _cancelSubscriptions();
    await _liveKit.dispose();

    final userId = _userId;
    if (userId != null) {
      try {
        await _matchmaking.leaveQueue(userId);
      } catch (_) {}
    }

    _roomId = null;
    _callDuration = Duration.zero;
    _searchDuration = Duration.zero;
    if (!_isDisposed) _setState(CallState.ended);
    _isHangingUp = false;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Starts the heartbeat — updates Firestore every 10 seconds so other
  /// users know we're still online and eligible for matching.
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    final userId = _userId;
    if (userId == null) return;
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_isDisposed || _state != CallState.searching) {
        _heartbeatTimer?.cancel();
        _heartbeatTimer = null;
        return;
      }
      _matchmaking.updateHeartbeat(userId);
    });
  }

  void _stopSearchTimers() {
    _searchTimer?.cancel();
    _searchTimer = null;
    _searchDuration = Duration.zero;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _stopAllTimers() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _connectingTimeoutTimer?.cancel();
    _connectingTimeoutTimer = null;
    _stopSearchTimers();
  }

  Future<void> _cancelSubscriptions() async {
    for (final sub in _subscriptions) {
      try {
        await sub.cancel();
      } catch (_) {}
    }
    _subscriptions.clear();
  }

  void _startSearchTimer() {
    _searchDuration = Duration.zero;
    _searchTimer?.cancel();
    _searchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isDisposed) return;
      _searchDuration += const Duration(seconds: 1);
      notifyListeners();
    });
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _callDuration = Duration.zero;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isDisposed) return;
      _callDuration += const Duration(seconds: 1);
      notifyListeners();

      // Auto-hangup when the 15-minute limit is reached.
      if (_callDuration >= maxCallDuration) {
        debugPrint(
          '[CallController] 15-minute call limit reached — ending call',
        );
        hangUp();
      }
    });
  }

  void _setState(CallState newState) {
    if (_isDisposed) return;
    final wasSearching = _state == CallState.searching;
    _state = newState;
    if (newState == CallState.searching && !wasSearching) {
      unawaited(_waitingAudio.start());
    } else if (wasSearching && newState != CallState.searching) {
      unawaited(_waitingAudio.stop());
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _stopAllTimers();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _liveKit.dispose();
    unawaited(_waitingAudio.dispose());
    super.dispose();
  }
}
