import 'package:flutter/material.dart';

/// Wraps an avatar and shows a pulsing ring while [isSpeaking] is true.
class SpeakingRing extends StatefulWidget {
  const SpeakingRing({
    super.key,
    required this.isSpeaking,
    required this.child,
    this.color = const Color(0xFF10B981),
  });

  final bool isSpeaking;
  final Widget child;
  final Color color;

  @override
  State<SpeakingRing> createState() => _SpeakingRingState();
}

class _SpeakingRingState extends State<SpeakingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isSpeaking) _anim.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant SpeakingRing old) {
    super.didUpdateWidget(old);
    if (widget.isSpeaking && !_anim.isAnimating) {
      _anim.repeat(reverse: true);
    } else if (!widget.isSpeaking && _anim.isAnimating) {
      _anim.stop();
      _anim.value = 0;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      child: widget.child,
      builder: (context, child) {
        final t = widget.isSpeaking ? _anim.value : 0.0;
        return Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.color.withValues(
                alpha: widget.isSpeaking ? 0.5 + 0.5 * t : 0,
              ),
              width: 2.5,
            ),
            boxShadow: widget.isSpeaking
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.35 * t),
                      blurRadius: 6 + 10 * t,
                      spreadRadius: 1 + 3 * t,
                    ),
                  ]
                : const [],
          ),
          child: child,
        );
      },
    );
  }
}
