import '../../shared/format/parse.dart';

class Profile {
  const Profile({
    required this.displayName,
    required this.username,
    this.avatarUrl,
    this.bio,
    this.gender,
    this.dateOfBirth,
    this.qrCode,
  });

  final String displayName;
  final String username;
  final String? avatarUrl;
  final String? bio;
  final String? gender;
  final String? dateOfBirth;
  final String? qrCode;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        displayName: (j['displayName'] ?? j['username'] ?? 'You') as String,
        username: (j['username'] ?? 'user') as String,
        avatarUrl: parseStr(j['avatarUrl']),
        bio: parseStr(j['bio']),
        gender: parseStr(j['gender']),
        dateOfBirth: parseStr(j['dateOfBirth']),
        qrCode: parseStr(j['qrCode']),
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
                  if (f is Map)
                    StatField.fromJson(Map<String, dynamic>.from(f))
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
