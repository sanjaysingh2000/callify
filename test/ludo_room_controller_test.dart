import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ludo/flutter_ludo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_call/core/utils/device_id_store.dart';
import 'package:quick_call/features/ludo/data/datasources/ludo_data_source.dart';
import 'package:quick_call/features/ludo/presentation/controllers/ludo_room_controller.dart';
import 'package:quick_call/features/panel/data/services/panel_livekit_service.dart';

void main() {
  test(
    'leaving while LiveKit is connecting releases the claimed seat',
    () async {
      final firestore = FakeFirebaseFirestore();
      final dataSource = LudoDataSource(firestore: firestore);
      final roomId = await dataSource.createRoom('Table', 'host', 'Host');
      final liveKit = _ControlledLiveKit();
      final controller = LudoRoomController(
        dataSource: dataSource,
        liveKitService: liveKit,
        deviceIdStore: _FixedDeviceIdStore('guest'),
      );

      final joining = controller.join(roomId, 'Guest');
      await liveKit.connectStarted.future;
      await controller.leave();
      await joining;

      final roomSnapshot = await firestore
          .collection('ludo_rooms')
          .doc(roomId)
          .get();
      expect(roomSnapshot.data()?['seats'], hasLength(4));
      expect(
        (roomSnapshot.data()?['seats'] as List).where(
          (seat) => (seat as Map)['userId'] != null,
        ),
        hasLength(1),
      );
      controller.dispose();
    },
  );

  test('failed LiveKit connection releases the claimed seat', () async {
    final firestore = FakeFirebaseFirestore();
    final dataSource = LudoDataSource(firestore: firestore);
    final roomId = await dataSource.createRoom('Table', 'host', 'Host');
    final liveKit = _ControlledLiveKit()..failConnect = true;
    final controller = LudoRoomController(
      dataSource: dataSource,
      liveKitService: liveKit,
      deviceIdStore: _FixedDeviceIdStore('guest'),
    );

    await controller.join(roomId, 'Guest');

    final roomSnapshot = await firestore
        .collection('ludo_rooms')
        .doc(roomId)
        .get();
    expect(
      (roomSnapshot.data()?['seats'] as List).where(
        (seat) => (seat as Map)['userId'] != null,
      ),
      hasLength(1),
    );
    expect(controller.errorMessage, isNotNull);
    controller.dispose();
  });

  test('failed mic-state sync rolls an unmute back to muted', () async {
    final firestore = FakeFirebaseFirestore();
    final baseDataSource = LudoDataSource(firestore: firestore);
    final roomId = await baseDataSource.createRoom('Table', 'host', 'Host');
    final dataSource = _FailingMuteDataSource(firestore);
    final liveKit = _FakeMicLiveKit();
    final controller = LudoRoomController(
      dataSource: dataSource,
      liveKitService: liveKit,
      deviceIdStore: _FixedDeviceIdStore('host'),
    );
    final roomReady = Completer<void>();
    controller.addListener(() {
      if (controller.room?.id == roomId && !roomReady.isCompleted) {
        roomReady.complete();
      }
    });

    await controller.join(roomId, 'Host');
    await roomReady.future;
    await controller.toggleMic();

    expect(liveKit.isMuted, isTrue);
    expect(controller.syncError, isNotNull);
    await controller.leave();
    controller.dispose();
  });

  test(
    'rejoined player cannot interact during another player\'s turn',
    () async {
      final firestore = FakeFirebaseFirestore();
      final dataSource = LudoDataSource(firestore: firestore);
      final roomId = await dataSource.createRoom('Table', 'host', 'Host');
      await dataSource.joinRoom(roomId, 'guest', 'Guest');
      const players = [
        LudoPlayer(name: 'Host', color: Color(0xFFE24B4B)),
        LudoPlayer(name: 'Guest', color: Color(0xFF3B82C4)),
      ];
      await dataSource.startGame(roomId, 'host', [
        'host',
        'guest',
      ], LudoGameState.initial(players).toJson());
      final controller = LudoRoomController(
        dataSource: dataSource,
        liveKitService: _FakeMicLiveKit(),
        deviceIdStore: _FixedDeviceIdStore('guest'),
      );
      final gameReady = Completer<void>();
      controller.addListener(() {
        if (controller.game != null && !gameReady.isCompleted) {
          gameReady.complete();
        }
      });

      await controller.join(roomId, 'Guest');
      await gameReady.future.timeout(const Duration(seconds: 2));

      expect(controller.game!.canRoll, isTrue);
      expect(controller.isMyTurn, isFalse);
      expect(controller.canInteract, isFalse);

      await controller.leave();
      controller.dispose();
    },
  );

  test('turn write retries once and persists the accepted roll', () async {
    final firestore = FakeFirebaseFirestore();
    final baseDataSource = LudoDataSource(firestore: firestore);
    final roomId = await baseDataSource.createRoom('Table', 'host', 'Host');
    await baseDataSource.joinRoom(roomId, 'guest', 'Guest');
    const players = [
      LudoPlayer(name: 'Host', color: Color(0xFFE24B4B)),
      LudoPlayer(name: 'Guest', color: Color(0xFF3B82C4)),
    ];
    await baseDataSource.startGame(roomId, 'host', [
      'host',
      'guest',
    ], LudoGameState.initial(players).toJson());
    final retryDataSource = _RetryGameDataSource(firestore);
    final controller = LudoRoomController(
      dataSource: retryDataSource,
      liveKitService: _FakeMicLiveKit(),
      deviceIdStore: _FixedDeviceIdStore('host'),
    );
    final gameReady = Completer<void>();
    controller.addListener(() {
      if (controller.game != null && !gameReady.isCompleted) {
        gameReady.complete();
      }
    });

    await controller.join(roomId, 'Host');
    await gameReady.future.timeout(const Duration(seconds: 2));
    controller.game!.rollDice();
    await retryDataSource.retrySucceeded.future.timeout(
      const Duration(seconds: 2),
    );
    await Future<void>.delayed(Duration.zero);

    final latest = await retryDataSource.getRoom(roomId);
    expect(LudoGameState.fromJson(latest!.gameState!).rollCount, 1);
    expect(retryDataSource.writeAttempts, 2);
    await controller.leave();
    controller.dispose();
  });
}

