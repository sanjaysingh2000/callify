import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_call/core/utils/device_id_store.dart';
import 'package:quick_call/features/panel/data/datasources/panel_data_source.dart';
import 'package:quick_call/features/panel/data/services/panel_livekit_service.dart';
import 'package:quick_call/features/panel/domain/entities/panel_participant.dart';
import 'package:quick_call/features/panel/presentation/controllers/panel_room_controller.dart';

void main() {
  test('join and leave loading states cover their async work', () async {
    final firestore = FakeFirebaseFirestore();
    final dataSource = PanelDataSource(firestore: firestore);
    final panelId = await dataSource.createPanel('Town Hall', 'host', 'Host');
    final liveKit = _GatedPanelLiveKit();
    final controller = PanelRoomController(
      panelDataSource: dataSource,
      liveKitService: liveKit,
      deviceIdStore: _FixedDeviceIdStore('guest'),
    );

    final joining = controller.joinPanel(panelId, 'Guest');
    await liveKit.connectStarted.future;
    expect(controller.isJoining, isTrue);
    liveKit.allowConnect.complete();
    await joining;
    expect(controller.isJoining, isFalse);

    final leaving = controller.endOrLeavePanel();
    await liveKit.disposeStarted.future;
    expect(controller.isLeaving, isTrue);
    liveKit.allowDispose.complete();
    await leaving;

    final participant = await firestore
        .collection('panels')
        .doc(panelId)
        .collection('participants')
        .doc('guest')
        .get();
    expect(participant.exists, isFalse);
    controller.dispose();
  });

  test('leaving during join waits for LiveKit connection to settle', () async {
    final firestore = FakeFirebaseFirestore();
    final dataSource = PanelDataSource(firestore: firestore);
    final panelId = await dataSource.createPanel('Town Hall', 'host', 'Host');
    final liveKit = _GatedPanelLiveKit();
    final controller = PanelRoomController(
      panelDataSource: dataSource,
      liveKitService: liveKit,
      deviceIdStore: _FixedDeviceIdStore('guest'),
    );

    final joining = controller.joinPanel(panelId, 'Guest');
    await liveKit.connectStarted.future;
    final leaving = controller.leaveWithoutEnding();
    expect(controller.isLeaving, isTrue);
    expect(liveKit.disposeStarted.isCompleted, isFalse);

    liveKit.allowConnect.complete();
    await joining;
    await liveKit.disposeStarted.future;
    expect(controller.isJoining, isFalse);

    liveKit.allowDispose.complete();
    await leaving;

    final participant = await firestore
        .collection('panels')
        .doc(panelId)
        .collection('participants')
        .doc('guest')
        .get();
    expect(participant.exists, isFalse);
    controller.dispose();
  });

  test('late joiner is disconnected after the shared one-hour limit', () async {
    final firestore = FakeFirebaseFirestore();
    final dataSource = PanelDataSource(firestore: firestore);
    final panelId = await dataSource.createPanel('Town Hall', 'host', 'Host');
    await dataSource.joinPanel(panelId, 'guest', 'Guest');
    await firestore.collection('panels').doc(panelId).update({
      'createdAt': Timestamp.fromDate(
        DateTime.now().subtract(const Duration(hours: 2)),
      ),
    });

    final liveKit = _FakePanelLiveKit();
    final controller = PanelRoomController(
      panelDataSource: dataSource,
      liveKitService: liveKit,
      deviceIdStore: _FixedDeviceIdStore('guest'),
    );
    final panelExpired = Completer<void>();
    controller.addListener(() {
      if (controller.panelEnded && !panelExpired.isCompleted) {
        panelExpired.complete();
      }
    });

    await controller.joinPanel(panelId, 'Guest');
    await panelExpired.future.timeout(const Duration(seconds: 2));
    await liveKit.disposalStarted.future.timeout(const Duration(seconds: 2));

    expect(controller.panelEnded, isTrue);
    expect(liveKit.disposeCalls, greaterThan(0));
    controller.dispose();
  });

  test('host can rejoin after audience members are already in the room', () async {
    final firestore = FakeFirebaseFirestore();
    final dataSource = PanelDataSource(firestore: firestore);
    final panelId = await dataSource.createPanel('Town Hall', 'host', 'Host');
    await dataSource.joinPanel(panelId, 'audience', 'Listener');

    final controller = PanelRoomController(
      panelDataSource: dataSource,
      liveKitService: _FakePanelLiveKit(),
      deviceIdStore: _FixedDeviceIdStore('host'),
    );

    await controller.joinPanel(panelId, 'Host');
    await _waitUntil(() => controller.myRole == PanelRole.host);

    expect(controller.myRole, PanelRole.host);
    expect(controller.panel?.status, 'live');
    expect(controller.participants.where((p) => p.userId == 'host').length, 1);
    expect(
      controller.participants.map((p) => p.userId),
      containsAll(['host', 'audience']),
    );
    controller.dispose();
  });

  test('audience can be in the room before the host returns, and the host regains host role without ending the panel', () async {
    final firestore = FakeFirebaseFirestore();
    final dataSource = PanelDataSource(firestore: firestore);
    final panelId = await dataSource.createPanel('Town Hall', 'host', 'Host');
    await dataSource.leavePanel(panelId, 'host');
    await dataSource.joinPanel(panelId, 'audience', 'Listener');

    final controller = PanelRoomController(
      panelDataSource: dataSource,
      liveKitService: _FakePanelLiveKit(),
      deviceIdStore: _FixedDeviceIdStore('host'),
    );

    await controller.joinPanel(panelId, 'Host');
    await _waitUntil(() => controller.myRole == PanelRole.host);

    final hostDoc = await firestore
        .collection('panels')
        .doc(panelId)
        .collection('participants')
        .doc('host')
        .get();

    expect(controller.myRole, PanelRole.host);
    expect(controller.panel?.status, 'live');
    expect(hostDoc.exists, isTrue);
    expect(hostDoc.data()?['role'], 'host');
    controller.dispose();
  });

  test('an ended panel is marked ended instead of leaving', () async {
    final firestore = FakeFirebaseFirestore();
    final dataSource = PanelDataSource(firestore: firestore);
    final panelId = await dataSource.createPanel('Town Hall', 'host', 'Host');
    await dataSource.joinPanel(panelId, 'audience', 'Listener');

    final controller = PanelRoomController(
      panelDataSource: dataSource,
      liveKitService: _FakePanelLiveKit(),
      deviceIdStore: _FixedDeviceIdStore('audience'),
    );

    await controller.joinPanel(panelId, 'Listener');
    await _waitUntil(() => controller.myRole == PanelRole.audience);

    await firestore.collection('panels').doc(panelId).update({'status': 'ended'});
    await _waitUntil(() => controller.panelEnded == true);

    expect(controller.panelEnded, isTrue);
    expect(controller.isLeaving, isFalse);
    controller.dispose();
  });

  test('host leaving without ending keeps the panel active for everyone else',
      () async {
    final firestore = FakeFirebaseFirestore();
    final dataSource = PanelDataSource(firestore: firestore);
    final panelId = await dataSource.createPanel('Town Hall', 'host', 'Host');
    await dataSource.joinPanel(panelId, 'audience', 'Listener');

    final controller = PanelRoomController(
      panelDataSource: dataSource,
      liveKitService: _FakePanelLiveKit(),
      deviceIdStore: _FixedDeviceIdStore('host'),
    );

    await controller.joinPanel(panelId, 'Host');
    await controller.leaveWithoutEnding();

    final panelDoc = await firestore.collection('panels').doc(panelId).get();
    final hostDoc = await firestore
        .collection('panels')
        .doc(panelId)
        .collection('participants')
        .doc('host')
        .get();

    expect(panelDoc.data()?['status'], 'live');
    expect(hostDoc.exists, isTrue);
    expect(hostDoc.data()?['role'], 'host');
    controller.dispose();
  });

  test('co-host keeps the panel running when the host is temporarily absent',
      () async {
    final firestore = FakeFirebaseFirestore();
    final dataSource = PanelDataSource(firestore: firestore);
    final panelId = await dataSource.createPanel('Town Hall', 'host', 'Host');
    await dataSource.joinPanel(panelId, 'cohost', 'Co-host');
    await dataSource.updateRole(panelId, 'cohost', PanelRole.coHost);
    await dataSource.joinPanel(panelId, 'audience', 'Listener');

    final controller = PanelRoomController(
      panelDataSource: dataSource,
      liveKitService: _FakePanelLiveKit(),
      deviceIdStore: _FixedDeviceIdStore('cohost'),
    );

    await controller.joinPanel(panelId, 'Co-host');
    await _waitUntil(() => controller.myRole == PanelRole.coHost);

    await controller.approveMicRequest('audience');
    await _waitUntil(() {
      final audienceParticipant = controller.participants.firstWhere(
        (p) => p.userId == 'audience',
        orElse: () => const PanelParticipant(
          userId: '',
          displayName: '',
          role: PanelRole.audience,
        ),
      );
      return audienceParticipant.role == PanelRole.speaker;
    });

    final audienceDoc = await firestore
        .collection('panels')
        .doc(panelId)
        .collection('participants')
        .doc('audience')
        .get();

    expect(controller.myRole, PanelRole.coHost);
    expect(controller.panel?.status, 'live');
    expect(controller.speakers.map((p) => p.userId), contains('cohost'));
    expect(audienceDoc.data()?['role'], 'speaker');
    controller.dispose();
  });

  test('when there is no host or co-host, the audience stays in a live wait state',
      () async {
    final firestore = FakeFirebaseFirestore();
    final dataSource = PanelDataSource(firestore: firestore);
    final panelId = await dataSource.createPanel('Town Hall', 'host', 'Host');
    await dataSource.joinPanel(panelId, 'audience', 'Listener');
    await dataSource.leavePanel(panelId, 'host');

    final controller = PanelRoomController(
      panelDataSource: dataSource,
      liveKitService: _FakePanelLiveKit(),
      deviceIdStore: _FixedDeviceIdStore('audience'),
    );

    await controller.joinPanel(panelId, 'Listener');
    await _waitUntil(() => controller.myRole == PanelRole.audience);

    expect(controller.myRole, PanelRole.audience);
    expect(controller.panel?.status, 'live');
    expect(controller.speakers.isEmpty, isTrue);
    expect(controller.audienceMembers.map((p) => p.userId), contains('audience'));
    controller.dispose();
  });

  for (final role in [PanelRole.host, PanelRole.coHost]) {
    test(
      '$role receives a notice when an audience member raises a hand',
      () async {
        final firestore = FakeFirebaseFirestore();
        final dataSource = PanelDataSource(firestore: firestore);
        final panelId = await dataSource.createPanel(
          'Town Hall',
          'host',
          'Host',
        );
        await dataSource.joinPanel(panelId, 'cohost', 'Co-host');
        await dataSource.joinPanel(panelId, 'audience', 'Listener');
        if (role == PanelRole.coHost) {
          await dataSource.updateRole(panelId, 'cohost', PanelRole.coHost);
        }

        final userId = role == PanelRole.host ? 'host' : 'cohost';
        final controller = PanelRoomController(
          panelDataSource: dataSource,
          liveKitService: _FakePanelLiveKit(),
          deviceIdStore: _FixedDeviceIdStore(userId),
        );
        final participantsReady = Completer<void>();
        final requestReceived = Completer<void>();
        controller.addListener(() {
          if (controller.participants.length == 3 &&
              !participantsReady.isCompleted) {
            participantsReady.complete();
          }
          if (controller.micRequestEventVersion == 1 &&
              !requestReceived.isCompleted) {
            requestReceived.complete();
          }
        });

        await controller.joinPanel(
          panelId,
          role == PanelRole.host ? 'Host' : 'Co-host',
        );
        await participantsReady.future.timeout(const Duration(seconds: 2));
        await dataSource.requestMic(panelId, 'audience');
        await requestReceived.future.timeout(const Duration(seconds: 2));

        expect(controller.latestMicRequestNotice, 'Listener wants to speak');
        expect(controller.micRequests.single.userId, 'audience');

        controller.dispose();
      },
    );
  }
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var i = 0; i < 50; i++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('Timed out waiting for panel condition to become true.');
}

class _FixedDeviceIdStore extends DeviceIdStore {
  _FixedDeviceIdStore(this.userId);

  final String userId;

  @override
  Future<String> getOrCreateDeviceId() async => userId;
}

class _FakePanelLiveKit extends PanelLiveKitService {
  int disposeCalls = 0;
  final disposalStarted = Completer<void>();

  @override
  Future<void> connect({
    required String roomName,
    required String identity,
    bool enableMicrophone = true,
  }) async {}

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (!disposalStarted.isCompleted) disposalStarted.complete();
  }
}

class _GatedPanelLiveKit extends _FakePanelLiveKit {
  final connectStarted = Completer<void>();
  final allowConnect = Completer<void>();
  final disposeStarted = Completer<void>();
  final allowDispose = Completer<void>();

  @override
  Future<void> connect({
    required String roomName,
    required String identity,
    bool enableMicrophone = true,
  }) async {
    connectStarted.complete();
    await allowConnect.future;
  }

  @override
  Future<void> dispose() async {
    if (!disposeStarted.isCompleted) disposeStarted.complete();
    await allowDispose.future;
  }
}
