import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/teams/team_models.dart';
import 'package:sportpadi_mobile/features/teams/sport_art.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Sport cards (web `components/groups/SportCards.tsx`): a group's Teams tab
/// is a grid — New team (admins), then one card per sport the group has a
/// team in — and each opens its sport's own screen at
/// `/groups/:id/teams/sport/:sport` (soccer, basketball, … or c-<categoryId>).

class SportBucket {
  SportBucket({required this.key, required this.name, this.def, this.emoji, List<TeamSummary>? teams}) : teams = teams ?? [];
  final String key;
  final String name;
  final SportDef? def;
  final String? emoji;
  final List<TeamSummary> teams;
  Color get color => def?.color ?? const Color(0xFF5E6B66);
}

String sportPath(String groupId, String key) => '/groups/$groupId/teams/sport/$key';

/// The sports the group has a team in (most teams first) — "New team" covers the rest.
List<SportBucket> bucketTeams(List<TeamSummary> teams) {
  final map = <String, SportBucket>{};
  for (final t in teams) {
    final def = sportFor(t.categoryName);
    final key = def?.key ?? 'c-${t.categoryId ?? 'other'}';
    map.putIfAbsent(key, () => SportBucket(key: key, name: def?.name ?? t.categoryName ?? 'Sport', def: def, emoji: t.categoryEmoji)).teams.add(t);
  }
  return map.values.toList()..sort((a, b) => b.teams.length != a.teams.length ? b.teams.length - a.teams.length : a.name.compareTo(b.name));
}

class _Card extends StatelessWidget {
  const _Card({required this.color, required this.onTap, required this.child, this.border});
  final Color color;
  final VoidCallback onTap;
  final Widget child;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) => Material(
        color: color,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 172,
            padding: const EdgeInsets.all(14),
            decoration: border == null ? null : BoxDecoration(border: border, borderRadius: BorderRadius.circular(24)),
            child: child,
          ),
        ),
      );
}

class SportCardsGrid extends StatelessWidget {
  const SportCardsGrid({super.key, required this.groupId, required this.teams, this.onNew, this.locked = false, this.onLocked});
  final String groupId;
  final List<TeamSummary> teams;

  /// Null = not an admin (no New card).
  final VoidCallback? onNew;

  /// Admin, but team building isn't on the plan: a locked card instead.
  final bool locked;
  final VoidCallback? onLocked;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    String names(List<TeamSummary> ts) {
      final first = ts.take(2).map((t) => t.name).join(', ');
      return ts.length > 2 ? '$first +${ts.length - 2}' : first;
    }

    final cards = <Widget>[
      if (onNew != null && !locked)
        _Card(
          color: p.surface,
          border: Border.all(color: p.line, width: 2),
          onTap: onNew!,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(16)),
              child: Icon(Icons.add_rounded, color: p.bg, size: 28),
            ),
            const Spacer(),
            Text('New team', style: TextStyle(color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('Any sport this group plays', style: TextStyle(color: p.muted, fontSize: 12)),
            const SizedBox(height: 8),
            Row(children: [
              for (final s in kSports.take(6))
                Container(
                    width: 14,
                    height: 6,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(9))),
            ]),
          ]),
        ),
      if (locked)
        _Card(
          color: p.orangeTint,
          onTap: onLocked ?? () {},
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SpIconTile(Icons.lock_outline_rounded, size: 48, iconSize: 22, bg: p.surface, fg: p.orangeInk),
            const Spacer(),
            Text('Build teams', style: TextStyle(color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('Upgrade, or redeem a promo code — one per sport, or several.',
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.orangeInk, fontSize: 12)),
          ]),
        ),
      for (final b in bucketTeams(teams))
        Opacity(
          opacity: b.teams.isEmpty ? 0.85 : 1,
          child: _Card(
            color: sportTint(p, b.color),
            onTap: () => context.push(sportPath(groupId, b.key)),
            child: Stack(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SportArt(b.def, emoji: b.emoji, width: 84),
                const Spacer(),
                Text(b.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                    b.teams.isEmpty
                        ? 'No teams yet'
                        : () {
                            final players = b.teams.fold<int>(0, (n, t) => n + (t.memberCount ?? 0));
                            return '${b.teams.length} team${b.teams.length == 1 ? '' : 's'} · $players player${players == 1 ? '' : 's'}';
                          }(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: sportInk(p, b.color), fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    child: Text(b.teams.isEmpty ? (onNew != null && !locked ? 'Build one' : 'See the sport') : names(b.teams),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.ink, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 18, color: p.ink),
                ]),
              ]),
              if (b.teams.isNotEmpty)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: b.color, borderRadius: BorderRadius.circular(99)),
                    child: Text('${b.teams.length}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
          ),
        ),
    ];

    if (cards.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(24),
        child: Text("This group hasn't built any teams yet.",
            textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 13.5)),
      );
    }
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: 10));
      rows.add(Row(children: [
        Expanded(child: cards[i]),
        const SizedBox(width: 10),
        Expanded(child: i + 1 < cards.length ? cards[i + 1] : const SizedBox.shrink()),
      ]));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}
