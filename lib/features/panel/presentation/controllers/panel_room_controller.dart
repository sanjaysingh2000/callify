import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/device_id_store.dart';
import '../../data/datasources/panel_data_source.dart';
import '../../data/services/panel_livekit_service.dart';
import '../../domain/entities/panel.dart';
import '../../domain/entities/panel_participant.dart';

/// Manages the live panel room — participants, roles, mic, and LiveKit connection.
///
/// Bugs fixed (v2):
///  - Host can go back without ending panel; panel only ends when host
///    explicitly taps "End Panel".
///  - Kick detection waits for first valid participant snapshot before checking.
///  - Duplicate `leavePanel()` calls are idempotent.
///  - Error state is exposed properly for the UI to show.
///  - Host rejoining is detected via Firestore participant doc.
class PanelRoomController extends ChangeNotifier {
  PanelRoomController({
    PanelDataSource? panelDataSource,
    PanelLiveKitService? liveKitService,
    DeviceIdStore? deviceIdStore,
  }) : _dataSource = panelDataSource ?? PanelDataSource(),
       _liveKit = liveKitService ?? PanelLiveKitService(),
       _deviceIdStore = deviceIdStore ?? DeviceIdStore();

  final PanelDataSource _dataSource;
  final PanelLiveKitService _liveKit;
  final DeviceIdStore _deviceIdStore;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  Panel? _panel;
  Panel? get panel => _panel;

  List<PanelParticipant> _participants = [];
  List<PanelParticipant> get participants => _participants;

  bool _isConnecting = true;
  bool get isConnecting => _isConnecting;

  bool _isJoining = false;
  bool get isJoining => _isJoining;

  bool get isLeaving => _isLeaving;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? _userId;
  String? _panelId;
  bool _isDisposed = false;
  bool _isLeaving = false;
  bool _isHost = false;
  bool _hasReceivedFirstSnapshot = false;

  // Events the UI should react to.
  bool _wasKicked = false;
  bool get wasKicked => _wasKicked;

  bool _panelEnded = false;
  bool get panelEnded => _panelEnded;

  int _micRequestEventVersion = 0;
  int get micRequestEventVersion => _micRequestEventVersion;

  String? _latestMicRequestNotice;
  String? get latestMicRequestNotice => _latestMicRequestNotice;

  StreamSubscription? _participantsSub;
  StreamSubscription? _panelSub;
  Timer? _panelDurationTimer;
  Completer<void>? _joinInProgress;

  /// Maximum panel duration defaults to one hour for existing and new rooms.
  Duration get maxPanelDuration =>
      _panel?.duration ?? const Duration(minutes: Panel.defaultDurationMinutes);

  Duration _panelDuration = Duration.zero;
  Duration get panelDuration => _panelDuration;

