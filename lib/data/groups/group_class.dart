import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// What kind of institution a group belongs to (docs/design/group-classes.md;
/// web twin: packages/lib/src/groupClasses.ts). Group admins pick one in Edit
/// group; the owner console can set it too and lock it ("Confirmed by
/// SportPadi"). Null = not set.
const groupClasses = <String>[
  'school',
  'university',
  'faith',
  'club',
  'academy',
  'workplace',
  'community',
];

const groupClassEmoji = <String, String>{
  'school': '🏫',
  'university': '🎓',
  'faith': '⛪',
  'club': '🏟️',
  'academy': '🥇',
  'workplace': '💼',
  'community': '🤝',
};

bool isGroupClass(Object? v) => v is String && groupClasses.contains(v);

/// A known class code from JSON, or null (unknown / not set).
String? parseGroupClass(Object? v) => isGroupClass(v) ? v as String : null;

/// The full name (`group_classSchool`…) — the group page badge and the picker.
String groupClassName(AppLocalizations t, String code) => switch (code) {
      'school' => t.group_classSchool,
      'university' => t.group_classUniversity,
      'faith' => t.group_classFaith,
      'club' => t.group_classClub,
      'academy' => t.group_classAcademy,
      'workplace' => t.group_classWorkplace,
      'community' => t.group_classCommunity,
      _ => t.group_classNotSet,
    };

/// The plural chip label (`group_classChipSchool`…) — Browse's type chips.
String groupClassChipLabel(AppLocalizations t, String code) => switch (code) {
      'school' => t.group_classChipSchool,
      'university' => t.group_classChipUniversity,
      'faith' => t.group_classChipFaith,
      'club' => t.group_classChipClub,
      'academy' => t.group_classChipAcademy,
      'workplace' => t.group_classChipWorkplace,
      'community' => t.group_classChipCommunity,
      _ => t.group_classAll,
    };
