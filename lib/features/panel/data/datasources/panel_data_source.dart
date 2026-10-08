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
      'durationMinutes': Panel.defaultDurationMinutes,
      'expiresAt': Timestamp.fromDate(now.add(const Duration(hours: 1))),
    });

    // Add host as first participant.
    batch.set(_participants(panelId).doc(hostId), {
      'userId': hostId,
      'displayName': hostDisplayName,
      'role': PanelRole.host.toFirestoreString(),
      'isMuted': false,
      'micRequested': false,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();

    return panelId;
  }

  /// Ends a panel (sets status to 'ended').
  Future<void> endPanel(String panelId) async {
    await _panels.doc(panelId).update({'status': 'ended'});
  }

  /// Joins a panel as audience.
  Future<void> joinPanel(
    String panelId,
    String userId,
    String displayName,
  ) async {
    final participantRef = _participants(panelId).doc(userId);
    await _firestore.runTransaction((transaction) async {
      final participant = await transaction.get(participantRef);
      if (participant.exists) return;

      transaction.set(participantRef, {
        'userId': userId,
        'displayName': displayName,
        'role': PanelRole.audience.toFirestoreString(),
        'isMuted': true,
        'micRequested': false,
        'joinedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(_panels.doc(panelId), {
        'participantCount': FieldValue.increment(1),
      });
    });
  }

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

      if (participant.exists) {
        transaction.update(participantRef, {
          'displayName': displayName,
          'role': PanelRole.host.toFirestoreString(),
          'isMuted': false,
          'micRequested': false,
        });
      } else {
        transaction.set(participantRef, {
          'userId': userId,
          'displayName': displayName,
          'role': PanelRole.host.toFirestoreString(),
          'isMuted': false,
          'micRequested': false,
          'joinedAt': FieldValue.serverTimestamp(),
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
        });
      }
    });
  }

  /// Removes a participant from a panel.
  Future<void> leavePanel(String panelId, String userId) async {
    final participantRef = _participants(panelId).doc(userId);
    await _firestore.runTransaction((transaction) async {
      final participant = await transaction.get(participantRef);
      if (!participant.exists) return;

      transaction.delete(participantRef);
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

  // ---------------------------------------------------------------------------
  // Participant lookup
  // ---------------------------------------------------------------------------

  /// Returns the role of a participant, or null if they don't exist.
  /// Used to detect host rejoin.
  Future<PanelRole?> getParticipantRole(String panelId, String userId) async {
    try {
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
    await _participants(
      panelId,
    ).doc(userId).update({'role': newRole.toFirestoreString()});
  }

  /// Sets a mic request flag.
  Future<void> requestMic(String panelId, String userId) async {
    await _participants(panelId).doc(userId).update({'micRequested': true});
  }

  /// Approves a mic request — promotes to speaker and clears request.
  Future<void> approveMic(String panelId, String userId) async {
    await _participants(panelId).doc(userId).update({
      'role': PanelRole.speaker.toFirestoreString(),
      'micRequested': false,
    });
  }

  /// Denies a mic request.
  Future<void> denyMic(String panelId, String userId) async {
    await _participants(panelId).doc(userId).update({'micRequested': false});
  }

  /// Kicks a user from the panel.
  Future<void> kickUser(String panelId, String userId) async {
    final participantRef = _participants(panelId).doc(userId);
    await _firestore.runTransaction((transaction) async {
      final participant = await transaction.get(participantRef);
      if (!participant.exists) return;

      transaction.delete(participantRef);
      transaction.update(_panels.doc(panelId), {
        'participantCount': FieldValue.increment(-1),
      });
    });
  }

  /// Sets a participant's muted state.
  Future<void> setMuted(String panelId, String userId, bool muted) async {
    await _participants(panelId).doc(userId).update({'isMuted': muted});
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
    );
  }

  PanelParticipant? _participantFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) return null;

    return PanelParticipant(
      userId: data['userId'] as String? ?? doc.id,
      displayName: data['displayName'] as String? ?? 'Unknown',
      role: PanelRole.fromString(data['role'] as String? ?? 'audience'),
      isMuted: data['isMuted'] as bool? ?? true,
      micRequested: data['micRequested'] as bool? ?? false,
    );
  }
}