  /// Time remaining before the panel is auto-ended.
  Duration get remainingDuration {
    final remaining = maxPanelDuration - _panelDuration;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Whether the panel is in the last 5 minutes.
  bool get isNearTimeLimit =>
      !_isConnecting &&
      _panel != null &&
      remainingDuration <= const Duration(minutes: 5);

  // ---------------------------------------------------------------------------
  // Derived getters
  // ---------------------------------------------------------------------------

  PanelParticipant? get myParticipant {
    final userId = _userId;
    if (userId == null) return null;

    final index = _participants.indexWhere((p) => p.userId == userId);
    if (index == -1) return null;
    return _participants[index];
  }

  PanelRole? get myRole => myParticipant?.role;

  bool get isMicEnabled => _liveKit.isMicEnabled;
  bool get isSpeakerOn => _liveKit.isSpeakerOn;

  List<PanelParticipant> get speakers => _participants
      .where(
        (p) =>
            p.role == PanelRole.host ||
            p.role == PanelRole.coHost ||
            p.role == PanelRole.speaker,
      )
      .toList();

  List<PanelParticipant> get audienceMembers =>
      _participants.where((p) => p.role == PanelRole.audience).toList();

  List<PanelParticipant> get micRequests =>
      _participants.where((p) => p.micRequested).toList();

  // ---------------------------------------------------------------------------
  // Join / Create
  // ---------------------------------------------------------------------------

  /// Join an existing panel as audience.
  Future<void> joinPanel(String panelId, String displayName) async {
    if (_isDisposed) return;
    _isJoining = true;
    final joinInProgress = Completer<void>();
    _joinInProgress = joinInProgress;
    notifyListeners();
    _isHost = false;
    try {
      _panelId = panelId;
      _userId = await _deviceIdStore.getOrCreateDeviceId();

      // Check if we already have a participant doc (e.g. host rejoining).
      final panel = await _dataSource.getPanel(panelId);
      final existingRole = await _dataSource.getParticipantRole(
        panelId,
        _userId!,
      );
      if (existingRole != null) {
        // We already have a doc — just reconnect without creating a new one.
        _isHost = existingRole == PanelRole.host;
        debugPrint(
          '[PanelRoom] Rejoining as ${existingRole.toFirestoreString()}',
        );
      } else if (panel?.hostId == _userId) {
        await _dataSource.joinPanelAsHost(panelId, _userId!, displayName);
        _isHost = true;
        debugPrint('[PanelRoom] Host rejoined and resumed host permissions');
      } else {
        await _dataSource.joinPanel(panelId, _userId!, displayName);
      }

      await _connectAndListen(panelId);

      // If we're the host (rejoining), enable mic.
      if (_isHost && !_isLeaving) {
        await _liveKit.enableMic();
        if (!_isDisposed) {
          await _dataSource.setMuted(panelId, _userId!, false);
        }
      }
    } catch (e) {
      if (_isDisposed) return;
      debugPrint('[PanelRoom] joinPanel error: $e');
      // Clean up: remove our participant doc since we failed to connect.
      // Only if we actually created one (not a rejoin).
      if (_userId != null && !_isHost) {
        try {
          await _dataSource.leavePanel(panelId, _userId!);
        } catch (_) {}
      }
      _errorMessage = 'Failed to join panel. Please try again.';
      _isConnecting = false;
      notifyListeners();
    } finally {
      _isJoining = false;
      _isConnecting = false;
      if (identical(_joinInProgress, joinInProgress)) {
        _joinInProgress = null;
      }
      if (!joinInProgress.isCompleted) joinInProgress.complete();
      if (!_isDisposed) notifyListeners();
    }
  }

  /// Called by host right after creating a panel.
  Future<void> createAndJoinPanel(String panelId, String displayName) async {
    if (_isDisposed) return;
    _isJoining = true;
    final joinInProgress = Completer<void>();
    _joinInProgress = joinInProgress;
    notifyListeners();
    _isHost = true;
    try {
      _panelId = panelId;
      _userId = await _deviceIdStore.getOrCreateDeviceId();

      await _connectAndListen(panelId);

      // Host starts with mic enabled.
      if (_isLeaving) return;
      await _liveKit.enableMic();
      if (!_isDisposed) {
        await _dataSource.setMuted(panelId, _userId!, false);
      }
    } catch (e) {
      if (_isDisposed) return;
      debugPrint('[PanelRoom] Host failed to connect, cleaning up panel: $e');
      // CRITICAL: If the host can't connect, end the panel so it doesn't
      // appear as a ghost panel for other users.
      try {
        await _dataSource.endPanel(panelId);
      } catch (_) {}
      _errorMessage = 'Failed to connect. Please try again.';
      _isConnecting = false;
      notifyListeners();
    } finally {
      _isJoining = false;
      _isConnecting = false;
      if (identical(_joinInProgress, joinInProgress)) {
        _joinInProgress = null;
      }
      if (!joinInProgress.isCompleted) joinInProgress.complete();
      if (!_isDisposed) notifyListeners();
    }
  }

  Future<void> _connectAndListen(String panelId) async {
    // Set up LiveKit disconnect callback.
    _liveKit.onDisconnected = () {
      if (!_isDisposed && !_isLeaving) {
        debugPrint('[PanelRoom] LiveKit disconnected unexpectedly');
        // Don't auto-leave — let the user see the UI and handle it.
      }
    };

    await _liveKit.connect(roomName: panelId, identity: _userId!);

    if (_isDisposed || _isLeaving) return;

    _isConnecting = false;
    notifyListeners();

    // Listen to participants.
    _participantsSub = _dataSource
        .participantsStream(panelId)
        .listen(
          (participants) {
            if (_isDisposed || _isLeaving) return;
            final hadPreviousSnapshot = _hasReceivedFirstSnapshot;

            // Kick detection: only check AFTER we've received at least one
            // snapshot that included us. This prevents false positives on first
            // load where our doc might not exist yet.
            if (_hasReceivedFirstSnapshot &&
                _userId != null &&
                participants.isNotEmpty &&
                !participants.any((p) => p.userId == _userId)) {
              debugPrint(
                '[PanelRoom] Detected kick — userId not in participants',
              );
              _wasKicked = true;
              notifyListeners();
              _disconnectOnly();
              return;
            }

            // Mark that we got a snapshot containing ourselves.
            if (_userId != null &&
                participants.any((p) => p.userId == _userId)) {
              _hasReceivedFirstSnapshot = true;
            }

            final previousRequestIds = _participants
                .where((participant) => participant.micRequested)
                .map((participant) => participant.userId)
                .toSet();
            final newRequests = participants
                .where(
                  (participant) =>
                      participant.micRequested &&
                      !previousRequestIds.contains(participant.userId),
                )
                .toList();
            final myCurrentRole = participants
                .where((participant) => participant.userId == _userId)
                .firstOrNull
                ?.role;
            if (hadPreviousSnapshot &&
                (myCurrentRole == PanelRole.host ||
                    myCurrentRole == PanelRole.coHost) &&
                newRequests.isNotEmpty) {
              final names = newRequests
                  .map((participant) => participant.displayName)
                  .where((name) => name.isNotEmpty)
                  .toList();
              _latestMicRequestNotice = names.length == 1
                  ? '${names.single} wants to speak'
                  : names.isEmpty
                  ? 'A listener wants to speak'
                  : '${names.join(', ')} want to speak';
              _micRequestEventVersion++;
              unawaited(HapticFeedback.vibrate().catchError((_) {}));
            }

            // Sort: host first, then co-hosts, speakers, audience.
            participants.sort((a, b) => a.role.index.compareTo(b.role.index));
            _participants = participants;
            notifyListeners();
          },
          onError: (e) {
            debugPrint('[PanelRoom] Participants stream error: $e');
          },
        );

    // Listen to panel status.
    _panelSub = _dataSource
        .panelStream(panelId)
        .listen(
          (panel) {
            if (_isDisposed || _isLeaving) return;
            _panel = panel;
            if (panel != null && panel.isLive) {
              _startPanelDurationTimer(panel.createdAt, panel.duration);
            }

            // If panel ended and I'm not the host, auto-leave.
            if (panel != null && panel.status == 'ended' && !_isHost) {
              debugPrint('[PanelRoom] Panel ended by host — leaving');
              _panelEnded = true;
              notifyListeners();
              _disconnectOnly();
              return;
            }

            notifyListeners();
          },
          onError: (e) {
            debugPrint('[PanelRoom] Panel stream error: $e');
          },
        );
  }

  // ---------------------------------------------------------------------------
  // Leave / End
  // ---------------------------------------------------------------------------

  /// Disconnects from LiveKit and stops listening, but does NOT remove
  /// our Firestore participant doc. Used when host goes back but doesn't
  /// want to end the panel.
  Future<void> disconnectQuietly() async {
    if (_isLeaving) return;
    _isLeaving = true;
    notifyListeners();
    await _joinInProgress?.future;

    _participantsSub?.cancel();
    _participantsSub = null;
    _panelSub?.cancel();
    _panelSub = null;
    _panelDurationTimer?.cancel();
    _panelDurationTimer = null;

    try {
      await _liveKit.dispose();
    } catch (_) {}
    if (!_isDisposed) notifyListeners();
  }

  /// Disconnects LiveKit only (used after kick/panel-end detection).
  /// Does not touch Firestore since the doc is already handled.
  /// Important: this is an automatic disconnect after the panel has already
  /// ended or the user was kicked, so it must not set the UI to the generic
  /// "Leaving panel…" state.
  Future<void> _disconnectOnly() async {
    await _joinInProgress?.future;

    _participantsSub?.cancel();
    _participantsSub = null;
    _panelSub?.cancel();
    _panelSub = null;
    _panelDurationTimer?.cancel();
    _panelDurationTimer = null;

    try {
      await _liveKit.dispose();
    } catch (_) {}
    if (!_isDisposed) notifyListeners();
  }

  /// Explicitly ends the panel (host only) or leaves it (anyone else).
  Future<void> endOrLeavePanel() async {
    if (_isLeaving) return;
    _isLeaving = true;
    notifyListeners();
    await _joinInProgress?.future;

    _participantsSub?.cancel();
    _participantsSub = null;
    _panelSub?.cancel();
    _panelSub = null;
    _panelDurationTimer?.cancel();
    _panelDurationTimer = null;

    try {
      await _liveKit.dispose();
    } catch (_) {}

    final panelId = _panelId;
    final userId = _userId;
    if (panelId != null && userId != null) {
      try {
        if (_isHost) {
          // Host explicitly ends the panel.
          await _dataSource.endPanel(panelId);
        } else {
          await _dataSource.leavePanel(panelId, userId);
        }
      } catch (e) {
        debugPrint('[PanelRoom] endOrLeavePanel cleanup error: $e');
      }
    }
    if (!_isDisposed) notifyListeners();
  }

  /// Called when host presses back (not "End Panel"). Disconnects from
  /// LiveKit but leaves the panel alive so the host can rejoin.
  Future<void> leaveWithoutEnding() async {
    if (_isLeaving) return;
    _isLeaving = true;
    notifyListeners();
    await _joinInProgress?.future;

    _participantsSub?.cancel();
    _participantsSub = null;
    _panelSub?.cancel();
    _panelSub = null;
    _panelDurationTimer?.cancel();
    _panelDurationTimer = null;

    try {
      await _liveKit.dispose();
    } catch (_) {}

    // Non-hosts still remove their participant doc.
    if (!_isHost) {
      final panelId = _panelId;
      final userId = _userId;
      if (panelId != null && userId != null) {
        try {
          await _dataSource.leavePanel(panelId, userId);
        } catch (_) {}
      }
    }
    // Host: keeps their participant doc so they can rejoin.
    if (!_isDisposed) notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Mic controls
  // ---------------------------------------------------------------------------

  /// Toggles the local microphone. Only allowed if canSpeak.
  Future<void> toggleMic() async {
    if (_isDisposed || _panelId == null || _userId == null) return;
    final me = myParticipant;
    if (me == null || !me.canSpeak) return;

    try {
      if (_liveKit.isMicEnabled) {
        await _liveKit.disableMic();
        await _dataSource.setMuted(_panelId!, _userId!, true);
      } else {
        await _liveKit.enableMic();
        await _dataSource.setMuted(_panelId!, _userId!, false);
      }
      if (!_isDisposed) notifyListeners();
    } catch (e) {
      debugPrint('[PanelRoom] toggleMic error: $e');
    }
  }

  /// Toggles speakerphone.
  Future<void> toggleSpeaker() async {
    if (_isDisposed) return;
    await _liveKit.toggleSpeaker();
    if (!_isDisposed) notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Host / Co-host actions
  // ---------------------------------------------------------------------------

  /// Request to speak (audience only).
  Future<void> requestMic() async {
    if (_isDisposed || _panelId == null || _userId == null) return;
    if (myRole != PanelRole.audience) return;
    try {
      await _dataSource.requestMic(_panelId!, _userId!);
    } catch (e) {
      debugPrint('[PanelRoom] requestMic error: $e');
    }
  }

  /// Approve a mic request (host or co-host).
  Future<void> approveMicRequest(String userId) async {
    if (_isDisposed || _panelId == null) return;
    if (myRole != PanelRole.host && myRole != PanelRole.coHost) return;
    try {
      await _dataSource.approveMic(_panelId!, userId);
    } catch (e) {
      debugPrint('[PanelRoom] approveMic error: $e');
    }
  }

  /// Deny a mic request (host or co-host).
  Future<void> denyMicRequest(String userId) async {
    if (_isDisposed || _panelId == null) return;
    if (myRole != PanelRole.host && myRole != PanelRole.coHost) return;
    try {
      await _dataSource.denyMic(_panelId!, userId);
    } catch (e) {
      debugPrint('[PanelRoom] denyMic error: $e');
    }
  }

  /// Kick a user. Only host can kick.
  Future<void> kickUser(String userId) async {
    if (_isDisposed || _panelId == null) return;
    if (myRole != PanelRole.host) return;
    if (userId == _userId) return;

    try {
      await _dataSource.kickUser(_panelId!, userId);
    } catch (e) {
      debugPrint('[PanelRoom] kickUser error: $e');
    }
  }

  /// Mute a user. Host can mute anyone. Co-host can mute speakers/audience only.
  Future<void> muteUser(String userId) async {
    if (_isDisposed || _panelId == null) return;
    if (myRole != PanelRole.host && myRole != PanelRole.coHost) return;

    if (myRole == PanelRole.coHost) {
      final target = _participants.where((p) => p.userId == userId).firstOrNull;
      if (target == null) return;
      if (target.role == PanelRole.host || target.role == PanelRole.coHost) {
        return;
      }
    }

    try {
      await _dataSource.setMuted(_panelId!, userId, true);
    } catch (e) {
      debugPrint('[PanelRoom] muteUser error: $e');
    }
  }

  /// Promote user to co-host. Only host can do this.
  Future<void> promoteToCoHost(String userId) async {
    if (_isDisposed || _panelId == null) return;
    if (myRole != PanelRole.host) return;
    try {
      await _dataSource.updateRole(_panelId!, userId, PanelRole.coHost);
    } catch (e) {
      debugPrint('[PanelRoom] promoteToCoHost error: $e');
    }
  }

  /// Promote user to speaker. Host or co-host can do this.
  Future<void> promoteToSpeaker(String userId) async {
    if (_isDisposed || _panelId == null) return;
    if (myRole != PanelRole.host && myRole != PanelRole.coHost) return;
    try {
      await _dataSource.approveMic(_panelId!, userId);
    } catch (e) {
      debugPrint('[PanelRoom] promoteToSpeaker error: $e');
    }
  }

  /// Demote user to audience.
  Future<void> demoteToAudience(String userId) async {
    if (_isDisposed || _panelId == null) return;
    if (myRole != PanelRole.host && myRole != PanelRole.coHost) return;

    if (myRole == PanelRole.coHost) {
      final target = _participants.where((p) => p.userId == userId).firstOrNull;
      if (target == null) return;
      if (target.role == PanelRole.host || target.role == PanelRole.coHost) {
        return;
      }
    }

    try {
      await _dataSource.updateRole(_panelId!, userId, PanelRole.audience);
      await _dataSource.setMuted(_panelId!, userId, true);
    } catch (e) {
      debugPrint('[PanelRoom] demoteToAudience error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _isDisposed = true;
    _participantsSub?.cancel();
    _panelSub?.cancel();
    _panelDurationTimer?.cancel();
    _panelDurationTimer = null;
    _liveKit.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Panel duration limit
  // ---------------------------------------------------------------------------

  void _startPanelDurationTimer(DateTime createdAt, Duration durationLimit) {
    _panelDurationTimer?.cancel();
    final elapsed = DateTime.now().difference(createdAt);
    _panelDuration = elapsed.isNegative ? Duration.zero : elapsed;

    if (_panelDuration >= durationLimit) {
      _expirePanel();
      return;
    }

    _panelDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isDisposed || _isLeaving) return;
      _panelDuration += const Duration(seconds: 1);
      notifyListeners();

      if (_panelDuration >= durationLimit) _expirePanel();
    });
  }

  void _expirePanel() {
    _panelDurationTimer?.cancel();
    _panelDurationTimer = null;
    debugPrint('[PanelRoom] Panel duration reached — ending panel');
    if (_isHost) {
      endOrLeavePanel();
    } else {
      _panelEnded = true;
      notifyListeners();
      _disconnectOnly();
    }
  }
}
