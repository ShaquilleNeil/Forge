import 'package:flutter/material.dart';

import '../theme.dart';

/// Skeleton loaders — the loading state on Today, History and Progress.
/// A pulsing card-colored box in the shape of the content that is
/// coming, instead of a spinner.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = ForgeTheme.radius,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Opacity(
          opacity: 0.35 + 0.35 * _controller.value,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: ForgeTheme.card,
              borderRadius: BorderRadius.circular(widget.radius),
            ),
          ),
        );
      },
    );
  }
}

/// Today loading: hero card + PR tile row + two quiet cards.
class TodaySkeleton extends StatelessWidget {
  const TodaySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: const [
        SkeletonBox(height: 220),
        SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: SkeletonBox(height: 72)),
            SizedBox(width: 8),
            Expanded(child: SkeletonBox(height: 72)),
            SizedBox(width: 8),
            Expanded(child: SkeletonBox(height: 72)),
            SizedBox(width: 8),
            Expanded(child: SkeletonBox(height: 72)),
          ],
        ),
        SizedBox(height: 16),
        SkeletonBox(height: 72),
        SizedBox(height: 16),
        SkeletonBox(height: 72),
      ],
    );
  }
}

/// History loading: month strip + two session cards.
class HistorySkeleton extends StatelessWidget {
  const HistorySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: const [
        SkeletonBox(height: 48),
        SizedBox(height: 16),
        SkeletonBox(height: 96),
        SizedBox(height: 12),
        SkeletonBox(height: 96),
      ],
    );
  }
}

/// Progress loading: score tiles + chart + two PR rows.
class ProgressSkeleton extends StatelessWidget {
  const ProgressSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: const [
        Row(
          children: [
            Expanded(child: SkeletonBox(height: 72)),
            SizedBox(width: 8),
            Expanded(child: SkeletonBox(height: 72)),
            SizedBox(width: 8),
            Expanded(child: SkeletonBox(height: 72)),
          ],
        ),
        SizedBox(height: 16),
        SkeletonBox(height: 180),
        SizedBox(height: 16),
        SkeletonBox(height: 88),
        SizedBox(height: 8),
        SkeletonBox(height: 88),
      ],
    );
  }
}
