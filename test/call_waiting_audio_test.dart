import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_call/core/utils/device_id_store.dart';
import 'package:quick_call/features/call/data/datasources/matchmaking_data_source.dart';
import 'package:quick_call/features/call/data/services/matchmaking_waiting_audio.dart';
import 'package:quick_call/features/call/domain/entities/call_state.dart';
import 'package:quick_call/features/call/presentation/controllers/call_controller.dart';

void main() {
  test(
    'waiting music starts while searching and stops when cancelled',
    () async {
      final dataSource = _WaitingMatchmakingDataSource();
      final waitingAudio = _FakeWaitingAudio();
      final controller = CallController(
        matchmakingDataSource: dataSource,
        deviceIdStore: _FixedDeviceIdStore(),
        waitingAudio: waitingAudio,
      );

      await controller.startRandomCall();

      expect(controller.state, CallState.searching);
      expect(waitingAudio.startCount, 1);
      expect(waitingAudio.stopCount, 0);

      await controller.cancelSearch();

      expect(controller.state, CallState.idle);
      expect(waitingAudio.stopCount, 1);

      controller.dispose();
      await dataSource.matches.close();
    },
  );

  test('waiting music stops as soon as a match is found', () async {
    final dataSource = _WaitingMatchmakingDataSource();
    final waitingAudio = _FakeWaitingAudio();
    final controller = CallController(
      matchmakingDataSource: dataSource,
      deviceIdStore: _FixedDeviceIdStore(),
      waitingAudio: waitingAudio,
    );
    final matched = Completer<void>();
    controller.addListener(() {
      if (controller.state == CallState.matched && !matched.isCompleted) {
        matched.complete();
      }
    });

    await controller.startRandomCall();
    expect(waitingAudio.startCount, 1);
    dataSource.matches.add(
      const MatchResult(partnerId: 'partner', roomId: 'room', role: 'caller'),
    );

    await matched.future.timeout(const Duration(seconds: 2));
    expect(waitingAudio.stopCount, 1);

    controller.dispose();
    await dataSource.matches.close();
  });
}

class _WaitingMatchmakingDataSource extends MatchmakingDataSource {
  _WaitingMatchmakingDataSource() : super(firestore: FakeFirebaseFirestore());

  final matches = StreamController<MatchResult>.broadcast();

  @override
  Future<void> joinQueue(String userId) async {}

  @override
  Future<MatchResult?> findMatch(String userId) async => null;

  @override
  Stream<MatchResult> onMatchFound(String userId) => matches.stream;

  @override
  Future<void> leaveQueue(String userId) async {}
}

class _FixedDeviceIdStore extends DeviceIdStore {
  @override
  Future<String> getOrCreateDeviceId() async => 'caller';
}

class _FakeWaitingAudio implements MatchmakingWaitingAudio {
  int startCount = 0;
  int stopCount = 0;
  int disposeCount = 0;
  bool _isPlaying = false;

  @override
  Future<void> start() async {
    if (_isPlaying) return;
    _isPlaying = true;
    startCount++;
  }

  @override
  Future<void> stop() async {
    if (!_isPlaying) return;
    _isPlaying = false;
    stopCount++;
  }

  @override
  Future<void> dispose() async => disposeCount++;
}
