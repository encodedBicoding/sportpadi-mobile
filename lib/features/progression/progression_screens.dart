import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/data/progression/progression_repository.dart';
import 'package:sportpadi_mobile/data/ads/placements.dart';
import 'package:sportpadi_mobile/features/ads/ad_anchor.dart';
import 'package:sportpadi_mobile/features/progression/progression_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// The cross-sport boards, in display order.
const kXpBoards = <({String key, String label})>[
  (key: 'xp', label: 'XP'),
  (key: 'attendance', label: 'Attendance'),
  (key: 'community', label: 'Community'),
  (key: 'explorer', label: 'Explorer'),
];

/// One board as a list — used by the platform Leaderboards screen and the
/// group leaderboard. Performance needs a category (stats only compare
/// within one sport).
class BoardList extends ConsumerWidget {
  const BoardList(
      {super.key,
      required this.board,
      this.groupId,
      this.categoryId,
      this.myUserId,
      this.seasonId});
  final String board;
  final String? groupId;
  final String? categoryId;
  final String? myUserId;
  final String? seasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final key = (
      board: board,
      groupId: groupId,
      categoryId: categoryId,
      seasonId: seasonId
    );
    // Watched here (during build), used inside the data builder below.
    final adPlacement = ref.watch(placementProvider('leaderboard.rows'));
    return AsyncView(
      value: ref.watch(boardProvider(key)),
      onRetry: () => ref.invalidate(boardProvider(key)),
      data: (d) {
        if (d.entries.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: GlassCard(
              child: Text(
                board == 'community'
                    ? 'Nobody on this board yet — it fills as people organise games and bring new players in.'
                    : board == 'performance'
                        ? 'No recorded stats in this sport yet — they come from games played with the live scoreboard.'
                        : 'Nobody on this board yet. It fills as people check in and play.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 13),
              ),
            ),
          );
        }
        final inList = d.entries.any((e) => e.userId == myUserId);
        // Ads between rows: the owner console decides whether, what and how
        // often (anchor "leaderboard.rows"); nothing unless it's set.
        final ads = AdInterleave.from(
            adPlacement, 'leaderboard.rows', d.entries.length);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(d.blurb,
                    style: TextStyle(color: p.muted, fontSize: 12)),
              ),
              for (final (i, e) in d.entries.indexed) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: GlassCard(
                    onTap: () => context.push('/players/${e.userId}'),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Row(children: [
                      SizedBox(
                        width: 26,
                        child: Text('${e.rank}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: e.rank <= 3 ? p.amber : p.muted,
                                fontSize: 14,
                                fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 6),
                      Crest(
                          logoUrl: e.avatarUrl, label: e.displayName, size: 32),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          e.userId == myUserId
                              ? '${e.displayName} (you)'
                              : e.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 13.5,
                              fontWeight: e.userId == myUserId
                                  ? FontWeight.w800
                                  : FontWeight.w600),
                        ),
                      ),
                      Text(e.value == null ? '—' : '${e.value} ${d.unit}',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
                ...ads.afterRow(i),
              ],
              if (myUserId != null && !inList)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      "You're not in the top ${d.entries.length} yet — keep showing up.",
                      style: TextStyle(color: p.muted, fontSize: 11.5)),
                ),
            ]);
      },
    );
  }
}

/// Platform-wide boards: the four cross-sport ones, and performance per sport.
class LeaderboardsScreen extends ConsumerStatefulWidget {
  const LeaderboardsScreen({super.key});

  @override
  ConsumerState<LeaderboardsScreen> createState() => _LeaderboardsScreenState();
}

class _LeaderboardsScreenState extends ConsumerState<LeaderboardsScreen> {
  String _board = 'xp';
  String? _categoryId;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final catId = _categoryId ?? (cats.isNotEmpty ? cats.first.id : null);
    Widget chip(String label, bool on, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
              label: Text(label), selected: on, onSelected: (_) => onTap()),
        );
    return Scaffold(
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('Leaderboards',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final b in kXpBoards)
              chip(b.label, _board == b.key,
                  () => setState(() => _board = b.key)),
            chip('Performance', _board == 'performance',
                () => setState(() => _board = 'performance')),
          ]),
        ),
        if (_board == 'performance') ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final c in cats)
                chip('${c.emoji ?? ''} ${c.name}'.trim(), catId == c.id,
                    () => setState(() => _categoryId = c.id)),
            ]),
          ),
        ],
        const SizedBox(height: 10),
        if (_board != 'performance' || catId != null)
          BoardList(
            board: _board,
            categoryId: _board == 'performance' ? catId : null,
            myUserId: ref.watch(meProvider).valueOrNull?.userId,
          ),
      ]),
    );
  }
}

/// Full progress: level, the whole achievements grid (locked ones greyed,
/// discoverable on purpose) and the XP / streak visibility switch.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('Progress',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: AsyncView(
        value: ref.watch(myProgressionProvider),
        onRetry: () => ref.invalidate(myProgressionProvider),
        data: (d) {
          if (d == null) {
            return Center(
              child: Text('Progress is coming soon.',
                  style: TextStyle(color: p.muted)),
            );
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            GlassCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text('${d.title} · Level ${d.level}',
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                      ),
                      StreakPill(streak: d.weekly),
                    ]),
                    const SizedBox(height: 10),
                    XpBar(
                        progress: d.progress,
                        xp: d.xp,
                        nextLevelXp: d.nextLevelXp),
                  ]),
            ),
            const SizedBox(height: 12),
            const ProgressionVisibilityTile(),
            const SizedBox(height: 16),
            Eyebrow(
                'Achievements · ${d.unlocked.length}/${d.catalogue.length}'),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.5,
              children: [
                for (final a in d.catalogue)
                  Opacity(
                    opacity: a.unlocked ? 1 : 0.5,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: a.unlocked ? p.accent.withAlpha(20) : p.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                                a.unlocked ? p.accent.withAlpha(90) : p.line),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(
                                  a.unlocked
                                      ? Icons.emoji_events_rounded
                                      : Icons.lock_outline_rounded,
                                  size: 15,
                                  color: a.unlocked ? p.amber : p.muted),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(a.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: p.ink,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ]),
                            const SizedBox(height: 4),
                            Expanded(
                              child: Text(a.description,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      TextStyle(color: p.muted, fontSize: 11)),
                            ),
                            Text('+${a.xp} XP',
                                style: TextStyle(
                                    color: p.muted,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700)),
                          ]),
                    ),
                  ),
              ],
            ),
          ]);
        },
      ),
    );
  }
}

