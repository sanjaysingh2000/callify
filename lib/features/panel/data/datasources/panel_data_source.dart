import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../domain/entities/panel.dart';
import '../../domain/entities/panel_participant.dart';

/// Firestore CRUD for panels and their participants.
class PanelDataSource {
  PanelDataSource({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final now = DateTime.now();

  CollectionReference<Map<String, dynamic>> get _panels =>
      _firestore.collection('panels');

  CollectionReference<Map<String, dynamic>> _participants(String panelId) =>
      _panels.doc(panelId).collection('participants');

  CollectionReference<Map<String, dynamic>> _emojiEvents(String panelId) =>
      _panels.doc(panelId).collection('emoji_events');

  Stream<QuerySnapshot<Map<String, dynamic>>> emojiEventsStream(
    String panelId,
  ) => _emojiEvents(
    panelId,
  ).orderBy('createdAt', descending: true).limit(20).snapshots();

  Future<void> sendEmoji(
    String panelId,
    String userId,
    String displayName,
    String emoji,
  ) async {
    await _emojiEvents(panelId).add({
      'userId': userId,
      'displayName': displayName,
      'emoji': emoji,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // Panel CRUD
  // ---------------------------------------------------------------------------

  /// Returns the panel metadata for a given panel ID.
  Future<Panel?> getPanel(String panelId) async {
    final doc = await _panels.doc(panelId).get();
    if (!doc.exists) return null;
    return _panelFromDoc(doc);
  }

  /// Creates a new panel and adds the host as the first participant.
  /// Returns the panel ID.
  Future<String> createPanel(
    String title,
    String hostId,
    String hostDisplayName,
  ) async {
    final panelRef = _panels.doc();
    final panelId = panelRef.id;

    final batch = _firestore.batch();
    batch.set(panelRef, {
      'title': title,
      'hostId': hostId,
      'hostDisplayName': hostDisplayName,
      'status': 'live',
      'createdAt': FieldValue.serverTimestamp(),
      'participantCount': 1,
      'memberRoles': {hostId: PanelRole.host.toFirestoreString()},
      'durationMinutes': Panel.defaultDurationMinutes,
      'expiresAt': Timestamp.fromDate(now.add(const Duration(hours: 1))),
    });

    // Add host as first participant.
    batch.set(_participants(panelId).doc(hostId), {
      'userId': hostId,
      'displayName': hostDisplayName,
      'role': PanelRole.host.toFirestoreString(),
      'isOnline': true,
      'isMuted': true,
      'micRequested': false,
      'joinedAt': FieldValue.serverTimestamp(),
      'lastSeen': FieldValue.serverTimestamp(),
    });
    await batch.commit();

    return panelId;
  }

  /// Ends a panel (sets status to 'ended').
  Future<void> endPanel(String panelId) async {
    final panelRef = _panels.doc(panelId);
    await panelRef.update({
      'status': 'ended',
      'participantCount': 0,
      'memberRoles': FieldValue.delete(),
    });

    final participants = await _participants(panelId).get();
    for (var start = 0; start < participants.docs.length; start += 450) {
      final batch = _firestore.batch();
      for (final participant in participants.docs.skip(start).take(450)) {
        batch.delete(participant.reference);
      }
      await batch.commit();
    }
  }

  /// Joins a panel as audience.
  /// Joins a panel as audience.
  /// Joins or resumes a participant without replacing their saved panel role.
  /// Returns true if this call created a participant record.
  Future<bool> joinPanel(
    String panelId,
    String userId,
    String displayName,
  ) async {
    final participantRef = _participants(panelId).doc(userId);
    return _firestore.runTransaction<bool>((transaction) async {
      final panel = await transaction.get(_panels.doc(panelId));
      if (!panel.exists || panel.data()?['status'] != 'live') {
        throw StateError('This panel is no longer live.');
      }
      final kickedUsers = panel.data()?['kickedUsers'] as List<dynamic>? ?? [];
      if (kickedUsers.contains(userId)) {
        throw StateError('You were removed from this panel and cannot rejoin.');
      }
      final participant = await transaction.get(participantRef);
      final memberRoles = panel.data()?['memberRoles'] as Map<String, dynamic>?;
      final savedRole = PanelRole.fromString(
        memberRoles?[userId] as String? ??
            participant.data()?['role'] as String? ??
            PanelRole.audience.toFirestoreString(),
      );
      final panelRef = _panels.doc(panelId);
      if (participant.exists) {
        final wasOffline = participant.data()?['isOnline'] == false;
        transaction.update(participantRef, {
          'displayName': displayName,
          'role': savedRole.toFirestoreString(),
          'isOnline': true,
          'isMuted': true,
          'lastSeen': FieldValue.serverTimestamp(),
        });
        transaction.update(panelRef, {
          'memberRoles.$userId': savedRole.toFirestoreString(),
        });
        if (wasOffline) {
          transaction.update(_panels.doc(panelId), {
            'participantCount': FieldValue.increment(1),
          });
        }
        return false;
      }

      transaction.set(participantRef, {
        'userId': userId,
        'displayName': displayName,
        'role': savedRole.toFirestoreString(),
        'isOnline': true,
        'isMuted': true,
        'micRequested': false,
        'joinedAt': FieldValue.serverTimestamp(),
        'lastSeen': FieldValue.serverTimestamp(),
      });
      transaction.update(panelRef, {
        'memberRoles.$userId': savedRole.toFirestoreString(),
      });
      transaction.update(_panels.doc(panelId), {
        'participantCount': FieldValue.increment(1),
      });
      return true;
    });
  }
  // Future<void> joinPanel(
  //   String panelId,
  //   String userId,
  //   String displayName,
  // ) async {
  //   final participantRef = _participants(panelId).doc(userId);
  //   await _firestore.runTransaction((transaction) async {
  //     final participant = await transaction.get(participantRef);
  //     if (participant.exists) return;

  //     transaction.set(participantRef, {
  //       'userId': userId,
  //       'displayName': displayName,
  //       'role': PanelRole.audience.toFirestoreString(),
  //       'isMuted': true,
  //       'micRequested': false,
  //       'joinedAt': FieldValue.serverTimestamp(),
  //     });
  //     transaction.update(_panels.doc(panelId), {
  //       'participantCount': FieldValue.increment(1),
  //     });
  //   });
  // }

  /// Rejoins or creates the participant doc as the panel host.
  Future<void> joinPanelAsHost(
    String panelId,
    String userId,
    String displayName,
  ) async {
    final participantRef = _participants(panelId).doc(userId);
    await _firestore.runTransaction((transaction) async {
      final participant = await transaction.get(participantRef);
      final panelDoc = await transaction.get(_panels.doc(panelId));
      final panelData = panelDoc.data();
      if (!panelDoc.exists || panelData?['status'] != 'live') {
        throw StateError('This panel is no longer live.');
      }
      if (panelData?['hostId'] != userId) {
        throw StateError('Only the panel host can rejoin as host.');
      }
      final kickedUsers = panelData?['kickedUsers'] as List<dynamic>? ?? [];
      if (kickedUsers.contains(userId)) {
        throw StateError('You were removed from this panel and cannot rejoin.');
      }

      if (participant.exists) {
        final wasOffline = participant.data()?['isOnline'] == false;
        transaction.update(participantRef, {
          'displayName': displayName,
          'role': PanelRole.host.toFirestoreString(),
          'isOnline': true,
          'isMuted': true,
          'micRequested': false,
          'lastSeen': FieldValue.serverTimestamp(),
        });
        if (wasOffline && panelDoc.exists) {
          transaction.update(_panels.doc(panelId), {
            'participantCount': FieldValue.increment(1),
          });
        }
      } else {
        transaction.set(participantRef, {
          'userId': userId,
          'displayName': displayName,
          'role': PanelRole.host.toFirestoreString(),
          'isOnline': true,
          'isMuted': true,
          'micRequested': false,
          'joinedAt': FieldValue.serverTimestamp(),
          'lastSeen': FieldValue.serverTimestamp(),
        });
        if (panelDoc.exists) {
          transaction.update(_panels.doc(panelId), {
            'participantCount': FieldValue.increment(1),
          });
        }
      }

      if (panelDoc.exists) {
        transaction.update(_panels.doc(panelId), {
          'hostId': userId,
          'hostDisplayName': displayName,
          'memberRoles.$userId': PanelRole.host.toFirestoreString(),
        });
      }
    });
  }

  /// Marks a participant offline while preserving their role for rejoining.
  Future<void> leavePanel(String panelId, String userId) async {
    debugPrint('[DS] leavePanel CALLED userId=$userId\n${StackTrace.current}');
    final participantRef = _participants(panelId).doc(userId);
    await _firestore.runTransaction((transaction) async {
      final participant = await transaction.get(participantRef);
      if (!participant.exists || participant.data()?['isOnline'] == false) {
        return;
      }

      transaction.update(participantRef, {
        'isOnline': false,
        'micRequested': false,
      });
      transaction.update(_panels.doc(panelId), {
        'participantCount': FieldValue.increment(-1),
      });
    });
  }

  // ---------------------------------------------------------------------------
  // Streams
  // ---------------------------------------------------------------------------

  /// Stream of all live panels, ordered by creation time (newest first).
  Stream<List<Panel>> livePanelsStream() {
    return _panels.where('status', isEqualTo: 'live').snapshots().map((
      snapshot,
    ) {
      final panels = snapshot.docs
          .map((doc) => _panelFromDoc(doc))
          .where((p) => p != null)
          .cast<Panel>()
          .toList();
      panels.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return panels;
    });
  }

  /// Stream of a single panel.
  Stream<Panel?> panelStream(String panelId) {
    return _panels.doc(panelId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return _panelFromDoc(doc);
    });
  }

  /// Real-time stream of participants in a panel.
  Stream<List<PanelParticipant>> participantsStream(String panelId) {
    return _participants(panelId).snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => _participantFromDoc(doc))
          .where((p) => p != null)
          .cast<PanelParticipant>()
          .toList(),
    );
  }

  Future<String?> getProfileImage(String userId) async {
    final profile = await _firestore.collection('users').doc(userId).get();
    return profile.data()?['profileImageBase64'] as String?;
  }

  // ---------------------------------------------------------------------------
  // Participant lookup
  // ---------------------------------------------------------------------------

  /// Returns the role of a participant, or null if they don't exist.
  /// Used to detect host rejoin.
  Future<PanelRole?> getParticipantRole(String panelId, String userId) async {
    try {
      final panel = await _panels.doc(panelId).get();
      final memberRoles = panel.data()?['memberRoles'] as Map<String, dynamic>?;
      final savedRole = memberRoles?[userId] as String?;
      if (savedRole != null) {
        return PanelRole.fromString(savedRole);
      }

      final doc = await _participants(panelId).doc(userId).get();
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;
      return PanelRole.fromString(data['role'] as String? ?? 'audience');
    } catch (e) {
      debugPrint('[PanelDataSource] getParticipantRole error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Role management
  // ---------------------------------------------------------------------------

  /// Updates a participant's role.
  Future<void> updateRole(
    String panelId,
    String userId,
    PanelRole newRole,
  ) async {
    final participantRef = _participants(panelId).doc(userId);
    final panelRef = _panels.doc(panelId);
    await _firestore.runTransaction((transaction) async {
      final participant = await transaction.get(participantRef);
      await transaction.get(panelRef);
      transaction.update(panelRef, {
        'memberRoles.$userId': newRole.toFirestoreString(),
      });
      if (participant.exists) {
        transaction.update(participantRef, {
          'role': newRole.toFirestoreString(),
        });
      }
    });
  }

  /// Sets a mic request flag.
  Future<void> requestMic(String panelId, String userId) async {
    await _participants(panelId).doc(userId).update({'micRequested': true});
  }

  /// Approves a mic request — promotes to speaker and clears request.
  Future<void> approveMic(String panelId, String userId) async {
    final participantRef = _participants(panelId).doc(userId);
    final panelRef = _panels.doc(panelId);
    await _firestore.runTransaction((transaction) async {
      final participant = await transaction.get(participantRef);
      await transaction.get(panelRef);
      transaction.update(panelRef, {
        'memberRoles.$userId': PanelRole.speaker.toFirestoreString(),
      });
      if (participant.exists) {
        transaction.update(participantRef, {
          'role': PanelRole.speaker.toFirestoreString(),
          'micRequested': false,
        });
      }
    });
  }

  /// Denies a mic request.
  Future<void> denyMic(String panelId, String userId) async {
    await _participants(panelId).doc(userId).update({'micRequested': false});
  }

  /// Kicks a user from the panel and bans them from rejoining.
  Future<void> kickUser(String panelId, String userId) async {
    debugPrint('[DS] kickUser CALLED userId=$userId\n${StackTrace.current}');
    final participantRef = _participants(panelId).doc(userId);
    final panelRef = _panels.doc(panelId);
    await _firestore.runTransaction((transaction) async {
      final participant = await transaction.get(participantRef);
      final panel = await transaction.get(panelRef);
      if (!participant.exists) return;

      transaction.delete(participantRef);
      final updates = <String, dynamic>{
        'kickedUsers': FieldValue.arrayUnion([userId]),
        'memberRoles.$userId': FieldValue.delete(),
      };
      if (participant.exists && participant.data()?['isOnline'] != false) {
        updates['participantCount'] = FieldValue.increment(-1);
      }
      if (panel.exists) transaction.update(panelRef, updates);
    });
  }

  /// Checks if a user has been kicked (banned) from a panel.
  Future<bool> isUserKicked(String panelId, String userId) async {
    try {
      final doc = await _panels.doc(panelId).get();
      if (!doc.exists) return false;
      final data = doc.data();
      if (data == null) return false;
      final kickedUsers = data['kickedUsers'] as List<dynamic>? ?? [];
      return kickedUsers.contains(userId);
    } catch (e) {
      debugPrint('[PanelDataSource] isUserKicked error: $e');
      return false;
    }
  }

  /// Lets a removed user ask the host to restore access.
  Future<void> requestRejoin(String panelId, String userId) async {
    final panelRef = _panels.doc(panelId);
    await _firestore.runTransaction((transaction) async {
      final panel = await transaction.get(panelRef);
      if (!panel.exists) throw StateError('This panel no longer exists.');
      final data = panel.data()!;
      final kickedUsers = data['kickedUsers'] as List<dynamic>? ?? [];
      if (!kickedUsers.contains(userId)) {
        throw StateError('You are not removed from this panel.');
      }
      transaction.update(panelRef, {
        'rejoinRequests': FieldValue.arrayUnion([userId]),
      });
    });
  }

  /// Restores a removed user's access. Callers must verify the host identity.
  Future<void> unblockUser(
    String panelId,
    String userId, {
    required String hostId,
  }) async {
    final panelRef = _panels.doc(panelId);
    await _firestore.runTransaction((transaction) async {
      final panel = await transaction.get(panelRef);
      if (!panel.exists) throw StateError('This panel no longer exists.');
      if (panel.data()?['hostId'] != hostId) {
        throw StateError('Only the panel host can unblock users.');
      }
      transaction.update(panelRef, {
        'kickedUsers': FieldValue.arrayRemove([userId]),
        'rejoinRequests': FieldValue.arrayRemove([userId]),
      });
    });
  }

  /// Sets a participant's muted state.
  Future<void> setMuted(String panelId, String userId, bool muted) async {
    await _participants(panelId).doc(userId).update({'isMuted': muted});
  }

  /// Updates the participant's heartbeat timestamp.
  Future<void> updateHeartbeat(String panelId, String userId) async {
    try {
      await _participants(
        panelId,
      ).doc(userId).update({'lastSeen': FieldValue.serverTimestamp()});
    } catch (_) {
      // Best-effort — doc may have been deleted.
    }
  }

  /// Removes stale participants (no heartbeat for > 45 seconds).
  Future<void> cleanupStaleParticipants(String panelId) async {
    try {
      final cutoff = Timestamp.fromDate(
        DateTime.now().toUtc().subtract(const Duration(seconds: 45)),
      );
      final stale = await _participants(
        panelId,
      ).where('lastSeen', isLessThan: cutoff).get();
      for (final doc in stale.docs) {
        final participantRef = _participants(panelId).doc(doc.id);
        await _firestore.runTransaction((transaction) async {
          final current = await transaction.get(participantRef);
          final lastSeen = current.data()?['lastSeen'];
          if (!current.exists ||
              current.data()?['isOnline'] == false ||
              lastSeen is! Timestamp ||
              !lastSeen.toDate().isBefore(cutoff.toDate())) {
            return;
          }
          debugPrint('[DS] Cleaning up stale participant: ${doc.id}');
          transaction.update(participantRef, {
            'isOnline': false,
            'micRequested': false,
          });
          transaction.update(_panels.doc(panelId), {
            'participantCount': FieldValue.increment(-1),
          });
        });
      }
    } catch (e) {
      debugPrint('[PanelDataSource] cleanupStaleParticipants error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Panel? _panelFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;

    // Handle server timestamp that may not have resolved yet.
    DateTime createdAt;
    final ts = data['createdAt'];
    if (ts is Timestamp) {
      createdAt = ts.toDate();
    } else {
      createdAt = DateTime.now();
    }

    return Panel(
      id: doc.id,
      title: data['title'] as String? ?? '',
      hostId: data['hostId'] as String? ?? '',
      hostDisplayName: data['hostDisplayName'] as String? ?? '',
      status: data['status'] as String? ?? 'ended',
      createdAt: createdAt,
      participantCount: (data['participantCount'] as num?)?.toInt() ?? 0,
      durationMinutes:
          (data['durationMinutes'] as num?)?.toInt() ??
          Panel.defaultDurationMinutes,
      kickedUserIds: (data['kickedUsers'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(growable: false),
      rejoinRequestUserIds: (data['rejoinRequests'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  PanelParticipant? _participantFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) return null;

    DateTime? lastSeen;
    final lastSeenTs = data['lastSeen'];
    if (lastSeenTs is Timestamp) {
      lastSeen = lastSeenTs.toDate();
    }

    return PanelParticipant(
      userId: data['userId'] as String? ?? doc.id,
      displayName: data['displayName'] as String? ?? 'Unknown',
      role: PanelRole.fromString(data['role'] as String? ?? 'audience'),
      isOnline: data['isOnline'] as bool? ?? true,
      isMuted: data['isMuted'] as bool? ?? true,
      micRequested: data['micRequested'] as bool? ?? false,
      lastSeen: lastSeen,
    );
  }
}
