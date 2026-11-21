import 'dart:async';

import 'package:flutter/material.dart';

import '../services/tutorial_service.dart';
import '../theme.dart';

/// Pushes the tour. Used by AppShell on first run and by Settings →
/// Replay tutorial. Purely informational: swipe through the screens
/// or skip — nothing to tap through, no pop-ups.
Future<void> showTutorial(BuildContext context, String uid) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => TutorialScreen(uid: uid)),
  );
}

/// First-run walk-through, rebuilt Nov 19: one swipeable page, each
/// page a picture of a real screen with the nav tab that screen lives
/// on highlighted. Swipe through or skip — that's it.
///
/// The pictures are built-in illustrations drawn from the real UI
/// (same theme, same layout) — not photos of a phone — because this
/// machine has no emulator to screenshot with.
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key, required this.uid});

  /// The account seeing the tour — the seen flag is per account.
  final String uid;

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  static const _pages = 8;

  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Any explicit exit ends the tour for this account (Settings can
  /// replay it). Backing out with the system back button does NOT
  /// mark it seen, so an accidental exit shows the tour again next
  /// launch.
  Future<void> _finish() async {
    await TutorialService().markTutorialSeen(widget.uid);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _next() {
    if (_page >= _pages - 1) {
      unawaited(_finish());
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip stays until the last page, where Start training
            // is the exit — the row keeps its height so the pages
            // below never jump.
            Align(
              alignment: Alignment.centerRight,
              child: _page < _pages - 1
                  ? TextButton(
                      onPressed: () => unawaited(_finish()),
                      child: const Text('Skip'),
                    )
                  : const SizedBox(height: 48),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => PageView(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [
                    _welcomePage(constraints.maxHeight),
                    _screenPage(
                      height: constraints.maxHeight,
                      title: 'Today',
                      body: 'Your workout for the day lives here. '
                          'Start it, move it to another day, or mix '
                          'two days into one.',
                      preview: _screenPreview(
                        title: 'Today',
                        navBar: _navBar(active: 0),
                        content: Column(
                          children: [
                            _mockDayCard(),
                          ],
                        ),
                      ),
                    ),
                    _screenPage(
                      height: constraints.maxHeight,
                      title: 'Program',
                      body: 'Your program lives here. Tap a day to '
                          'see its exercises, tap a weight to change '
                          'it — and import your spreadsheet from the '
                          'button up top.',
                      preview: _screenPreview(
                        title: 'Program',
                        action: const Icon(
                          Icons.file_upload_outlined,
                          color: ForgeTheme.accent,
                          size: 22,
                        ),
                        navBar: _navBar(active: 1),
                        content: Column(
                          children: [
                            _mockWeekChips(),
                            const SizedBox(height: 10),
                            _mockRow('D1 · Squat + bench', '5 exercises'),
                            _mockRow('D2 · Hinge + back', '4 exercises'),
                            _mockRow('D3 · Bench + arms', '5 exercises'),
                          ],
                        ),
                      ),
                    ),
                    _screenPage(
                      height: constraints.maxHeight,
                      title: 'The runner',
                      body: 'Log sets as you go. Tap the weight or '
                          'reps to type them in — the rest timer '
                          'starts itself when a set is done. You get '
                          'here from the + in the middle.',
                      preview: _screenPreview(
                        title: 'Workout',
                        // No tab is highlighted: the runner is not a
                        // tab — the + below is how you reach it.
                        navBar: _navBar(active: -1),
                        content: Column(
                          children: [
                            _mockRow('Set 1 — Squat', '120 kg × 5 ✓',
                                done: true),
                            _mockRow('Set 2 — Squat', '120 kg × 5'),
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: ForgeTheme.raised,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'Rest — next: Set 2 · 2:34',
                                style: TextStyle(
                                  color: ForgeTheme.accent,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _screenPage(
                      height: constraints.maxHeight,
                      title: 'History',
                      body: 'Every workout, kept. Tap one to review '
                          'it — every set, and any video you attached.',
                      preview: _screenPreview(
                        title: 'History',
                        navBar: _navBar(active: 3),
                        content: Column(
                          children: [
                            _mockMonthStrip(),
                            const SizedBox(height: 10),
                            _mockRow('Sat, Nov 14 · D4', 'Squat 180 × 1'),
                            _mockRow('Fri, Nov 13 · D3', 'Bench 120 × 1'),
                          ],
                        ),
                      ),
                    ),
                    _screenPage(
                      height: constraints.maxHeight,
                      title: 'Progress',
                      body: 'Your best lifts, estimated one-rep '
                          'maxes and weekly volume.',
                      preview: _screenPreview(
                        title: 'Progress',
                        navBar: _navBar(active: 4),
                        content: Column(
                          children: [
                            _mockRow('Squat', '240 kg'),
                            _mockRow('Bench', '170 kg'),
                            _mockRow('Deadlift', '275 kg'),
                            const SizedBox(height: 12),
                            _mockBars(),
                          ],
                        ),
                      ),
                    ),
                    _screenPage(
                      height: constraints.maxHeight,
                      title: 'Coach',
                      body: 'Pair athletes with your QR code or '
                          '6-letter code. Tap a client to review '
                          'their workouts or send them a program.',
                      preview: _screenPreview(
                        title: 'Clients',
                        navBar: _navBar(coach: true, active: 0),
                        content: Column(
                          children: [
                            _mockQrCard(),
                            const SizedBox(height: 10),
                            _mockRow('Athlete', 'Linked · tap to review'),
                          ],
                        ),
                      ),
                    ),
                    _screenPage(
                      height: constraints.maxHeight,
                      title: 'Settings',
                      body: 'Rest timers, sheet write-back and your '
                          'alerts. Open it from the gear on Today.',
                      preview: _screenPreview(
                        title: 'Settings',
                        // No nav bar: Settings is not a tab — it is
                        // reached from the gear on Today.
                        content: Column(
                          children: [
                            _mockRow(
                              'Rest timer',
                              'Main 3:00 · Accessories 1:30',
                            ),
                            _mockRow(
                              'Sheet write-back',
                              'Off — fills empty cells only',
                            ),
                            _mockRow('Replay tutorial', ''),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Container(
                      width: i == _page ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? ForgeTheme.accent
                            : ForgeTheme.divider,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(
                    _page == _pages - 1 ? 'Start training' : 'Next',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Page 1: the intro — no screen picture, just what to do.
  Widget _welcomePage(double height) {
    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: ForgeTheme.accent,
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'F',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: ForgeTheme.scaffoldBg,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'This is Forge',
                style: ForgeTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Swipe through the screens to see where everything '
                'lives — or skip. Takes about 30 seconds.',
                style: ForgeTheme.bodyMuted,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A screen page: a line of explanation, then the picture.
  Widget _screenPage({
    required double height,
    required String title,
    required String body,
    required Widget preview,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              title,
              style: ForgeTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: ForgeTheme.bodyMuted,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Expanded(child: preview),
          ],
        ),
      ),
    );
  }

  /// A picture of a screen: app-bar title, simplified content, and
  /// the bottom nav with the active tab highlighted.
  Widget _screenPreview({
    required String title,
    required Widget content,
    Widget? action,
    Widget? navBar,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: ForgeTheme.surface,
        border: Border.all(color: ForgeTheme.divider),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Text(title, style: ForgeTheme.titleLarge),
                const Spacer(),
                if (action != null) action,
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: content,
            ),
          ),
          if (navBar != null) navBar,
        ],
      ),
    );
  }

  /// The bottom nav as the user sees it. Training: Today, Program,
  /// + (the runner), History, Progress. Coach: Clients, + (scan),
  /// Programs. The + is always orange — it is the app's one solid
  /// orange button — so a page whose entry is the + passes
  /// active: -1 and no tab lights up.
  Widget _navBar({bool coach = false, required int active}) {
    final items = coach
        ? const <(IconData, String)?>[
            (Icons.people_outlined, 'Clients'),
            null,
            (Icons.view_module_outlined, 'Programs'),
          ]
        : const <(IconData, String)?>[
            (Icons.calendar_today_outlined, 'Today'),
            (Icons.view_module_outlined, 'Program'),
            null,
            (Icons.history_outlined, 'History'),
            (Icons.trending_up_outlined, 'Progress'),
          ];
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: ForgeTheme.divider)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < items.length; i++)
            if (items[i] == null)
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: ForgeTheme.accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add,
                  color: ForgeTheme.scaffoldBg,
                  size: 24,
                ),
              )
            else
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    items[i]!.$1,
                    size: 22,
                    color: i == active
                        ? ForgeTheme.accent
                        : ForgeTheme.muted,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items[i]!.$2,
                    style: TextStyle(
                      fontSize: 10,
                      color: i == active
                          ? ForgeTheme.accent
                          : ForgeTheme.muted,
                    ),
                  ),
                ],
              ),
        ],
      ),
    );
  }

  Widget _mockRow(String label, String value, {bool done = false}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ForgeTheme.raised,
        border: Border.all(
          color: done ? ForgeTheme.green : ForgeTheme.divider,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: ForgeTheme.bodyMedium),
          if (value.isNotEmpty)
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: done ? ForgeTheme.green : ForgeTheme.muted,
              ),
            ),
        ],
      ),
    );
  }

  /// The Today preview's day card, with its Start button.
  Widget _mockDayCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ForgeTheme.raised,
        border: Border.all(color: ForgeTheme.accent),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Iron Ascent · W1 Oct 26',
            style: ForgeTheme.captionMuted,
          ),
          const SizedBox(height: 6),
          const Text('D1 · Squat + bench', style: ForgeTheme.bodyMedium),
          const SizedBox(height: 4),
          const Text(
            '5 exercises · about 55 min',
            style: ForgeTheme.captionMuted,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            height: 44,
            decoration: BoxDecoration(
              color: ForgeTheme.accent,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Text(
              'Start workout',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: ForgeTheme.scaffoldBg,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mockWeekChips() {
    return Row(
      children: [
        _mockChip('W1 Oct 26', hot: true),
        _mockChip('W2 Nov 2'),
        _mockChip('W3 Nov 9'),
      ],
    );
  }

  Widget _mockChip(String label, {bool hot = false}) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: hot ? ForgeTheme.accent : ForgeTheme.divider,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: hot ? ForgeTheme.accent : ForgeTheme.muted,
        ),
      ),
    );
  }

  Widget _mockMonthStrip() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        for (var i = 0; i < 7; i++)
          Container(
            width: 32,
            height: 40,
            decoration: BoxDecoration(
              color: ForgeTheme.raised,
              border: Border.all(color: ForgeTheme.divider),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${10 + i}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: ForgeTheme.text,
                  ),
                ),
                if (i == 2 || i == 5)
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: const BoxDecoration(
                      color: ForgeTheme.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// Three bars in the lift colours: squat orange, bench blue,
  /// deadlift green.
  Widget _mockBars() {
    return Container(
      width: double.infinity,
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: ForgeTheme.raised,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _MockBar(height: 40, color: ForgeTheme.accent),
          _MockBar(height: 28, color: Color(0xFF5B9BD5)),
          _MockBar(height: 52, color: ForgeTheme.green),
        ],
      ),
    );
  }

  Widget _mockQrCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ForgeTheme.raised,
        border: Border.all(color: ForgeTheme.divider),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: ForgeTheme.surface,
              border: Border.all(color: ForgeTheme.divider),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.qr_code_2,
              size: 48,
              color: ForgeTheme.muted,
            ),
          ),
          const SizedBox(height: 8),
          const Text('FORGE-A7K2M9', style: ForgeTheme.bodyMedium),
          const Text(
            'Share your code with an athlete',
            style: ForgeTheme.captionMuted,
          ),
        ],
      ),
    );
  }
}

class _MockBar extends StatelessWidget {
  const _MockBar({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      ),
    );
  }
}
