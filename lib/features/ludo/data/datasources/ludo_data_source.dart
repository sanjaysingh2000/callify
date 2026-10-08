import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_ludo/flutter_ludo.dart';

import '../../domain/entities/ludo_room.dart';

class LudoDataSource {
  LudoDataSource({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _rooms =>
      _firestore.collection('ludo_rooms');

  CollectionReference<Map<String, dynamic>> _players(String roomId) =>
      _rooms.doc(roomId).collection('players');

  Future<String> createRoom(
    String title,
    String userId,
    String displayName,
  ) async {
    final room = _rooms.doc();
    final seats = List.generate(
      4,
      (_) => const LudoSeat(
        userId: null,
        displayName: null,
        isMuted: true,
      ).toMap(),
    );
    seats[0] = LudoSeat(
      userId: userId,
      displayName: displayName,
      isMuted: true,
    ).toMap();

    final batch = _firestore.batch();
    batch.set(room, {
      'title': title,
      'hostId': userId,
      'status': 'live',
      'seats': seats,
      'gameState': null,
      'gameUserIds': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(_players(room.id).doc(userId), {
      'userId': userId,
      'displayName': displayName,
      'seatIndex': 0,
      'isMuted': true,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return room.id;
  }

  Future<int> joinRoom(String roomId, String userId, String displayName) async {
    return _firestore.runTransaction((transaction) async {
      final roomRef = _rooms.doc(roomId);
      final roomSnapshot = await transaction.get(roomRef);
      if (!roomSnapshot.exists)
        throw StateError('This Ludo table no longer exists.');
      final room = LudoRoom.fromDocument(roomId, roomSnapshot.data()!);
      if (!room.isLive) throw StateError('This Ludo table has closed.');

      final existingIndex = room.seats.indexWhere(
        (seat) => seat.userId == userId,
      );
      if (existingIndex >= 0) {
        final seat = room.seats[existingIndex];
        final playerRef = _players(roomId).doc(userId);
        final playerSnapshot = await transaction.get(playerRef);
        if (!playerSnapshot.exists) {
          transaction.set(playerRef, {
            'userId': userId,
            'displayName': seat.displayName ?? displayName,
            'seatIndex': existingIndex,
            'isMuted': seat.isMuted,
            'joinedAt': FieldValue.serverTimestamp(),
          });
        }
        return existingIndex;
      }
      if (room.gameState != null)
        throw StateError('This game has already started.');
      final seatIndex = room.seats.indexWhere((seat) => !seat.isOccupied);
      if (seatIndex < 0) throw StateError('This Ludo table is full.');

      final seats = room.seats.toList();
      seats[seatIndex] = LudoSeat(
        userId: userId,
        displayName: displayName,
        isMuted: true,
      );
      transaction.update(roomRef, {
        'seats': seats.map((seat) => seat.toMap()).toList(),
      });
      transaction.set(_players(roomId).doc(userId), {
        'userId': userId,
        'displayName': displayName,
        'seatIndex': seatIndex,
        'isMuted': true,
        'joinedAt': FieldValue.serverTimestamp(),
      });
      return seatIndex;
    });
  }

  Future<void> leaveRoom(
    String roomId,
    String userId, {
    bool keepWaitingRoom = false,
  }) async {
    await _firestore.runTransaction((transaction) async {
      final roomRef = _rooms.doc(roomId);
      final roomSnapshot = await transaction.get(roomRef);
      if (!roomSnapshot.exists) return;
      final room = LudoRoom.fromDocument(roomId, roomSnapshot.data()!);
      final seatIndex = room.seats.indexWhere((seat) => seat.userId == userId);
      if (seatIndex < 0) return;
      if (room.gameState != null) {
        transaction.update(roomRef, {'status': 'ended'});
        transaction.delete(_players(roomId).doc(userId));
        return;
      }
      if (room.hostId == userId) {
        if (keepWaitingRoom) return;
        transaction.update(roomRef, {'status': 'ended'});
        transaction.delete(_players(roomId).doc(userId));
        return;
      }
      final seats = room.seats.toList();
      seats[seatIndex] = const LudoSeat(
        userId: null,
        displayName: null,
        isMuted: true,
      );
      final remaining = seats.where((seat) => seat.isOccupied).toList();
      if (remaining.isEmpty) {
        transaction.update(roomRef, {'status': 'ended'});
      } else {
        transaction.update(roomRef, {
          'seats': seats.map((seat) => seat.toMap()).toList(),
        });
      }
      transaction.delete(_players(roomId).doc(userId));
    });
  }

  Future<void> startGame(
    String roomId,
    String hostId,
    List<String> gameUserIds,
    Map<String, Object?> gameState,
  ) async {
    await _firestore.runTransaction((transaction) async {
      final roomRef = _rooms.doc(roomId);
      final roomSnapshot = await transaction.get(roomRef);
      if (!roomSnapshot.exists)
        throw StateError('This Ludo table no longer exists.');
      final room = LudoRoom.fromDocument(roomId, roomSnapshot.data()!);
      if (room.gameState != null) return;
      if (!room.isLive) throw StateError('This Ludo table has closed.');
      if (room.hostId != hostId ||
          !room.seats.any((seat) => seat.userId == hostId)) {
        throw StateError('Only the seated host can start the game.');
      }
      if (room.playerCount < 2)
        throw StateError('At least two players are needed.');

      final occupiedSeats = room.seats
          .where((seat) => seat.isOccupied)
          .toList();
      if (gameUserIds.length != occupiedSeats.length ||
          !List.generate(occupiedSeats.length, (index) => index).every(
            (index) => gameUserIds[index] == occupiedSeats[index].userId,
          ) ||
          gameUserIds.toSet().length != gameUserIds.length) {
        throw StateError('The game roster must match the seated players.');
      }

      final state = LudoGameState.fromJson(gameState);
      if (state.players.length != occupiedSeats.length ||
          !List.generate(occupiedSeats.length, (index) => index).every(
            (index) =>
                state.players[index].name == occupiedSeats[index].displayName,
          ) ||
          jsonEncode(LudoGameState.initial(state.players).toJson()) !=
              jsonEncode(state.toJson())) {
        throw StateError(
          'A new game must start from the seated players and initial state.',
        );
      }
      transaction.update(roomRef, {
        'gameState': gameState,
        'gameUserIds': gameUserIds,
      });
    });
  }

  Future<bool> applyGameState(
    String roomId,
    String userId,
    Map<String, Object?> gameState,
  ) => _firestore.runTransaction((transaction) async {
    final roomRef = _rooms.doc(roomId);
    final snapshot = await transaction.get(roomRef);
    if (!snapshot.exists) return false;
    final room = LudoRoom.fromDocument(roomId, snapshot.data()!);
    final seatIndex = room.gameUserIds.indexOf(userId);
    if (!room.isLive ||
        !room.seats.any((seat) => seat.userId == userId) ||
        seatIndex < 0 ||
        room.gameState == null) {
      return false;
    }

    final before = LudoGameState.fromJson(room.gameState!);
    final after = LudoGameState.fromJson(gameState);
    if (before.currentPlayerIndex != seatIndex) return false;

    final isRoll =
        before.phase == LudoTurnPhase.awaitingRoll &&
        after.rollCount == before.rollCount + 1 &&
        after.lastRollPlayerIndex == seatIndex;
    final isMove =
        before.phase == LudoTurnPhase.awaitingPieceSelection &&
        after.rollCount == before.rollCount &&
        after.lastMovedPiece != null;
    if (!isRoll && !isMove) return false;

    final engine = LudoEngine(const LudoDiceRules.modern());
    final expected = isRoll
        ? engine.roll(before, after.lastRoll!).state
        : engine
              .move(before, after.lastMovedPiece!.id)
              .state
              .copyWith(lastMovedPiece: after.lastMovedPiece);
    if (jsonEncode(expected.toJson()) != jsonEncode(after.toJson())) {
      return false;
    }

    transaction.update(roomRef, {'gameState': gameState});
    return true;
  });

  Future<void> setMuted(String roomId, String userId, bool muted) async {
    final roomRef = _rooms.doc(roomId);
    final playerRef = _players(roomId).doc(userId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(roomRef);
      final playerSnapshot = await transaction.get(playerRef);
      if (!snapshot.exists || !playerSnapshot.exists) return;
      final room = LudoRoom.fromDocument(roomId, snapshot.data()!);
      if (!room.isLive) return;
      final index = room.seats.indexWhere((seat) => seat.userId == userId);
      if (index < 0) return;
      final seats = room.seats.toList();
      final seat = seats[index];
      seats[index] = LudoSeat(
        userId: seat.userId,
        displayName: seat.displayName,
        isMuted: muted,
      );
      transaction.update(playerRef, {'isMuted': muted});
      transaction.update(roomRef, {
        'seats': seats.map((seat) => seat.toMap()).toList(),
      });
    });
  }

  Stream<List<LudoRoom>> liveRoomsStream() => _rooms
      .where('status', isEqualTo: 'live')
      .limit(50)
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs
                .map((doc) => LudoRoom.fromDocument(doc.id, doc.data()))
                .toList()
              ..sort((a, b) => a.title.compareTo(b.title)),
      );

  Stream<LudoRoom?> roomStream(String roomId) => _rooms
      .doc(roomId)
      .snapshots()
      .map(
        (snapshot) => snapshot.exists
            ? LudoRoom.fromDocument(roomId, snapshot.data()!)
            : null,
      );

  Future<LudoRoom?> getRoom(String roomId) async {
    final snapshot = await _rooms.doc(roomId).get();
    if (!snapshot.exists) return null;
    return LudoRoom.fromDocument(roomId, snapshot.data()!);
  }
}
