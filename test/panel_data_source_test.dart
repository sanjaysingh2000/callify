import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_call/features/panel/data/datasources/panel_data_source.dart';
import 'package:quick_call/features/panel/domain/entities/panel.dart';
import 'package:quick_call/features/panel/domain/entities/panel_participant.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late PanelDataSource dataSource;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    dataSource = PanelDataSource(firestore: firestore);
  });

  test('creates a live panel with its host participant', () async {
    final panelId = await dataSource.createPanel('Town Hall', 'host-1', 'Host');

    final panel = await firestore.collection('panels').doc(panelId).get();
    final host = await firestore
        .collection('panels')
        .doc(panelId)
        .collection('participants')
        .doc('host-1')
        .get();

    expect(panel.data(), containsPair('title', 'Town Hall'));
    expect(panel.data(), containsPair('status', 'live'));
    expect(panel.data(), containsPair('hostId', 'host-1'));
    expect(panel.data(), containsPair('hostDisplayName', 'Host'));
    expect(panel.data(), containsPair('participantCount', 1));
    expect(panel.data(), containsPair('durationMinutes', 60));
    expect(host.data(), containsPair('role', 'host'));
    expect(host.data(), containsPair('isMuted', true));

    final mappedPanel = (await dataSource.livePanelsStream().first).single;
    expect(mappedPanel.hostDisplayName, 'Host');
    expect(mappedPanel.durationMinutes, Panel.defaultDurationMinutes);
  });

  test(
    'joining the same user twice does not inflate participant count',
    () async {
      final panelId = await dataSource.createPanel(
        'Town Hall',
        'host-1',
        'Host',
      );

      await dataSource.joinPanel(panelId, 'guest-1', 'Guest');
      await dataSource.joinPanel(panelId, 'guest-1', 'Guest');

      final panel = await firestore.collection('panels').doc(panelId).get();
      final participants = await firestore
          .collection('panels')
          .doc(panelId)
          .collection('participants')
          .get();

      expect(panel.data()?['participantCount'], 2);
      expect(participants.docs, hasLength(2));
    },
  );

  test('role and microphone operations update participant state', () async {
    final panelId = await dataSource.createPanel('Town Hall', 'host-1', 'Host');
    await dataSource.joinPanel(panelId, 'guest-1', 'Guest');

    await dataSource.requestMic(panelId, 'guest-1');
    var guest = await _participant(firestore, panelId, 'guest-1');
    expect(guest.data()?['micRequested'], isTrue);

    await dataSource.approveMic(panelId, 'guest-1');
    guest = await _participant(firestore, panelId, 'guest-1');
    expect(guest.data(), containsPair('role', 'speaker'));
    expect(guest.data()?['micRequested'], isFalse);

    await dataSource.setMuted(panelId, 'guest-1', false);
    guest = await _participant(firestore, panelId, 'guest-1');
    expect(guest.data()?['isMuted'], isFalse);

    await dataSource.denyMic(panelId, 'guest-1');
    guest = await _participant(firestore, panelId, 'guest-1');
    expect(guest.data()?['micRequested'], isFalse);
  });

  test('streams map live panels and participants to domain entities', () async {
    final panelId = await dataSource.createPanel('Town Hall', 'host-1', 'Host');
    await dataSource.joinPanel(panelId, 'guest-1', 'Guest');

    final panel = await dataSource.livePanelsStream().first;
    final participants = await dataSource.participantsStream(panelId).first;

    expect(panel, hasLength(1));
    expect(panel.single.id, panelId);
    expect(panel.single.isLive, isTrue);
    expect(
      participants.map((p) => p.userId),
      containsAll(['host-1', 'guest-1']),
    );
    expect(
      participants.firstWhere((p) => p.userId == 'guest-1').role,
      PanelRole.audience,
    );
  });

  test(
    'leaving marks the participant offline and decrements the count',
    () async {
      final panelId = await dataSource.createPanel(
        'Town Hall',
        'host-1',
        'Host',
      );
      await dataSource.joinPanel(panelId, 'guest-1', 'Guest');

      await dataSource.leavePanel(panelId, 'guest-1');

      final panel = await firestore.collection('panels').doc(panelId).get();
      final guest = await _participant(firestore, panelId, 'guest-1');

      expect(panel.data()?['participantCount'], 1);
      expect(guest.data()?['isOnline'], isFalse);
      expect(guest.data()?['role'], 'audience');
    },
  );

  test('leaving and rejoining preserves co-host and speaker roles', () async {
    final panelId = await dataSource.createPanel('Town Hall', 'host-1', 'Host');
    await dataSource.joinPanel(panelId, 'cohost-1', 'Co-host');
    await dataSource.updateRole(panelId, 'cohost-1', PanelRole.coHost);
    await dataSource.joinPanel(panelId, 'speaker-1', 'Speaker');
    await dataSource.approveMic(panelId, 'speaker-1');

    await dataSource.leavePanel(panelId, 'cohost-1');
    await dataSource.leavePanel(panelId, 'speaker-1');
    await dataSource.joinPanel(panelId, 'cohost-1', 'Co-host');
    await dataSource.joinPanel(panelId, 'speaker-1', 'Speaker');

    final cohost = await _participant(firestore, panelId, 'cohost-1');
    final speaker = await _participant(firestore, panelId, 'speaker-1');
    final panel = await firestore.collection('panels').doc(panelId).get();
    expect(cohost.data()?['role'], 'co-host');
    expect(cohost.data()?['isOnline'], isTrue);
    expect(speaker.data()?['role'], 'speaker');
    expect(speaker.data()?['isOnline'], isTrue);
    expect(panel.data()?['participantCount'], 3);
  });

  test(
    'stale heartbeat cleanup marks a force-closed participant offline',
    () async {
      final panelId = await dataSource.createPanel(
        'Town Hall',
        'host-1',
        'Host',
      );
      await dataSource.joinPanel(panelId, 'guest-1', 'Guest');
      await firestore
          .collection('panels')
          .doc(panelId)
          .collection('participants')
          .doc('guest-1')
          .update({
            'lastSeen': Timestamp.fromDate(
              DateTime.now().toUtc().subtract(const Duration(seconds: 46)),
            ),
          });

      await dataSource.cleanupStaleParticipants(panelId);

      final panel = await firestore.collection('panels').doc(panelId).get();
      final guest = await _participant(firestore, panelId, 'guest-1');
      final host = await _participant(firestore, panelId, 'host-1');
      expect(guest.data()?['isOnline'], isFalse);
      expect(guest.data()?['role'], 'audience');
      expect(host.exists, isTrue);
      expect(panel.data()?['participantCount'], 1);
    },
  );

  test(
    'kicking and repeated leave do not decrement below actual members',
    () async {
      final panelId = await dataSource.createPanel(
        'Town Hall',
        'host-1',
        'Host',
      );
      await dataSource.joinPanel(panelId, 'guest-1', 'Guest');

      await dataSource.kickUser(panelId, 'guest-1');
      await dataSource.leavePanel(panelId, 'guest-1');

      final panel = await firestore.collection('panels').doc(panelId).get();
      expect(panel.data()?['participantCount'], 1);
    },
  );

  test('ending a panel changes its status', () async {
    final panelId = await dataSource.createPanel('Town Hall', 'host-1', 'Host');
    await dataSource.joinPanel(panelId, 'guest-1', 'Guest');

    await dataSource.endPanel(panelId);

    final panel = await firestore.collection('panels').doc(panelId).get();
    final participants = await firestore
        .collection('panels')
        .doc(panelId)
        .collection('participants')
        .get();
    expect(panel.data()?['status'], 'ended');
    expect(panel.data()?['participantCount'], 0);
    expect(participants.docs, isEmpty);
  });

  test('cannot join a panel after the host destroys it', () async {
    final panelId = await dataSource.createPanel('Town Hall', 'host-1', 'Host');
    await dataSource.endPanel(panelId);

    await expectLater(
      dataSource.joinPanel(panelId, 'guest-1', 'Guest'),
      throwsA(isA<StateError>()),
    );
  });

  test('host cannot rejoin a panel after it has ended', () async {
    final panelId = await dataSource.createPanel('Town Hall', 'host-1', 'Host');
    await dataSource.endPanel(panelId);

    await expectLater(
      dataSource.joinPanelAsHost(panelId, 'host-1', 'Host'),
      throwsA(isA<StateError>()),
    );
    final host = await _participant(firestore, panelId, 'host-1');
    expect(host.exists, isFalse);
  });

  test('non-host cannot use host rejoin path', () async {
    final panelId = await dataSource.createPanel('Town Hall', 'host-1', 'Host');

    await expectLater(
      dataSource.joinPanelAsHost(panelId, 'guest-1', 'Guest'),
      throwsA(isA<StateError>()),
    );
    final guest = await _participant(firestore, panelId, 'guest-1');
    expect(guest.exists, isFalse);
  });

  test('legacy panel documents default to a one-hour duration', () async {
    final roomId = await dataSource.createPanel('Town Hall', 'host-1', 'Host');
    await firestore.collection('panels').doc(roomId).update({
      'durationMinutes': FieldValue.delete(),
    });

    final panel = (await dataSource.livePanelsStream().first).single;
    expect(panel.durationMinutes, Panel.defaultDurationMinutes);
  });
}

Future<DocumentSnapshot<Map<String, dynamic>>> _participant(
  FakeFirebaseFirestore firestore,
  String panelId,
  String userId,
) {
  return firestore
      .collection('panels')
      .doc(panelId)
      .collection('participants')
      .doc(userId)
      .get();
}
