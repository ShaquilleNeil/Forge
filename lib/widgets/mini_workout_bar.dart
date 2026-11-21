import 'package:flutter/material.dart';

import '../services/active_session.dart';
import '../theme.dart';

/// The persistent mini workout bar: sits directly above the bottom nav
/// whenever a session is active, and is hidden on the Runner itself
/// (the runner is a pushed route that covers the shell).
///
/// Shows elapsed time, the next set to do, and the rest countdown while
/// resting. Tap opens the runner.
class MiniWorkoutBar extends StatelessWidget {
  const MiniWorkoutBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ActiveSession.current,
      builder: (context, session, _) {
        if (session == null) return const SizedBox.shrink();
        final now = DateTime.now();
        final next = nextOpenSet(session);
        final restRemaining = formatRestRemaining(session.restEndsAt, now);
        final resting = restRemaining != null;
        final elapsed = formatElapsed(session.date, now);

        final done = session.sets
            .where((s) => s.completed || s.skipped)
            .length;
        final total = session.sets.length;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Material(
            color: ForgeTheme.raised,
            borderRadius: BorderRadius.circular(ForgeTheme.radius),
            child: InkWell(
              borderRadius: BorderRadius.circular(ForgeTheme.radius),
              onTap: () => Navigator.of(context).pushNamed('/runner'),
              child: SizedBox(
                height: 56,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(
                        resting ? Icons.timer_outlined : Icons.fitness_center,
                        color: ForgeTheme.accent,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        elapsed,
                        style: ForgeTheme.titleMediumBoldTabular,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              next == null
                                  ? 'All sets logged'
                                  : next.name,
                              style: ForgeTheme.bodyMediumSemibold,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              next == null
                                  ? session.title
                                  : 'Set ${next.setIndex + 1} · $done/$total sets',
                              style: ForgeTheme.captionMuted,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (resting)
                        Text(
                          'Rest $restRemaining',
                          style: ForgeTheme.titleMediumAccentTabular,
                        )
                      else
                        const Icon(
                          Icons.chevron_right,
                          color: ForgeTheme.muted,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The center nav destination: "+" when idle, a progress ring around a
/// timer icon while a session is active (ring = fraction of sets done).
class CenterWorkoutIcon extends StatelessWidget {
  const CenterWorkoutIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ActiveSession.current,
      builder: (context, session, _) {
        if (session == null || session.sets.isEmpty) {
          return const Icon(
            Icons.add_circle,
            size: 32,
            color: ForgeTheme.accent,
          );
        }
        final done = session.sets
            .where((s) => s.completed || s.skipped)
            .length;
        final progress = (done / session.sets.length).clamp(0.0, 1.0);
        return SizedBox(
          width: 32,
          height: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2.5,
                  color: ForgeTheme.accent,
                  backgroundColor: ForgeTheme.divider,
                ),
              ),
              const Icon(
                Icons.timer_outlined,
                size: 18,
                color: ForgeTheme.accent,
              ),
            ],
          ),
        );
      },
    );
  }
}
