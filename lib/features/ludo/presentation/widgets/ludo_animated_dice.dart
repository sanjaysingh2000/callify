import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_ludo/flutter_ludo.dart';

class LudoAnimatedDice extends StatefulWidget {
  const LudoAnimatedDice({
    super.key,
    required this.controller,
    required this.theme,
  });

  final LudoController controller;
  final LudoTheme theme;

  @override
  State<LudoAnimatedDice> createState() => _LudoAnimatedDiceState();
}

class _LudoAnimatedDiceState extends State<LudoAnimatedDice>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rollAnimation;
  late int _seenRollCount;

  @override
  void initState() {
    super.initState();
    _seenRollCount = widget.controller.state.rollCount;
    _rollAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
    widget.controller.addListener(_onGameChanged);
  }

  @override
  void didUpdateWidget(covariant LudoAnimatedDice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onGameChanged);
      _seenRollCount = widget.controller.state.rollCount;
      widget.controller.addListener(_onGameChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onGameChanged);
    _rollAnimation.dispose();
    super.dispose();
  }

  void _onGameChanged() {
    final rollCount = widget.controller.state.rollCount;
    if (rollCount != _seenRollCount) {
      _seenRollCount = rollCount;
      _rollAnimation.forward(from: 0);
    }
    if (mounted) setState(() {});
  }

  void _roll() {
    if (widget.controller.canRoll) widget.controller.rollDice();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _rollAnimation,
      builder: (context, _) {
        final state = widget.controller.state;
        final canRoll = widget.controller.canRoll && !state.isFinished;
        final rollProgress = Curves.easeOutCubic.transform(
          _rollAnimation.value,
        );
        final isRolling = _rollAnimation.isAnimating;
        final shownValue = state.diceValue ?? state.lastRoll;
        final faceValue = isRolling
            ? (_rollAnimation.value * 18).floor() % 6 + 1
            : shownValue;
        final rollerIndex = state.diceValue != null
            ? state.currentPlayerIndex
            : state.lastRollPlayerIndex;
        final faceColor =
            rollerIndex != null && rollerIndex < state.players.length
            ? state.players[rollerIndex].color
            : widget.theme.mutedTextColor;
        final rotation = isRolling
            ? rollProgress * math.pi * 2 +
                  math.sin(rollProgress * math.pi * 8) * 0.12
            : 0.0;
        final scale = isRolling
            ? 1 + math.sin(rollProgress * math.pi) * 0.2
            : 1.0;
        final buttonLabel = state.isFinished
            ? 'Game over'
            : canRoll
            ? 'Roll dice'
            : state.phase == LudoTurnPhase.awaitingPieceSelection
            ? 'Choose a piece'
            : 'Wait for turn';

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: widget.theme.panelColor,
            border: Border(top: BorderSide(color: widget.theme.dividerColor)),
          ),
          child: Row(
            children: [
              Semantics(
                label: faceValue == null ? 'Dice' : 'Dice showing $faceValue',
                child: GestureDetector(
                  onTap: canRoll ? _roll : null,
                  child: Transform.rotate(
                    angle: rotation,
                    child: Transform.scale(
                      scale: scale,
                      child: LudoDiceFace(
                        key: const ValueKey('ludo-dice-face'),
                        value: faceValue,
                        color: faceColor,
                        size: 58,
                        dimmed: shownValue == null && !isRolling,
                        backgroundColor: const Color(0xFFF9F7EE),
                        emptyColor: widget.theme.dividerColor,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      canRoll ? 'YOUR ROLL' : 'DICE',
                      style: TextStyle(
                        color: widget.theme.mutedTextColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      canRoll
                          ? 'Tap to roll'
                          : state.phase == LudoTurnPhase.awaitingPieceSelection
                          ? 'Move the highlighted token'
                          : 'Watch the active player',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.theme.textColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: canRoll ? _roll : null,
                icon: const Icon(Icons.casino_rounded, size: 19),
                label: Text(buttonLabel),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      state.players[state.currentPlayerIndex].color,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: widget.theme.dividerColor,
                  disabledForegroundColor: widget.theme.mutedTextColor,
                  minimumSize: const Size(144, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
