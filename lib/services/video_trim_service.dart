import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:path_provider/path_provider.dart';

/// In-app video trimming (stream copy — fast, no re-encode).
///
/// Cut with the maintained ffmpeg-kit fork (ffmpeg_kit_flutter_new_min):
/// the original arthenica binaries were pulled from Maven Central when
/// FFmpegKit retired in April 2025, so the old package can no longer
/// build on Android. This fork's min build still publishes its native
/// library there.
///
/// The cut lands on the nearest keyframe at or before the chosen start,
/// so the kept clip can start up to a second or two early. For a set
/// video that is fine; the end is exact. The trimmed file is the one
/// that gets uploaded — the original is left alone on disk.

/// "75.0" -> "1:15". Pure, so it is unit-testable.
String formatMmSs(double seconds) {
  final total = seconds.round();
  final minutes = total ~/ 60;
  final secs = total % 60;
  return '$minutes:${secs.toString().padLeft(2, '0')}';
}

/// True when the kept cut fits inside [maxKeptSec]. Pure.
bool isTrimWithinLimit(double startSec, double endSec, double maxKeptSec) =>
    endSec - startSec <= maxKeptSec;

/// Cuts [inputPath] down to [startSec]..[endSec] and returns the trimmed
/// file's path, or null when the cut failed. A full-range trim (start 0,
/// end == duration) is the caller's job to skip — calling this on it
/// still works, it just copies the file.
Future<String?> trimVideo({
  required String inputPath,
  required double startSec,
  required double endSec,
}) async {
  final dir = await getTemporaryDirectory();
  final outPath =
      '${dir.path}/trimmed_${DateTime.now().millisecondsSinceEpoch}.mp4';
  final duration = endSec - startSec;
  final session = await FFmpegKit.execute(
    '-y -ss ${startSec.toStringAsFixed(2)} -i "$inputPath" '
    '-t ${duration.toStringAsFixed(2)} -c copy "$outPath"',
  );
  final code = await session.getReturnCode();
  if (code == null || !ReturnCode.isSuccess(code)) return null;
  final out = File(outPath);
  if (!await out.exists()) return null;
  return outPath;
}
