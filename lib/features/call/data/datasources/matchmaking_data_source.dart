import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Manages the Firestore-based matchmaking queue for random calls.
///
/// Firestore structure:
/// ```
/// waiting_queue/{userId}
///   ├── userId: string
///   ├── status: 'waiting' | 'matched'
///   ├── matchedWith: string (userId of partner)
///   ├── roomId: string (LiveKit room ID)
///   ├── role: 'caller' | 'callee'
///   ├── timestamp: serverTimestamp      ← when the user joined
///   └── lastSeen: serverTimestamp       ← heartbeat (updated every 10s)
/// ```
class MatchmakingDataSource {
  MatchmakingDataSource({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// How old a heartbeat can be before the user is considered stale/offline.
  static const Duration staleCutoff = Duration(seconds: 30);

  CollectionReference<Map<String, dynamic>> get _queue =>
      _firestore.collection('waiting_queue');

  // ---------------------------------------------------------------------------
  // Queue operations
  // ---------------------------------------------------------------------------

  /// Adds the user to the waiting queue with an initial heartbeat.
  Future<void> joinQueue(String userId) async {
    await _queue.doc(userId).set({
      'userId': userId,
      'status': 'waiting',
      'matchedWith': null,
      'roomId': null,
      'role': null,
      'timestamp': FieldValue.serverTimestamp(),
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

  /// Updates the heartbeat timestamp so other users know we're still online.
  ///
  /// Called periodically (every ~10 seconds) while in the searching state.
  Future<void> updateHeartbeat(String userId) async {
    try {
      await _queue.doc(userId).update({
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Best-effort — doc may have been deleted if we were matched.
    }
  }

  /// Tries to find and match with another waiting user using a transaction.
  ///
  /// Returns a [MatchResult] if a match was found, or `null` if no match
  /// is available (in which case the caller should listen for being matched).
  ///
  /// Only matches users whose [lastSeen] heartbeat is within [staleCutoff].
  /// This prevents matching with users who went offline.
  Future<MatchResult?> findMatch(String userId) async {
    return _firestore.runTransaction<MatchResult?>((transaction) async {
      // Only match users whose heartbeat is fresh (within staleCutoff).
      final cutoff = Timestamp.fromDate(
        DateTime.now().toUtc().subtract(staleCutoff),
      );
      // Query only on status so matchmaking does not depend on a manually
      // deployed composite Firestore index. Freshness is checked locally and
      // again inside the transaction below.
      final querySnapshot = await _queue
          .where('status', isEqualTo: 'waiting')
          .limit(50)
          .get();

      // Find a user that isn't us.
      DocumentSnapshot<Map<String, dynamic>>? matchDoc;
      for (final doc in querySnapshot.docs) {
        final lastSeen = doc.data()['lastSeen'] as Timestamp?;
        if (doc.id != userId &&
            lastSeen != null &&
            !lastSeen.toDate().isBefore(cutoff.toDate())) {
          matchDoc = doc;
          break;
        }
      }

      if (matchDoc == null) return null;

      // Re-read inside transaction to ensure consistency.
      final freshMatch = await transaction.get(_queue.doc(matchDoc.id));
      if (!freshMatch.exists ||
          freshMatch.data()?['status'] != 'waiting') {
        return null; // Someone else matched them already.
      }

      // Double-check heartbeat is still fresh inside the transaction.
      final lastSeen = freshMatch.data()?['lastSeen'] as Timestamp?;
      if (lastSeen == null ||
          lastSeen.toDate().isBefore(DateTime.now().toUtc().subtract(staleCutoff))) {
        return null; // User went offline.
      }

      // Generate a room ID for LiveKit.
      final roomId = _firestore.collection('rooms').doc().id;

      // Mark the matched user as callee.
      transaction.update(_queue.doc(matchDoc.id), {
        'status': 'matched',
        'matchedWith': userId,
        'roomId': roomId,
        'role': 'callee',
      });

      // Mark ourselves as caller.
      transaction.update(_queue.doc(userId), {
        'status': 'matched',
        'matchedWith': matchDoc.id,
        'roomId': roomId,
        'role': 'caller',
      });

      return MatchResult(
        partnerId: matchDoc.id,
        roomId: roomId,
        role: 'caller',
      );
    });
  }

  /// Listens for this user's queue document to be updated to 'matched'.
  ///
  /// This is used when no match was found immediately — we wait for
  /// another user to match us.
  Stream<MatchResult> onMatchFound(String userId) {
    return _queue
        .doc(userId)
        .snapshots()
        .where((snapshot) {
          final data = snapshot.data();
          return data != null &&
              data['status'] == 'matched' &&
              data['matchedWith'] is String &&
              data['roomId'] is String &&
              data['role'] is String;
        })
        .map((snapshot) {
          final data = snapshot.data()!;
          return MatchResult(
            partnerId: data['matchedWith'] as String,
            roomId: data['roomId'] as String,
            role: data['role'] as String,
          );
        });
  }

  /// Removes the user from the queue (on cancel or cleanup).
  Future<void> leaveQueue(String userId) async {
    try {
      await _queue.doc(userId).delete();
    } catch (_) {
      // Best-effort cleanup.
    }
  }
}

/// Result of a successful match.
class MatchResult {
  const MatchResult({
    required this.partnerId,
    required this.roomId,
    required this.role,
  });

  /// The matched partner's user ID.
  final String partnerId;

  /// The room ID for LiveKit.
  final String roomId;

  /// This user's role: 'caller' or 'callee'.
  final String role;

  bool get isCaller => role == 'caller';
}
