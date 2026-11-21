/// Plate math: what plates go on each side of the bar for a target weight.
/// Calibrated plates use IPF colours; gym plates are lb.
class PlateLoad {
  final List<double> platesPerSide; // in the set's unit (kg or lb)
  final String unit; // 'kg' | 'lb'
  final double perSideWeight; // plates only, per side, in [unit]
  final double totalWeightKg; // bar + plates, kg
  final double achievedWeightKg; // nearest achievable total (kg)

  const PlateLoad({
    required this.platesPerSide,
    required this.unit,
    required this.perSideWeight,
    required this.totalWeightKg,
    required this.achievedWeightKg,
  });
}

class PlatesService {
  /// Calibrated kg plates, largest first.
  static const List<double> calibratedKg = [25, 20, 15, 10, 5, 2.5, 1.25, 0.5];

  /// Gym plates in lb, largest first.
  static const List<double> gymLb = [45, 35, 25, 10, 5, 2.5];

  /// IPF plate colours (kg plates). Change plates (<= 5 kg) are grey/white.
  // `final`, not `const`: double keys cannot be const-map keys.
  static final Map<double, int> ipfColors = {
    25: 0xFFD32F2F, // red
    20: 0xFF1E88E5, // blue
    15: 0xFFFBC02D, // yellow
    10: 0xFF43A047, // green
    5: 0xFFF5F5F5, // white
    2.5: 0xFF9E9E9E, // grey
    1.25: 0xFF9E9E9E,
    0.5: 0xFF9E9E9E,
  };

  /// Greedy largest-first plates per side for [targetKg] total (bar included).
  /// [plateSet] is 'calibrated' (kg) or 'gym' (lb). Returns the nearest
  /// achievable load at or below the target when the exact load is not
  /// reachable with the available plates.
  static PlateLoad platesFor({
    required double targetKg,
    required double barWeightKg,
    String plateSet = 'calibrated',
  }) {
    if (plateSet == 'gym') {
      const lbPerKg = 2.2046226218;
      final targetLb = targetKg * lbPerKg;
      final barLb = barWeightKg * lbPerKg;
      final perSideLb = (targetLb - barLb) / 2;
      final plates = _greedy(perSideLb, gymLb);
      final achievedPerSideLb =
          plates.fold(0.0, (sum, p) => sum + p);
      final totalLb = barLb + achievedPerSideLb * 2;
      return PlateLoad(
        platesPerSide: plates,
        unit: 'lb',
        perSideWeight: achievedPerSideLb,
        totalWeightKg: totalLb / lbPerKg,
        achievedWeightKg: totalLb / lbPerKg,
      );
    }
    final perSideKg = (targetKg - barWeightKg) / 2;
    final plates = _greedy(perSideKg, calibratedKg);
    final achievedPerSideKg = plates.fold(0.0, (sum, p) => sum + p);
    final totalKg = barWeightKg + achievedPerSideKg * 2;
    return PlateLoad(
      platesPerSide: plates,
      unit: 'kg',
      perSideWeight: achievedPerSideKg,
      totalWeightKg: totalKg,
      achievedWeightKg: totalKg,
    );
  }

  static List<double> _greedy(double perSide, List<double> plates) {
    final result = <double>[];
    var remaining = perSide;
    for (final plate in plates) {
      while (remaining >= plate - 1e-9) {
        result.add(plate);
        remaining -= plate;
      }
    }
    return result;
  }
}
