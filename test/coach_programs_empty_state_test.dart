import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge/theme.dart';
import 'package:forge/widgets/coach_programs_empty_state.dart';

Future<void> pumpEmptyState(
  WidgetTester tester, {
  VoidCallback? onBuild,
  VoidCallback? onImport,
  VoidCallback? onCopy,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ForgeTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: CoachProgramsEmptyState(
            onBuild: onBuild ?? () {},
            onImport: onImport ?? () {},
            onCopy: onCopy ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CoachProgramsEmptyState', () {
    testWidgets('shows all three ways in', (tester) async {
      await pumpEmptyState(tester);
      expect(find.text('No coaching programs yet'), findsOneWidget);
      expect(find.text('Build your own'), findsOneWidget);
      expect(find.text('Import from spreadsheet'), findsOneWidget);
      expect(find.text('Copy from training'), findsOneWidget);
    });

    testWidgets('each option fires its callback', (tester) async {
      var built = false;
      var imported = false;
      var copied = false;
      await pumpEmptyState(
        tester,
        onBuild: () => built = true,
        onImport: () => imported = true,
        onCopy: () => copied = true,
      );
      await tester.tap(find.text('Build your own'));
      expect(built, isTrue);
      await tester.tap(find.text('Import from spreadsheet'));
      expect(imported, isTrue);
      await tester.tap(find.text('Copy from training'));
      expect(copied, isTrue);
    });

    testWidgets('spaces every element deliberately — no glued rows',
        (tester) async {
      await pumpEmptyState(tester);
      // Glyph -> title.
      final glyph = tester.getRect(find.byType(Icon).first);
      final title = tester.getRect(find.text('No coaching programs yet'));
      expect(
        title.top - glyph.bottom,
        CoachProgramsEmptyState.gapGlyphToTitle,
      );
      // Title -> body.
      final body = tester.getRect(find.textContaining('separate from your'));
      expect(
        body.top - title.bottom,
        CoachProgramsEmptyState.gapTitleToBody,
      );
      // Body -> first option card (the option text sits 16px inside
      // its card, so the gap is measured to the card's top).
      final cards = find.byType(Card);
      expect(cards, findsNWidgets(3));
      final firstCard = tester.getRect(cards.at(0));
      expect(
        firstCard.top - body.bottom,
        CoachProgramsEmptyState.gapBodyToOptions,
      );
      // Option -> option: the gap is the SizedBox between the cards,
      // measured from the bottom of one card's surface to the top of
      // the next.
      final secondCard = tester.getRect(cards.at(1));
      expect(
        secondCard.top - firstCard.bottom,
        CoachProgramsEmptyState.gapOptionToOption,
      );
    });
  });
}
