import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore-backed friend requests and accepted friendships.
class FriendDataSource {
  FriendDataSource({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _requests(String userId) =>
      _firestore.collection('users').doc(userId).collection('friend_requests');

  CollectionReference<Map<String, dynamic>> _friends(String userId) =>
      _firestore.collection('users').doc(userId).collection('friends');

  Stream<QuerySnapshot<Map<String, dynamic>>> incomingRequests(String userId) =>
      _requests(userId).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> friends(String userId) =>
      _friends(userId).snapshots();

  Future<void> sendRequest({
    required String senderId,
    required String recipientId,
  }) async {
    if (senderId == recipientId) throw ArgumentError('Cannot add yourself');
    final recipientRef = _firestore.collection('users').doc(recipientId);
    final senderRef = _firestore.collection('users').doc(senderId);
    final requestRef = _requests(recipientId).doc(senderId);
    final outgoingRef = _requests(senderId).doc(recipientId);
    final senderFriend = _friends(senderId).doc(recipientId);

    await _firestore.runTransaction((transaction) async {
      final snapshots = await Future.wait([
        transaction.get(senderRef),
        transaction.get(recipientRef),
        transaction.get(senderFriend),
        transaction.get(requestRef),
        transaction.get(outgoingRef),
      ]);
      if (!snapshots[0].exists || !snapshots[1].exists) {
        throw StateError('Could not find both user profiles');
      }
      if (snapshots[2].exists) throw StateError('You are already friends');
      if (snapshots[3].exists) throw StateError('Friend request already sent');
      if (snapshots[4].exists) {
        throw StateError('This person already sent you a request');
      }

      final senderName =
          snapshots[0].data()?['displayName'] as String? ?? 'A Callify user';
      transaction.set(requestRef, {
        'senderId': senderId,
        'senderName': senderName,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> acceptRequest({
    required String recipientId,
    required String senderId,
  }) async {
    final recipientRef = _firestore.collection('users').doc(recipientId);
    final senderRef = _firestore.collection('users').doc(senderId);
    final requestRef = _requests(recipientId).doc(senderId);
    final recipientFriend = _friends(recipientId).doc(senderId);
    final senderFriend = _friends(senderId).doc(recipientId);

    await _firestore.runTransaction((transaction) async {
      final snapshots = await Future.wait([
        transaction.get(requestRef),
        transaction.get(recipientRef),
        transaction.get(senderRef),
      ]);
      if (!snapshots[0].exists) {
        throw StateError('This request is no longer available');
      }
      final recipientName =
          snapshots[1].data()?['displayName'] as String? ?? 'Callify user';
      final senderName =
          snapshots[2].data()?['displayName'] as String? ?? 'Callify user';
      final acceptedAt = FieldValue.serverTimestamp();
      transaction.set(recipientFriend, {
        'userId': senderId,
        'displayName': senderName,
        'addedAt': acceptedAt,
      });
      transaction.set(senderFriend, {
        'userId': recipientId,
        'displayName': recipientName,
        'addedAt': acceptedAt,
      });
      transaction.delete(requestRef);
      transaction.delete(_requests(senderId).doc(recipientId));
    });
  }

  Future<void> rejectRequest({
    required String recipientId,
    required String senderId,
  }) async {
    await _requests(recipientId).doc(senderId).delete();
  }

  Future<void> removeFriend({
    required String userId,
    required String friendId,
  }) async {
    if (userId == friendId) return;
    final batch = _firestore.batch();
    batch.delete(_friends(userId).doc(friendId));
    batch.delete(_friends(friendId).doc(userId));
    await batch.commit();
  }
}
