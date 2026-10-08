import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/datasources/last_call_store.dart';
import '../../domain/entities/call_state.dart';
import '../controllers/call_controller.dart';

/// Full-screen call page that handles the entire flow:
/// searching → partner found → audio call → ended.
class CallPage extends StatefulWidget {
  const CallPage({super.key, this.lastCall});

  final LastCall? lastCall;

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> with TickerProviderStateMixin {
  late final CallController _controller;

  // Pulse animation for searching state.
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // Radar sweep animation for searching state.
  late final AnimationController _radarController;

  // Scale animation for partner found popup.
  late final AnimationController _matchPopupController;
  late final Animation<double> _matchScaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = CallController();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _matchPopupController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _matchScaleAnimation = CurvedAnimation(
      parent: _matchPopupController,
      curve: Curves.elasticOut,
    );

    // Listen for matched state to trigger popup animation.
    _controller.addListener(_onControllerChanged);

    // Start the random call flow.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final lastCall = widget.lastCall;
      if (lastCall == null) {
        _controller.startRandomCall();
      } else {
        _controller.reconnectToLastUser(
          partnerId: lastCall.partnerId,
          roomId: lastCall.roomId,
        );
      }
    });
  }

  void _onControllerChanged() {
    if (_controller.state == CallState.matched) {
      _matchPopupController.forward(from: 0);
    }
    // Auto-navigate to ended screen when partner leaves / disconnects.
    // The ended screen has a "Back to Home" button so we don't pop immediately.
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    // Only hangUp if the call isn't already ended (prevents double cleanup).
    if (_controller.state != CallState.ended &&
        _controller.state != CallState.idle &&
        _controller.state != CallState.error) {
      _controller.hangUp();
    }
    _controller.dispose();
    _pulseController.dispose();
    _radarController.dispose();
    _matchPopupController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Consumer<CallController>(
        builder: (context, controller, _) {
          return Scaffold(
            backgroundColor: const Color(0xFF0A1628),
            body: SafeArea(child: _buildBody(controller)),
          );
        },
      ),
    );
  }

  Widget _buildBody(CallController controller) {
    switch (controller.state) {
      case CallState.searching:
        return _buildSearchingScreen(controller);
      case CallState.matched:
        return _buildMatchedScreen(controller);
      case CallState.connecting:
        return _buildConnectingScreen(controller);
      case CallState.connected:
        return _buildConnectedScreen(controller);
      case CallState.ended:
        return _buildEndedScreen();
      case CallState.error:
        return _buildErrorScreen(controller);
      case CallState.idle:
        return const Center(
          child: CircularProgressIndicator(color: Color(0xFF06B6D4)),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Searching screen
  // ---------------------------------------------------------------------------

  Widget _buildSearchingScreen(CallController controller) {
    return Column(
      children: [
        _buildTopBar(null),
        const Spacer(),

        // Animated radar
        SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer rings
              ...List.generate(3, (i) {
                return AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (_, _) {
                    final size = 140.0 + (i * 40.0);
                    return Container(
                      width: size * (i == 0 ? _pulseAnimation.value : 1.0),
                      height: size * (i == 0 ? _pulseAnimation.value : 1.0),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(
                            0xFF06B6D4,
                          ).withValues(alpha: 0.3 - (i * 0.08)),
                          width: 1.5,
                        ),
                      ),
                    );
                  },
                );
              }),

              // Radar sweep
              AnimatedBuilder(
                animation: _radarController,
                builder: (_, child) {
                  return Transform.rotate(
                    angle: _radarController.value * 2 * pi,
                    child: child,
                  );
                },
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        const Color(0xFF06B6D4).withValues(alpha: 0.0),
                        const Color(0xFF06B6D4).withValues(alpha: 0.3),
                        const Color(0xFF06B6D4).withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.25, 0.5],
                    ),
                  ),
                ),
              ),

              // Center icon
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0E7490), Color(0xFF06B6D4)],
                  ),
                ),
                child: const Icon(
                  Icons.person_search,
                  size: 36,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        const Text(
          'Looking for a practice partner...',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: 12),

        Text(
          _formatDuration(controller.searchDuration),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 16,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),

        const Spacer(),

        // Cancel button
        Padding(
          padding: const EdgeInsets.only(bottom: 48),
          child: SizedBox(
            width: 180,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () async {
                await controller.cancelSearch();
                if (mounted) Navigator.of(context).pop();
              },
              icon: const Icon(Icons.close, size: 20),
              label: const Text('Cancel'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Partner found screen
  // ---------------------------------------------------------------------------

  Widget _buildMatchedScreen(CallController controller) {
    return Column(
      children: [
        _buildTopBar(null),
        const Spacer(),

        ScaleTransition(
          scale: _matchScaleAnimation,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Checkmark circle
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.4),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.people_alt_rounded,
                  size: 52,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Partner Found!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Connecting you now...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),

        const Spacer(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Connecting screen
  // ---------------------------------------------------------------------------

  Widget _buildConnectingScreen(CallController controller) {
    return Column(
      children: [
        _buildTopBar('Connecting...'),
        const Spacer(),
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (_, child) =>
              Transform.scale(scale: _pulseAnimation.value, child: child),
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF334155), Color(0xFF1E293B)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0E7490).withValues(alpha: 0.2),
                  blurRadius: 20,
                ),
              ],
            ),
            child: const Icon(Icons.phone, size: 48, color: Colors.white),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Establishing connection...',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 16,
          ),
        ),
        const Spacer(),
        _buildHangUpButton(controller),
        const SizedBox(height: 48),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Connected screen
  // ---------------------------------------------------------------------------

  Widget _buildConnectedScreen(CallController controller) {
    return Column(
      children: [
        _buildTopBar('Connected'),
        const Spacer(),

        // Avatar
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0E7490), Color(0xFF06B6D4)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0E7490).withValues(alpha: 0.4),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: const Icon(Icons.phone_in_talk, size: 56, color: Colors.white),
        ),

        const SizedBox(height: 24),

        const Text(
          'Practice English',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),

        const SizedBox(height: 8),

        // Duration
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: controller.isNearTimeLimit
                ? Colors.red.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: controller.isNearTimeLimit
                ? Border.all(color: Colors.red.withValues(alpha: 0.4))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatDuration(controller.callDuration),
                style: TextStyle(
                  color: controller.isNearTimeLimit
                      ? Colors.red.shade300
                      : Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '/ ${_formatDuration(CallController.maxCallDuration)}',
                style: TextStyle(
                  color: controller.isNearTimeLimit
                      ? Colors.red.shade300.withValues(alpha: 0.7)
                      : Colors.white.withValues(alpha: 0.4),
                  fontSize: 14,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),

        if (controller.isNearTimeLimit)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Call ends in ${_formatDuration(controller.remainingDuration)}',
              style: TextStyle(
                color: Colors.red.shade300,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

        const Spacer(),

        // Controls bar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ControlButton(
                icon: controller.isMuted ? Icons.mic_off : Icons.mic,
                label: controller.isMuted ? 'Unmute' : 'Mute',
                isActive: controller.isMuted,
                onTap: () => controller.toggleMute(),
              ),
              _ControlButton(
                icon: controller.isSpeakerOn ? Icons.volume_up : Icons.hearing,
                label: controller.isSpeakerOn ? 'Speaker' : 'Earpiece',
                isActive: controller.isSpeakerOn,
                onTap: () => controller.toggleSpeaker(),
              ),
              _ControlButton(
                icon: Icons.call_end,
                label: 'End',
                isDestructive: true,
                onTap: () async {
                  await controller.hangUp();
                  if (mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Ended screen
  // ---------------------------------------------------------------------------

  Widget _buildEndedScreen() {
    return Column(
      children: [
        _buildTopBar(null),
        const Spacer(),
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.08),
          ),
          child: const Icon(Icons.call_end, size: 44, color: Colors.white54),
        ),
        const SizedBox(height: 24),
        const Text(
          'Call Ended',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Great practice session!',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '15-minute limit per call',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 12,
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(bottom: 48),
          child: ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back to Home'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0E7490),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Error screen
  // ---------------------------------------------------------------------------

  Widget _buildErrorScreen(CallController controller) {
    return Column(
      children: [
        _buildTopBar(null),
        const Spacer(),
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red.withValues(alpha: 0.15),
          ),
          child: Icon(
            Icons.error_outline,
            size: 44,
            color: Colors.red.shade300,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Something went wrong',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (controller.errorMessage != null) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              controller.errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red.shade300, fontSize: 14),
            ),
          ),
        ],
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(bottom: 48),
          child: ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            label: const Text('Close'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Shared widgets
  // ---------------------------------------------------------------------------

  Widget _buildTopBar(String? statusText) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          IconButton(
            onPressed: () async {
              final state = _controller.state;
              // Skip hangUp on terminal states — already cleaned up.
              if (state != CallState.ended &&
                  state != CallState.error &&
                  state != CallState.idle) {
                await _controller.hangUp();
              }
              if (mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70),
          ),
          const Spacer(),
          if (statusText != null)
            Text(
              statusText,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          const Spacer(),
          const SizedBox(width: 48), // Balance the back button.
        ],
      ),
    );
  }

  Widget _buildHangUpButton(CallController controller) {
    return GestureDetector(
      onTap: () async {
        await controller.hangUp();
        if (mounted) Navigator.of(context).pop();
      },
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.red.shade600,
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.3),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(Icons.call_end, color: Colors.white, size: 28),
      ),
    );
  }
}

// =============================================================================
// Private widgets
// =============================================================================

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.isDestructive = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final bool isDestructive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bgColor = isDestructive
        ? Colors.red.shade600
        : isActive
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.white.withValues(alpha: 0.08);

    final iconColor = isDestructive
        ? Colors.white
        : isActive
        ? const Color(0xFF06B6D4)
        : Colors.white70;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              boxShadow: isDestructive
                  ? [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : [],
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: isDestructive ? Colors.red.shade300 : Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}