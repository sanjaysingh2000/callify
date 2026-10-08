import 'package:flutter/material.dart';

import '../../../../core/utils/device_id_store.dart';
import '../../data/datasources/ludo_data_source.dart';
import '../../domain/entities/ludo_room.dart';
import 'ludo_room_page.dart';

class LudoListPage extends StatefulWidget {
  const LudoListPage({super.key, required this.displayName});

  final String displayName;

  @override
  State<LudoListPage> createState() => _LudoListPageState();
}

class _LudoListPageState extends State<LudoListPage> {
  final _dataSource = LudoDataSource();
  final _deviceIdStore = DeviceIdStore();
  late final Future<String> _userIdFuture = _deviceIdStore
      .getOrCreateDeviceId();

  Future<void> _createRoom() async {
    var roomTitle = 'Ludo table';
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D1B69),
        title: const Text('Create a Ludo table', style: TextStyle(color: Color(0xFFFFD700))),
        content: TextFormField(
          initialValue: roomTitle,
          maxLength: 28,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Table name',
            labelStyle: TextStyle(color: Color(0xFFFFD700)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFDAA520))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFFD700))),
          ),
          onChanged: (value) => roomTitle = value,
          onFieldSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDAA520),
              foregroundColor: const Color(0xFF1A0A2E),
            ),
            onPressed: () => Navigator.pop(context, roomTitle.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (!mounted || title == null || title.trim().isEmpty) return;

    try {
      final userId = await _deviceIdStore.getOrCreateDeviceId();
      final roomId = await _dataSource.createRoom(
        title.trim(),
        userId,
        widget.displayName,
      );
      if (!mounted) return;
      _openRoom(roomId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create a Ludo table.')),
      );
    }
  }

  void _openRoom(String roomId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            LudoRoomPage(roomId: roomId, displayName: widget.displayName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A0A2E), Color(0xFF2D1B69)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.casino, color: Color(0xFFFFD700)),
              const SizedBox(width: 8),
              const Text(
                'Ludo Tables',
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFDAA520)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: FloatingActionButton.extended(
            onPressed: _createRoom,
            backgroundColor: Colors.transparent,
            elevation: 0,
            highlightElevation: 0,
            focusElevation: 0,
            hoverElevation: 0,
            foregroundColor: const Color(0xFF1A0A2E),
            icon: const Icon(Icons.add),
            label: const Text('Create table', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
        body: FutureBuilder<String>(
          future: _userIdFuture,
          builder: (context, userSnapshot) {
            if (userSnapshot.hasError) {
              return const _LobbyMessage(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load your player profile',
                subtitle: 'Restart the app and try again.',
              );
            }
            if (!userSnapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFFFFD700)),
              );
            }
            final userId = userSnapshot.data!;
            return StreamBuilder<List<LudoRoom>>(
              stream: _dataSource.liveRoomsStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const _LobbyMessage(
                    icon: Icons.cloud_off_outlined,
                    title: 'Tables are unavailable',
                    subtitle: 'Check your connection and try again.',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFFD700)),
                  );
                }
                final rooms = snapshot.data!;
                if (rooms.isEmpty) {
                  return const _LobbyMessage(
                    icon: Icons.casino_outlined,
                    title: 'No open tables',
                    subtitle: 'Start a table and invite players to join.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: rooms.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _LudoRoomCard(
                    room: rooms[index],
                    userId: userId,
                    onTap: () => _openRoom(rooms[index].id),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _LudoRoomCard extends StatelessWidget {
  const _LudoRoomCard({
    required this.room,
    required this.userId,
    required this.onTap,
  });

  final LudoRoom room;
  final String userId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSeated = room.seats.any((seat) => seat.userId == userId);
    final isInGame = room.gameState != null;
    final canOpen = isInGame ? isSeated : isSeated || room.vacantSeats > 0;
    final actionLabel = isInGame
        ? isSeated
              ? 'Rejoin'
              : 'In game'
        : isSeated
        ? 'Open'
        : room.vacantSeats > 0
        ? 'Join'
        : 'Full';
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2D1B69),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDAA520), width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFDAA520).withValues(alpha: 0.2),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: canOpen ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDAA520).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFFD700).withValues(alpha: 0.3),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.casino, color: Color(0xFFFFD700)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        room.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _StatusTag(
                      label: room.gameState == null ? 'WAITING' : 'IN GAME',
                      color: room.gameState == null
                          ? const Color(0xFFFFD700)
                          : const Color(0xFF43A047),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 7,
                  children: List.generate(4, (index) {
                    final seat = room.seats[index];
                    return _SeatDot(index: index, occupied: seat.isOccupied);
                  }),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      '${room.playerCount}/4 joined',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${room.vacantSeats} vacant',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    if (canOpen)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            actionLabel,
                            style: TextStyle(
                              color: isInGame
                                  ? const Color(0xFF43A047)
                                  : const Color(0xFFFFD700),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            isInGame ? Icons.refresh : Icons.arrow_forward,
                            color: isInGame
                                ? const Color(0xFF43A047)
                                : const Color(0xFFFFD700),
                            size: 17,
                          ),
                        ],
                      )
                    else if (!isInGame)
                      const Text('Full', style: TextStyle(color: Colors.white38))
                    else
                      const Text(
                        'In game',
                        style: TextStyle(color: Colors.white60),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SeatDot extends StatelessWidget {
  const _SeatDot({required this.index, required this.occupied});

  final int index;
  final bool occupied;

  static const colors = [
    Color(0xFFE53935),
    Color(0xFF1E88E5),
    Color(0xFF43A047),
    Color(0xFFFDD835),
  ];

  @override
  Widget build(BuildContext context) => Container(
    width: 18,
    height: 18,
    decoration: BoxDecoration(
      color: occupied ? colors[index] : Colors.transparent,
      shape: BoxShape.circle,
      border: Border.all(color: colors[index], width: 1.5),
      boxShadow: occupied
          ? [
              BoxShadow(
                color: colors[index].withValues(alpha: 0.5),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ]
          : null,
    ),
  );
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
    ),
  );
}

class _LobbyMessage extends StatelessWidget {
  const _LobbyMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: const Color(0xFFFFD700).withValues(alpha: 0.6)),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60),
          ),
        ],
      ),
    ),
  );
}
