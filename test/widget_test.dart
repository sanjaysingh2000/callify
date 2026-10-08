import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quick_call/features/home/presentation/pages/home_page.dart';
import 'package:quick_call/features/panel/presentation/widgets/create_panel_dialog.dart';
import 'package:quick_call/features/profile/data/user_profile_store.dart';
import 'package:quick_call/features/profile/presentation/pages/profile_gate_page.dart';
import 'package:quick_call/main.dart';

void main() {
  testWidgets('shows the Callify home screen', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const QuickCallApp(home: HomePage(displayName: 'Test User')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Callify'), findsOneWidget);
    expect(find.text('Start Practice'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows reconnect when a last practice partner is saved', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'last_call_partner_id': 'partner-1',
      'last_call_room_id': 'room-1',
    });

    await tester.pumpWidget(
      const QuickCallApp(home: HomePage(displayName: 'Test User')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reconnect to last user'), findsOneWidget);
  });

  testWidgets('Talk with AI shows a coming soon message', (tester) async {
    await tester.pumpWidget(
      const QuickCallApp(home: HomePage(displayName: 'Test User')),
    );
    await tester.ensureVisible(find.text('Talk with AI'));
    await tester.tap(find.text('Talk with AI'));
    await tester.pump();

    expect(find.text('Talk with AI is coming soon'), findsOneWidget);
  });

  testWidgets('Friend List shows a coming soon message', (tester) async {
    await tester.pumpWidget(
      const QuickCallApp(home: HomePage(displayName: 'Test User')),
    );
    await tester.ensureVisible(find.text('Friend List'));
    await tester.tap(find.text('Friend List'));
    await tester.pump();

    expect(find.text('Friend List is coming soon'), findsOneWidget);
  });

  testWidgets('panel creation asks only for a panel title', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => CreatePanelDialog.show(context),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Panel Title'), findsOneWidget);
    expect(find.text('Your Name'), findsNothing);
    expect(find.text('Enter Your Name'), findsNothing);
  });

  testWidgets('panel creation validates and trims the title', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await CreatePanelDialog.show(context);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a title'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '  Speaking Club  ');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(result, 'Speaking Club');
    expect(find.text('Create Panel'), findsNothing);
  });

  testWidgets('blank profile names are treated as missing and show onboarding', (
    tester,
  ) async {
    final profileStore = _BlankNameProfileStore();

    await tester.pumpWidget(
      MaterialApp(home: ProfileGatePage(profileStore: profileStore)),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('What should people call you?'), findsOneWidget);
    expect(find.text('Start Practice'), findsNothing);
  });
}

class _BlankNameProfileStore extends UserProfileStore {
  @override
  Future<String?> loadDisplayName() async => '   ';
}
