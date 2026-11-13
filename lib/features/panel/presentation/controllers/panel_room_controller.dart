import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
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
  List<PanelParticipant> get participants =>
      _participants.where((participant) => participant.isActive).toList();
  final Map<String, String?> _profileImages = {};
  final Set<String> _profileImageLookups = {};

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

  int _actionErrorVersion = 0;
  int get actionErrorVersion => _actionErrorVersion;
  String? _latestActionError;
  String? get latestActionError => _latestActionError;

  StreamSubscription? _participantsSub;
  StreamSubscription? _panelSub;
  StreamSubscription? _emojiSub;
  final Map<String, Map<String, dynamic>> _activeEmojiEvents = {};
  final Map<String, Timer> _emojiTimers = {};
  List<Map<String, dynamic>> get activeEmojiEvents =>
      List.unmodifiable(_activeEmojiEvents.values);
  Timer? _panelDurationTimer;
  Timer? _presenceTimer;
  Completer<void>? _joinInProgress;

  Set<String> _speakingUserIds = {};
  Set<String> get speakingUserIds => _speakingUserIds;

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

    final index = participants.indexWhere((p) => p.userId == userId);
    if (index == -1) return null;
    return participants[index];
  }

  PanelRole? get myRole => myParticipant?.role;

  bool get isMicEnabled => _liveKit.isMicEnabled;
  bool get isSpeakerOn => _liveKit.isSpeakerOn;
  int get liveMemberCount => _liveKit.connectedParticipantCount;

  List<PanelParticipant> get speakers => participants
      .where(
        (p) =>
            p.role == PanelRole.host ||
            p.role == PanelRole.coHost ||
            p.role == PanelRole.speaker,
      )
      .toList();

  List<PanelParticipant> get audienceMembers =>
      participants.where((p) => p.role == PanelRole.audience).toList();

  List<PanelParticipant> get micRequests =>
      participants.where((p) => p.micRequested).toList();

  // ---------------------------------------------------------------------------
  // Join / Create
  // ---------------------------------------------------------------------------

  /// Join an existing panel as audience.
  Future<void> joinPanel(String panelId, String displayName) async {
    if (_isDisposed) return;
    bool createdDocThisSession = false;
    _isJoining = true;
    final joinInProgress = Completer<void>();
    _joinInProgress = joinInProgress;
    notifyListeners();
    _isHost = false;
    debugPrint('[PanelRoom] joinPanel START panelId=$panelId');
    try {
      _panelId = panelId;
      _userId = await _deviceIdStore.getOrCreateDeviceId();
      debugPrint('[PanelRoom] userId=$_userId');

      final panel = await _dataSource.getPanel(panelId);
      debugPrint(
        '[PanelRoom] panel fetched: exists=${panel != null} '
        'hostId=${panel?.hostId} status=${panel?.status}',
      );

      final existingRole = await _dataSource.getParticipantRole(
        panelId,
        _userId!,
      );
      debugPrint(
        '[PanelRoom] existingRole=${existingRole?.toFirestoreString()}',
      );

      if (existingRole != null) {
        _isHost = existingRole == PanelRole.host;
        debugPrint(
          '[PanelRoom] Rejoining as ${existingRole.toFirestoreString()} '
          '(preserving saved role)',
        );
        if (_isHost) {
          await _dataSource.joinPanelAsHost(panelId, _userId!, displayName);
        } else {
          await _dataSource.joinPanel(panelId, _userId!, displayName);
        }
      } else if (panel?.hostId == _userId) {
        debugPrint('[PanelRoom] No doc, but hostId matches -> joinPanelAsHost');
        await _dataSource.joinPanelAsHost(panelId, _userId!, displayName);
        _isHost = true;
      } else {
        debugPrint('[PanelRoom] No doc -> joining as audience');
        createdDocThisSession = await _dataSource.joinPanel(
          panelId,
          _userId!,
          displayName,
        );
        debugPrint('[PanelRoom] createdDocThisSession=$createdDocThisSession');
      }

      debugPrint('[PanelRoom] connecting to LiveKit...');
      await _connectAndListen(panelId);
      debugPrint('[PanelRoom] LiveKit connected + listeners attached');

      debugPrint('[PanelRoom] joinPanel DONE');
    } catch (e, st) {
      debugPrint('[PanelRoom] joinPanel ERROR: $e\n$st');
      if (_isDisposed) return;

      debugPrint(
        '[PanelRoom] cleanup check: userId=$_userId '
        'createdDocThisSession=$createdDocThisSession',
      );
      if (_userId != null) {
        debugPrint(
          '[PanelRoom] Marking participant offline after join failure',
        );
        try {
          await _dataSource.leavePanel(panelId, _userId!);
        } catch (_) {}
      }
      _errorMessage = e is StateError
          ? e.message.toString()
          : 'Failed to join panel. Please try again.';
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

      // Start every participant muted; the host can unmute when ready.
      if (_isLeaving) return;
      if (!_isDisposed) {
        await _dataSource.setMuted(panelId, _userId!, true);
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
    _liveKit.onPartnerJoined = () {
      if (_isDisposed || _isLeaving) return;
      notifyListeners();
    };

    _liveKit.onPartnerLeft = (identity) {
      if (_isDisposed || _isLeaving || identity == _userId) return;
      debugPrint('[PanelRoom] LiveKit participant disconnected: $identity');
      notifyListeners();
      // LiveKit detects a force-closed app independently of the killed client's
      // timers. Remove its panel record so everyone sees the participant leave.
      unawaited(_dataSource.leavePanel(panelId, identity));
    };

    // Set up LiveKit disconnect callback.
    _liveKit.onDisconnected = () {
      if (!_isDisposed && !_isLeaving) {
        debugPrint('[PanelRoom] LiveKit disconnected unexpectedly');
        // Don't auto-leave — let the user see the UI and handle it.
      }
    };

    _liveKit.onActiveSpeakersChanged = (ids) {
      if (_isDisposed || _isLeaving) return;
      if (setEquals(ids, _speakingUserIds)) {
        return; // unnecessary rebuild mat karo
      }
      _speakingUserIds = ids;
      notifyListeners();
    };

    // CHANGE 1: listeners must not publish mic until promoted.
    await _liveKit.connect(
      roomName: panelId,
      identity: _userId!,
      enableMicrophone: false,
    );

    if (_isDisposed || _isLeaving) return;

    _isConnecting = false;
    notifyListeners();

    // Listen to participants.
    _participantsSub = _dataSource
        .participantsStream(panelId)
        .listen(
          (participants) {
            if (_isDisposed || _isLeaving) return;

            // Kick detection (unchanged)
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
            if ((myCurrentRole == PanelRole.host ||
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
              debugPrint(
                '[PanelRoom] New mic request from ${newRequests.map((p) => p.userId).join(', ')}; notifying $myCurrentRole.',
              );
              unawaited(_vibrateForMicRequest());
            }

            // CHANGE 2: sync forced mute / demote to the local LiveKit mic.
            final me = participants
                .where((p) => p.userId == _userId)
                .firstOrNull;
            if (me != null) {
              final shouldBeMuted = me.isMuted || !me.canSpeak;
              if (shouldBeMuted && _liveKit.isMicEnabled) {
                unawaited(_liveKit.disableMic());
              }
            }

            // Sort: host first, then co-hosts, speakers, audience.
            participants.sort((a, b) => a.role.index.compareTo(b.role.index));
            _participants = participants
                .map(
                  (participant) => participant.copyWith(
                    profileImageBase64: _profileImages[participant.userId],
                  ),
                )
                .toList();
            notifyListeners();
            _loadProfileImages(participants);
          },
          onError: (e) {
            debugPrint('[PanelRoom] Participants stream error: $e');
          },
        );

    _emojiSub = _dataSource
        .emojiEventsStream(panelId)
        .listen(
          (snapshot) {
            if (_isDisposed || _isLeaving) return;
            final now = DateTime.now();
            for (final doc in snapshot.docs.reversed) {
              if (_activeEmojiEvents.containsKey(doc.id)) continue;
              final data = doc.data();
              final createdAt = data['createdAt'];
              if (createdAt is! Timestamp ||
                  now.difference(createdAt.toDate()) >
                      const Duration(seconds: 4)) {
                continue;
              }

              _activeEmojiEvents[doc.id] = {...data, 'eventId': doc.id};
              _emojiTimers[doc.id] = Timer(const Duration(seconds: 3), () {
                _emojiTimers.remove(doc.id)?.cancel();
                _activeEmojiEvents.remove(doc.id);
                if (!_isDisposed) notifyListeners();
              });
            }
            while (_activeEmojiEvents.length > 6) {
              final oldestId = _activeEmojiEvents.keys.first;
              _activeEmojiEvents.remove(oldestId);
              _emojiTimers.remove(oldestId)?.cancel();
            }
            notifyListeners();
          },
          onError: (Object error) {
            debugPrint('[PanelRoom] Emoji stream error: $error');
          },
        );

    // Listen to panel status (unchanged)
    _panelSub = _dataSource
        .panelStream(panelId)
        .listen(
          (panel) {
            if (_isDisposed || _isLeaving) return;
            _panel = panel;
            if (panel != null && panel.isLive) {
              _startPanelDurationTimer(panel.createdAt, panel.duration);
            }

            if (panel == null || panel.status == 'ended') {
              debugPrint('[PanelRoom] Panel ended or removed — leaving');
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

    // Keep our presence fresh and prune users whose app was force-closed.
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isDisposed || _isLeaving || _panelId == null || _userId == null) {
        return;
      }
      // Refresh the view even when Firestore has no new snapshot, so a user
      // whose process was killed disappears as soon as their heartbeat expires.
      notifyListeners();
      unawaited(_dataSource.updateHeartbeat(_panelId!, _userId!));
      unawaited(_dataSource.cleanupStaleParticipants(_panelId!));
    });
    unawaited(_dataSource.updateHeartbeat(panelId, _userId!));
  }

  // Keep participant documents small; load each profile photo once per room.
  // The participant stream can update frequently during a live panel.
  void _loadProfileImages(List<PanelParticipant> participants) {
    for (final participant in participants) {
      if (!_profileImageLookups.add(participant.userId)) continue;
      unawaited(_loadProfileImage(participant.userId));
    }
  }

  Future<void> _loadProfileImage(String userId) async {
    try {
      final image = await _dataSource.getProfileImage(userId);
      if (_isDisposed) return;
      if (image != null && image.isNotEmpty) {
        _profileImages[userId] = image;
        _participants = _participants
            .map(
              (participant) => participant.userId == userId
                  ? participant.copyWith(profileImageBase64: image)
                  : participant,
            )
            .toList();
        notifyListeners();
      }
    } catch (error) {
      debugPrint(
        '[PanelRoom] Could not load profile image for $userId: $error',
      );
    }
  }

  // Future<void> _connectAndListen(String panelId) async {
  //   // Set up LiveKit disconnect callback.
  //   _liveKit.onDisconnected = () {
  //     if (!_isDisposed && !_isLeaving) {
  //       debugPrint('[PanelRoom] LiveKit disconnected unexpectedly');
  //       // Don't auto-leave — let the user see the UI and handle it.
  //     }
  //   };

  //   await _liveKit.connect(roomName: panelId, identity: _userId!);

  //   if (_isDisposed || _isLeaving) return;

  //   _isConnecting = false;
  //   notifyListeners();

  //   // Listen to participants.
  //   _participantsSub = _dataSource
  //       .participantsStream(panelId)
  //       .listen(
  //         (participants) {
  //           if (_isDisposed || _isLeaving) return;
  //           final hadPreviousSnapshot = _hasReceivedFirstSnapshot;

  //           // Kick detection: only check AFTER we've received at least one
  //           // snapshot that included us. This prevents false positives on first
  //           // load where our doc might not exist yet.
  //           if (_hasReceivedFirstSnapshot &&
  //               _userId != null &&
  //               participants.isNotEmpty &&
  //               !participants.any((p) => p.userId == _userId)) {
  //             debugPrint(
  //               '[PanelRoom] Detected kick — userId not in participants',
  //             );
  //             _wasKicked = true;
  //             notifyListeners();
  //             _disconnectOnly();
  //             return;
  //           }

  //           // Mark that we got a snapshot containing ourselves.
  //           if (_userId != null &&
  //               participants.any((p) => p.userId == _userId)) {
  //             _hasReceivedFirstSnapshot = true;
  //           }

  //           final previousRequestIds = _participants
  //               .where((participant) => participant.micRequested)
  //               .map((participant) => participant.userId)
  //               .toSet();
  //           final newRequests = participants
  //               .where(
  //                 (participant) =>
  //                     participant.micRequested &&
  //                     !previousRequestIds.contains(participant.userId),
  //               )
  //               .toList();
  //           final myCurrentRole = participants
  //               .where((participant) => participant.userId == _userId)
  //               .firstOrNull
  //               ?.role;
  //           if (hadPreviousSnapshot &&
  //               (myCurrentRole == PanelRole.host ||
  //                   myCurrentRole == PanelRole.coHost) &&
  //               newRequests.isNotEmpty) {
  //             final names = newRequests
  //                 .map((participant) => participant.displayName)
  //                 .where((name) => name.isNotEmpty)
  //                 .toList();
  //             _latestMicRequestNotice = names.length == 1
  //                 ? '${names.single} wants to speak'
  //                 : names.isEmpty
  //                 ? 'A listener wants to speak'
  //                 : '${names.join(', ')} want to speak';
  //             _micRequestEventVersion++;
  //             unawaited(HapticFeedback.vibrate().catchError((_) {}));
  //           }

  //           // Sort: host first, then co-hosts, speakers, audience.
  //           participants.sort((a, b) => a.role.index.compareTo(b.role.index));
  //           _participants = participants;
  //           notifyListeners();
  //         },
  //         onError: (e) {
  //           debugPrint('[PanelRoom] Participants stream error: $e');
  //         },
  //       );

  //   // Listen to panel status.
  //   _panelSub = _dataSource
  //       .panelStream(panelId)
  //       .listen(
  //         (panel) {
  //           if (_isDisposed || _isLeaving) return;
  //           _panel = panel;
  //           if (panel != null && panel.isLive) {
  //             _startPanelDurationTimer(panel.createdAt, panel.duration);
  //           }

  //           // If panel ended and I'm not the host, auto-leave.
  //           if (panel != null && panel.status == 'ended' && !_isHost) {
  //             debugPrint('[PanelRoom] Panel ended by host — leaving');
  //             _panelEnded = true;
  //             notifyListeners();
  //             _disconnectOnly();
  //             return;
  //           }

  //           notifyListeners();
  //         },
  //         onError: (e) {
  //           debugPrint('[PanelRoom] Panel stream error: $e');
  //         },
  //       );
  // }

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
    _presenceTimer?.cancel();
    _presenceTimer = null;

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
    _presenceTimer?.cancel();
    _presenceTimer = null;

    try {
      await _liveKit.dispose();
    } catch (_) {}
    if (!_isDisposed) notifyListeners();
  }

  /// Leaves the panel while keeping it live for everyone else.
  Future<void> leavePanel() => _finishPanelSession(destroyPanel: false);

  /// Destroys the live panel and removes its participant records (host only).
  Future<void> destroyPanel() => _finishPanelSession(destroyPanel: true);

  /// Backwards-compatible exit action: hosts end the room, others leave.
  Future<void> endOrLeavePanel() => _finishPanelSession(destroyPanel: _isHost);

  Future<void> _finishPanelSession({required bool destroyPanel}) async {
    if (_isLeaving) return;
    if (destroyPanel && !_isHost) return;
    _isLeaving = true;
    notifyListeners();
    await _joinInProgress?.future;

    _participantsSub?.cancel();
    _participantsSub = null;
    _panelSub?.cancel();
    _panelSub = null;
    _panelDurationTimer?.cancel();
    _panelDurationTimer = null;
    _presenceTimer?.cancel();
    _presenceTimer = null;

    try {
      await _liveKit.dispose();
    } catch (_) {}

    final panelId = _panelId;
    final userId = _userId;
    if (panelId != null && userId != null) {
      try {
        if (destroyPanel) {
          await _dataSource.endPanel(panelId);
        } else {
          await _dataSource.leavePanel(panelId, userId);
        }
      } catch (e) {
        debugPrint('[PanelRoom] panel exit cleanup error: $e');
      }
    }
    if (!_isDisposed) notifyListeners();
  }

  /// Disconnects without ending the room and marks this user offline while
  /// preserving their role for a later rejoin.
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
    _presenceTimer?.cancel();
    _presenceTimer = null;

    try {
      await _liveKit.dispose();
    } catch (_) {}

    final panelId = _panelId;
    final userId = _userId;
    if (panelId != null && userId != null) {
      try {
        await _dataSource.leavePanel(panelId, userId);
      } catch (e) {
        debugPrint('[PanelRoom] disconnect cleanup error: $e');
      }
    }

    // Keep participant docs for ALL users (not just host) so they can
    // rejoin with their current role (co-host, speaker, etc.).
    if (!_isDisposed) notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Mic controls
  // ---------------------------------------------------------------------------

  /// Toggles between receiver/headset routing and the loudspeaker.
  Future<void> toggleSpeaker() async {
    if (_isDisposed || _isLeaving) return;

    try {
      await _liveKit.setSpeakerphoneOn(!_liveKit.isSpeakerOn);
      if (!_isDisposed) notifyListeners();
    } catch (error) {
      _reportActionError('Could not switch audio output.', error);
    }
  }

  /// Toggles the local microphone. Only allowed if canSpeak.
  Future<void> toggleMic() async {
    if (_isDisposed || _panelId == null || _userId == null) return;
    final me = myParticipant;
    if (me == null || !me.canSpeak) return;

    try {
      final expectedMicEnabled = !_liveKit.isMicEnabled;
      if (expectedMicEnabled) {
        await _liveKit.enableMic();
      } else {
        await _liveKit.disableMic();
      }
      final micEnabled = _liveKit.isMicEnabled;
      await _dataSource.setMuted(_panelId!, _userId!, !micEnabled);
      if (micEnabled != expectedMicEnabled) {
        throw StateError('LiveKit did not update the microphone state.');
      }
      if (!_isDisposed) notifyListeners();
    } catch (e) {
      _reportActionError(
        'Could not change your microphone. Please try again.',
        e,
      );
    }
  }

  Future<void> sendEmoji(String emoji) async {
    final participant = myParticipant;
    final panelId = _panelId;
    final userId = _userId;
    if (_isDisposed ||
        participant == null ||
        panelId == null ||
        userId == null) {
      return;
    }

    try {
      await _dataSource.sendEmoji(
        panelId,
        userId,
        participant.displayName,
        emoji,
      );
    } catch (e) {
      _reportActionError('Could not send your reaction. Try again.', e);
    }
  }

  Future<void> _vibrateForMicRequest() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await const MethodChannel(
          'quick_call/device_vibration',
        ).invokeMethod<void>('vibrate');
      } else {
        await HapticFeedback.mediumImpact();
      }
    } catch (error) {
      debugPrint('[PanelRoom] Hand-raise vibration error: $error');
    }
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
      _reportActionError(
        'Could not send your speaking request. Check your connection and try again.',
        e,
      );
    }
  }

  /// Approve a mic request (host or co-host).
  Future<void> approveMicRequest(String userId) async {
    if (_isDisposed || _panelId == null) return;
    if (myRole != PanelRole.host && myRole != PanelRole.coHost) return;
    await _dataSource.approveMic(_panelId!, userId);
  }

  /// Deny a mic request (host or co-host).
  Future<void> denyMicRequest(String userId) async {
    if (_isDisposed || _panelId == null) return;
    if (myRole != PanelRole.host && myRole != PanelRole.coHost) return;
    await _dataSource.denyMic(_panelId!, userId);
  }

  /// Kick a user. Only host can kick.
  Future<void> kickUser(String userId) async {
    if (_isDisposed || _panelId == null) return;
    if (myRole != PanelRole.host) return;
    if (userId == _userId) return;

    try {
      await _dataSource.kickUser(_panelId!, userId);
    } catch (e) {
      _reportActionError('Could not remove this participant. Try again.', e);
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
      _reportActionError('Could not mute this participant. Try again.', e);
    }
  }

  /// Promote user to co-host. Only host can do this.
  Future<void> promoteToCoHost(String userId) async {
    if (_isDisposed || _panelId == null) return;
    if (myRole != PanelRole.host) return;
    final target = _participants.where((p) => p.userId == userId).firstOrNull;
    if (target == null || target.role != PanelRole.speaker) return;
    try {
      await _dataSource.updateRole(_panelId!, userId, PanelRole.coHost);
    } catch (e) {
      _reportActionError('Could not make this participant a co-host.', e);
    }
  }

  /// Promote user to speaker. Host or co-host can do this.
  Future<void> promoteToSpeaker(String userId) async {
    if (_isDisposed || _panelId == null) return;
    if (myRole != PanelRole.host && myRole != PanelRole.coHost) return;
    try {
      await _dataSource.approveMic(_panelId!, userId);
    } catch (e) {
      _reportActionError('Could not make this participant a speaker.', e);
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
      _reportActionError('Could not move this participant to the audience.', e);
    }
  }

  void _reportActionError(String message, Object error) {
    debugPrint('[PanelRoom] $message $error');
    if (_isDisposed) return;
    _latestActionError = message;
    _actionErrorVersion++;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _isDisposed = true;
    _participantsSub?.cancel();
    _emojiSub?.cancel();
    for (final timer in _emojiTimers.values) {
      timer.cancel();
    }
    _emojiTimers.clear();
    _panelSub?.cancel();
    _panelDurationTimer?.cancel();
    _panelDurationTimer = null;
    _presenceTimer?.cancel();
    _presenceTimer = null;
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
      unawaited(_expirePanel());
      return;
    }

    _panelDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isDisposed || _isLeaving) return;
      _panelDuration += const Duration(seconds: 1);
      notifyListeners();

      if (_panelDuration >= durationLimit) unawaited(_expirePanel());
    });
  }

  Future<void> _expirePanel() async {
    _panelDurationTimer?.cancel();
    _panelDurationTimer = null;
    if (_panelEnded || _isLeaving) return;
    debugPrint('[PanelRoom] Panel duration reached — ending panel');
    if (_isHost) {
      await endOrLeavePanel();
      if (_isDisposed) return;
      _panelEnded = true;
      notifyListeners();
    } else {
      _panelEnded = true;
      notifyListeners();
      await _disconnectOnly();
    }
  }
}
