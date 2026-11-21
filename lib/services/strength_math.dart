import 'dart:math' as math;

/// Strength math. All weights in kg unless stated.
class StrengthMath {
  /// Epley estimated 1RM: w * (1 + reps / 30).
  static double e1rm(double weightKg, int reps) {
    if (reps <= 1) return weightKg;
    return weightKg * (1 + reps / 30.0);
  }

  /// IPF DOTS score. [sex] is 'male' or 'female'.
  /// DOTS = 500 * total / (a*bw^4 + b*bw^3 + c*bw^2 + d*bw + e)
  static double dots(double totalKg, double bodyweightKg, String sex) {
    final bw = bodyweightKg;
    late final double a, b, c, d, e;
    if (sex.toLowerCase() == 'female') {
      a = -0.0000010706;
      b = 0.0009849623;
      c = -0.2278507675;
      d = 27.6408938;
      e = -376.10204;
    } else {
      a = -0.0000010930;
      b = 0.0007391293;
      c = -0.1918759221;
      d = 24.0900756;
      e = -307.75076;
    }
    final denom = a * math.pow(bw, 4) +
        b * math.pow(bw, 3) +
        c * math.pow(bw, 2) +
        d * bw +
        e;
    if (denom <= 0) return 0;
    return 500 * totalKg / denom;
  }

  /// IPF Goodlift (GL) points.
  /// GL = 100 * total / (a - b * exp(-c * bw))
  static double glPoints(double totalKg, double bodyweightKg, String sex) {
    late final double a, b, c;
    if (sex.toLowerCase() == 'female') {
      a = 610.32796;
      b = 1045.59282;
      c = 0.03048;
    } else {
      a = 1199.72839;
      b = 1025.18162;
      c = 0.009560;
    }
    final denom = a - b * math.exp(-c * bodyweightKg);
    if (denom <= 0) return 0;
    return 100 * totalKg / denom;
  }

  /// Round a weight to the nearest achievable increment (default 2.5 kg).
  static double roundToIncrement(double weightKg, double increment) {
    if (increment <= 0) return weightKg;
    return (weightKg / increment).round() * increment;
  }

  /// Convert kg to lb and back (display only; kg stays the stored truth).
  static double kgToLb(double kg) => kg * 2.2046226218;
  static double lbToKg(double lb) => lb / 2.2046226218;
}

/// The one shared weight formatter (A19): a stored kg value rendered in
/// the user's units — '83 kg' / '183.0 lb'. Whole numbers print without
/// decimals; anything else prints one decimal. Every screen that shows
/// a weight to the user should go through this instead of formatting
/// kg inline, so lb users never see a kg number labelled lb (or vice
/// versa). Kg stays the stored truth; this is display only.
String formatWeight(double kg, String units) {
  final value = units == 'lb' ? StrengthMath.kgToLb(kg) : kg;
  final label = units == 'lb' ? 'lb' : 'kg';
  final text = value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
  return '$text $label';
}
