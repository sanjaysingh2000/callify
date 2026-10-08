import 'package:flutter/material.dart';
import 'package:flutter_ludo/flutter_ludo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_call/features/ludo/presentation/pages/ludo_flame_board.dart';

void main() {
  for (var playerIndex = 0; playerIndex < 4; playerIndex++) {
    testWidgets(
      'player $playerIndex can tap a legal token with their home front-right',
      (tester) async {
        final game = LudoController(
          players: const [
            LudoPlayer(name: 'Red', color: Color(0xFFE24B4B)),
            LudoPlayer(name: 'Blue', color: Color(0xFF3B82C4)),
          ],
          diceRoller: () => 6,
          stepAnimationDuration: Duration.zero,
          autoMoveSingleChoice: false,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox.square(
                  dimension: 300,
                  child: LudoFlameBoard(
                    controller: game,
                    theme: LudoTheme.dark,
                    playerIndex: playerIndex,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));

        game.rollDice();
        await tester.pump();
        final boardOrigin = tester.getTopLeft(find.byType(LudoFlameBoard));
        final quarterTurns = (2 - playerIndex + 4) % 4;
        final tokenPosition = switch (quarterTurns) {
          0 => const Offset(30, 30),
          1 => const Offset(270, 30),
          2 => const Offset(270, 270),
          _ => const Offset(30, 270),
        };
        await tester.tapAt(boardOrigin + tokenPosition);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(game.state.pieceById(0).trackPosition, 0);

        game.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
