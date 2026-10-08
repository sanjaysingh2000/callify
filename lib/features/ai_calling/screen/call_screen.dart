import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_call/features/ai_calling/provider/ai_calling_provider.dart';

class AiCallScreen extends StatelessWidget {
  const AiCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AiCallProvider(),
      child: const _AiCallView(),
    );
  }
}

enum _Phase { standby, connecting, live }

class _Palette {
  static const bg = Color(0xFF070B14);
  static const surface = Color(0xFF0E1626);
  static const cyan = Color(0xFF22D3EE);
  static const amber = Color(0xFFFBBF24);
  static const green = Color(0xFF34D399);
  static const red = Color(0xFFF87171);
  static const muted = Color(0xFF64748B);
}

TextStyle _mono({
  double size = 12,
  FontWeight weight = FontWeight.w500,
  Color color = Colors.white,
  double spacing = 0,
}) {
  return TextStyle(
    fontFamily: 'monospace',
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: spacing,
  );
}

class _AiCallView extends StatefulWidget {
  const _AiCallView();

  @override
  State<_AiCallView> createState() => _AiCallViewState();
}

class _AiCallViewState extends State<_AiCallView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = context.watch<AiCallProvider>();
    final phase = call.isCalling
        ? _Phase.live
        : call.isConnecting
            ? _Phase.connecting
            : _Phase.standby;
    final accent = switch (phase) {
      _Phase.standby => _Palette.cyan,
      _Phase.connecting => _Palette.amber,
      _Phase.live => _Palette.green,
    };

    return Scaffold(
      backgroundColor: _Palette.bg,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                children: [
                  _header(phase, accent),
                  const Spacer(),
                  _orb(call, phase, accent),
                  const SizedBox(height: 28),
                  _status(call, phase, accent),
                  const Spacer(),
                  _readouts(call, phase, accent),
                  const SizedBox(height: 20),
                  _controls(call, phase, accent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Header ----------
  Widget _header(_Phase phase, Color accent) {
    final label = switch (phase) {
      _Phase.standby => 'STANDBY',
      _Phase.connecting => 'CONNECTING',
      _Phase.live => 'LIVE',
    };

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _Palette.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
          ),
          child: Icon(Icons.graphic_eq, color: accent, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Callify', style: _mono(size: 14, weight: FontWeight.w700, spacing: 2)),
              Text('AI English Trainer', style: _mono(size: 10, color: _Palette.muted, spacing: 2)),
            ],
          ),
        ),
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            final blink = phase == _Phase.standby
                ? 1.0
                : 0.4 + 0.6 * (0.5 + 0.5 * math.sin(_ctrl.value * math.pi * 4));
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: accent.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: blink),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(label, style: _mono(size: 11, weight: FontWeight.w700, color: accent, spacing: 1.5)),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ---------- Orb ----------
  Widget _orb(AiCallProvider call, _Phase phase, Color accent) {
    final m = call.secondsLeft ~/ 60;
    final s = (call.secondsLeft % 60).toString().padLeft(2, '0');

    final Widget center = switch (phase) {
      _Phase.standby => Icon(Icons.settings_voice, key: const ValueKey('s'), color: accent, size: 44),
      _Phase.connecting => SizedBox(
          key: const ValueKey('c'),
          width: 40,
          height: 40,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: accent),
        ),
      _Phase.live => Text('$m:$s', key: const ValueKey('l'), style: _mono(size: 30, weight: FontWeight.w700, color: accent)),
    };

    return SizedBox(
      width: 280,
      height: 280,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => CustomPaint(
              size: const Size(280, 280),
              painter: _OrbPainter(
                t: _ctrl.value,
                phase: phase,
                color: accent,
                progress: call.secondsLeft / 120,
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: center,
          ),
        ],
      ),
    );
  }

  // ---------- Status text ----------
  Widget _status(AiCallProvider call, _Phase phase, Color accent) {
    final (title, sub) = switch (phase) {
      _Phase.standby => ('SYSTEM READY', 'Start a 2 minute session with the AI assistant.'),
      _Phase.connecting => ('ESTABLISHING LINK', 'Connecting to the AI assistant. Please wait...'),
      _Phase.live => ('CHANNEL OPEN', 'Speak naturally. The session ends automatically.'),
    };

    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            title,
            key: ValueKey(title),
            style: _mono(size: 18, weight: FontWeight.w700, color: accent, spacing: 3),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          sub,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _Palette.muted, fontSize: 13, height: 1.4),
        ),
        if (call.errorMessage != null && phase == _Phase.standby) ...[
          const SizedBox(height: 10),
          Text(
            call.errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _Palette.red, fontSize: 12.5),
          ),
        ],
      ],
    );
  }

  // ---------- Readouts ----------
  Widget _readouts(AiCallProvider call, _Phase phase, Color accent) {
    final link = switch (phase) {
      _Phase.standby => 'IDLE',
      _Phase.connecting => 'SYNC',
      _Phase.live => 'ACTIVE',
    };
    final mic = phase != _Phase.live ? 'OFF' : (call.isMuted ? 'MUTED' : 'OPEN');

    return Row(
      children: [
        _readout('LIMIT', '02:00', Colors.white),
        const SizedBox(width: 10),
        _readout('LINK', link, accent),
        const SizedBox(width: 10),
        _readout('MIC', mic, call.isMuted ? _Palette.red : Colors.white),
      ],
    );
  }

  Widget _readout(String label, String value, Color valueColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: _Palette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: _mono(size: 10, color: _Palette.muted, spacing: 1.5)),
            const SizedBox(height: 4),
            Text(value, style: _mono(size: 14, weight: FontWeight.w700, color: valueColor)),
          ],
        ),
      ),
    );
  }

  // ---------- Controls ----------
  Widget _controls(AiCallProvider call, _Phase phase, Color accent) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    final textStyle = _mono(size: 14, weight: FontWeight.w700, spacing: 2);

    if (phase == _Phase.live) {
      return Row(
        children: [
          InkWell(
            onTap: call.toggleMute,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _Palette.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: (call.isMuted ? _Palette.red : Colors.white).withValues(alpha: 0.25),
                ),
              ),
              child: Icon(
                call.isMuted ? Icons.mic_off : Icons.mic,
                color: call.isMuted ? _Palette.red : Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: call.stopCall,
                icon: const Icon(Icons.call_end),
                label: Text('END CALL', style: textStyle),
                style: FilledButton.styleFrom(
                  backgroundColor: _Palette.red,
                  foregroundColor: _Palette.bg,
                  shape: shape,
                ),
              ),
            ),
          ),
        ],
      );
    }

    final connecting = phase == _Phase.connecting;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        onPressed: connecting ? null : call.startCall,
        icon: connecting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: _Palette.amber),
              )
            : const Icon(Icons.call),
        label: Text(connecting ? 'CONNECTING...' : 'START AI CALL', style: textStyle),
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: _Palette.bg,
          disabledBackgroundColor: _Palette.surface,
          disabledForegroundColor: _Palette.amber,
          shape: shape,
        ),
      ),
    );
  }
}

