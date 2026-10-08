import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_ludo/flutter_ludo.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/ludo_room.dart';
import '../controllers/ludo_room_controller.dart';
import '../widgets/ludo_animated_dice.dart';
import 'ludo_flame_board.dart';

const _ludoBackdrop = Color(0xFF0B2026);
const _ludoPanel = Color(0xFF123238);
const _ludoPanelRaised = Color(0xFF183D42);
const _ludoLine = Color(0xFF294A4F);
const _ludoAccent = Color(0xFFF0C55A);

const _ludoRoomTheme = LudoTheme(
  boardBackgroundColor: Color(0xFF173A3D),
  pathCellColor: Color(0xFFF4F2E8),
  safeCellColor: Color(0xFFFFD76A),
  gridLineColor: Color(0xFF31545A),
  centerCellColor: Color(0xFFF4F2E8),
  starIconColor: Color(0xFF99712A),
  homeBorderColor: Color(0xFFE4D7AD),
  homePartitionColor: Color(0xFFBDD0CE),
  movementTrailColor: Color(0x5074E6CE),
  backgroundColor: _ludoBackdrop,
  panelColor: _ludoPanel,
  textColor: Color(0xFFF5FAF6),
  mutedTextColor: Color(0xFFA0B5B2),
  dividerColor: _ludoLine,
  lastMovedColor: Color(0xFFF6C453),
);

class LudoRoomPage extends StatefulWidget {
  const LudoRoomPage({
    super.key,
    required this.roomId,
    required this.displayName,
  });

  final String roomId;
  final String displayName;

  @override
  State<LudoRoomPage> createState() => _LudoRoomPageState();
}

