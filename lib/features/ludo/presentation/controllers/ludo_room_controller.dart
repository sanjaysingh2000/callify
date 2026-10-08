import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_ludo/flutter_ludo.dart';

import '../../../../core/utils/device_id_store.dart';
import '../../../panel/data/services/panel_livekit_service.dart';
import '../../data/datasources/ludo_data_source.dart';
import '../../domain/entities/ludo_room.dart';

class LudoRoomController extends ChangeNotifier {
  LudoRoomController({
    LudoDataSource? dataSource,
    PanelLiveKitService? liveKitService,
    DeviceIdStore? deviceIdStore,
  }) : _dataSource = dataSource ?? LudoDataSource(),
       _liveKit = liveKitService ?? PanelLiveKitService(),
       _deviceIdStore = deviceIdStore ?? DeviceIdStore();

  static const _seatColors = <Color>[
    Color(0xFFE24B4B),
    Color(0xFF3B82C4),
    Color(0xFF32A875),
    Color(0xFFE2A83B),
  ];

  final LudoDataSource _dataSource;
  final PanelLiveKitService _liveKit;
  final DeviceIdStore _deviceIdStore;

  LudoRoom? _room;
  LudoRoom? get room => _room;

  LudoController? _game;
  LudoController? get game => _game;

  String? _userId;
  String? get userId => _userId;

  String? _roomId;

  int? _seatIndex;
  int? get seatIndex => _seatIndex;

  bool _isConnecting = true;
  bool get isConnecting => _isConnecting;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? _syncError;
  String? get syncError => _syncError;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  bool _isSyncBlocked = false;
  bool _isMicUpdating = false;
  bool get isMicUpdating => _isMicUpdating;

  bool _roomEnded = false;
  bool get roomEnded => _roomEnded;

  bool _isStartingGame = false;
  bool get isStartingGame => _isStartingGame;

  bool _gameStartPending = false;
  bool get hasStartedGame =>
      _room?.gameState != null || _game != null || _gameStartPending;

  bool get isMuted => _liveKit.isMuted;
  bool get isHost => _room?.hostId == _userId;
  int? get playerIndex {
    final userId = _userId;
    if (userId == null) return null;
    final index = _room?.gameUserIds.indexOf(userId) ?? -1;
    return index < 0 ? null : index;
  }

  bool get isMyTurn {
    final game = _game;
    final room = _room;
    if (game == null || room == null || _userId == null) return false;
    return room.gameUserIds.length > game.state.currentPlayerIndex &&
        room.gameUserIds[game.state.currentPlayerIndex] == _userId;
  }

  bool get canRoll =>
      _game?.canRoll == true && isMyTurn && !_isSyncing && !_isSyncBlocked;
  bool get canSelectPiece =>
      _game?.canSelectPiece == true &&
      isMyTurn &&
      !_isSyncing &&
      !_isSyncBlocked;
  bool get canInteract =>
      isMyTurn &&
      !_isSyncing &&
      !_isSyncBlocked &&
      _game != null &&
      !_game!.state.isFinished;

  StreamSubscription<LudoRoom?>? _roomSub;
  bool _disposed = false;
  bool _leaving = false;
  bool _seatClaimed = false;
  Completer<void>? _joinFinished;
  Future<void> _pendingStateWrite = Future<void>.value();

  Future<void> join(String roomId, String displayName) async {
    if (_roomId != null || _disposed || _leaving) return;
    _roomId = roomId;
    final joinFinished = Completer<void>();
    _joinFinished = joinFinished;
    try {
      _userId = await _deviceIdStore.getOrCreateDeviceId();
      if (_disposed || _leaving) return;
      _seatIndex = await _dataSource.joinRoom(roomId, _userId!, displayName);
      _seatClaimed = true;
      if (_disposed || _leaving) {
        await _releaseSeat();
        return;
      }
      await _liveKit.connect(
        roomName: 'ludo_$roomId',
        identity: _userId!,
        enableMicrophone: false,
      );
      if (_disposed || _leaving) {
        await _releaseSeat();
        return;
      }

      _isConnecting = false;
      notifyListeners();
      _roomSub = _dataSource
          .roomStream(roomId)
          .listen(
            _onRoomChanged,
            onError: (Object error) => _onStreamError(error),
          );
    } catch (error) {
      try {
        await _liveKit.dispose();
        await _releaseSeat();
      } catch (_) {}
      if (!_disposed && !_leaving) {
        _errorMessage = error is StateError
            ? error.message
            : 'Could not join this Ludo table. Check your connection and try again.';
        _isConnecting = false;
        notifyListeners();
      }
    } finally {
      if (!joinFinished.isCompleted) joinFinished.complete();
    }
  }

  Future<void> _releaseSeat({bool keepWaitingRoom = false}) async {
    final roomId = _roomId;
    final userId = _userId;
    if (!_seatClaimed || roomId == null || userId == null) return;
    _seatClaimed = false;
    await _dataSource.leaveRoom(
      roomId,
      userId,
      keepWaitingRoom: keepWaitingRoom,
    );
  }

  void _onStreamError(Object error) {
    if (_disposed || _leaving) return;
    debugPrint('[LudoRoom] room stream error: $error');
    _errorMessage = 'Lost connection to this table. Leave and rejoin to retry.';
    _isConnecting = false;
    notifyListeners();
  }