// ---------- Painters ----------
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    const step = 32.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.t,
    required this.phase,
    required this.color,
    required this.progress,
  });

  final double t;
  final _Phase phase;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;

    // concentric guide rings
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: 0.15);
    for (final f in [0.45, 0.65, 0.85]) {
      canvas.drawCircle(c, r * f, ring);
    }

    // tick marks
    final tick = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (int i = 0; i < 60; i++) {
      final a = i * math.pi / 30;
      final len = i % 5 == 0 ? 9.0 : 4.0;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * (r - len), c + dir * r, tick);
    }

    // expanding ripples (connecting + live)
    if (phase != _Phase.standby) {
      for (int i = 0; i < 3; i++) {
        final p = (t + i / 3) % 1.0;
        canvas.drawCircle(
          c,
          r * (0.3 + 0.55 * p),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = color.withValues(alpha: (1 - p) * 0.5),
        );
      }
    }

    // radar sweep while connecting
    if (phase == _Phase.connecting) {
      final rect = Rect.fromCircle(center: c, radius: r * 0.9);
      final sweep = Paint()
        ..shader = SweepGradient(
          colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.45)],
          transform: GradientRotation(t * math.pi * 2),
        ).createShader(rect);
      canvas.drawCircle(c, r * 0.9, sweep);
    }

    // remaining-time arc while live
    if (phase == _Phase.live) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * 0.95),
        -math.pi / 2,
        math.pi * 2 * progress.clamp(0.0, 1.0),
        false,
        arc,
      );
    }

    // core
    final breathe = 0.5 + 0.5 * math.sin(t * math.pi * 2);
    canvas.drawCircle(
      c,
      r * 0.3 + breathe * 4,
      Paint()
        ..color = color.withValues(alpha: 0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawCircle(c, r * 0.26, Paint()..color = _Palette.surface);
    canvas.drawCircle(
      c,
      r * 0.26,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: 0.8),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) => true;
}