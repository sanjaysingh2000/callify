import 'package:flutter/material.dart';

import '../../domain/entities/panel_participant.dart';
import '../controllers/panel_room_controller.dart';

/// Bottom sheet showing pending mic requests for the host/co-host to approve or deny.
class MicRequestSheet extends StatefulWidget {
  const MicRequestSheet({super.key, required this.controller});

  final PanelRoomController controller;

  /// Shows this sheet as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required PanelRoomController controller,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF111C2D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => MicRequestSheet(controller: controller),
    );
  }

  @override
  State<MicRequestSheet> createState() => _MicRequestSheetState();
}

class _MicRequestSheetState extends State<MicRequestSheet> {
  bool _isClosing = false;
  bool _closeScheduled = false;

  Future<void> _decide(
    String userId,
    Future<void> Function(String userId) action,
  ) async {
    if (_isClosing) return;
    _isClosing = true;
    try {
      await action(userId);
    } finally {
      _popIfCurrent();
    }
  }

  void _popIfCurrent() {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final requests = widget.controller.micRequests;
        if (requests.isEmpty && !_isClosing && !_closeScheduled) {
          _closeScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _closeScheduled = false;
            if (!mounted || widget.controller.micRequests.isNotEmpty) return;
            _isClosing = true;
            _popIfCurrent();
          });
        }

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF164E63),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.front_hand_rounded,
                        color: Color(0xFF67E8F9),
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Requests to speak',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${requests.length} pending',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.58),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (requests.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    child: Center(
                      child: Text(
                        'All requests have been handled',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.64),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.55,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: requests.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      itemBuilder: (context, index) => _RequestRow(
                        participant: requests[index],
                        onApprove: () => _decide(
                          requests[index].userId,
                          widget.controller.approveMicRequest,
                        ),
                        onDeny: () => _decide(
                          requests[index].userId,
                          widget.controller.denyMicRequest,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.participant,
    required this.onApprove,
    required this.onDeny,
  });

  final PanelParticipant participant;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    final initial = participant.displayName.isEmpty
        ? '?'
        : participant.displayName[0].toUpperCase();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: const Color(0xFF26384B),
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  participant.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Wants to speak',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.56),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDeny,
            tooltip: 'Deny request',
            icon: const Icon(Icons.close_rounded),
            color: const Color(0xFFFCA5A5),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF3B202A),
            ),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            onPressed: onApprove,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Allow'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0E7490),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
    );
  }
}
