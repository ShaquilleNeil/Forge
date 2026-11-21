import 'package:flutter/material.dart';

import '../services/side_service.dart';
import '../theme.dart';

/// The small pill at the top right, next to the settings gear. It shows
/// which side of Forge you are on — "Training" or "Coach" — and tapping it
/// opens a small menu to switch sides. Small and neat by design.
class SidePill extends StatelessWidget {
  const SidePill({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: SideService.current,
      builder: (context, side, _) {
        final isCoach = side == SideService.coach;
        return Center(
          child: PopupMenuButton<String>(
            tooltip: 'Switch side',
            offset: const Offset(0, 44),
            onSelected: (value) => SideService.set(value),
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: SideService.training,
                child: Row(
                  children: [
                    const Text('My training'),
                    if (!isCoach) ...[
                      const Spacer(),
                      const Icon(Icons.check,
                          size: 18, color: ForgeTheme.accent),
                    ],
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: SideService.coach,
                child: Row(
                  children: [
                    const Text('Coach'),
                    if (isCoach) ...[
                      const Spacer(),
                      const Icon(Icons.check,
                          size: 18, color: ForgeTheme.accent),
                    ],
                  ],
                ),
              ),
            ],
            child: SizedBox(
              height: 48,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: ForgeTheme.card,
                    border: Border.all(color: ForgeTheme.divider),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isCoach ? 'Coach' : 'Training',
                        style: ForgeTheme.labelSmall
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.keyboard_arrow_down,
                        size: 14,
                        color: ForgeTheme.accent,
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
