import 'package:sportpadi_mobile/data/highlights/highlight_models.dart';

/// "+" on a match page's stat row: the stat to post a highlight of, and —
/// when it would be a ward's highlight — whose (the web's `AddHighlight`,
/// `components/highlights/GameBadges.tsx`).
class HighlightAdd {
  const HighlightAdd({required this.activityId, this.forName});
  final String activityId;

  /// The ward's name when every free place on the stat is a ward's; null
  /// when the highlight would be the viewer's own.
  final String? forName;
}

/// Whether a match row offers "+", and for whom — the web's `addFor`
/// (`useGameHighlights`), rule for rule:
/// * nothing for a signed-out viewer ([me] null or empty), nor before the
///   match's highlights (`byGame`, [existing]) have LOADED ([ready]): "+"
///   must not be offered before knowing what already exists;
/// * a row the server listed ([places], `linkable?gameId=`, by stat id):
///   "+" only while some entry on it has no highlight; it names the ward when
///   EVERY free entry is a ward's (`forWard`), and is the viewer's own
///   otherwise — the composer picks the viewer's own entry first too
///   ([highlightPreselect]);
/// * a row the server did not list (a stat recorded a moment ago, or the list
///   could not be loaded): the viewer's own stat can still be told from the
///   row itself — not a substitution, the viewer is one of its two players,
///   and no highlight on it is already about the viewer.
///
/// Pure, so it can be checked without a phone (`~/kmdock/chk` holds the
/// table it was checked against).
HighlightAdd? highlightAddFor({
  required String? me,
  required bool ready,
  required Map<String, List<LinkableStat>> places,
  required List<GameHighlightRef> existing,
  required String activityId,
  required String type,
  required String playerId,
  String? relatedPlayerId,
}) {
  if (me == null || me.isEmpty || !ready) return null;
  final known = places[activityId];
  if (known != null && known.isNotEmpty) {
    final free = [
      for (final s in known)
        if (s.highlightId == null) s
    ];
    if (free.isEmpty) return null;
    final forWard = free.every((s) => s.forWard);
    return HighlightAdd(
        activityId: activityId,
        forName: forWard ? free.first.subject.displayName : null);
  }
  final own = type != 'substitution' &&
      (playerId == me || relatedPlayerId == me) &&
      !existing.any((h) => h.subject.userId == me);
  return own ? HighlightAdd(activityId: activityId) : null;
}

/// The entry the composer starts with when a row's "+" opened it
/// (`/highlights/new?gameId=&activityId=`): of the FREE entries for that
/// stat, the viewer's own first, else the first — a stat shared with a ward
/// is listed once per player. Null when the stat has no free entry (taken
/// since, voided, not theirs): the composer then says so. The web's
/// `preselected` (`app/highlights/new/NewHighlightClient.tsx`).
LinkableStat? highlightPreselect(Iterable<LinkableStat> listed,
    {required String activityId, required String? me}) {
  final free = [
    for (final s in listed)
      if (s.stat.activityId == activityId && s.highlightId == null) s
  ];
  if (free.isEmpty) return null;
  for (final s in free) {
    if (me != null && s.subject.userId == me) return s;
  }
  return free.first;
}
