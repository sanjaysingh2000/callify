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
    expect(host.data(), containsPair('isMuted', false));

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

  test('leaving removes the participant and decrements the count', () async {
    final panelId = await dataSource.createPanel('Town Hall', 'host-1', 'Host');
    await dataSource.joinPanel(panelId, 'guest-1', 'Guest');

    await dataSource.leavePanel(panelId, 'guest-1');

    final panel = await firestore.collection('panels').doc(panelId).get();
    final guest = await _participant(firestore, panelId, 'guest-1');

    expect(panel.data()?['participantCount'], 1);
    expect(guest.exists, isFalse);
  });

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

    await dataSource.endPanel(panelId);

    final panel = await firestore.collection('panels').doc(panelId).get();
    expect(panel.data()?['status'], 'ended');
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
