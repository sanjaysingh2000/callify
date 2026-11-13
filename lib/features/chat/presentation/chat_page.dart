import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../friends/data/chat_data_source.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.userId,
    required this.friendId,
    required this.friendName,
  });

  final String userId;
  final String friendId;
  final String friendName;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const _background = Color(0xFF0D171A);
  static const _surface = Color(0xFF172629);
  static const _mint = Color(0xFF63DCC8);

  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _chatDataSource = ChatDataSource();
  late final Stream<ChatTypingStatus?> _friendTypingStream;
  Timer? _typingIdleTimer;
  Timer? _typingHeartbeatTimer;
  Future<void> _typingWrites = Future<void>.value();
  bool _isTyping = false;
  bool _sending = false;

  String get _conversationId {
    final participantIds = [widget.userId, widget.friendId]..sort();
    return participantIds.join('_');
  }

  @override
  void initState() {
    super.initState();
    _friendTypingStream = _chatDataSource.typingStatusStream(
      chatId: _conversationId,
      userId: widget.friendId,
    );
    _messageController.addListener(_handleTextChanged);
  }

  @override
  void dispose() {
    _messageController.removeListener(_handleTextChanged);
    _typingIdleTimer?.cancel();
    _typingHeartbeatTimer?.cancel();
    if (_isTyping) _publishTypingState(false);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    if (_messageController.text.trim().isEmpty) {
      _stopTyping();
      return;
    }

    if (!_isTyping) {
      _isTyping = true;
      _publishTypingState(true);
      _typingHeartbeatTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => _publishTypingState(true),
      );
    }

    _typingIdleTimer?.cancel();
    _typingIdleTimer = Timer(const Duration(seconds: 3), _stopTyping);
  }

  void _stopTyping() {
    _typingIdleTimer?.cancel();
    _typingIdleTimer = null;
    _typingHeartbeatTimer?.cancel();
    _typingHeartbeatTimer = null;
    if (!_isTyping) return;
    _isTyping = false;
    _publishTypingState(false);
  }

  void _publishTypingState(bool isTyping) {
    _typingWrites = _typingWrites
        .then(
          (_) => _chatDataSource.setTyping(
            chatId: _conversationId,
            userId: widget.userId,
            isTyping: isTyping,
          ),
        )
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('[ChatPage] Could not update typing status: $error');
        });
  }

  Future<void> _send() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _sending) return;
    _stopTyping();
    setState(() => _sending = true);
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_conversationId)
          .collection('messages')
          .add({
            'senderId': widget.userId,
            'text': message,
            'createdAt': FieldValue.serverTimestamp(),
          });
      _messageController.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: const Text('Could not send message. Try again.'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF24433F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = FirebaseFirestore.instance
        .collection('chats')
        .doc(_conversationId)
        .collection('messages')
        .orderBy('createdAt');
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            _avatar(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.friendName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  _TypingStatusLabel(
                    stream: _friendTypingStream,
                    fallbackName: 'Your friend',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: .06),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: messages.snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _messageState(
                          icon: Icons.cloud_off_rounded,
                          title: 'Messages aren’t available',
                          detail: 'Check your connection and try again.',
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(color: _mint),
                        );
                      }
                      final docs = snapshot.data!.docs;
                      if (docs.isEmpty) return _emptyConversation();
                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data = docs[index].data();
                          final mine = data['senderId'] == widget.userId;
                          final text = data['text'];
                          if (text is! String) return const SizedBox.shrink();
                          final createdAt = data['createdAt'];
                          final time = createdAt is Timestamp
                              ? _formatTime(createdAt.toDate())
                              : null;
                          return _messageBubble(text, mine, time);
                        },
                      );
                    },
                  ),
                ),
                _composer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar() {
    final initial = widget.friendName.trim().isEmpty
        ? '?'
        : widget.friendName.trim().characters.first.toUpperCase();
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _mint.withValues(alpha: .14),
        border: Border.all(color: _mint.withValues(alpha: .24)),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          color: _mint,
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _emptyConversation() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _avatar(),
          const SizedBox(height: 18),
          Text(
            'Say hello to ${widget.friendName}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your conversation starts here. Send a message to keep in touch.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF91A5A6),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Text(
              'FRIENDS',
              style: TextStyle(
                color: _mint,
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _messageState({
    required IconData icon,
    required String title,
    required String detail,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF718587), size: 34),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF91A5A6), fontSize: 13),
          ),
        ],
      ),
    ),
  );

  Widget _messageBubble(String text, bool mine, String? time) => Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * .76,
      ),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(15, 11, 15, 8),
      decoration: BoxDecoration(
        color: mine ? const Color(0xFF63DCC8) : _surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(mine ? 18 : 5),
          bottomRight: Radius.circular(mine ? 5 : 18),
        ),
        border: mine
            ? null
            : Border.all(color: Colors.white.withValues(alpha: .045)),
      ),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
              color: mine ? const Color(0xFF0D2725) : const Color(0xFFF2F7F6),
              fontSize: 15,
              height: 1.35,
            ),
          ),
          if (time != null) ...[
            const SizedBox(height: 3),
            Text(
              time,
              style: TextStyle(
                color: mine ? const Color(0xFF27534D) : const Color(0xFF91A5A6),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _composer() => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: _background,
      border: Border(
        top: BorderSide(color: Colors.white.withValues(alpha: .06)),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _messageController,
            minLines: 1,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Write a message…',
              hintStyle: const TextStyle(
                color: Color(0xFF718587),
                fontSize: 14,
              ),
              filled: true,
              fillColor: _surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 17,
                vertical: 13,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: .045),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide(color: _mint.withValues(alpha: .6)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 48,
          height: 48,
          child: FilledButton(
            onPressed: _sending ? null : _send,
            style: FilledButton.styleFrom(
              backgroundColor: _mint,
              foregroundColor: const Color(0xFF0D2725),
              disabledBackgroundColor: _mint.withValues(alpha: .5),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _sending
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF0D2725),
                    ),
                  )
                : const Icon(Icons.arrow_upward_rounded, size: 22),
          ),
        ),
      ],
    ),
  );

  String _formatTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour < 12 ? 'AM' : 'PM'}';
  }
}

