import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge/widgets/set_row.dart';

void main() {
  Widget row({bool hasVideo = false}) => MaterialApp(
        home: Scaffold(
          body: SetRow(
            key: const ValueKey('set-1'),
            setNumber: 1,
            state: SetRowState.pending,
            weightLabel: '120 kg',
            reps: 4,
            hasVideo: hasVideo,
            onComplete: () {},
            onSkip: () {},
            onWeightTap: () {},
            onRepsTap: () {},
            onPreviousTap: () {},
          ),
        ),
      );

  group('SetRow video indicator', () {
    testWidgets('shows a camera icon when the set has a video',
        (tester) async {
      await tester.pumpWidget(row(hasVideo: true));
      expect(find.byIcon(Icons.videocam), findsOneWidget);
    });

    testWidgets('shows no camera icon when the set has no video',
        (tester) async {
      await tester.pumpWidget(row(hasVideo: false));
      expect(find.byIcon(Icons.videocam), findsNothing);
    });
  });
}
