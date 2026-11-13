import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_call/features/friends/data/friend_data_source.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FriendDataSource dataSource;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    dataSource = FriendDataSource(firestore: firestore);
    await firestore.collection('users').doc('alice').set({
      'deviceId': 'alice',
      'displayName': 'Alice',
    });
    await firestore.collection('users').doc('bob').set({
      'deviceId': 'bob',
      'displayName': 'Bob',
    });
  });

  test('sending a request stores sender identity for the recipient', () async {
    await dataSource.sendRequest(senderId: 'alice', recipientId: 'bob');

    final request = await firestore
        .collection('users')
        .doc('bob')
        .collection('friend_requests')
        .doc('alice')
        .get();
    expect(request.data()?['senderId'], 'alice');
    expect(request.data()?['senderName'], 'Alice');
    expect(request.data()?['createdAt'], isNotNull);
  });

  test(
    'duplicate, reciprocal pending, and self requests are rejected',
    () async {
      await dataSource.sendRequest(senderId: 'alice', recipientId: 'bob');

      await expectLater(
        dataSource.sendRequest(senderId: 'alice', recipientId: 'bob'),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        dataSource.sendRequest(senderId: 'bob', recipientId: 'alice'),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        dataSource.sendRequest(senderId: 'alice', recipientId: 'alice'),
        throwsA(isA<ArgumentError>()),
      );
    },
  );

  test('accepting a request creates a friendship for both users', () async {
    await dataSource.sendRequest(senderId: 'alice', recipientId: 'bob');
    await dataSource.acceptRequest(recipientId: 'bob', senderId: 'alice');

    final bobFriend = await firestore
        .collection('users')
        .doc('bob')
        .collection('friends')
        .doc('alice')
        .get();
    final aliceFriend = await firestore
        .collection('users')
        .doc('alice')
        .collection('friends')
        .doc('bob')
        .get();
    final request = await firestore
        .collection('users')
        .doc('bob')
        .collection('friend_requests')
        .doc('alice')
        .get();

    expect(bobFriend.data()?['displayName'], 'Alice');
    expect(aliceFriend.data()?['displayName'], 'Bob');
    expect(bobFriend.data()?['addedAt'], isNotNull);
    expect(aliceFriend.data()?['addedAt'], isNotNull);
    expect(request.exists, isFalse);
  });

  test('rejecting a request removes it without creating friendship', () async {
    await dataSource.sendRequest(senderId: 'alice', recipientId: 'bob');
    await dataSource.rejectRequest(recipientId: 'bob', senderId: 'alice');

    final request = await firestore
        .collection('users')
        .doc('bob')
        .collection('friend_requests')
        .doc('alice')
        .get();
    final friendship = await firestore
        .collection('users')
        .doc('bob')
        .collection('friends')
        .doc('alice')
        .get();
    expect(request.exists, isFalse);
    expect(friendship.exists, isFalse);
  });
}
