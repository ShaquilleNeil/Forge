import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

/// Set videos: users/{uid}/videos/{setId}.mp4, max 5 minutes (300 s).
/// Longer clips are cut down in the trim editor before they get here.
class StorageService {
  static const int maxVideoSeconds = 300;

  final FirebaseStorage _storage = FirebaseStorage.instance;

  Reference _videoRef(String uid, String setId) =>
      _storage.ref().child('users/$uid/videos/$setId.mp4');

  /// Uploads a set video. [durationSec] is the clip length in seconds
  /// (measured by the runner with video_player); clips over 5 minutes
  /// are rejected before any bytes are uploaded. Returns the download URL.
  Future<String> uploadSetVideo({
    required String uid,
    required String setId,
    required File file,
    required double durationSec,
  }) async {
    if (durationSec > maxVideoSeconds) {
      throw ArgumentError(
        'Video is ${durationSec.toStringAsFixed(1)}s; max is $maxVideoSeconds s.',
      );
    }
    final ref = _videoRef(uid, setId);
    await ref.putFile(file, SettableMetadata(contentType: 'video/mp4'));
    return ref.getDownloadURL();
  }

  Future<void> deleteSetVideo(String uid, String setId) async {
    try {
      await _videoRef(uid, setId).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }

  Future<String?> getSetVideoUrl(String uid, String setId) async {
    try {
      return await _videoRef(uid, setId).getDownloadURL();
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return null;
      rethrow;
    }
  }
}
