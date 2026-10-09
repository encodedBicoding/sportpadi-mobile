import '../../shared/format/parse.dart';

class Profile {
  const Profile({
    this.userId,
    required this.displayName,
    required this.username,
    this.avatarUrl,
    this.bio,
    this.gender,
    this.dateOfBirth,
    this.qrCode,
    this.email,
    this.intent,
    this.intentSeenAt,
  });

  final String? userId;
  final String displayName;
  final String username;
  final String? avatarUrl;
  final String? bio;
  final String? gender;
  final String? dateOfBirth;
  final String? qrCode;
  final String? email;

  /// Why they came (intent card picked before sign-up):
  /// play | coach | guardian | host — and when its start wizard was seen.
  final String? intent;
  final String? intentSeenAt;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        userId: parseStr(j['userId']),
        displayName: (j['displayName'] ?? j['username'] ?? 'You') as String,
        username: (j['username'] ?? 'user') as String,
        avatarUrl: parseStr(j['avatarUrl']),
        bio: parseStr(j['bio']),
        gender: parseStr(j['gender']),
        dateOfBirth: parseStr(j['dateOfBirth']),
        qrCode: parseStr(j['qrCode']),
        email: parseStr(j['email']),
        intent: parseStr(j['intent']),
        intentSeenAt: parseStr(j['intentSeenAt']),
      );
}

/// A guardian supervising me (`GET /api/mobile/me/privacy`).
class PrivacyGuardian {
  const PrivacyGuardian(
      {required this.userId, required this.displayName, this.avatarUrl});
  final String userId;
  final String displayName;
  final String? avatarUrl;

  factory PrivacyGuardian.fromJson(Map<String, dynamic> j) => PrivacyGuardian(
        userId: parseStr(j['userId']) ?? '',
        displayName: parseStr(j['displayName']) ?? 'Your guardian',
        avatarUrl: parseStr(j['avatarUrl']),
      );
}

/// Profile privacy for a player who claimed their account under 18 (Wards
/// 3): who sees their profile and whether search finds them, until
/// [supervisedUntil]. [applies] is false for everyone else.
class MyPrivacy {
  const MyPrivacy({
    this.applies = false,
    this.visibility = 'private',
    this.searchable = false,
    this.supervisedUntil,
    this.guardians = const [],
    this.profilePrivate = false,
  });

  final bool applies;

  /// Everyone else ([applies] false): their public profile is private —
  /// others see name, @username and photo, and that it's private.
  final bool profilePrivate;

  /// private | groups | public
  final String visibility;
  final bool searchable;

  /// Their 18th birthday, "YYYY-MM-DD" (a calendar date).
  final String? supervisedUntil;
  final List<PrivacyGuardian> guardians;

  factory MyPrivacy.fromJson(Map<String, dynamic> j) => MyPrivacy(
        applies: j['applies'] == true,
        visibility: parseStr(j['visibility']) ?? 'private',
        searchable: j['searchable'] == true,
        supervisedUntil: parseStr(j['supervisedUntil']),
        profilePrivate: j['profilePrivate'] == true,
        guardians: j['guardians'] is List
            ? [
                for (final g in j['guardians'] as List)
                  if (g is Map)
                    PrivacyGuardian.fromJson(Map<String, dynamic>.from(g))
              ]
            : const [],
      );
}

/// One configurable stat field on a sport (from the category's statSchema).
class StatField {
  const StatField({
    required this.key,
    required this.label,
    this.type = 'choice', // choice | multi
    this.max,
    this.options = const [],
  });
  final String key;
  final String label;
  final String type;
  final int? max;
  final List<String> options;

  factory StatField.fromJson(Map<String, dynamic> j) => StatField(
        key: (j['key'] ?? '') as String,
        label: (j['label'] ?? j['key'] ?? '') as String,
        type: parseStr(j['type']) ?? 'choice',
        max: parseInt(j['max']),
        options: parseStrList(j['options']),
      );
}

/// A sport category with its stat schema.
class SportCategory {
  const SportCategory({
    required this.id,
    required this.name,
    this.emoji,
    this.fields = const [],
  });
  final String id;
  final String name;
  final String? emoji;
  final List<StatField> fields;

  factory SportCategory.fromJson(Map<String, dynamic> j) => SportCategory(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? 'Sport') as String,
        emoji: parseStr(j['emoji']),
        fields: j['statSchema'] is List
            ? [
                for (final f in j['statSchema'] as List)
                  if (f is Map) StatField.fromJson(Map<String, dynamic>.from(f))
              ]
            : const [],
      );
}

/// The player's saved setup for one sport: answers keyed by StatField.key.
/// Values are String (choice) or List<String> (multi).
class MySport {
  const MySport({required this.categoryId, this.answers = const {}});
  final String categoryId;
  final Map<String, dynamic> answers;

  factory MySport.fromJson(Map<String, dynamic> j) => MySport(
        categoryId: (j['categoryId'] ?? '') as String,
        answers: j['extra'] is Map
            ? Map<String, dynamic>.from(j['extra'] as Map)
            : const {},
      );
}

/// Combined payload for the profile "My Sports" section.
class SportsSetup {
  const SportsSetup({this.categories = const [], this.mine = const []});
  final List<SportCategory> categories;
  final List<MySport> mine;

  factory SportsSetup.fromJson(Map<String, dynamic> j) => SportsSetup(
        categories: j['categories'] is List
            ? [
                for (final c in j['categories'] as List)
                  SportCategory.fromJson(Map<String, dynamic>.from(c as Map))
              ]
            : const [],
        mine: j['mine'] is List
            ? [
                for (final m in j['mine'] as List)
                  MySport.fromJson(Map<String, dynamic>.from(m as Map))
              ]
            : const [],
      );
}

/// A saved card on file (personal — speeds up ticket checkout).
class PaymentCard {
  const PaymentCard({
    required this.id,
    required this.isPrimary,
    this.brand,
    this.last4,
    this.expMonth,
    this.expYear,
  });
  final String id;
  final bool isPrimary;
  final String? brand;
  final String? last4;
  final int? expMonth;
  final int? expYear;

  String get label =>
      '${(brand ?? 'Card')[0].toUpperCase()}${(brand ?? 'Card').substring(1)} •••• ${last4 ?? '????'}';
  String? get expiry =>
      expMonth != null && expYear != null ? '$expMonth/$expYear' : null;

  factory PaymentCard.fromJson(Map<String, dynamic> j) => PaymentCard(
        id: (j['id'] ?? '') as String,
        isPrimary: j['isPrimary'] == true,
        brand: parseStr(j['brand']),
        last4: parseStr(j['last4']),
        expMonth: parseInt(j['expMonth']),
        expYear: parseInt(j['expYear']),
      );
}
