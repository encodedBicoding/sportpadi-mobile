import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/data/groups/group_models.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';
import 'package:sportpadi_mobile/features/progression/progression_screens.dart';
import 'package:sportpadi_mobile/data/progression/progression_repository.dart';

/// Group leaderboard — rankings from completed games (web /leaderboard page):
/// per sport category (switcher chips, soccer default), points (3/1/0),
/// W-D-L, games, and the headline tallies.
class GroupLeaderboardScreen extends ConsumerStatefulWidget {
  const GroupLeaderboardScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<GroupLeaderboardScreen> createState() =>
      _GroupLeaderboardScreenState();
}

class _GroupLeaderboardScreenState
    extends ConsumerState<GroupLeaderboardScreen> {
  String get groupId => widget.groupId;
  String? _categoryId;
  bool _picked = false;
  // 'performance' = the per-sport stats table below; the rest are the
  // cross-sport gamification boards.
  String _board = 'performance';
  String? _seasonId; // null = the current season (or all time)

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Pick the default sport (soccer when present) once categories load.
    final cats =
        ref.watch(groupLeaderboardCategoriesProvider(groupId)).valueOrNull;
    if (!_picked && cats != null) {
      _picked = true;
      Map<String, dynamic>? soccer;
      for (final c in cats) {
        final name = parseStr(c['name']) ?? '';
        if (parseStr(c['emoji']) == '⚽' ||
            RegExp('soccer|football|futsal', caseSensitive: false)
                .hasMatch(name)) {
          soccer = c;
          break;
        }
      }
      _categoryId = parseStr((soccer ?? (cats.isNotEmpty ? cats.first : null))
              ?['id']) ??
          _categoryId;
    }
    final board = ref.watch(groupLeaderboardProvider(
        (groupId: groupId, categoryId: _categoryId)));
    final group = ref.watch(groupProvider(groupId)).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Leaderboard',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (group != null)
              Text(group.name,
                  style: TextStyle(color: p.muted, fontSize: 11.5)),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(groupLeaderboardProvider(
                (groupId: groupId, categoryId: _categoryId))
            .future),
        child: Column(children: [
          // Five boards, so the best athlete isn't the only one who can top one.
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 4),
              children: [
                for (final b in [(key: 'performance', label: 'Performance'), ...kXpBoards])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(b.label),
                      selected: _board == b.key,
                      onSelected: (_) => setState(() => _board = b.key),
                    ),
                  ),
              ],
            ),
          ),
          if (_board != 'performance')
            Expanded(
              child: ListView(padding: const EdgeInsets.all(16), children: [
                _seasonRow(context, p, group?.canManage ?? false),
                const SizedBox(height: 10),
                BoardList(
                  board: _board,
                  groupId: groupId,
                  seasonId: _seasonId,
                  myUserId: ref.watch(meProvider).valueOrNull?.userId,
                ),
              ]),
            )
          else ...[
          // Sport switcher — one board per category.
          if ((cats ?? const []).isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                children: [
                  for (final c in cats!)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Material(
                        color: _categoryId == parseStr(c['id'])
                            ? p.accent
                            : p.surface,
                        borderRadius: BorderRadius.circular(999),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => setState(
                              () => _categoryId = parseStr(c['id'])),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 13, vertical: 7),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                  color:
                                      _categoryId == parseStr(c['id'])
                                          ? p.accent
                                          : p.line),
                            ),
                            child: Text(
                              '${parseStr(c['emoji']) ?? ''} ${parseStr(c['name']) ?? ''}'
                                  .trim(),
                              style: TextStyle(
                                  color: _categoryId == parseStr(c['id'])
                                      ? Colors.white
                                      : p.muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: AsyncView(
          value: board,
          onRetry: () => ref.invalidate(groupLeaderboardProvider(
              (groupId: groupId, categoryId: _categoryId))),
          data: (rows) {
            if (rows.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 100),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      (cats ?? const []).length > 1
                          ? 'No completed games in this sport yet — try another category above.'
                          : 'No completed games yet. Once games finish, players show up here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.muted, fontSize: 13),
                    ),
                  ),
                ),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _row(context, rows[i], i + 1),
            );
          },
            ),
          ),
          ],
        ]),
      ),
    );
  }

  /// Which season the XP boards show; admins can start a new one (the open
  /// season closes; nobody loses XP).
  Widget _seasonRow(BuildContext context, AppPalette p, bool canManage) {
    final gp = ref.watch(groupProgressionProvider(groupId)).valueOrNull;
    final seasons = gp?.seasons ?? const <Season>[];
    final current = gp?.currentSeason;
    Season? shown = current;
    if (_seasonId != null) {
      shown = null;
      for (final s in seasons) {
        if (s.id == _seasonId) shown = s;
      }
    }
    String fmt(DateTime? d) => d == null ? '' : '${d.day}/${d.month}/${d.year}';
    return Row(children: [
      Icon(Icons.date_range_outlined, size: 16, color: p.muted),
      const SizedBox(width: 6),
      Expanded(
        child: PopupMenuButton<String?>(
          enabled: seasons.isNotEmpty,
          onSelected: (v) => setState(() => _seasonId = v),
          itemBuilder: (_) => [
            PopupMenuItem<String?>(
              value: null,
              child: Text(current != null ? '${current.name} (current)' : 'All time'),
            ),
            for (final s in seasons.where((s) => s.id != current?.id))
              PopupMenuItem<String?>(value: s.id, child: Text(s.name)),
          ],
          child: Text(
            shown == null
                ? 'All time'
                : '${shown.name} · since ${fmt(shown.startsAt)}${shown.endsAt != null ? ' – ${fmt(shown.endsAt)}' : ''}',
            style: TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      if (canManage)
        TextButton(
          onPressed: () => _newSeason(context, seasons.length + 1),
          child: const Text('New season'),
        ),
    ]);
  }

  Future<void> _newSeason(BuildContext context, int n) async {
    final ctrl = TextEditingController(text: 'Season $n');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start a new season'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('The boards start fresh from now. The current season is kept; nobody loses XP or level.'),
          const SizedBox(height: 12),
          TextField(controller: ctrl, maxLength: 60, decoration: const InputDecoration(labelText: 'Name')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start')),
        ],
      ),
    );
    final name = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(progressionRepositoryProvider).startSeason(groupId, name.isEmpty ? 'Season $n' : name);
      setState(() => _seasonId = null);
      ref.invalidate(groupProgressionProvider(groupId));
      ref.invalidate(boardProvider);
      messenger.showSnackBar(SnackBar(content: Text('${name.isEmpty ? 'Season $n' : name} has started')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _row(BuildContext context, LeaderboardRow r, int rank) {
    final p = context.palette;
    // Highlight the viewer's own row so they spot themselves instantly.
    final mine = ref.watch(meProvider).valueOrNull?.userId == r.playerId;
    final medal = rank == 1
        ? '🥇'
        : rank == 2
            ? '🥈'
            : rank == 3
                ? '🥉'
                : null;
    // Headline tallies (goals/assists first, then whatever else the sport has).
    final headline = <String>[];
    void take(String key, String label) {
      final v = r.tallies[key];
      if (v != null && v > 0) headline.add('$v $label');
    }

    take('goals', 'goals');
    take('assists', 'assists');
    if (headline.length < 2) {
      for (final e in r.tallies.entries) {
        if (e.key == 'goals' || e.key == 'assists') continue;
        if (e.value > 0 && headline.length < 3) {
          headline.add('${e.value} ${e.key.replaceAll('_', ' ')}');
        }
      }
    }
    final card = GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        SizedBox(
          width: 30,
          child: medal != null
              ? Text(medal, style: const TextStyle(fontSize: 18))
              : Text('$rank',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
        ),
        ClipOval(
          child: Crest(logoUrl: r.avatarUrl, label: r.displayName, size: 34),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(r.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 13.5,
                          fontWeight:
                              mine ? FontWeight.w800 : FontWeight.w600)),
                ),
                if (mine) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: p.accent.withAlpha(31),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('You',
                        style: TextStyle(
                            color: p.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ]),
              Text(
                [
                  '${r.wins}W-${r.draws}D-${r.losses}L',
                  '${r.games} game${r.games == 1 ? '' : 's'}',
                  ...headline,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 11.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(children: [
          Text('${r.points}',
              style: TextStyle(
                  color: p.accent,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
          Text('pts', style: TextStyle(color: p.muted, fontSize: 10)),
        ]),
      ]),
    );
    if (!mine) return card;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.accent, width: 1.6),
      ),
      child: card,
    );
  }
}
