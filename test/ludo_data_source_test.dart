import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ludo/flutter_ludo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_call/features/ludo/data/datasources/ludo_data_source.dart';
import 'package:quick_call/features/ludo/domain/entities/ludo_room.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late LudoDataSource dataSource;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    dataSource = LudoDataSource(firestore: firestore);
  });

  test('creates a table with four seats and a muted host', () async {
    final roomId = await dataSource.createRoom('Friday game', 'host', 'Host');
    final snapshot = await firestore.collection('ludo_rooms').doc(roomId).get();
    final room = LudoRoom.fromDocument(roomId, snapshot.data()!);

    expect(room.playerCount, 1);
    expect(room.vacantSeats, 3);
    expect(room.seats.first.displayName, 'Host');
    expect(room.seats.first.isMuted, isTrue);
    expect(room.seats, hasLength(4));
  });

  test('malformed seat data is treated as vacant instead of crashing', () {
    final room = LudoRoom.fromDocument('broken', {
      'seats': [
        {'userId': 42, 'displayName': false, 'isMuted': 'no'},
        'invalid seat',
      ],
      'gameUserIds': [42, 'host'],
    });

    expect(room.seats, hasLength(4));
    expect(room.playerCount, 0);
    expect(room.seats.first.isMuted, isTrue);
    expect(room.gameUserIds, ['host']);
  });

  test('joining claims an open seat once and rejects a fifth player', () async {
    final roomId = await dataSource.createRoom('Friday game', 'host', 'Host');
    expect(await dataSource.joinRoom(roomId, 'guest-1', 'Guest 1'), 1);
    expect(await dataSource.joinRoom(roomId, 'guest-1', 'Guest 1'), 1);
    await dataSource.joinRoom(roomId, 'guest-2', 'Guest 2');
    await dataSource.joinRoom(roomId, 'guest-3', 'Guest 3');

    await expectLater(
      dataSource.joinRoom(roomId, 'guest-4', 'Guest 4'),
      throwsA(isA<StateError>()),
    );

    final room = await dataSource.roomStream(roomId).first;
    expect(room!.playerCount, 4);
    expect(room.vacantSeats, 0);
  });

  test('rejoining repairs a missing participant document', () async {
    final roomId = await dataSource.createRoom('Friday game', 'host', 'Host');
    await dataSource.joinRoom(roomId, 'guest', 'Guest');
    final guestRef = firestore
        .collection('ludo_rooms')
        .doc(roomId)
        .collection('players')
        .doc('guest');
    await guestRef.delete();

    expect(await dataSource.joinRoom(roomId, 'guest', 'Guest'), 1);

    expect((await guestRef.get()).exists, isTrue);
  });

  test(
    'only the player whose turn it is can publish a legal game state',
    () async {
      final roomId = await dataSource.createRoom('Friday game', 'host', 'Host');
      await dataSource.joinRoom(roomId, 'guest', 'Guest');
      const players = [
        LudoPlayer(name: 'Host', color: Color(0xFFE24B4B)),
        LudoPlayer(name: 'Guest', color: Color(0xFF3B82C4)),
      ];
      final state = LudoGameState.initial(players);
      await dataSource.startGame(roomId, 'host', [
        'host',
        'guest',
      ], state.toJson());
      final storedRoom = await firestore
          .collection('ludo_rooms')
          .doc(roomId)
          .get();
      final room = LudoRoom.fromDocument(roomId, storedRoom.data()!);
      expect(room.gameUserIds, ['host', 'guest']);
      expect(LudoGameState.fromJson(room.gameState!).toJson(), state.toJson());

      final game = LudoController(
        players: players,
        diceRules: const LudoDiceRules.modern(),
        diceRoller: () => 6,
        stepAnimationDuration: Duration.zero,
        autoMoveSingleChoice: false,
      );
      game.rollDice();
      final rolled = game.state;
      expect(rolled.rollCount, 1);
      expect(rolled.lastRollPlayerIndex, 0);
      expect(
        await dataSource.applyGameState(roomId, 'guest', rolled.toJson()),
        isFalse,
      );
      expect(
        await dataSource.applyGameState(
          roomId,
          'host',
          rolled.copyWith(currentPlayerIndex: 1).toJson(),
        ),
        isFalse,
      );
      expect(
        await dataSource.applyGameState(roomId, 'host', rolled.toJson()),
        isTrue,
        reason: 'the active seat should be able to publish its roll',
      );

      await game.selectPiece(rolled.legalMoves.first.pieceId);
      final moved = game.state;
      expect(
        await dataSource.applyGameState(roomId, 'host', moved.toJson()),
        isTrue,
        reason: 'the active seat should be able to publish its piece move',
      );
      game.dispose();
    },
  );

  test('game cannot start until a second player has joined', () async {
    final roomId = await dataSource.createRoom('Friday game', 'host', 'Host');
    const players = [LudoPlayer(name: 'Host', color: Color(0xFFE24B4B))];

    await expectLater(
      dataSource.startGame(roomId, 'host', [
        'host',
      ], LudoGameState.initial(players).toJson()),
      throwsA(isA<StateError>()),
    );
    final snapshot = await firestore.collection('ludo_rooms').doc(roomId).get();
    expect(snapshot.data()?['gameState'], isNull);
  });

  test('mic state is reflected in the room seat', () async {
    final roomId = await dataSource.createRoom('Friday game', 'host', 'Host');
    await dataSource.setMuted(roomId, 'host', false);

    final snapshot = await firestore.collection('ludo_rooms').doc(roomId).get();
    final room = LudoRoom.fromDocument(roomId, snapshot.data()!);
    expect(room.seats.first.isMuted, isFalse);
  });

  test('host can return to the list without closing a waiting table', () async {
    final roomId = await dataSource.createRoom('Friday game', 'host', 'Host');
    await dataSource.joinRoom(roomId, 'guest', 'Guest');

    await dataSource.leaveRoom(roomId, 'host', keepWaitingRoom: true);

    final rooms = await dataSource.liveRoomsStream().first;
    expect(rooms, hasLength(1));
    expect(rooms.single.id, roomId);
    expect(rooms.single.status, 'live');
    expect(rooms.single.seats.first.userId, 'host');
    expect(await dataSource.joinRoom(roomId, 'host', 'Host'), 0);
  });

  test('leaving as host normally closes a waiting table', () async {
    final roomId = await dataSource.createRoom('Friday game', 'host', 'Host');
    await dataSource.leaveRoom(roomId, 'host');

    expect(await dataSource.liveRoomsStream().first, isEmpty);
  });

  test('guest can leave one waiting table and join another', () async {
    final firstRoomId = await dataSource.createRoom(
      'First table',
      'host-1',
      'Host 1',
    );
    final secondRoomId = await dataSource.createRoom(
      'Second table',
      'host-2',
      'Host 2',
    );
    await dataSource.joinRoom(firstRoomId, 'guest', 'Guest');

    await dataSource.leaveRoom(firstRoomId, 'guest');

    final firstRoom = await dataSource.getRoom(firstRoomId);
    expect(firstRoom!.playerCount, 1);
    expect(firstRoom.seats[1].userId, isNull);
    expect(await dataSource.joinRoom(secondRoomId, 'guest', 'Guest'), 1);
  });

  test(
    'game start rejects a roster that does not match occupied seats',
    () async {
      final roomId = await dataSource.createRoom('Friday game', 'host', 'Host');
      await dataSource.joinRoom(roomId, 'guest', 'Guest');
      const players = [
        LudoPlayer(name: 'Host', color: Color(0xFFE24B4B)),
        LudoPlayer(name: 'Guest', color: Color(0xFF3B82C4)),
      ];

      await expectLater(
        dataSource.startGame(roomId, 'host', [
          'host',
          'intruder',
        ], LudoGameState.initial(players).toJson()),
        throwsA(isA<StateError>()),
      );
      final snapshot = await firestore
          .collection('ludo_rooms')
          .doc(roomId)
          .get();
      expect(snapshot.data()?['gameState'], isNull);
    },
  );

  test('game start rejects a non-initial board snapshot', () async {
    final roomId = await dataSource.createRoom('Friday game', 'host', 'Host');
    await dataSource.joinRoom(roomId, 'guest', 'Guest');
    const players = [
      LudoPlayer(name: 'Host', color: Color(0xFFE24B4B)),
      LudoPlayer(name: 'Guest', color: Color(0xFF3B82C4)),
    ];
    final modifiedState = LudoGameState.initial(players).copyWith(rollCount: 1);

    await expectLater(
      dataSource.startGame(roomId, 'host', [
        'host',
        'guest',
      ], modifiedState.toJson()),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'seated players can rejoin a started game but outsiders cannot',
    () async {
      final roomId = await dataSource.createRoom('Friday game', 'host', 'Host');
      await dataSource.joinRoom(roomId, 'guest', 'Guest');
      const players = [
        LudoPlayer(name: 'Host', color: Color(0xFFE24B4B)),
        LudoPlayer(name: 'Guest', color: Color(0xFF3B82C4)),
      ];
      await dataSource.startGame(roomId, 'host', [
        'host',
        'guest',
      ], LudoGameState.initial(players).toJson());

      expect(await dataSource.joinRoom(roomId, 'host', 'Host'), 0);
      expect(await dataSource.joinRoom(roomId, 'guest', 'Guest'), 1);
      await expectLater(
        dataSource.joinRoom(roomId, 'outsider', 'Outsider'),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('non-member cannot end a started game by leaving', () async {
    final roomId = await dataSource.createRoom('Friday game', 'host', 'Host');
    await dataSource.joinRoom(roomId, 'guest', 'Guest');
    const players = [
      LudoPlayer(name: 'Host', color: Color(0xFFE24B4B)),
      LudoPlayer(name: 'Guest', color: Color(0xFF3B82C4)),
    ];
    await dataSource.startGame(roomId, 'host', [
      'host',
      'guest',
    ], LudoGameState.initial(players).toJson());

    await dataSource.leaveRoom(roomId, 'intruder');

    final snapshot = await firestore.collection('ludo_rooms').doc(roomId).get();
    expect(snapshot.data()?['status'], 'live');
  });
}
