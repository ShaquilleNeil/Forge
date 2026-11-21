import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression: Nov 18, 2026 — the Today pager's "Today" jump button
/// was wrapped in Visibility(maintainSize: true, maintainState: true)
/// with no maintainAnimation. That red-screened the whole Today tab
/// in debug builds (Flutter asserts "Cannot maintain size if
/// animations are not maintained" — Visibility lives in
/// indexed_stack.dart in Flutter 3.47). The header no longer uses
/// Visibility at all (the button is disabled on today instead); this
/// test pins the Flutter rule so the pattern is never reused.
void main() {
  testWidgets('Visibility that keeps size must also keep animations',
      (tester) async {
    // The old flag combination — the constructor assert must fire.
    // (Non-const on purpose: a const failing assert is a compile
    // error, not a runtime one.)
    expect(
      () => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Visibility(
              visible: false,
              maintainSize: true,
              maintainState: true,
              child: const Text('Today'),
            ),
          ),
        ),
      ),
      throwsAssertionError,
    );

    // The same flags plus maintainAnimation — builds fine.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Visibility(
            visible: false,
            maintainSize: true,
            maintainState: true,
            maintainAnimation: true,
            child: Text('Today'),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