class _TypingStatusLabel extends StatefulWidget {
  const _TypingStatusLabel({
    required this.stream,
    required this.fallbackName,
  });

  final Stream<ChatTypingStatus?> stream;
  final String fallbackName;

  @override
  State<_TypingStatusLabel> createState() => _TypingStatusLabelState();
}

class _TypingStatusLabelState extends State<_TypingStatusLabel> {
  static const _typingStatusLifetime = Duration(seconds: 10);

  Timer? _expiryTimer;
  DateTime? _scheduledUpdateAt;
  DateTime? _expiredUpdateAt;

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  void _scheduleExpiry(DateTime? updatedAt) {
    if (updatedAt == null || updatedAt == _scheduledUpdateAt) return;

    _expiryTimer?.cancel();
    _scheduledUpdateAt = updatedAt;
    _expiredUpdateAt = null;
    final remaining =
        _typingStatusLifetime - DateTime.now().difference(updatedAt);
    _expiryTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      () {
        if (!mounted) return;
        setState(() => _expiredUpdateAt = updatedAt);
      },
    );
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<ChatTypingStatus?>(
    stream: widget.stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        debugPrint('[ChatPage] Typing status stream failed: ${snapshot.error}');
      }

      final typingStatus = snapshot.data;
      final updatedAt = typingStatus?.updatedAt;
      _scheduleExpiry(updatedAt);
      final isFresh = updatedAt == null ||
          DateTime.now().difference(updatedAt) < _typingStatusLifetime;
      final isTyping = typingStatus != null &&
          isFresh &&
          updatedAt != _expiredUpdateAt;

      return Text(
        isTyping ? 'Typing…' : widget.fallbackName,
        style: TextStyle(
          color: isTyping ? const Color(0xFF63DCC8) : const Color(0xFF91A5A6),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      );
    },
  );
}
