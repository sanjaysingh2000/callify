import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/device_id_store.dart';
import '../data/friend_data_source.dart';
import '../../chat/presentation/chat_page.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  static const _background = Color(0xFF0D171A);
  static const _surface = Color(0xFF172629);
  static const _mint = Color(0xFF63DCC8);

  FriendDataSource? _dataSource;
  final _searchController = TextEditingController();
  late final Future<String> _userId = DeviceIdStore().getOrCreateDeviceId();
  final Set<String> _busy = {};
  String? _streamsUserId;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _requestsStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _friendsStream;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _act(
    String id,
    Future<void> Function() action,
    String success,
  ) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      await action();
      if (mounted) _showMessage(success);
    } catch (error) {
      if (mounted) {
        _showMessage(
          error is StateError
              ? error.message
              : 'Could not complete that action. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF24433F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _userId,
    builder: (context, userSnapshot) {
      if (userSnapshot.hasError) {
        return _scaffold(
          const Center(
            child: _EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Could not open friends',
              detail: 'Check your connection and try again.',
            ),
          ),
        );
      }
      if (!userSnapshot.hasData) {
        return _scaffold(
          const Center(child: CircularProgressIndicator(color: _mint)),
        );
      }
      final userId = userSnapshot.data!;
      final dataSource = _getDataSource();
      if (dataSource == null) {
        return _scaffold(
          const Center(
            child: _EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Friends are unavailable',
              detail: 'Connect to the internet and try again.',
            ),
          ),
        );
      }
      if (_streamsUserId != userId) {
        _streamsUserId = userId;
        _requestsStream = dataSource.incomingRequests(userId);
        _friendsStream = dataSource.friends(userId);
      }
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _requestsStream,
        builder: (context, requestsSnapshot) =>
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _friendsStream,
              builder: (context, friendsSnapshot) {
                final requests = requestsSnapshot.data?.docs ?? const [];
                final allFriends = friendsSnapshot.data?.docs ?? const [];
                final filteredFriends =
                    allFriends.where((friend) {
                      final name =
                          (friend.data()['displayName'] as String? ?? '')
                              .toLowerCase();
                      return name.contains(_query.trim().toLowerCase());
                    }).toList()..sort(
                      (a, b) => (a.data()['displayName'] as String? ?? '')
                          .toLowerCase()
                          .compareTo(
                            (b.data()['displayName'] as String? ?? '')
                                .toLowerCase(),
                          ),
                    );
                return _scaffold(
                  requestsSnapshot.hasError || friendsSnapshot.hasError
                      ? const _EmptyState(
                          icon: Icons.cloud_off_rounded,
                          title: 'Can’t sync your people',
                          detail:
                              'Check your connection. Your list will update when you’re back online.',
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
                          children: [
                            _introCard(requests.length, allFriends.length),
                            const SizedBox(height: 28),
                            _sectionHeader(
                              'Requests',
                              count: requests.length,
                              trailing: requests.isEmpty
                                  ? null
                                  : 'NEEDS YOUR REPLY',
                            ),
                            const SizedBox(height: 12),
                            if (!requestsSnapshot.hasData)
                              const _LoadingRow()
                            else if (requests.isEmpty)
                              const _CompactEmpty(
                                icon: Icons.mark_email_read_outlined,
                                text:
                                    'You’re all caught up. New requests will show up here.',
                              )
                            else
                              ...requests.map(
                                (request) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _requestCard(request, userId),
                                ),
                              ),
                            const SizedBox(height: 22),
                            _sectionHeader(
                              'Your friends',
                              count: allFriends.length,
                            ),
                            const SizedBox(height: 12),
                            if (allFriends.isNotEmpty) ...[
                              _searchBox(),
                              const SizedBox(height: 10),
                            ],
                            if (!friendsSnapshot.hasData)
                              const _LoadingRow()
                            else if (allFriends.isEmpty)
                              const _CompactEmpty(
                                icon: Icons.people_outline_rounded,
                                text:
                                    'Friends you make after a call will be kept here, ready for next time.',
                              )
                            else if (filteredFriends.isEmpty)
                              const _CompactEmpty(
                                icon: Icons.search_off_rounded,
                                text: 'No friends match that name.',
                              )
                            else
                              ...filteredFriends.map(
                                (friend) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _friendRow(friend),
                                ),
                              ),
                          ],
                        ),
                );
              },
            ),
      );
    },
  );

  FriendDataSource? _getDataSource() {
    if (_dataSource != null) return _dataSource;
    try {
      _dataSource = FriendDataSource();
      return _dataSource;
    } catch (error) {
      debugPrint('[FriendsPage] Firestore is unavailable: $error');
      return null;
    }
  }

  Widget _scaffold(Widget body) => Scaffold(
    backgroundColor: _background,
    appBar: AppBar(
      backgroundColor: _background,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
      ),
      title: const Text(
        'Your people',
        style: TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
      centerTitle: false,
    ),
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: body,
        ),
      ),
    ),
  );

  Widget _introCard(int requestCount, int friendCount) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1D4645), Color(0xFF173334), Color(0xFF192A30)],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: .07)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _mint.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.diversity_3_rounded,
                color: _mint,
                size: 25,
              ),
            ),
            const Spacer(),
            _statPill(Icons.people_alt_rounded, '$friendCount friends'),
          ],
        ),
        const SizedBox(height: 18),
        const Text(
          'Good conversations\ncan start a friendship.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 23,
            height: 1.16,
            fontWeight: FontWeight.w800,
            letterSpacing: -.35,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          requestCount == 0
              ? 'Connect after a call and keep in touch here.'
              : '$requestCount ${requestCount == 1 ? 'person is' : 'people are'} waiting for your reply.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .66),
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ],
    ),
  );

  Widget _statPill(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .18),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _mint, size: 15),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _sectionHeader(String title, {required int count, String? trailing}) =>
      Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -.2,
            ),
          ),
          const SizedBox(width: 9),
          Container(
            constraints: const BoxConstraints(minWidth: 23),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .8),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          if (trailing != null)
            Text(
              trailing,
              style: const TextStyle(
                color: _mint,
                fontSize: 9,
                letterSpacing: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      );

  Widget _requestCard(
    QueryDocumentSnapshot<Map<String, dynamic>> request,
    String userId,
  ) {
    final name = request.data()['senderName'] as String? ?? 'Callify user';
    final busy = _busy.contains('request:${request.id}');
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _mint.withValues(alpha: .19)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _avatar(name, large: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Would like to be friends',
                      style: TextStyle(color: Color(0xFF9BAEB0), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: _mint,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (busy)
            const SizedBox(
              height: 42,
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2, color: _mint),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: OutlinedButton(
                      onPressed: () => _act(
                        'request:${request.id}',
                        () => _dataSource!.rejectRequest(
                          recipientId: userId,
                          senderId: request.id,
                        ),
                        'Request declined',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFCAD5D4),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: .14),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Decline'),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: FilledButton.icon(
                      onPressed: () => _act(
                        'request:${request.id}',
                        () => _dataSource!.acceptRequest(
                          recipientId: userId,
                          senderId: request.id,
                        ),
                        'You’re friends now',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _mint,
                        foregroundColor: const Color(0xFF0D2725),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(
                        Icons.person_add_alt_1_rounded,
                        size: 17,
                      ),
                      label: const Text(
                        'Accept',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _friendRow(QueryDocumentSnapshot<Map<String, dynamic>> friend) {
    final name = friend.data()['displayName'] as String? ?? 'Callify user';
    final friendId = friend.id;
    final removing = _busy.contains('friend:$friendId');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .045)),
      ),
      child: Row(
        children: [
          _avatar(name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: _mint, size: 12),
                    SizedBox(width: 5),
                    Text(
                      'Friend',
                      style: TextStyle(color: Color(0xFF9BAEB0), fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Message $name',
            onPressed: removing
                ? null
                : () async {
                    final userId = await _userId;
                    if (!mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ChatPage(
                          userId: userId,
                          friendId: friendId,
                          friendName: name,
                        ),
                      ),
                    );
                  },
            icon: const Icon(Icons.message_outlined, color: _mint),
          ),
          PopupMenuButton<String>(
            tooltip: 'More options for $name',
            enabled: !removing,
            color: _surface,
            onSelected: (action) {
              if (action == 'remove') _confirmRemoveFriend(friendId, name);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'remove',
                child: Row(
                  children: [
                    Icon(
                      Icons.person_remove_alt_1_rounded,
                      size: 19,
                      color: Colors.red.shade300,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Remove friend',
                      style: TextStyle(color: Colors.red.shade300),
                    ),
                  ],
                ),
              ),
            ],
            icon: removing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _mint,
                    ),
                  )
                : const Icon(Icons.more_vert_rounded, color: Color(0xFF9BAEB0)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemoveFriend(String friendId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Remove friend?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '$name will be removed from your friends. You can send a new request later.',
          style: const TextStyle(color: Color(0xFFB5C6C5), height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFFB5C6C5)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Remove',
              style: TextStyle(
                color: Colors.red.shade300,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final userId = await _userId;
    if (!mounted) return;
    await _act(
      'friend:$friendId',
      () => _dataSource!.removeFriend(userId: userId, friendId: friendId),
      'Friend removed',
    );
  }

  Widget _avatar(String name, {bool large = false}) {
    final initial = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();
    final colors = [
      const Color(0xFF4ADBC4),
      const Color(0xFFFFA477),
      const Color(0xFF91AFFF),
      const Color(0xFFF2C14E),
    ];
    final color = colors[name.hashCode.abs() % colors.length];
    return Container(
      width: large ? 48 : 44,
      height: large ? 48 : 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: .14),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: color,
          fontSize: large ? 19 : 17,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _searchBox() => TextField(
    controller: _searchController,
    onChanged: (value) => setState(() => _query = value),
    style: const TextStyle(color: Colors.white, fontSize: 14),
    decoration: InputDecoration(
      hintText: 'Search friends',
      hintStyle: const TextStyle(color: Color(0xFF718587), fontSize: 13),
      prefixIcon: const Icon(
        Icons.search_rounded,
        color: Color(0xFF718587),
        size: 21,
      ),
      suffixIcon: _query.isEmpty
          ? null
          : IconButton(
              icon: const Icon(Icons.close, color: Color(0xFF718587), size: 18),
              onPressed: () {
                _searchController.clear();
                setState(() => _query = '');
              },
            ),
      filled: true,
      fillColor: const Color(0xFF142225),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .05)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _mint, width: 1),
      ),
    ),
  );
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 22),
    child: Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Color(0xFF63DCC8),
        ),
      ),
    ),
  );
}

class _CompactEmpty extends StatelessWidget {
  const _CompactEmpty({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
    decoration: BoxDecoration(
      color: const Color(0xFF142225),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: .045)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF63DCC8), size: 19),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFFA9B9BA),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: const Color(0xFF63DCC8), size: 42),
      const SizedBox(height: 14),
      Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Text(
          detail,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF9BAEB0),
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ),
    ],
  );
}
