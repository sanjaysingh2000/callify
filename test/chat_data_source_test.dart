import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_call/features/friends/data/chat_data_source.dart';

void main() {
  test(
    'typing status is published and cleared for one chat participant',
    () async {
      final firestore = FakeFirebaseFirestore();
      final dataSource = ChatDataSource(firestore: firestore);
      final statuses = <ChatTypingStatus?>[];
      final activeStatusReceived = Completer<void>();
      final inactiveStatusReceived = Completer<void>();
      final subscription = dataSource
          .typingStatusStream(chatId: 'alice_bob', userId: 'bob')
          .listen((status) {
            statuses.add(status);
            if (status != null && !activeStatusReceived.isCompleted) {
              activeStatusReceived.complete();
            } else if (status == null &&
                activeStatusReceived.isCompleted &&
                !inactiveStatusReceived.isCompleted) {
              inactiveStatusReceived.complete();
            }
          });
      addTearDown(subscription.cancel);

      await dataSource.setTyping(
        chatId: 'alice_bob',
        userId: 'bob',
        isTyping: true,
      );
      await activeStatusReceived.future.timeout(const Duration(seconds: 2));

      final activeStatus = statuses.last!;
      expect(activeStatus.updatedAt, isNotNull);

      await dataSource.setTyping(
        chatId: 'alice_bob',
        userId: 'bob',
        isTyping: false,
      );
      await inactiveStatusReceived.future.timeout(const Duration(seconds: 2));

      expect(statuses.last, isNull);
      final typingDocument = await firestore
          .collection('chats')
          .doc('alice_bob')
          .collection('typing')
          .doc('bob')
          .get();
      expect(typingDocument.exists, isFalse);
    },
  );

  test('typing status is isolated by chat and participant', () async {
    final firestore = FakeFirebaseFirestore();
    final dataSource = ChatDataSource(firestore: firestore);
    await dataSource.setTyping(
      chatId: 'alice_bob',
      userId: 'alice',
      isTyping: true,
    );

    final friendStatus = await dataSource
        .typingStatusStream(chatId: 'alice_bob', userId: 'alice')
        .first;
    final unrelatedStatus = await dataSource
        .typingStatusStream(chatId: 'alice_bob', userId: 'bob')
        .first;
    final otherChatStatus = await dataSource
        .typingStatusStream(chatId: 'alice_charlie', userId: 'alice')
        .first;

    expect(friendStatus, isNotNull);
    expect(unrelatedStatus, isNull);
    expect(otherChatStatus, isNull);
  });
}