class _FixedDeviceIdStore extends DeviceIdStore {
  _FixedDeviceIdStore(this.deviceId);

  final String deviceId;

  @override
  Future<String> getOrCreateDeviceId() async => deviceId;
}

class _ControlledLiveKit extends PanelLiveKitService {
  final connectStarted = Completer<void>();
  final _allowConnect = Completer<void>();
  bool failConnect = false;

  @override
  Future<void> connect({
    required String roomName,
    required String identity,
    bool enableMicrophone = false,
  }) async {
    connectStarted.complete();
    if (failConnect) throw StateError('LiveKit unavailable');
    await _allowConnect.future;
  }

  @override
  Future<void> dispose() async {
    if (!_allowConnect.isCompleted) _allowConnect.complete();
  }
}

class _FailingMuteDataSource extends LudoDataSource {
  _FailingMuteDataSource(FakeFirebaseFirestore firestore)
    : super(firestore: firestore);

  @override
  Future<void> setMuted(String roomId, String userId, bool muted) async {
    throw StateError('Firestore unavailable');
  }
}

class _FakeMicLiveKit extends PanelLiveKitService {
  bool _muted = true;

  @override
  bool get isMuted => _muted;

  @override
  bool get isMicEnabled => !_muted;

  @override
  Future<void> connect({
    required String roomName,
    required String identity,
    bool enableMicrophone = false,
  }) async {}

  @override
  Future<void> enableMic() async => _muted = false;

  @override
  Future<void> disableMic() async => _muted = true;

  @override
  Future<void> dispose() async {}
}

class _RetryGameDataSource extends LudoDataSource {
  _RetryGameDataSource(FakeFirebaseFirestore firestore)
    : super(firestore: firestore);

  final retrySucceeded = Completer<void>();
  int writeAttempts = 0;

  @override
  Future<bool> applyGameState(
    String roomId,
    String userId,
    Map<String, Object?> gameState,
  ) async {
    writeAttempts++;
    if (writeAttempts == 1) throw StateError('Temporary network failure');
    final accepted = await super.applyGameState(roomId, userId, gameState);
    if (accepted && !retrySucceeded.isCompleted) retrySucceeded.complete();
    return accepted;
  }
}
