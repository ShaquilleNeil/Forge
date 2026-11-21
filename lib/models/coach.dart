import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

/// A coach–client link. One doc per (coach, client) pair, id
/// "<coachUid>_<clientUid>". Either side can delete it to unlink.
class CoachLink {
  final String id;
  final String coachUid;
  final String clientUid;
  final DateTime createdAt;

  /// Last time the coach opened this client's detail screen. A client
  /// workout newer than this gets the NEW badge in the clients list.
  final DateTime? lastViewedAt;

  const CoachLink({
    required this.id,
    required this.coachUid,
    required this.clientUid,
    required this.createdAt,
    this.lastViewedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'coachUid': coachUid,
        'clientUid': clientUid,
        'createdAt': Timestamp.fromDate(createdAt),
        'lastViewedAt':
            lastViewedAt == null ? null : Timestamp.fromDate(lastViewedAt!),
        'status': 'active',
      };

  factory CoachLink.fromJson(Map<String, dynamic> json) {
    final createdRaw = json['createdAt'];
    final viewedRaw = json['lastViewedAt'];
    return CoachLink(
      id: json['id'] as String? ?? '',
      coachUid: json['coachUid'] as String? ?? '',
      clientUid: json['clientUid'] as String? ?? '',
      createdAt: createdRaw is Timestamp
          ? createdRaw.toDate()
          : DateTime.tryParse(createdRaw?.toString() ?? '') ?? DateTime.now(),
      lastViewedAt: viewedRaw is Timestamp
          ? viewedRaw.toDate()
          : (viewedRaw is String ? DateTime.tryParse(viewedRaw) : null),
    );
  }

  CoachLink copyWith({DateTime? lastViewedAt}) => CoachLink(
        id: id,
        coachUid: coachUid,
        clientUid: clientUid,
        createdAt: createdAt,
        lastViewedAt: lastViewedAt ?? this.lastViewedAt,
      );
}

/// A one-time pairing code a client shows (QR) or shares so a coach can
/// link to them. The code itself is the credential: 6 characters from an
/// unambiguous alphabet, valid 24 hours, single use.
class PairingCode {
  final String code; // 6 chars, e.g. "7K2Q9X" — shown as "FORGE-7K2Q9X"
  final String clientUid;
  final String clientName;
  final DateTime createdAt;
  final DateTime expiresAt;

  const PairingCode({
    required this.code,
    required this.clientUid,
    required this.clientName,
    required this.createdAt,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  String get display => 'FORGE-$code';

  Map<String, dynamic> toJson() => {
        'code': code,
        'clientUid': clientUid,
        'clientName': clientName,
        'createdAt': Timestamp.fromDate(createdAt),
        'expiresAt': Timestamp.fromDate(expiresAt),
      };

  factory PairingCode.fromJson(Map<String, dynamic> json) {
    final createdRaw = json['createdAt'];
    final expiresRaw = json['expiresAt'];
    return PairingCode(
      code: json['code'] as String? ?? '',
      clientUid: json['clientUid'] as String? ?? '',
      clientName: json['clientName'] as String? ?? '',
      createdAt: createdRaw is Timestamp
          ? createdRaw.toDate()
          : DateTime.tryParse(createdRaw?.toString() ?? '') ?? DateTime.now(),
      expiresAt: expiresRaw is Timestamp
          ? expiresRaw.toDate()
          : DateTime.tryParse(expiresRaw?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

/// Pairing-code rules, kept pure so they are unit-testable.
class PairingCodes {
  /// No 0/O, 1/I/L — codes are read out loud and typed by hand.
  static const String alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const int length = 6;
  static const Duration validity = Duration(hours: 24);

  /// A fresh 6-character code.
  static String generate([Random? random]) {
    final r = random ?? Random.secure();
    return List.generate(
      length,
      (_) => alphabet[r.nextInt(alphabet.length)],
    ).join();
  }

  /// What the client shows and shares: "FORGE-7K2Q9X".
  static String display(String code) => 'FORGE-$code';

  /// Accepts "7K2Q9X", "forge-7k2q9x", a QR scan of either, or pasted text
  /// around the code. Returns the bare 6-character code, or '' when the
  /// input holds nothing that looks like one.
  static String normalize(String raw) {
    final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (cleaned.startsWith('FORGE')) {
      final rest = cleaned.substring('FORGE'.length);
      if (rest.length == length) return rest;
    }
    if (cleaned.length == length) return cleaned;
    return '';
  }
}
