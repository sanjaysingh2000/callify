import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/entities/message.dart';

/// Firestore CRUD for chat messages and chat metadata.
class ChatDataSource {
  ChatDataSource({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _typingDocument(
    String chatId,
    String userId,
  ) => _firestore
      .collection('chats')
      .doc(chatId)
      .collection('typing')
      .doc(userId);

  /// Sorts both IDs alphabetically and joins with `_` to guarantee
  /// the same chatId for both participants.
  static String getChatId(String userId1, String userId2) {
    final ids = [userId1, userId2]..sort();
    return ids.join('_');
  }

  /// Sends a new message and updates chat doc's last message metadata in a batch.
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String text,
  }) async {
    final batch = _firestore.batch();
    final chatRef = _firestore.collection('chats').doc(chatId);
    final messageRef = chatRef.collection('messages').doc();

    batch.set(messageRef, {
      'senderId': senderId,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    });

    batch.set(chatRef, {
      'lastMessage': text,
      'lastMessageAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// Creates chat document with participants if it does not already exist.
  Future<void> ensureChatExists({
    required String chatId,
    required String userId1,
    required String userId2,
  }) async {
    final chatRef = _firestore.collection('chats').doc(chatId);
    await chatRef.set({
      'participants': [userId1, userId2],
    }, SetOptions(merge: true));
  }

  /// Publishes or clears a participant's transient typing presence.
  Future<void> setTyping({
    required String chatId,
    required String userId,
    required bool isTyping,
  }) async {
    final typingDocument = _typingDocument(chatId, userId);
    if (!isTyping) {
      await typingDocument.delete();
      return;
    }

    await typingDocument.set({
      'isTyping': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Streams the other participant's typing state and last server update.
  Stream<ChatTypingStatus?> typingStatusStream({
    required String chatId,
    required String userId,
  }) {
    return _typingDocument(chatId, userId).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null || data['isTyping'] != true) return null;

      final updatedAt = data['updatedAt'];
      return ChatTypingStatus(
        updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : DateTime.now(),
      );
    });
  }

  /// Returns stream of messages ordered by createdAt ascending, limited to [limit].
  Stream<List<Message>> messagesStream(String chatId, {int limit = 50}) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            return Message(
              id: doc.id,
              senderId: data['senderId'] as String? ?? '',
              text: data['text'] as String? ?? '',
              createdAt: _parseDateTime(data['createdAt']),
              read: data['read'] as bool? ?? false,
            );
          }).toList();
        });
  }

  /// Marks a specific message as read.
  Future<void> markAsRead(String chatId, String messageId) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({'read': true});
  }

  /// Stream of the chat doc data for last message preview.
  Stream<Map<String, dynamic>?> chatMetaStream(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .snapshots()
        .map((snapshot) => snapshot.data());
  }

  DateTime _parseDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return DateTime.now();
  }
}

class ChatTypingStatus {
  const ChatTypingStatus({required this.updatedAt});

  final DateTime? updatedAt;
}