class _LudoRoomPageState extends State<LudoRoomPage> {
  late final LudoRoomController _controller;
  bool _isClosing = false;
  bool _isConfirmingLeave = false;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    _controller = LudoRoomController()..addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.join(widget.roomId, widget.displayName);
    });
  }

  void _onChanged() {
    if (_controller.roomEnded && !_isClosing && mounted) {
      _isClosing = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This Ludo table has closed.')),
      );
      _popClosedRoom();
    }
  }

  Future<void> _popClosedRoom() async {
    final currentRoute = ModalRoute.of(context);
    if (currentRoute != null) {
      Navigator.of(context).popUntil((route) => route == currentRoute);
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _requestLeave({bool cancelRoom = false}) async {
    if (_isClosing || _isConfirmingLeave) return;
    _isConfirmingLeave = true;
    var shouldLeave = true;
    if (_controller.hasStartedGame || cancelRoom) {
      final isCancellingRoom = cancelRoom && !_controller.hasStartedGame;
      shouldLeave =
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              backgroundColor: _ludoPanel,
              title: Text(
                isCancellingRoom ? 'Cancel Ludo room?' : 'Leave Ludo game?',
                style: const TextStyle(color: Colors.white),
              ),
              content: Text(
                isCancellingRoom
                    ? 'This will close the waiting room for everyone. Continue?'
                    : 'Leaving will end this Ludo table for everyone. Do you want to continue?',
                style: const TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Stay'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB64C38),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(isCancellingRoom ? 'Cancel room' : 'Leave game'),
                ),
              ],
            ),
          ) ??
          false;
    }
    _isConfirmingLeave = false;
    if (!mounted || _isClosing || !shouldLeave) return;

    _isClosing = true;
    final keepWaitingRoom =
        _controller.isHost && !_controller.hasStartedGame && !cancelRoom;
    await _controller.leave(keepWaitingRoom: keepWaitingRoom);
    if (!mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  void _onPopInvoked(bool didPop, Object? result) {
    if (!didPop) _requestLeave();
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    if (!_isClosing) _controller.leave();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Consumer<LudoRoomController>(
        builder: (context, controller, _) => PopScope<void>(
          canPop: _allowPop,
          onPopInvokedWithResult: _onPopInvoked,
          child: Scaffold(
            backgroundColor: _ludoBackdrop,
            body: SafeArea(
              child: controller.isConnecting
                  ? const Center(
                      child: CircularProgressIndicator(color: _ludoAccent),
                    )
                  : controller.errorMessage != null
                  ? _ErrorView(
                      message: controller.errorMessage!,
                      onBack: _requestLeave,
                    )
                  : _buildRoom(controller),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoom(LudoRoomController controller) {
    final room = controller.room;
    if (room == null) {
      return const Center(child: CircularProgressIndicator(color: _ludoAccent));
    }
    final game = controller.game;
    return Column(
      children: [
        _RoomHeader(
          title: room.title,
          isHost: controller.isHost,
          hasStartedGame: controller.hasStartedGame,
          isMuted: controller.isMuted,
          isMicUpdating: controller.isMicUpdating,
          onMicTap: controller.toggleMic,
          onLeave: () => _requestLeave(
            cancelRoom: controller.isHost && !controller.hasStartedGame,
          ),
        ),
        if (controller.syncError != null)
          _SyncNotice(message: controller.syncError!),
        if (game != null) ...[
          _TurnBanner(
            game: game,
            isMyTurn: controller.isMyTurn,
            isSyncing: controller.isSyncing,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final boardSize = math.min(
                  math.max(0.0, constraints.maxWidth - 20),
                  math.max(0.0, constraints.maxHeight - 154),
                );
                return Align(
                  alignment: const Alignment(0, -0.25),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                        child: Container(
                          width: boardSize,
                          height: boardSize,
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _ludoPanelRaised,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _ludoAccent, width: 1.5),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x30F0C55A),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: AbsorbPointer(
                              absorbing: !controller.canInteract,
                              child: SizedBox.expand(
                                child: LudoFlameBoard(
                                  controller: game,
                                  theme: _ludoRoomTheme,
                                  playerIndex: controller.playerIndex ?? 0,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        decoration: controller.canInteract
                            ? const BoxDecoration(
                                boxShadow: [
                                  BoxShadow(
                                    color: Color(0x30F0C55A),
                                    blurRadius: 15,
                                  ),
                                ],
                              )
                            : null,
                        child: Opacity(
                          opacity: controller.canInteract ? 1 : 0.55,
                          child: AbsorbPointer(
                            absorbing: !controller.canInteract,
                            child: LudoAnimatedDice(
                              controller: game,
                              theme: _ludoRoomTheme,
                            ),
                          ),
                        ),
                      ),
                      _VoiceRoster(room: room),
                    ],
                  ),
                );
              },
            ),
          ),
        ] else ...[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
              children: [
                _LobbySummary(room: room),
                const SizedBox(height: 18),
                _SeatGrid(room: room, myUserId: controller.userId),
                const SizedBox(height: 24),
                if (controller.isHost)
                  FilledButton.icon(
                    onPressed:
                        room.playerCount >= 2 && !controller.isStartingGame
                        ? controller.startGame
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      controller.isStartingGame ? 'Starting…' : 'Start game',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _ludoAccent,
                      foregroundColor: Colors.black87,
                      disabledBackgroundColor: Colors.white12,
                      minimumSize: const Size.fromHeight(54),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      'Waiting for the host to start',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({
    required this.title,
    required this.isHost,
    required this.hasStartedGame,
    required this.isMuted,
    required this.isMicUpdating,
    required this.onMicTap,
    required this.onLeave,
  });

  final String title;
  final bool isHost;
  final bool hasStartedGame;
  final bool isMuted;
  final bool isMicUpdating;
  final VoidCallback onMicTap;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) => Container(
    height: 62,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: const BoxDecoration(
      color: _ludoBackdrop,
      border: Border(bottom: BorderSide(color: _ludoLine)),
    ),
    child: Row(
      children: [
        IconButton(
          onPressed: onLeave,
          tooltip: isHost && !hasStartedGame
              ? 'Cancel room'
              : hasStartedGame
              ? 'Leave game'
              : 'Leave table',
          icon: Icon(
            isHost && !hasStartedGame
                ? Icons.cancel_outlined
                : Icons.arrow_back,
            color: Colors.white70,
          ),
        ),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton.filledTonal(
          onPressed: isMicUpdating ? null : onMicTap,
          tooltip: isMuted ? 'Turn microphone on' : 'Turn microphone off',
          style: IconButton.styleFrom(
            backgroundColor: isMuted
                ? Colors.white.withValues(alpha: 0.1)
                : const Color(0xFF43A047),
            foregroundColor: Colors.white,
          ),
          icon: Icon(isMuted ? Icons.mic_off : Icons.mic),
        ),
      ],
    ),
  );
}

class _LobbySummary extends StatelessWidget {
  const _LobbySummary({required this.room});

  final LudoRoom room;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _ludoPanel,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white10),
    ),
    child: Row(
      children: [
        const Icon(Icons.casino, color: _ludoAccent, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${room.playerCount} players joined',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${room.vacantSeats} seats open',
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SeatGrid extends StatelessWidget {
  const _SeatGrid({required this.room, required this.myUserId});

  final LudoRoom room;
  final String? myUserId;

  static const _colors = [
    Color(0xFFE53935),
    Color(0xFF1E88E5),
    Color(0xFF43A047),
    Color(0xFFFDD835),
  ];

  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: room.seats.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.55,
    ),
    itemBuilder: (context, index) {
      final seat = room.seats[index];
      final isMine = seat.userId == myUserId;
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _ludoPanel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: seat.isOccupied
                ? _colors[index].withValues(alpha: 0.8)
                : Colors.white12,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _colors[index].withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                seat.isOccupied ? Icons.person : Icons.person_add_alt_1,
                color: _colors[index],
                size: 18,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    seat.displayName ?? 'Open seat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isMine
                        ? 'You'
                        : seat.isOccupied
                        ? 'Player'
                        : 'Vacant',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (seat.isOccupied)
              Icon(
                seat.isMuted ? Icons.mic_off : Icons.mic,
                color: seat.isMuted ? Colors.white38 : const Color(0xFF43A047),
                size: 17,
              ),
          ],
        ),
      );
    },
  );
}

class _TurnBanner extends StatelessWidget {
  const _TurnBanner({
    required this.game,
    required this.isMyTurn,
    required this.isSyncing,
  });

  final LudoController game;
  final bool isMyTurn;
  final bool isSyncing;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: game,
      builder: (context, _) {
        final state = game.state;
        final message = state.isFinished
            ? '${state.players[state.winners.first].name} wins'
            : isSyncing
            ? 'Saving turn…'
            : isMyTurn
            ? state.phase == LudoTurnPhase.awaitingPieceSelection
                  ? 'Choose a piece'
                  : 'Your turn · Roll the dice'
            : "${state.currentPlayer.name}'s turn";
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: _ludoPanel,
            border: Border(
              left: BorderSide(
                color: state.isFinished
                    ? _ludoAccent
                    : state.currentPlayer.color,
                width: 3,
              ),
              bottom: const BorderSide(color: _ludoLine),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              Icon(
                state.isFinished
                    ? Icons.emoji_events_outlined
                    : isMyTurn
                    ? Icons.casino_outlined
                    : Icons.sync_alt,
                color: state.isFinished
                    ? _ludoAccent
                    : state.currentPlayer.color,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF4F1E8),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (state.lastRoll != null)
                Text(
                  'LAST ${state.lastRoll}',
                  style: const TextStyle(
                    color: Color(0xFFB8A9D4),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _VoiceRoster extends StatelessWidget {
  const _VoiceRoster({required this.room});

  final LudoRoom room;

  @override
  Widget build(BuildContext context) {
    final seats = room.seats.where((seat) => seat.isOccupied).toList();
    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: _ludoBackdrop,
        border: Border(top: BorderSide(color: _ludoLine)),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 16, right: 10),
            child: Icon(Icons.graphic_eq, color: Color(0xFFB8A9D4), size: 18),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(0, 10, 14, 10),
              scrollDirection: Axis.horizontal,
              itemCount: seats.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final seat = seats[index];
                return Container(
                  constraints: const BoxConstraints(maxWidth: 170),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: _ludoPanel,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _ludoLine),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        seat.isMuted ? Icons.mic_off : Icons.mic,
                        size: 16,
                        color: seat.isMuted
                            ? const Color(0xFFB8A9D4)
                            : const Color(0xFF43A047),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          seat.displayName ?? 'Player',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFF4F1E8),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncNotice extends StatelessWidget {
  const _SyncNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    color: const Color(0xFF6B4D20),
    child: Row(
      children: [
        const Icon(Icons.sync_problem, color: Color(0xFFFFD27A), size: 17),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onBack});

  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: _ludoAccent, size: 48),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back to tables'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ),
    ),
  );
}