  void _onRoomChanged(LudoRoom? room) {
    if (_disposed || _leaving) return;
    if (room == null || !room.isLive) {
      _roomEnded = true;
      notifyListeners();
      return;
    }
    _room = room;
    _syncError = null;
    _isSyncBlocked = false;
    final stateData = room.gameState;
    if (stateData != null) {
      _gameStartPending = false;
      try {
        final state = LudoGameState.fromJson(stateData);
        if (_game == null) {
          _game = _createGame(state.players);
          _game!.restore(state);
        } else if (jsonEncode(_game!.state.toJson()) !=
            jsonEncode(state.toJson())) {
          _game!.restore(state);
        }
      } catch (error) {
        debugPrint('[LudoRoom] invalid game state: $error');
        _isSyncBlocked = true;
        _syncError = 'Game data is invalid. Leave this table and rejoin.';
      }
    }
    notifyListeners();
  }

  LudoController _createGame(List<LudoPlayer> players) => LudoController(
    players: players,
    diceRules: const LudoDiceRules.modern(),
    stepAnimationDuration: const Duration(milliseconds: 120),
    autoMoveSingleChoice: false,
    onDiceRolled: (_) => _queueGameState(),
    onPieceMoved: (_, _, _) => _queueGameState(),
  );

  Future<void> startGame() async {
    final room = _room;
    if (room == null || !isHost || room.playerCount < 2 || _isStartingGame) {
      return;
    }
    _isStartingGame = true;
    notifyListeners();
    final activeSeats = room.seats.indexed
        .where((entry) => entry.$2.isOccupied)
        .toList();
    final gameUserIds = activeSeats.map((entry) => entry.$2.userId!).toList();
    final players = activeSeats.indexed
        .map(
          (entry) => LudoPlayer(
            name: entry.$2.$2.displayName ?? 'Player ${entry.$1 + 1}',
            color: _seatColors[entry.$1],
          ),
        )
        .toList();
    final initialState = LudoGameState.initial(players);
    try {
      await _dataSource.startGame(
        room.id,
        _userId!,
        gameUserIds,
        initialState.toJson(),
      );
      _gameStartPending = _room?.gameState == null;
    } catch (error) {
      _gameStartPending = false;
      _errorMessage = error is StateError
          ? error.message
          : 'Could not start the game.';
      notifyListeners();
    } finally {
      _isStartingGame = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _queueGameState() {
    final state = _game?.state.toJson();
    if (state == null) return;
    _isSyncing = true;
    notifyListeners();
    _pendingStateWrite = _pendingStateWrite.then((_) async {
      try {
        await _publishGameState(state);
      } finally {
        if (!_disposed) {
          _isSyncing = false;
          notifyListeners();
        }
      }
    });
  }

  Future<void> _publishGameState(Map<String, Object?> state) async {
    final room = _room;
    final userId = _userId;
    if (_leaving || room == null || userId == null) return;
    try {
      var applied = false;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          applied = await _dataSource.applyGameState(room.id, userId, state);
          break;
        } catch (error) {
          if (attempt == 1) rethrow;
          debugPrint('[LudoRoom] retrying game state update: $error');
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
      if (!applied) {
        final latest = await _dataSource.getRoom(room.id);
        if (latest == null) {
          _roomEnded = true;
          notifyListeners();
          return;
        }
        _onRoomChanged(latest);
        _syncError = 'Turn changed elsewhere. The board was refreshed.';
        notifyListeners();
      }
    } catch (error) {
      debugPrint('[LudoRoom] game state update failed: $error');
      try {
        final latest = await _dataSource.getRoom(room.id);
        if (latest == null) {
          _roomEnded = true;
          _isSyncBlocked = true;
          _syncError = 'This table is no longer available.';
        } else {
          _onRoomChanged(latest);
          _syncError = 'Connection interrupted. The board was refreshed.';
        }
      } catch (reconcileError) {
        debugPrint(
          '[LudoRoom] game state reconciliation failed: $reconcileError',
        );
        _isSyncBlocked = true;
        _syncError = 'Game sync is unavailable. Leave and rejoin to continue.';
      }
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> toggleMic() async {
    final room = _room;
    final userId = _userId;
    if (room == null || userId == null || _leaving || _isMicUpdating) return;
    final wasMuted = _liveKit.isMuted;
    _isMicUpdating = true;
    notifyListeners();
    try {
      if (!wasMuted) {
        await _liveKit.disableMic();
      } else {
        await _liveKit.enableMic();
      }
      Object? lastError;
      var saved = false;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          await _dataSource.setMuted(room.id, userId, _liveKit.isMuted);
          saved = true;
          break;
        } catch (error) {
          lastError = error;
          if (attempt == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
        }
      }
      if (saved) {
        _syncError = null;
      } else {
        if (wasMuted && _liveKit.isMicEnabled) await _liveKit.disableMic();
        _syncError = wasMuted
            ? 'Microphone could not sync. It has been muted again.'
            : 'Microphone is muted locally, but its status could not sync.';
        debugPrint('[LudoRoom] microphone update failed: $lastError');
      }
    } catch (error) {
      if (wasMuted && _liveKit.isMicEnabled) await _liveKit.disableMic();
      _syncError = 'Microphone update failed. Your microphone remains muted.';
      debugPrint('[LudoRoom] microphone update failed: $error');
    } finally {
      _isMicUpdating = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> leave({bool keepWaitingRoom = false}) async {
    if (_leaving) {
      await _joinFinished?.future;
      return;
    }
    _leaving = true;
    await _roomSub?.cancel();
    try {
      await _liveKit.dispose();
    } catch (error) {
      debugPrint('[LudoRoom] leave cleanup failed: $error');
    }
    await _joinFinished?.future;
    try {
      await _releaseSeat(keepWaitingRoom: keepWaitingRoom);
    } catch (error) {
      debugPrint('[LudoRoom] seat release failed: $error');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (!_leaving) unawaited(leave());
    _roomSub?.cancel();
    _game?.dispose();
    _liveKit.dispose();
    super.dispose();
  }
}
