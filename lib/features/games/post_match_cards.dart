// After full time on a game's screen — the app twins of the web's
// components/progression/YourMatchCard.tsx and the per-team section of
// components/PostMatchSummary.tsx:
//
//   YourMatchCard        — for someone who played: result, their stat line,
//                          XP by reason, unlocks, level + streak, and
//                          "See your progress".
//   PostMatchTeamCards   — one card per team: score, the team's stat totals,
//                          scorers with minutes, and every player's
//                          contributions (from the sport's own stat schema,
//                          so it works for any sport, not just goals).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/games/game_models.dart';
import 'package:sportpadi_mobile/data/games/games_repository.dart';
import 'package:sportpadi_mobile/data/progression/progression_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/player_link.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart' show PersonAvatar;
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

const _mint = Color(0xFF6EDC9E);

/// The reward moment after a completed game, for someone who played it.
/// Renders nothing for spectators (or until the summary has loaded).
class YourMatchCard extends ConsumerWidget {
  const YourMatchCard({super.key, required this.gameId});
  final String gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(matchSummaryProvider(gameId)).valueOrNull;
    if (d == null || d.status != 'completed' || !d.played) {
      return const SizedBox.shrink();
    }
    final p = context.palette;
    final mine = d.teams.where((t) => t.mine).toList();
    final result = mine.isEmpty
        ? 'Full time'
        : switch (mine.first.result) {
            'win' => 'You won',
            'loss' => 'You lost',
            'draw' => 'Draw',
            _ => 'Full time',
          };
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.hero,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('YOUR MATCH',
                  style: TextStyle(
                      color: _mint,
                      fontSize: 11,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(result,
                  style: TextStyle(
                      color: p.onHero,
                      fontSize: 22,
                      height: 1.15,
                      fontWeight: FontWeight.w800)),
            ]),
          ),
          if (d.rating != null) ...[
            Tooltip(
              message: 'Match rating — 6.0 is par',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: d.rating! >= 7.5
                        ? p.accent
                        : d.rating! >= 6
                            ? Colors.white.withAlpha(38)
                            : p.amber.withAlpha(64),
                    borderRadius: BorderRadius.circular(99)),
                child: Text(d.rating!.toStringAsFixed(1),
                    style: TextStyle(
                        color: d.rating! < 6 ? p.amber : Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 6),
          ],
          if (d.xp != 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: d.xp > 0 ? Colors.white : p.amber.withAlpha(64),
                  borderRadius: BorderRadius.circular(99)),
              child: Text('${d.xp > 0 ? '+' : ''}${d.xp} XP',
                  style: TextStyle(
                      color: d.xp > 0 ? const Color(0xFF0E1411) : p.amber,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800)),
            ),
        ]),
        if (d.kudos.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final k in d.kudos)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: p.orange.withAlpha(51),
                    borderRadius: BorderRadius.circular(99)),
                child: Text('${k.icon} ${k.label}${k.count > 1 ? ' ×${k.count}' : ''}',
                    style: TextStyle(
                        color: p.onHero, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
          ]),
        ],
        if (d.myStats.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in d.myStats)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.white.withAlpha(26),
                    borderRadius: BorderRadius.circular(99)),
                child: Text.rich(TextSpan(children: [
                  if (s.icon != null) TextSpan(text: '${s.icon} '),
                  TextSpan(
                      text: '${s.value}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800)),
                  TextSpan(text: ' ${s.label.toLowerCase()}'),
                ]), style: TextStyle(color: p.heroMuted, fontSize: 12)),
              ),
          ]),
        ],
        if (d.earned.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white.withAlpha(15),
                borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              for (final l in d.earned)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                          '${l.label}${l.count > 1 ? ' ×${l.count}' : ''}',
                          style: TextStyle(color: p.heroMuted, fontSize: 12)),
                    ),
                    Text(
                        l.xp > 0
                            ? '+${l.xp}'
                            : l.xp < 0
                                ? '${l.xp}'
                                : '✓',
                        style: TextStyle(
                            color: l.xp < 0 ? p.amber : _mint,
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  ]),
                ),
            ]),
          ),
        ],
        if (d.unlocked.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: p.orange.withAlpha(51),
                borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final u in d.unlocked)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Icon(Icons.auto_awesome_rounded, size: 16, color: p.amber),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Achievement unlocked: $u',
                          style: TextStyle(
                              color: p.onHero,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ),
            ]),
          ),
        ],
        if (d.identity != null) ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: Text('Level ${d.identity!.level} · ${d.identity!.title}',
                  style: TextStyle(color: p.heroMuted, fontSize: 12)),
            ),
            if (d.identity!.weeklyStreak > 0)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.local_fire_department_rounded, size: 15, color: p.amber),
                const SizedBox(width: 3),
                Text('${d.identity!.weeklyStreak}-week streak',
                    style: TextStyle(
                        color: p.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ]),
          ]),
        ],
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: Colors.white.withAlpha(26),
            shape: StadiumBorder(side: BorderSide(color: Colors.white.withAlpha(38))),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => context.push('/progress'),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                child: Text('See your progress →',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// A stat a team or player can have, from the sport's schema (tally keys,
/// plus the assist tally): label + icon, first definition wins.
typedef _Field = ({String key, String label, String? icon});

List<_Field> _statFields(List<ActivityDef> schema) {
  final out = <_Field>[];
  final seen = <String>{};
  void push(String k, String label, String? icon) {
    if (seen.add(k)) out.add((key: k, label: label, icon: icon));
  }

  for (final d in schema) {
    for (final k in d.tally.keys) {
      push(k, d.label, d.icon);
    }
    if (d.assistAllowed) {
      for (final k in d.assistTally.keys) {
        push(k, 'Assist', '🅰️');
      }
    }
  }
  return out;
}

/// One card per team after full time: score, stat totals, scorers (with
/// minutes) and each player's contributions. Web: PostMatchSummary's
/// "Per-team scorers + contributions".
class PostMatchTeamCards extends StatelessWidget {
  const PostMatchTeamCards({super.key, required this.game});
  final GameDetail game;

  @override
  Widget build(BuildContext context) {
    final g = game;
    final defs = {for (final d in g.schema) d.type: d};
    final fields = _statFields(g.schema);

    // Scorers: activities that score for the player's OWN team.
    final scorers = <String, ({String name, String teamId, int? jersey, List<int> minutes, int count})>{};
    for (final a in g.activities) {
      if (defs[a.type]?.scoreTeam != 'own') continue;
      final s = scorers[a.playerId];
      scorers[a.playerId] = (
        name: a.playerName,
        teamId: a.teamId,
        jersey: a.jersey,
        minutes: [...?s?.minutes, if (a.minute != null) a.minute!],
        count: (s?.count ?? 0) + 1,
      );
    }

    // Per-player tallies and per-team totals (assists to the assister).
    final byPlayer = <String, Map<String, int>>{};
    final byTeam = <String, Map<String, int>>{};
    void bump(Map<String, Map<String, int>> m, String id, Map<String, int> eff) {
      if (eff.isEmpty) return;
      final r = m.putIfAbsent(id, () => {});
      eff.forEach((k, v) => r[k] = (r[k] ?? 0) + v);
    }

    for (final a in g.activities) {
      final d = defs[a.type];
      if (d == null) continue;
      bump(byPlayer, a.playerId, d.tally);
      bump(byTeam, a.teamId, d.tally);
      if (d.assistAllowed && a.relatedPlayerId != null) {
        bump(byPlayer, a.relatedPlayerId!, d.assistTally);
        bump(byTeam, a.teamId, d.assistTally);
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final t in g.teams) ...[
        const SizedBox(height: 12),
        _TeamCard(
          team: t,
          fields: fields,
          totals: byTeam[t.teamId] ?? const {},
          scorers: [
            for (final e in scorers.entries)
              if (e.value.teamId == t.teamId) (id: e.key, s: e.value),
          ],
          ratings: g.ratings,
          contributors: [
            for (final pl in g.participants.where((x) => x.teamId == t.teamId))
              if ((byPlayer[pl.playerId] ?? const {}).values.any((v) => v > 0) ||
                  (g.ratings[pl.playerId] != null && g.ratings[pl.playerId] != 6))
                (player: pl, tallies: byPlayer[pl.playerId] ?? const {}),
          ]..sort((a, b) => (g.ratings[b.player.playerId] ?? 6)
              .compareTo(g.ratings[a.player.playerId] ?? 6)),
        ),
      ],
    ]);
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.team,
    required this.fields,
    required this.totals,
    required this.scorers,
    required this.contributors,
    this.ratings = const {},
  });
  final GameTeam team;
  final Map<String, double> ratings;
  final List<_Field> fields;
  final Map<String, int> totals;
  final List<({String id, ({String name, String teamId, int? jersey, List<int> minutes, int count}) s})> scorers;
  final List<({GamePlayer player, Map<String, int> tallies})> contributors;

  static String _jn(int? j) => j != null ? '#$j ' : '';

  Color _color(String? hex) {
    if (hex == null || hex.isEmpty) return const Color(0xFF888888);
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFF888888);
  }

  Widget _label(AppPalette p, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                color: p.muted,
                fontSize: 10.5,
                letterSpacing: 1,
                fontWeight: FontWeight.w800)),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final teamTotals = [for (final f in fields) if ((totals[f.key] ?? 0) > 0) f];
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
                color: _color(team.color), borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(team.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          Text('${team.score}',
              style: TextStyle(
                  color: p.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
        // The team's stat totals.
        if (teamTotals.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final f in teamTotals)
              Tooltip(
                message: f.label,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: p.surface2, borderRadius: BorderRadius.circular(99)),
                  child: Text('${f.icon ?? '•'} ${totals[f.key]}',
                      style: TextStyle(
                          color: p.ink, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
        ],
        // Scorers, with minutes.
        if (scorers.isNotEmpty) ...[
          const SizedBox(height: 12),
          _label(p, 'Scorers'),
          for (final x in scorers)
            PlayerTap(
              userId: x.id,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text.rich(TextSpan(children: [
                  const TextSpan(text: '⚽ '),
                  TextSpan(
                      text: '${_jn(x.s.jersey)}${x.s.name}',
                      style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
                  if (x.s.minutes.isNotEmpty)
                    TextSpan(
                        text: ' ${([...x.s.minutes]..sort()).map((m) => "$m'").join(', ')}',
                        style: TextStyle(color: p.muted))
                  else if (x.s.count > 1)
                    TextSpan(text: ' ×${x.s.count}', style: TextStyle(color: p.muted)),
                ]), style: TextStyle(color: p.ink, fontSize: 13)),
              ),
            ),
        ],
        // Every player's contributions.
        if (contributors.isNotEmpty) ...[
          const SizedBox(height: 12),
          _label(p, 'Contributions'),
          for (final c in contributors)
            PlayerTap(
              userId: c.player.playerId,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  PersonAvatar(url: c.player.avatarUrl, name: c.player.displayName, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${_jn(c.player.jersey)}${c.player.displayName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.ink, fontSize: 13)),
                  ),
                  const SizedBox(width: 6),
                  if (ratings[c.player.playerId] != null) ...[
                    RatingBadge(value: ratings[c.player.playerId]!),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        for (final f in fields)
                          if ((c.tallies[f.key] ?? 0) > 0)
                            Tooltip(
                              message: f.label,
                              child: Text('${f.icon ?? '•'} ${c.tallies[f.key]}',
                                  style: TextStyle(
                                      color: p.ink, fontSize: 12, fontWeight: FontWeight.w700)),
                            ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
        ],
        if (scorers.isEmpty && contributors.isEmpty) ...[
          const SizedBox(height: 8),
          Text('No recorded stats.', style: TextStyle(color: p.muted, fontSize: 12)),
        ],
      ]),
    );
  }
}


/// A match rating (1–10): 6.0 is par; strong reads green, poor amber.
class RatingBadge extends StatelessWidget {
  const RatingBadge({super.key, required this.value});
  final double value;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (bg, fg) = value >= 7.5
        ? (p.accent, Colors.white)
        : value >= 6
            ? (p.surface2, p.ink)
            : (p.amber.withAlpha(40), p.amber);
    return Tooltip(
      message: 'Match rating',
      child: Container(
        constraints: const BoxConstraints(minWidth: 38),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(value.toStringAsFixed(1),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: fg,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ),
    );
  }
}

/// Kudos after full time: who got what, and — for players on the game, within
/// a week — tag ONE teammate for the work no stat records.
class KudosCard extends ConsumerStatefulWidget {
  const KudosCard({super.key, required this.gameId, required this.game});
  final String gameId;
  final GameDetail game;
  @override
  ConsumerState<KudosCard> createState() => _KudosCardState();
}

class _KudosCardState extends ConsumerState<KudosCard> {
  String? _to;
  bool _busy = false;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
      ref.invalidate(gameKudosProvider(widget.gameId));
      ref.invalidate(matchSummaryProvider(widget.gameId));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final d = ref.watch(gameKudosProvider(widget.gameId)).valueOrNull;
    if (d == null) return const SizedBox.shrink();
    final people = {for (final x in widget.game.participants) x.playerId: x};
    final received = d.received.entries.toList()
      ..sort((a, b) => b.value.values.fold(0, (s, n) => s + n).compareTo(a.value.values.fold(0, (s, n) => s + n)));
    if (!d.canGive && received.isEmpty) return const SizedBox.shrink();
    final target = _to ?? d.mine?.toUser;
    final mineTo = d.mine == null ? null : people[d.mine!.toUser];
    final repo = ref.read(gamesRepositoryProvider);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Kudos', style: TextStyle(color: p.ink, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('For the work no stat records. One tag each, to a teammate.',
              style: TextStyle(color: p.muted, fontSize: 12)),
          for (final r in received) ...[
            const SizedBox(height: 10),
            PlayerTap(
              userId: r.key,
              child: Row(children: [
                PersonAvatar(url: people[r.key]?.avatarUrl, name: people[r.key]?.displayName ?? 'Player', size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(people[r.key]?.displayName ?? 'Player',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.ink, fontSize: 13)),
                ),
                Flexible(
                  child: Wrap(alignment: WrapAlignment.end, spacing: 4, runSpacing: 4, children: [
                    for (final t in r.value.entries)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: p.orange.withAlpha(38), borderRadius: BorderRadius.circular(99)),
                        child: Text(
                            '${d.tags.where((x) => x.key == t.key).map((x) => '${x.icon} ${x.label}').firstOrNull ?? t.key}${t.value > 1 ? ' ×${t.value}' : ''}',
                            style: TextStyle(color: p.ink, fontSize: 11.5, fontWeight: FontWeight.w700)),
                      ),
                  ]),
                ),
              ]),
            ),
          ],
          if (d.canGive) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                    mineTo != null
                        ? 'You tagged ${mineTo.displayName} — change it?'
                        : 'Who carried the team today?',
                    style: TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final id in d.teammates)
                    ChoiceChip(
                      label: Text(people[id]?.displayName ?? 'Player'),
                      avatar: PersonAvatar(url: people[id]?.avatarUrl, name: people[id]?.displayName ?? '?', size: 18),
                      selected: target == id,
                      onSelected: _busy ? null : (_) => setState(() => _to = id),
                    ),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final t in d.tags)
                    Tooltip(
                      message: t.hint,
                      child: ChoiceChip(
                        label: Text('${t.icon} ${t.label}'),
                        selected: d.mine?.tag == t.key && target == d.mine?.toUser,
                        onSelected: _busy || target == null
                            ? null
                            : (_) => _run(() => repo.giveKudos(widget.gameId, target, t.key)),
                      ),
                    ),
                ]),
                if (d.mine != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _busy ? null : () => _run(() => repo.removeKudos(widget.gameId)),
                      child: const Text('Take it back'),
                    ),
                  ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}
