import 'package:flutter/material.dart';

import '../services/plates_service.dart';
import '../services/strength_math.dart';
import '../theme.dart';

/// Draws the plates for ONE SIDE of the bar as thin vertical bars
/// (IPF colours), with the count text underneath.
///
/// [targetKg] is the total target load in kg (bar included). Plate math
/// comes from [PlatesService.platesFor] with the profile's [barWeightKg]
/// and [plateSet]. [units] ('kg' | 'lb') only changes the displayed
/// numbers — kg stays the stored truth.
///
/// When [onTargetChanged] is given, a +/- stepper (step [stepKg],
/// default 2.5 kg) is shown so the target can be adjusted and the
/// drawing updates.
class PlateCalculator extends StatelessWidget {
  const PlateCalculator({
    super.key,
    required this.targetKg,
    this.barWeightKg = 20.0,
    this.plateSet = 'calibrated',
    this.units = 'kg',
    this.stepKg,
    this.onTargetChanged,
  });

  final double targetKg;
  final double barWeightKg;
  final String plateSet;
  final String units;

  /// Step for the +/- stepper, in kg. Defaults to 2.5 kg.
  final double? stepKg;

  /// When non-null the stepper is shown and called with the new target.
  final ValueChanged<double>? onTargetChanged;

  /// Lb plate colours, mirroring the IPF order (largest = red).
  /// `final`, not `const`: double keys cannot be const-map keys.
  static final Map<double, int> _lbColors = {
    45: 0xFFD32F2F,
    35: 0xFF1E88E5,
    25: 0xFFFBC02D,
    10: 0xFF43A047,
    5: 0xFFF5F5F5,
    2.5: 0xFF9E9E9E,
  };

  String _fmtNum(double v) {
    final s = v.toStringAsFixed(2);
    return s.replaceAll(RegExp(r'\.?0+$'), '');
  }

  /// Display a kg value in the user's preferred unit.
  String _fmtWeight(double kg) {
    if (units == 'lb') return '${StrengthMath.kgToLb(kg).round()} lb';
    return '${_fmtNum(kg)} kg';
  }

  Color _plateColor(double plate, String unit) {
    if (unit == 'lb') {
      final c = _lbColors[plate];
      return c == null ? ForgeTheme.muted : Color(c);
    }
    final c = PlatesService.ipfColors[plate];
    return c == null ? ForgeTheme.muted : Color(c);
  }

  double _plateHeight(double plate, double maxPlate) {
    // 30 px for the smallest change plate up to 88 px for the biggest.
    if (maxPlate <= 0) return 30;
    return 30 + 58 * (plate / maxPlate);
  }

  String _countText(PlateLoad load) {
    if (load.platesPerSide.isEmpty) return 'No plates';
    final groups = <String>[];
    var i = 0;
    while (i < load.platesPerSide.length) {
      var count = 1;
      while (i + count < load.platesPerSide.length &&
          load.platesPerSide[i + count] == load.platesPerSide[i]) {
        count++;
      }
      groups.add(
          '$count × ${_fmtNum(load.platesPerSide[i])} ${load.unit}');
      i += count;
    }
    return '${groups.join(' + ')} per side';
  }

  @override
  Widget build(BuildContext context) {
    final load = PlatesService.platesFor(
      targetKg: targetKg,
      barWeightKg: barWeightKg,
      plateSet: plateSet,
    );
    final maxPlate = plateSet == 'gym' ? 45.0 : 25.0;
    final barOnly = targetKg <= barWeightKg + 0.001;
    final diffKg = targetKg - load.achievedWeightKg;
    final isExact = diffKg.abs() < 0.01 && !barOnly;
    final step = stepKg ?? 2.5;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // --- Plate drawing: one side only, thin vertical bars. ---
        SizedBox(
          height: 110,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // The bar sleeve running behind the plates.
              Container(
                height: 8,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: ForgeTheme.muted.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (load.platesPerSide.isEmpty)
                    Container(
                      width: 14,
                      height: 44,
                      decoration: BoxDecoration(
                        color: ForgeTheme.muted,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    )
                  else
                    for (final plate in load.platesPerSide)
                      Container(
                        width: 9,
                        height: _plateHeight(plate, maxPlate),
                        margin:
                            const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          color: _plateColor(plate, load.unit),
                          borderRadius: BorderRadius.circular(ForgeTheme.radiusSm),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.25),
                          ),
                        ),
                      ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          barOnly ? 'Bar only — no plates needed' : _countText(load),
          textAlign: TextAlign.center,
          style: ForgeTheme.bodyMediumSemibold,
        ),
        const SizedBox(height: 4),
        Text(
          'Per side: ${_fmtWeight(load.perSideWeight)}  ·  '
          'Total: ${_fmtWeight(load.achievedWeightKg)}',
          textAlign: TextAlign.center,
          style: ForgeTheme.bodyMuted,
        ),
        const SizedBox(height: 8),
        if (barOnly)
          const Chip(
            label: Text('Bodyweight / bar only'),
            backgroundColor: ForgeTheme.card,
          )
        else if (isExact)
          const Chip(
            label: Text('Exact'),
            backgroundColor: ForgeTheme.green,
            labelStyle: TextStyle(color: ForgeTheme.scaffoldBg),
          )
        else
          Chip(
            label: Text(
              '${_fmtWeight(diffKg)} under target',
              style: const TextStyle(color: ForgeTheme.text),
            ),
            backgroundColor: ForgeTheme.card,
            side: const BorderSide(color: ForgeTheme.accent),
          ),
        if (onTargetChanged != null) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                iconSize: 28,
                tooltip: 'Lighter',
                onPressed: targetKg - step <= barWeightKg
                    ? null
                    : () => onTargetChanged!(targetKg - step),
              ),
              SizedBox(
                width: 130,
                child: Text(
                  _fmtWeight(targetKg),
                  textAlign: TextAlign.center,
                  style: ForgeTheme.headlineMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                iconSize: 28,
                tooltip: 'Heavier',
                onPressed: () => onTargetChanged!(targetKg + step),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
