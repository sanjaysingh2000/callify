import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ludo/flutter_ludo.dart';

class LudoFlameBoard extends StatefulWidget {
  const LudoFlameBoard({
    super.key,
    required this.controller,
    required this.theme,
    required this.playerIndex,
  });

  final LudoController controller;
  final LudoTheme theme;
  final int playerIndex;

  @override
  State<LudoFlameBoard> createState() => _LudoFlameBoardState();
}

class _LudoFlameBoardState extends State<LudoFlameBoard> {
  late _LudoFlameGame _game;

  @override
  void initState() {
    super.initState();
    _game = _LudoFlameGame(widget.controller, widget.theme, widget.playerIndex);
  }

  @override
  void didUpdateWidget(covariant LudoFlameBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.theme != widget.theme ||
        oldWidget.playerIndex != widget.playerIndex) {
      _game.releaseController();
      _game = _LudoFlameGame(
        widget.controller,
        widget.theme,
        widget.playerIndex,
      );
    }
  }

  @override
  void dispose() {
    _game.releaseController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GameWidget<_LudoFlameGame>(game: _game);
}

class _LudoFlameGame extends FlameGame with TapCallbacks {
  _LudoFlameGame(this.controller, this.theme, this.playerIndex)
    : _state = controller.state {
    controller.addListener(_syncState);
  }

  final LudoController controller;
  final LudoTheme theme;
  final int playerIndex;
  LudoGameState _state;
  LudoPiece? _animatingPiece;
  final Map<int, _PieceMotion> _motions = {};
  ui.Picture? _boardPicture;
  double _elapsed = 0;
  bool _detached = false;

  int get _quarterTurnsClockwise => (2 - playerIndex + 4) % 4;

  void releaseController() {
    if (_detached) return;
    _detached = true;
    controller.removeListener(_syncState);
    _boardPicture?.dispose();
    _boardPicture = null;
  }

  void _syncState() {
    final nextState = controller.state;
    final nextAnimatingPiece = controller.animatingPiece;
    final previousState = _state;

    if (nextAnimatingPiece != null) {
      final from = _visualCenter(
        nextAnimatingPiece.id,
        previousState,
        _animatingPiece,
      );
      final to = _pieceCenter(nextAnimatingPiece);
      if (from != to) {
        _motions[nextAnimatingPiece.id] = _PieceMotion(
          from: from,
          to: to,
          duration: math.max(
            0.12,
            controller.stepAnimationDuration.inMilliseconds / 1000,
          ),
        );
      }
    } else {
      for (final piece in nextState.pieces) {
        final oldPiece = previousState.pieceById(piece.id);
        if (oldPiece.trackPosition == piece.trackPosition) continue;
        if (_animatingPiece?.id == piece.id &&
            nextState.lastMovedPiece?.id == piece.id) {
          continue;
        }
        _motions[piece.id] = _PieceMotion(
          from: _visualCenter(piece.id, previousState, _animatingPiece),
          to: _pieceCenter(piece),
          duration: 0.24,
        );
      }
    }

    _state = nextState;
    _animatingPiece = nextAnimatingPiece;
  }

  Offset _visualCenter(
    int pieceId,
    LudoGameState state, [
    LudoPiece? animatingPiece,
  ]) {
    final motion = _motions[pieceId];
    if (motion != null) return motion.position;
    if (animatingPiece?.id == pieceId) return _pieceCenter(animatingPiece!);
    return _pieceCenter(state.pieceById(pieceId));
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    for (final motion in _motions.values) {
      motion.elapsed += dt;
    }
    _motions.removeWhere((_, motion) => motion.isComplete);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final width = canvasSize.x;
    final height = canvasSize.y;
    final side = math.min(width, height);
    if (side <= 0) return;

    final left = (width - side) / 2;
    final top = (height - side) / 2;
    canvas.drawRect(
      Offset.zero & Size(width, height),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(width, height),
          const [Color(0xFF0B2026), Color(0xFF173A3D)],
        ),
    );

