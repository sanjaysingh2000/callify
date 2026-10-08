import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/panel_participant.dart';
import '../controllers/panel_room_controller.dart';
import '../widgets/mic_request_sheet.dart';
import '../widgets/participant_tile.dart';

/// Main panel room screen — speakers grid, audience list, and controls.
class PanelRoomPage extends StatefulWidget {
  const PanelRoomPage({
    super.key,
    required this.panelId,
    required this.displayName,
    required this.isHost,
  });

  final String panelId;
  final String displayName;
  final bool isHost;

  @override
  State<PanelRoomPage> createState() => _PanelRoomPageState();
}

class _PanelRoomPageState extends State<PanelRoomPage> {
  late final PanelRoomController _controller;
  bool _hasNavigatedAway = false;
  bool _allowPop = false;
  bool _isHandlingBack = false;
  int _lastMicRequestEventVersion = 0;

  @override
  void initState() {
    super.initState();
    _controller = PanelRoomController();
    _controller.addListener(_onControllerChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.isHost) {
        _controller.createAndJoinPanel(widget.panelId, widget.displayName);
      } else {
        _controller.joinPanel(widget.panelId, widget.displayName);
      }
    });
  }

  void _onControllerChanged() {
    if (_hasNavigatedAway) return;

    if (_controller.wasKicked) {
      _hasNavigatedAway = true;
      if (mounted) {
        setState(() => _allowPop = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You were removed from the panel'),
            backgroundColor: Colors.red,
          ),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
      return;
    } else if (_controller.panelEnded) {
      _hasNavigatedAway = true;
      if (mounted) {
        setState(() => _allowPop = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Panel has ended'),
            backgroundColor: Color(0xFF0E7490),
          ),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
      return;
    }

    if (_controller.micRequestEventVersion > _lastMicRequestEventVersion) {
      _lastMicRequestEventVersion = _controller.micRequestEventVersion;
      final notice = _controller.latestMicRequestNotice;
      if (mounted && notice != null) {
        final messenger = ScaffoldMessenger.of(context);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(notice),
              backgroundColor: const Color(0xFF173042),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'VIEW',
                textColor: const Color(0xFF67E8F9),
                onPressed: () =>
                    MicRequestSheet.show(context, controller: _controller),
              ),
            ),
          );
      }
    }
  }

  Future<void> _leaveFromBack() async {
    if (_isHandlingBack || _controller.isLeaving) return;
    _isHandlingBack = true;
    _hasNavigatedAway = true;
    await _controller.leaveWithoutEnding();
    if (!mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    // If we haven't explicitly left (via kicked/ended/button), disconnect
    // quietly. Host keeps their Firestore doc so they can rejoin.
    // Non-host removes their participant doc.
    if (!_hasNavigatedAway) {
      _controller.leaveWithoutEnding();
    }
    _controller.dispose();
    super.dispose();
  }

  void _showParticipantActions(PanelParticipant participant) {
    final myRole = _controller.myRole;
    if (myRole == null) return;
    if (participant.userId == _controller.myParticipant?.userId) return;

    final actions = <_ActionItem>[];

    // Host actions.
    if (myRole == PanelRole.host) {
      if (participant.role != PanelRole.host) {
        if (participant.role != PanelRole.coHost) {
          actions.add(
            _ActionItem(
              icon: Icons.star,
              label: 'Make Co-host',
              color: const Color(0xFF8B5CF6),
              onTap: () => _controller.promoteToCoHost(participant.userId),
            ),
          );
        }
        if (participant.role == PanelRole.audience) {
          actions.add(
            _ActionItem(
              icon: Icons.mic,
              label: 'Make Speaker',
              color: const Color(0xFF10B981),
              onTap: () => _controller.promoteToSpeaker(participant.userId),
            ),
          );
        }
        if (participant.role != PanelRole.audience) {
          actions.add(
            _ActionItem(
              icon: Icons.arrow_downward,
              label: 'Move to Audience',
              color: Colors.orange,
              onTap: () => _controller.demoteToAudience(participant.userId),
            ),
          );
        }
        if (participant.canSpeak && !participant.isMuted) {
          actions.add(
            _ActionItem(
              icon: Icons.mic_off,
              label: 'Mute',
              color: Colors.amber,
              onTap: () => _controller.muteUser(participant.userId),
            ),
          );
        }
        actions.add(
          _ActionItem(
            icon: Icons.person_remove,
            label: 'Kick',
            color: Colors.red,
            onTap: () => _controller.kickUser(participant.userId),
          ),
        );
      }
    }
    // Co-host actions.
    else if (myRole == PanelRole.coHost) {
      if (participant.role == PanelRole.audience) {
        actions.add(
          _ActionItem(
            icon: Icons.mic,
            label: 'Make Speaker',
            color: const Color(0xFF10B981),
            onTap: () => _controller.promoteToSpeaker(participant.userId),
          ),
        );
      }
      if (participant.role == PanelRole.speaker) {
        actions.add(
          _ActionItem(
            icon: Icons.arrow_downward,
            label: 'Move to Audience',
            color: Colors.orange,
            onTap: () => _controller.demoteToAudience(participant.userId),
          ),
        );
        if (!participant.isMuted) {
          actions.add(
            _ActionItem(
              icon: Icons.mic_off,
              label: 'Mute',
              color: Colors.amber,
              onTap: () => _controller.muteUser(participant.userId),
            ),
          );
        }
      }
    }

    if (actions.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              participant.displayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            ...actions.map(
              (a) => ListTile(
                leading: Icon(a.icon, color: a.color),
                title: Text(
                  a.label,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  a.onTap();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Consumer<PanelRoomController>(
        builder: (context, ctrl, _) {
          return PopScope<void>(
            canPop: _allowPop,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _leaveFromBack();
            },
            child: Stack(
              children: [
                Scaffold(
                  backgroundColor: const Color(0xFF0A1628),
                  body: SafeArea(
                    child: ctrl.isConnecting || ctrl.isJoining
                        ? _buildLoading()
                        : ctrl.errorMessage != null
                        ? _buildError(ctrl)
                        : Column(
                            children: [
                              _buildTopBar(ctrl),
                              Expanded(child: _buildContent(ctrl)),
                              _buildBottomBar(ctrl),
                            ],
                          ),
                  ),
                ),
                if (ctrl.isLeaving && !ctrl.panelEnded && !ctrl.wasKicked)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: SafeArea(
                      child: IgnorePointer(
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B).withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.amber.withValues(alpha: 0.4),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.amber.withValues(alpha: 0.12),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.amber,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Leaving panel…',
                                    style: TextStyle(
                                      color: Colors.amber,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Color(0xFF06B6D4)),
          SizedBox(height: 16),
          Text(
            'Joining panel...',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildError(PanelRoomController ctrl) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withValues(alpha: 0.15),
              ),
              child: Icon(
                Icons.error_outline,
                size: 40,
                color: Colors.red.shade300,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              ctrl.errorMessage ?? 'Something went wrong',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Go Back'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0E7490),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Top bar
  // ---------------------------------------------------------------------------

  Widget _buildTopBar(PanelRoomController ctrl) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: ctrl.isLeaving || ctrl.isJoining
                    ? null
                    : _leaveFromBack,
                tooltip: 'Back to panels',
                icon: const Icon(Icons.arrow_back_rounded),
                color: Colors.white70,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ctrl.panel?.title ?? 'Panel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'by ${ctrl.panel?.hostDisplayName.isNotEmpty == true ? ctrl.panel!.hostDisplayName : 'Panel host'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.58),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if ((ctrl.myRole == PanelRole.host ||
                      ctrl.myRole == PanelRole.coHost) &&
                  ctrl.micRequests.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () =>
                        MicRequestSheet.show(context, controller: ctrl),
                    child: Stack(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.front_hand,
                            color: Colors.amber,
                            size: 20,
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.red,
                            ),
                            child: Center(
                              child: Text(
                                '${ctrl.micRequests.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              _buildLeaveButton(ctrl),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'LIVE · ${ctrl.participants.length} members',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.schedule_rounded,
                size: 14,
                color: ctrl.isNearTimeLimit
                    ? const Color(0xFFFBBF24)
                    : const Color(0xFF67E8F9),
              ),
              const SizedBox(width: 4),
              Semantics(
                label:
                    'Panel time remaining ${_formatPanelTime(ctrl.remainingDuration)}',
                child: Text(
                  _formatPanelTime(ctrl.remainingDuration),
                  style: TextStyle(
                    color: ctrl.isNearTimeLimit
                        ? const Color(0xFFFBBF24)
                        : Colors.white.withValues(alpha: 0.72),
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatPanelTime(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildLeaveButton(PanelRoomController ctrl) {
    final isHost = ctrl.myRole == PanelRole.host;
    return GestureDetector(
      onTap: () async {
        if (ctrl.isLeaving || ctrl.isJoining) return;
        if (isHost) {
          // Confirm before ending panel.
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'End Panel?',
                style: TextStyle(color: Colors.white),
              ),
              content: const Text(
                'This will end the panel for all participants.',
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('End Panel'),
                ),
              ],
            ),
          );
          if (confirmed != true || !mounted) return;
          _hasNavigatedAway = true;
          await ctrl.endOrLeavePanel();
          if (mounted) {
            setState(() => _allowPop = true);
            await WidgetsBinding.instance.endOfFrame;
            if (mounted) Navigator.of(context).pop();
          }
        } else {
          _hasNavigatedAway = true;
          await ctrl.endOrLeavePanel();
          if (mounted) {
            setState(() => _allowPop = true);
            await WidgetsBinding.instance.endOfFrame;
            if (mounted) Navigator.of(context).pop();
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: (isHost ? Colors.red : Colors.white.withValues(alpha: 0.1)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          isHost ? 'End Panel' : 'Leave',
          style: TextStyle(
            color: isHost ? Colors.white : Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Content — Speakers + Audience
  // ---------------------------------------------------------------------------

  Widget _buildContent(PanelRoomController ctrl) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Speakers section.
          _buildSectionHeader('Speakers', ctrl.speakers.length),
          const SizedBox(height: 12),
          if (ctrl.speakers.isEmpty)
            _buildEmptySection('No speakers yet')
          else
            Wrap(
              spacing: 12,
              runSpacing: 16,
              children: ctrl.speakers
                  .map(
                    (p) => ParticipantTile(
                      participant: p,
                      onTap: () => _showParticipantActions(p),
                    ),
                  )
                  .toList(),
            ),

          const SizedBox(height: 28),

          // Audience section.
          _buildSectionHeader('Audience', ctrl.audienceMembers.length),
          const SizedBox(height: 12),
          if (ctrl.audienceMembers.isEmpty)
            _buildEmptySection('No audience yet')
          else
            Wrap(
              spacing: 8,
              runSpacing: 12,
              children: ctrl.audienceMembers
                  .map(
                    (p) => ParticipantTile(
                      participant: p,
                      compact: true,
                      onTap: () => _showParticipantActions(p),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptySection(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.3),
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Bottom bar
  // ---------------------------------------------------------------------------

  Widget _buildBottomBar(PanelRoomController ctrl) {
    final myRole = ctrl.myRole;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Mic toggle (speakers only).
          if (myRole != null &&
              (myRole == PanelRole.host ||
                  myRole == PanelRole.coHost ||
                  myRole == PanelRole.speaker))
            _BottomButton(
              icon: ctrl.isMicEnabled ? Icons.mic : Icons.mic_off,
              label: ctrl.isMicEnabled ? 'Mute' : 'Unmute',
              color: ctrl.isMicEnabled
                  ? const Color(0xFF10B981)
                  : Colors.red.shade400,
              onTap: ctrl.toggleMic,
            ),

          // Request to speak (audience only).
          if (myRole == PanelRole.audience) ...[
            if (ctrl.myParticipant?.micRequested == true)
              _BottomButton(
                icon: Icons.hourglass_top,
                label: 'Requested',
                color: Colors.amber,
                onTap: null,
              )
            else
              _BottomButton(
                icon: Icons.front_hand,
                label: 'Request Mic',
                color: Colors.amber,
                onTap: ctrl.requestMic,
              ),
          ],

          const SizedBox(width: 16),

          // Speaker toggle.
          _BottomButton(
            icon: ctrl.isSpeakerOn ? Icons.volume_up : Icons.hearing,
            label: ctrl.isSpeakerOn ? 'Speaker' : 'Earpiece',
            color: const Color(0xFF06B6D4),
            onTap: ctrl.toggleSpeaker,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Private widgets
// =============================================================================

class _ActionItem {
  const _ActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

class _BottomButton extends StatelessWidget {
  const _BottomButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (isDisabled ? Colors.grey : color).withValues(alpha: 0.15),
            ),
            child: Icon(
              icon,
              color: isDisabled ? Colors.grey : color,
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isDisabled
                  ? Colors.grey
                  : Colors.white.withValues(alpha: 0.6),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
