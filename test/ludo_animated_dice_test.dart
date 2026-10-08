import 'package:flutter/material.dart';
import 'package:flutter_ludo/flutter_ludo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_call/features/ludo/presentation/widgets/ludo_animated_dice.dart';

void main() {
  testWidgets('dice visibly rolls and settles on the controller result', (
    tester,
  ) async {
    final game = LudoController(
      players: const [
        LudoPlayer(name: 'Red', color: Color(0xFFE24B4B)),
        LudoPlayer(name: 'Blue', color: Color(0xFF3B82C4)),
      ],
      diceRoller: () => 6,
      autoMoveSingleChoice: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LudoAnimatedDice(controller: game, theme: LudoTheme.dark),
        ),
      ),
    );

    await tester.tap(find.text('Roll dice'));
    await tester.pump();
    final firstFrame = tester.widget<LudoDiceFace>(
      find.byKey(const ValueKey('ludo-dice-face')),
    );
    await tester.pump(const Duration(milliseconds: 180));
    final rollingFrame = tester.widget<LudoDiceFace>(
      find.byKey(const ValueKey('ludo-dice-face')),
    );
    expect(rollingFrame.value, isNot(firstFrame.value));

    await tester.pump(const Duration(milliseconds: 700));
    final finalFrame = tester.widget<LudoDiceFace>(
      find.byKey(const ValueKey('ludo-dice-face')),
    );
    expect(finalFrame.value, 6);

    game.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