/// Settings switch: others can see my XP total and streaks (level and
/// achievements are always public).
/// "XP private / XP public" on Profile opens this: the same switch as in
/// Settings, right where the question comes up.
Future<void> showXpVisibilitySheet(BuildContext context) {
  return showSpSheet<void>(
    context,
    builder: (_) => const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSheetHeader(
          icon: Icons.visibility_outlined,
          title: 'Who sees your XP',
          subtitle:
              'Your level and achievements are always visible. Your XP number, '
              'streaks and per-sport levels stay private unless you share them.',
        ),
        ProgressionVisibilityTile(),
      ],
    ),
  );
}

class ProgressionVisibilityTile extends ConsumerStatefulWidget {
  const ProgressionVisibilityTile({super.key});

  @override
  ConsumerState<ProgressionVisibilityTile> createState() =>
      _ProgressionVisibilityTileState();
}

class _ProgressionVisibilityTileState
    extends ConsumerState<ProgressionVisibilityTile> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final d = ref.watch(myProgressionProvider).valueOrNull;
    if (d == null) return const SizedBox.shrink();
    return GlassCard(
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Show my XP and streaks to others',
                style: TextStyle(
                    color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('Your level and achievements are always visible.',
                style: TextStyle(color: p.muted, fontSize: 11.5)),
          ]),
        ),
        Switch(
          value: d.isPublic,
          onChanged: _saving
              ? null
              : (v) async {
                  setState(() => _saving = true);
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await ref.read(progressionRepositoryProvider).setPublic(v);
                    ref.invalidate(myProgressionProvider);
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text('$e')));
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
        ),
      ]),
    );
  }
}

/// Post-match: result, the player's stats (from the sport's own tallies), XP
/// by reason, unlocks, streak. What the "Match complete" push opens.
class MatchSummaryScreen extends ConsumerWidget {
  const MatchSummaryScreen({super.key, required this.gameId});
  final String gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('Match summary',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: AsyncView(
        value: ref.watch(matchSummaryProvider(gameId)),
        onRetry: () => ref.invalidate(matchSummaryProvider(gameId)),
        data: (d) {
          final mine = d.teams.where((t) => t.mine).toList();
          final result = mine.isEmpty
              ? 'Full time'
              : switch (mine.first.result) {
                  'win' => 'You won',
                  'loss' => 'You lost',
                  'draw' => 'Draw',
                  _ => 'Full time',
                };
          return ListView(padding: const EdgeInsets.all(16), children: [
            GlassCard(
              child: Column(children: [
                if (d.eventTitle != null)
                  Text(d.eventTitle!,
                      style: TextStyle(color: p.muted, fontSize: 12)),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < d.teams.length; i++) ...[
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text('–',
                            style: TextStyle(color: p.muted, fontSize: 22)),
                      ),
                    Flexible(
                      child: Column(children: [
                        Text('${d.teams[i].score}',
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 34,
                                fontWeight: FontWeight.w900)),
                        Text(d.teams[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: d.teams[i].mine ? p.accent : p.muted,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ],
                ]),
                if (d.played) ...[
                  const SizedBox(height: 8),
                  Text(result,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                ],
              ]),
            ),
            if (d.played) ...[
              const SizedBox(height: 12),
              GlassCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text('Your match',
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                        ),
                        if (d.xp > 0)
                          Text('+${d.xp} XP',
                              style: TextStyle(
                                  color: p.accent,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800)),
                      ]),
                      if (d.myStats.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final s in d.myStats)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: p.line)),
                              child: Text(
                                  '${s.icon != null ? '${s.icon} ' : ''}${s.value} ${s.label.toLowerCase()}',
                                  style: TextStyle(color: p.ink, fontSize: 12)),
                            ),
                        ]),
                      ],
                      if (d.earned.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        for (final l in d.earned)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(children: [
                              Expanded(
                                child: Text(
                                    '${l.label}${l.count > 1 ? ' ×${l.count}' : ''}',
                                    style: TextStyle(
                                        color: p.muted, fontSize: 12.5)),
                              ),
                              Text(l.xp > 0 ? '+${l.xp}' : '✓',
                                  style: TextStyle(
                                      color: p.muted, fontSize: 12.5)),
                            ]),
                          ),
                      ],
                      for (final u in d.unlocked)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(children: [
                            Icon(Icons.auto_awesome_rounded,
                                size: 16, color: p.amber),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text('Achievement unlocked: $u',
                                  style: TextStyle(
                                      color: p.ink,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ]),
                        ),
                      if (d.identity != null) ...[
                        const SizedBox(height: 10),
                        Row(children: [
                          LevelBadge(
                              level: d.identity!.level,
                              title: d.identity!.title,
                              streak: d.identity!.weeklyStreak),
                        ]),
                      ],
                    ]),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.push('/games/$gameId'),
              child: const Text('Full match details'),
            ),
          ]);
        },
      ),
    );
  }
}
