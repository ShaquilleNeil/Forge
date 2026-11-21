import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// TEMPORARY repro for the Nov 21 red screen: adding a coaching
/// program, then hitting Cancel, crashed with
/// "Failed assertion: '_dependents.isEmpty': is not true" in
/// InheritedElement.debugDeactivated. Delete once diagnosed.
Future<void> pumpDialogOpener(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              final nameController =
                  TextEditingController(text: 'My program');
              final choice = await showDialog<String>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('New coaching program'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Program name',
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Start blank, or use the Simple Strength (3-day) template built from 1RMs.',
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop('blank'),
                      child: const Text('Blank program'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop('template'),
                      child: const Text('Use template'),
                    ),
                  ],
                ),
              );
              final name = nameController.text.trim();
              nameController.dispose();
              if (choice == null || name.isEmpty) return;
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('coach new-program dialog, Cancel', (tester) async {
    await pumpDialogOpener(tester);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });
}