    canvas.save();
    canvas.translate(left, top);
    canvas.scale(side / 15);
    canvas.translate(7.5, 7.5);
    canvas.rotate(_quarterTurnsClockwise * math.pi / 2);
    canvas.translate(-7.5, -7.5);
    _boardPicture ??= _createBoardPicture();
    canvas.drawPicture(_boardPicture!);
    _paintPieces(canvas);
    canvas.restore();
  }

  ui.Picture _createBoardPicture() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _paintBoard(canvas);
    return recorder.endRecording();
  }

  void _paintBoard(Canvas canvas) {
    final boardRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, 15, 15),
      const Radius.circular(0.32),
    );
    canvas.drawRRect(boardRect, Paint()..color = theme.boardBackgroundColor);
    canvas.drawRRect(
      boardRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.09,
    );

    _paintHomeBases(canvas);
    _paintSharedPath(canvas);
    _paintHomeStretches(canvas);
    _paintCenter(canvas);
  }

  void _paintHomeBases(Canvas canvas) {
    for (var playerIndex = 0; playerIndex < 4; playerIndex++) {
      final origin = kHomeBaseOrigins[playerIndex];
      final color = playerIndex < _state.players.length
          ? _state.players[playerIndex].color
          : const Color(0xFF78909C);
      final outer = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          origin[1].toDouble() + 0.12,
          origin[0].toDouble() + 0.12,
          5.76,
          5.76,
        ),
        const Radius.circular(0.38),
      );
      canvas.drawRRect(
        outer,
        Paint()
          ..shader = ui.Gradient.linear(
            outer.outerRect.topLeft,
            outer.outerRect.bottomRight,
            [color.withValues(alpha: 0.48), color.withValues(alpha: 0.16)],
          ),
      );
      canvas.drawRRect(
        outer,
        Paint()
          ..color = color.withValues(alpha: 0.72)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.07,
      );

      if (playerIndex >= _state.players.length) continue;
      final yard = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          origin[1].toDouble() + 1.1,
          origin[0].toDouble() + 1.1,
          3.8,
          3.8,
        ),
        const Radius.circular(0.32),
      );
      canvas.drawRRect(yard, Paint()..color = const Color(0xFFEAF3EF));
      canvas.drawRRect(
        yard,
        Paint()
          ..color = color.withValues(alpha: 0.64)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.045,
      );

      for (final slot in kHomeYardSlots) {
        final center = Offset(
          origin[1] + slot[1] + 0.5,
          origin[0] + slot[0] + 0.5,
        );
        canvas.drawCircle(
          center,
          0.38,
          Paint()..color = color.withValues(alpha: 0.13),
        );
        canvas.drawCircle(
          center,
          0.38,
          Paint()
            ..color = color.withValues(alpha: 0.52)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.035,
        );
      }
    }
  }

  void _paintSharedPath(Canvas canvas) {
    for (var index = 0; index < kPathCells.length; index++) {
      final cell = kPathCells[index];
      final rect = Rect.fromLTWH(
        cell[1].toDouble(),
        cell[0].toDouble(),
        1.0,
        1.0,
      );
      final safe = kSafeIndices.contains(index);
      _paintCell(
        canvas,
        rect,
        safe ? theme.safeCellColor : theme.pathCellColor,
      );
      if (safe) _paintStar(canvas, rect.center, 0.24, theme.starIconColor);
    }
  }

  void _paintHomeStretches(Canvas canvas) {
    for (
      var playerIndex = 0;
      playerIndex < _state.players.length;
      playerIndex++
    ) {
      final color = _state.players[playerIndex].color;
      for (
        var index = 0;
        index < kHomeStretchCells[playerIndex].length;
        index++
      ) {
        final cell = kHomeStretchCells[playerIndex][index];
        final rect = Rect.fromLTWH(
          cell[1].toDouble(),
          cell[0].toDouble(),
          1.0,
          1.0,
        );
        final shade = 0.42 + index * 0.075;
        _paintCell(canvas, rect, color.withValues(alpha: shade));
      }
    }
  }

  void _paintCenter(Canvas canvas) {
    final center = RRect.fromRectAndRadius(
      const Rect.fromLTWH(6.0, 6.0, 3.0, 3.0),
      const Radius.circular(0.14),
    );
    canvas.drawRRect(center, Paint()..color = theme.centerCellColor);
    final square = center.outerRect;
    final point = square.center;
    final triangleCorners = [
      [square.topLeft, square.topRight],
      [square.topRight, square.bottomRight],
      [square.bottomRight, square.bottomLeft],
      [square.bottomLeft, square.topLeft],
    ];
    const trianglePlayers = [1, 2, 3, 0];
    for (var index = 0; index < triangleCorners.length; index++) {
      final playerIndex = trianglePlayers[index];
      final color = playerIndex < _state.players.length
          ? _state.players[playerIndex].color
          : const Color(0xFF90A4AE);
      final corners = triangleCorners[index];
      final path = Path()
        ..moveTo(point.dx, point.dy)
        ..lineTo(corners[0].dx, corners[0].dy)
        ..lineTo(corners[1].dx, corners[1].dy)
        ..close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.78));
    }
    _paintStar(canvas, point, 0.43, const Color(0xFFFFF3C6));
    canvas.drawRRect(
      center,
      Paint()
        ..color = theme.gridLineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.055,
    );
  }

  void _paintCell(Canvas canvas, Rect rect, Color fill) {
    canvas.drawRect(rect, Paint()..color = fill);
    canvas.drawRect(
      rect,
      Paint()
        ..color = theme.gridLineColor.withValues(alpha: 0.72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.035,
    );
  }

  void _paintStar(Canvas canvas, Offset center, double radius, Color color) {
    final path = Path();
    for (var index = 0; index < 10; index++) {
      final pointRadius = index.isEven ? radius : radius * 0.44;
      final angle = index * math.pi / 5 - math.pi / 2;
      final point = Offset(
        center.dx + pointRadius * math.cos(angle),
        center.dy + pointRadius * math.sin(angle),
      );
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _paintPieces(Canvas canvas) {
    final pieces = [
      ..._visiblePieces.where(
        (piece) => piece.playerIndex != _state.currentPlayerIndex,
      ),
      ..._visiblePieces.where(
        (piece) => piece.playerIndex == _state.currentPlayerIndex,
      ),
    ];
    final legalIds = controller.canSelectPiece
        ? _state.legalMoves.map((move) => move.pieceId).toSet()
        : const <int>{};

    for (final piece in pieces) {
      final radius = 0.34;
      final center = _pieceCenter(piece) + _stackOffset(piece, radius);
      final color = _state.players[piece.playerIndex].color;
      final isLegal = legalIds.contains(piece.id);
      final isLastMoved =
          _state.lastMovedPiece?.id == piece.id && _animatingPiece == null;
      _paintPiece(
        canvas,
        center,
        radius,
        color,
        isLegal: isLegal,
        isLastMoved: isLastMoved,
        label: _isStacked(piece) ? '${piece.id % 4 + 1}' : null,
      );
    }
  }

  List<LudoPiece> get _visiblePieces {
    final animatingPiece = _animatingPiece;
    if (animatingPiece == null) return _state.pieces;
    return [
      for (final piece in _state.pieces)
        piece.id == animatingPiece.id ? animatingPiece : piece,
    ];
  }

  void _paintPiece(
    Canvas canvas,
    Offset center,
    double radius,
    Color color, {
    required bool isLegal,
    required bool isLastMoved,
    required String? label,
  }) {
    if (isLegal) {
      final pulse = (math.sin(_elapsed * 5) + 1) / 2;
      canvas.drawCircle(
        center,
        radius * (1.34 + pulse * 0.12),
        Paint()
          ..color = const Color(
            0xFFFFE082,
          ).withValues(alpha: 0.15 + pulse * 0.1),
      );
      canvas.drawCircle(
        center,
        radius * (1.18 + pulse * 0.08),
        Paint()
          ..color = const Color(0xFFFFD166).withValues(alpha: 0.74)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.045,
      );
    }

    final circlePath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.drawShadow(circlePath, const Color(0xAA061417), 0.08, true);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          center.translate(-radius * 0.3, -radius * 0.34),
          radius * 1.6,
          [
            Color.lerp(color, Colors.white, 0.44)!,
            color,
            Color.lerp(color, Colors.black, 0.28)!,
          ],
          const [0, 0.58, 1],
        ),
    );
    canvas.drawCircle(
      center,
      radius * 0.88,
      Paint()
        ..color = isLastMoved
            ? theme.lastMovedColor
            : Colors.white.withValues(alpha: 0.86)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isLastMoved ? 0.07 : 0.045,
    );
    canvas.drawCircle(
      center.translate(-radius * 0.28, -radius * 0.3),
      radius * 0.15,
      Paint()..color = Colors.white.withValues(alpha: 0.76),
    );
    if (label != null) {
      final text = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * 0.72,
            fontWeight: FontWeight.w800,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 2)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(
        canvas,
        Offset(center.dx - text.width / 2, center.dy - text.height / 2),
      );
    }
  }

  Offset _pieceCenter(LudoPiece piece) {
    if (piece.isHome) {
      final origin = kHomeBaseOrigins[piece.playerIndex];
      final slot = kHomeYardSlots[piece.id % 4];
      return Offset(origin[1] + slot[1] + 0.5, origin[0] + slot[0] + 0.5);
    }
    if (piece.isFinished) {
      const offsets = [
        Offset(-0.55, -0.55),
        Offset(0.55, -0.55),
        Offset(0.55, 0.55),
        Offset(-0.55, 0.55),
      ];
      final fan = (piece.id % 4 - 1.5) * 0.12;
      final offset = offsets[piece.playerIndex];
      return Offset(7 + offset.dx + fan, 7 + offset.dy + fan);
    }
    final cell = gridCellFor(piece.playerIndex, piece.trackPosition)!;
    return Offset(cell[1] + 0.5, cell[0] + 0.5);
  }

  Offset _stackOffset(LudoPiece piece, double radius) {
    final peers = _peers(piece);
    if (peers.length < 2) return Offset.zero;
    final index = peers.indexWhere((peer) => peer.id == piece.id);
    final angle = index / peers.length * 2 * math.pi + math.pi / 4;
    return Offset(
      radius * 0.46 * math.cos(angle),
      radius * 0.46 * math.sin(angle),
    );
  }

  bool _isStacked(LudoPiece piece) => _peers(piece).length > 1;

  List<LudoPiece> _peers(LudoPiece piece) {
    if (piece.isHome || piece.isFinished) return [piece];
    final cell = gridCellFor(piece.playerIndex, piece.trackPosition)!;
    return _visiblePieces.where((other) {
      if (other.isHome || other.isFinished) return false;
      final otherCell = gridCellFor(other.playerIndex, other.trackPosition)!;
      return cell[0] == otherCell[0] && cell[1] == otherCell[1];
    }).toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (!controller.canSelectPiece) return;

    final width = canvasSize.x;
    final height = canvasSize.y;
    final side = math.min(width, height);
    if (side <= 0) return;
    final cellSize = side / 15;
    final visiblePoint = Offset(
      (event.canvasPosition.x - (width - side) / 2) / cellSize,
      (event.canvasPosition.y - (height - side) / 2) / cellSize,
    );
    final relative = visiblePoint - const Offset(7.5, 7.5);
    final inverseAngle = -_quarterTurnsClockwise * math.pi / 2;
    final point =
        Offset(
          relative.dx * math.cos(inverseAngle) -
              relative.dy * math.sin(inverseAngle),
          relative.dx * math.sin(inverseAngle) +
              relative.dy * math.cos(inverseAngle),
        ) +
        const Offset(7.5, 7.5);
    final tappedPiece =
        _visiblePieces
            .map(
              (piece) => (
                piece: piece,
                center: _pieceCenter(piece) + _stackOffset(piece, 0.34),
              ),
            )
            .where((entry) => (entry.center - point).distance <= 0.48)
            .toList()
          ..sort((a, b) => b.piece.id.compareTo(a.piece.id));
    if (tappedPiece.isEmpty) return;

    final tapped = tappedPiece.first.piece;
    final legalPieces = _state.legalMoves
        .map((move) => _state.pieceById(move.pieceId))
        .where(
          (piece) =>
              piece.playerIndex == _state.currentPlayerIndex &&
              _sameCell(piece, tapped),
        )
        .toList();
    if (legalPieces.isEmpty) return;

    final selected = legalPieces.any((piece) => piece.id == tapped.id)
        ? tapped
        : legalPieces.first;
    unawaited(controller.selectPiece(selected.id).catchError((Object _) {}));
  }

  bool _sameCell(LudoPiece first, LudoPiece second) {
    if (first.isHome != second.isHome ||
        first.isFinished != second.isFinished) {
      return false;
    }
    if (first.isHome || first.isFinished) return first.id == second.id;
    return first.trackPosition == second.trackPosition &&
        first.playerIndex == second.playerIndex;
  }
}

class _PieceMotion {
  _PieceMotion({required this.from, required this.to, required this.duration});

  final Offset from;
  final Offset to;
  final double duration;
  double elapsed = 0;

  bool get isComplete => elapsed >= duration;

  Offset get position {
    final progress = (elapsed / duration).clamp(0.0, 1.0);
    final eased = Curves.easeInOutCubic.transform(progress);
    return Offset.lerp(from, to, eased)!;
  }
}
