import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/data/groups/group_models.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/features/progression/progression_screens.dart';
import 'package:sportpadi_mobile/data/progression/progression_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/player_link.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';

/// Group leaderboard — rankings from completed games (web /leaderboard page):
/// per sport category (switcher chips, soccer default), points (3/1/0),
/// W-D-L, games, and the headline tallies.
///
/// Two views, as on web: "Ranking" (podium with a crown on the leader, then
/// the list) and "Full table" (every stat, sortable, with # and Player
/// frozen). Both show how each player moved since the last session — up,
/// down, held or new — and the viewer gets a "You moved up 2" card.
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
  int _view = 0; // 0 = ranking, 1 = full table
  String _ageBand = 'all'; // all | u12 | u16 | u18 | adults

  static const _ageBands = [
    (key: 'all', label: 'All ages'),
    (key: 'u12', label: 'Under 12'),
    (key: 'u16', label: 'Under 16'),
    (key: 'u18', label: 'Under 18'),
    (key: 'adults', label: 'Adults'),
  ];

  ({String groupId, String? categoryId, String ageBand}) get _boardKey =>
      (groupId: groupId, categoryId: _categoryId, ageBand: _ageBand);
  String _sortKey = 'points'; // games | points | goals | assists
  bool _sortDesc = true;

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
      _categoryId =
          parseStr((soccer ?? (cats.isNotEmpty ? cats.first : null))?['id']) ??
              _categoryId;
    }
    final board = ref.watch(groupLeaderboardProvider(_boardKey));
    final group = ref.watch(groupProvider(groupId)).valueOrNull;
    final me = ref.watch(meProvider).valueOrNull?.userId;

    Widget pill(String label, bool active, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Material(
            color: active ? p.hero : p.surface,
            shape: StadiumBorder(
                side: active ? BorderSide.none : BorderSide(color: p.line)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text(label,
                    style: TextStyle(
                        color: active ? p.onHero : p.ink,
                        fontSize: 12.5,
                        fontWeight:
                            active ? FontWeight.w700 : FontWeight.w600)),
              ),
            ),
          ),
        );

    final children = <Widget>[
      SpHeader(title: 'Leaderboard', subtitle: group?.name),
      const SizedBox(height: 14),
      // Five boards, so the best athlete isn't the only one who can top one.
      SizedBox(
        height: 38,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final b in [
              (key: 'performance', label: 'Performance'),
              ...kXpBoards
            ])
              pill(b.label, _board == b.key,
                  () => setState(() => _board = b.key)),
          ],
        ),
      ),
      const SizedBox(height: 12),
    ];

    if (_board != 'performance') {
      children.addAll([
        _seasonRow(context, p, group?.canManage ?? false),
        const SizedBox(height: 12),
        BoardList(
          board: _board,
          groupId: groupId,
          seasonId: _seasonId,
          myUserId: me,
        ),
      ]);
    } else {
      // Sport switcher — one board per category.
      if ((cats ?? const []).isNotEmpty) {
        children.addAll([
          // Sports sit on a quieter row than the boards above: a green
          // tint marks the one you're looking at.
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final c in cats!)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Material(
                      color: _categoryId == parseStr(c['id'])
                          ? p.accentTint
                          : p.surface2,
                      shape: const StadiumBorder(),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: () =>
                            setState(() => _categoryId = parseStr(c['id'])),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 13, vertical: 8),
                          child: Text(
                            '${parseStr(c['emoji']) ?? ''} ${parseStr(c['name']) ?? ''}'
                                .trim(),
                            style: TextStyle(
                                color: _categoryId == parseStr(c['id'])
                                    ? p.greenText
                                    : p.ink,
                                fontSize: 12.5,
                                fontWeight: _categoryId == parseStr(c['id'])
                                    ? FontWeight.w700
                                    : FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ]);
      }
      // Age bands — styled like the sport chips (juniors get their own
      // table, from date of birth).
      children.addAll([
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final b in _ageBands)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Material(
                    color: _ageBand == b.key ? p.accentTint : p.surface2,
                    shape: const StadiumBorder(),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: () => setState(() => _ageBand = b.key),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 8),
                        child: Text(
                          b.label,
                          style: TextStyle(
                              color: _ageBand == b.key ? p.greenText : p.ink,
                              fontSize: 12.5,
                              fontWeight: _ageBand == b.key
                                  ? FontWeight.w700
                                  : FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
      ]);
      children.add(board.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => GlassCard(
          child: Column(children: [
            Text('$e',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 13)),
            const SizedBox(height: 10),
            SpButton(
                label: 'Retry',
                onTap: () =>
                    ref.invalidate(groupLeaderboardProvider(_boardKey))),
          ]),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return GlassCard(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const SpIconTile(Icons.leaderboard_outlined,
                    size: 56, iconSize: 26),
                const SizedBox(height: 12),
                Text(
                    _ageBand == 'all'
                        ? 'No completed games yet'
                        : 'No players in this age group yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  _ageBand != 'all'
                      ? 'Try another age group above.'
                      : (cats ?? const []).length > 1
                          ? 'Nothing finished in this sport yet — try another one above.'
                          : 'Once games finish, players show up here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.muted, fontSize: 13),
                ),
              ]),
            );
          }
          final podium = rows.length >= 3;
          final rest = podium ? rows.sublist(3) : rows;
          LeaderboardRow? mine;
          for (final r in rows) {
            if (r.playerId == me) mine = r;
          }
          final toggle = SpSegmented(
            options: const ['Ranking', 'Full table'],
            icons: const [
              Icons.format_list_numbered_rounded,
              Icons.table_chart_outlined
            ],
            index: _view,
            onChanged: (i) => setState(() => _view = i),
          );
          if (_view == 1) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  toggle,
                  const SizedBox(height: 14),
                  _FullTable(
                    rows: rows,
                    me: me,
                    sortKey: _sortKey,
                    desc: _sortDesc,
                    onSort: (k) => setState(() {
                      if (_sortKey == k) {
                        _sortDesc = !_sortDesc;
                      } else {
                        _sortKey = k;
                        _sortDesc = true;
                      }
                    }),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Tap MP, Pts, G or A to sort. MP matches · W wins · D draws · L losses · Pts points (3 a win, 1 a draw) · G goals · A assists · OG own goals · YC/RC cards. Arrows show movement since the last session.',
                    style:
                        TextStyle(color: p.muted, fontSize: 11.5, height: 1.45),
                  ),
                ]);
          }
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                toggle,
                const SizedBox(height: 14),
                if (mine != null && (mine.move != null || mine.isNew)) ...[
                  _MyMovement(row: mine),
                  const SizedBox(height: 16),
                ],
                if (podium) ...[
                  _Podium(rows: rows.take(3).toList(), me: me),
                  const SizedBox(height: 16),
                ],
                if (rest.isNotEmpty)
                  SpListCard(children: [
                    for (var i = 0; i < rest.length; i++)
                      _row(context, rest[i], (podium ? 4 : 1) + i,
                          mine: rest[i].playerId == me),
                  ]),
                const SizedBox(height: 12),
                Text(
                  'Points: 3 a win, 1 a draw. Local group games only — tournaments keep their own tables. Arrows show movement since the last session.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.muted, fontSize: 12, height: 1.4),
                ),
              ]);
        },
      ));
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            children: children,
          ),
        ),
      ),
    );
  }

  /// Pull to refresh: the header, the sport chips and whichever board is
  /// showing (the performance table, or an XP board with its seasons).
  Future<void> _refresh() {
    final BoardKey xpKey = (
      board: _board,
      groupId: groupId,
      categoryId: null,
      seasonId: _seasonId
    );
    final xp = _board != 'performance';
    ref.invalidate(groupProvider(groupId));
    ref.invalidate(groupLeaderboardCategoriesProvider(groupId));
    ref.invalidate(groupLeaderboardProvider(_boardKey));
    ref.invalidate(groupProgressionProvider(groupId));
    ref.invalidate(boardProvider);
    return settleAll([
      ref.read(groupProvider(groupId).future),
      ref.read(groupLeaderboardCategoriesProvider(groupId).future),
      ref.read(groupLeaderboardProvider(_boardKey).future),
      if (xp) ref.read(groupProgressionProvider(groupId).future),
      if (xp) ref.read(boardProvider(xpKey).future),
    ]);
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
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(children: [
        const SpIconTile(Icons.date_range_outlined, size: 38, iconSize: 18),
        const SizedBox(width: 10),
        Expanded(
          child: PopupMenuButton<String?>(
            enabled: seasons.isNotEmpty,
            onSelected: (v) => setState(() => _seasonId = v),
            itemBuilder: (_) => [
              PopupMenuItem<String?>(
                value: null,
                child: Text(
                    current != null ? '${current.name} (current)' : 'All time'),
              ),
              for (final s in seasons.where((s) => s.id != current?.id))
                PopupMenuItem<String?>(value: s.id, child: Text(s.name)),
            ],
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(shown == null ? 'All time' : shown.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                    ),
                    if (seasons.isNotEmpty)
                      Icon(Icons.expand_more_rounded, size: 18, color: p.muted),
                  ]),
                  if (shown != null)
                    Text(
                        'Since ${fmt(shown.startsAt)}${shown.endsAt != null ? ' – ${fmt(shown.endsAt)}' : ''}',
                        style: TextStyle(color: p.muted, fontSize: 11.5)),
                ]),
          ),
        ),
        if (canManage)
          TextButton(
            onPressed: () => _newSeason(context, seasons.length + 1),
            style: TextButton.styleFrom(
                foregroundColor: p.greenText,
                textStyle: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700)),
            child: const Text('New season'),
          ),
      ]),
    );
  }

  Future<void> _newSeason(BuildContext context, int n) async {
    final ctrl = TextEditingController(text: 'Season $n');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start a new season'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'The boards start fresh from now. The current season is kept; nobody loses XP or level.'),
          const SizedBox(height: 12),
          TextField(
              controller: ctrl,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Name')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Start')),
        ],
      ),
    );
    final name = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(progressionRepositoryProvider)
          .startSeason(groupId, name.isEmpty ? 'Season $n' : name);
      setState(() => _seasonId = null);
      ref.invalidate(groupProgressionProvider(groupId));
      ref.invalidate(boardProvider);
      messenger.showSnackBar(SnackBar(
          content: Text('${name.isEmpty ? 'Season $n' : name} has started')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _row(BuildContext context, LeaderboardRow r, int rank,
      {bool mine = false}) {
    final p = context.palette;
    final headline = leaderboardHeadline(r);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => openPlayerProfile(context, ref, r.playerId),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          // Highlight the viewer's own row so they spot themselves instantly.
          color: mine ? p.accentTint : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          SizedBox(
            width: 34,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$rank',
                      style: TextStyle(
                          color: mine ? p.greenText : p.muted,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                  _Move(move: r.move, isNew: r.isNew),
                ]),
          ),
          ClipOval(
            child: Crest(logoUrl: r.avatarUrl, label: r.displayName, size: 38),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(mine ? 'You' : r.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 14,
                            fontWeight:
                                mine ? FontWeight.w800 : FontWeight.w700)),
                  ),
                  if (r.isWard) ...[
                    const SizedBox(width: 6),
                    const WardBadge(),
                  ],
                ]),
                Text(
                  [
                    '${r.wins}-${r.draws}-${r.losses}',
                    '${r.games} game${r.games == 1 ? '' : 's'}',
                    ...headline,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${r.points}',
                style: TextStyle(
                    color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
            Text('pts', style: TextStyle(color: p.muted, fontSize: 10.5)),
          ]),
        ]),
      ),
    );
  }
}

/// Headline tallies for a row (goals/assists first, then whatever else the
/// sport tracks).
List<String> leaderboardHeadline(LeaderboardRow r, {int max = 2}) {
  final out = <String>[];
  void take(String key, String label) {
    final v = r.tallies[key];
    if (v != null && v > 0) out.add('$v $label');
  }

  take('goals', 'goals');
  take('assists', 'assists');
  if (out.length < max) {
    for (final e in r.tallies.entries) {
      if (e.key == 'goals' || e.key == 'assists') continue;
      if (e.value > 0 && out.length < max) {
        out.add('${e.value} ${e.key.replaceAll('_', ' ')}');
      }
    }
  }
  return out.take(max).toList();
}

/// The top three on pedestals: 2nd · 1st · 3rd, the winner on a dark block.
class _Podium extends StatelessWidget {
  const _Podium({required this.rows, this.me});
  final List<LeaderboardRow> rows;
  final String? me;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget place(LeaderboardRow r, int rank, double h) {
      final first = rank == 1;
      final mine = r.playerId == me;
      final ring = first
          ? p.orange
          : mine
              ? p.accent
              : p.line;
      final head = leaderboardHeadline(r, max: 1);
      return Expanded(
        child: PlayerTap(
          userId: r.playerId,
          borderRadius: 20,
          child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
            // A gold crown on the leader.
            if (first) ...[
              const _Crown(width: 30),
              const SizedBox(height: 3),
            ],
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ring, width: 2.5),
              ),
              child: ClipOval(
                child: Crest(
                    logoUrl: r.avatarUrl,
                    label: r.displayName,
                    size: first ? 58 : 46),
              ),
            ),
            const SizedBox(height: 6),
            Text(mine ? 'You' : r.displayName.split(' ').first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: p.ink, fontSize: 13, fontWeight: FontWeight.w700)),
            Text(head.isNotEmpty ? head.first : '${r.games} games',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 11)),
            if (r.move != null || r.isNew) ...[
              const SizedBox(height: 3),
              _Move(move: r.move, isNew: r.isNew),
            ],
            const SizedBox(height: 8),
            Container(
              height: h,
              width: double.infinity,
              decoration: BoxDecoration(
                color: first ? p.hero : p.surface,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20), bottom: Radius.circular(8)),
                boxShadow: first ? null : cardShadow(context),
              ),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$rank',
                        style: TextStyle(
                            color: first ? p.onHero : p.ink,
                            fontSize: first ? 26 : 22,
                            fontWeight: FontWeight.w800)),
                    Text('${r.points} pts',
                        style: TextStyle(
                            color: first ? const Color(0xFF6EDC9E) : p.muted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700)),
                  ]),
            ),
          ]),
        ),
      );
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      place(rows[1], 2, 92),
      const SizedBox(width: 10),
      place(rows[0], 1, 118),
      const SizedBox(width: 10),
      place(rows[2], 3, 76),
    ]);
  }
}

const _gold = Color(0xFFF0A500);

/// The leader's crown — gold, three points with round tips.
class _Crown extends StatelessWidget {
  const _Crown({this.width = 28});
  final double width;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Leader',
        child: CustomPaint(
          size: Size(width, width * 0.72),
          painter: _CrownPainter(),
        ),
      );
}

class _CrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final fill = Paint()..color = _gold;
    final body = Path()
      ..moveTo(w * 0.08, h * 0.92)
      ..lineTo(w * 0.02, h * 0.3)
      ..lineTo(w * 0.3, h * 0.58)
      ..lineTo(w * 0.5, h * 0.12)
      ..lineTo(w * 0.7, h * 0.58)
      ..lineTo(w * 0.98, h * 0.3)
      ..lineTo(w * 0.92, h * 0.92)
      ..close();
    canvas.drawPath(body, fill);
    // Band + jewel tips.
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.08, h * 0.8, w * 0.84, h * 0.2),
            Radius.circular(h * 0.08)),
        fill);
    final tip = w * 0.075;
    canvas.drawCircle(Offset(w * 0.02, h * 0.3), tip, fill);
    canvas.drawCircle(Offset(w * 0.5, h * 0.1), tip, fill);
    canvas.drawCircle(Offset(w * 0.98, h * 0.3), tip, fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Movement since the last session: ▲2 green, ▼1 red, – held, NEW orange.
class _Move extends StatelessWidget {
  const _Move({required this.move, required this.isNew});
  final int? move;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (isNew) {
      return Container(
        margin: const EdgeInsets.only(top: 1),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
            color: p.orangeTint, borderRadius: BorderRadius.circular(999)),
        child: Text('NEW',
            style: TextStyle(
                color: p.orangeInk,
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4)),
      );
    }
    final m = move;
    if (m == null) return const SizedBox.shrink();
    if (m == 0) {
      return Text('–',
          style: TextStyle(
              color: p.muted, fontSize: 12, fontWeight: FontWeight.w800));
    }
    final up = m > 0;
    final c = up ? p.greenText : p.danger;
    return Semantics(
      label: up ? 'Up ${m.abs()}' : 'Down ${m.abs()}',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(up ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
            size: 18, color: c),
        Text('${m.abs()}',
            style: TextStyle(
                color: c,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1)),
      ]),
    );
  }
}

/// "You moved up 2" — the viewer's movement since the last session.
class _MyMovement extends StatelessWidget {
  const _MyMovement({required this.row});
  final LeaderboardRow row;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final m = row.move ?? 0;
    final (icon, bg, fg, title) = row.isNew
        ? (
            Icons.fiber_new_rounded,
            p.orangeTint,
            p.orangeInk,
            "You're on the board"
          )
        : m > 0
            ? (
                Icons.trending_up_rounded,
                p.accentTint,
                p.greenText,
                'You moved up $m'
              )
            : m < 0
                ? (
                    Icons.trending_down_rounded,
                    p.liveTint,
                    p.danger,
                    'You dropped ${-m} place${m == -1 ? '' : 's'}'
                  )
                : (
                    Icons.trending_flat_rounded,
                    p.surface2,
                    p.ink,
                    'You held your place'
                  );
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
      child: Row(children: [
        SpIconTile(icon, bg: bg, fg: fg, size: 42),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    color: p.ink, fontSize: 15, fontWeight: FontWeight.w800)),
            Text(
                row.prevRank != null && !row.isNew
                    ? 'Was #${row.prevRank} · since the last session'
                    : 'Since the last session',
                style: TextStyle(color: p.muted, fontSize: 12)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('#${row.rank}',
              style: TextStyle(
                  color: p.ink, fontSize: 20, fontWeight: FontWeight.w800)),
          Text('${row.points} pts',
              style: TextStyle(color: p.muted, fontSize: 11)),
        ]),
      ]),
    );
  }
}

/// Every stat for every player, sortable — the web "Full table". # and
/// Player stay put; the stat columns scroll sideways.
class _FullTable extends StatelessWidget {
  const _FullTable({
    required this.rows,
    required this.me,
    required this.sortKey,
    required this.desc,
    required this.onSort,
  });
  final List<LeaderboardRow> rows;
  final String? me;
  final String sortKey;
  final bool desc;
  final ValueChanged<String> onSort;

  static const _rowH = 54.0;
  static const _headH = 42.0;

  int _stat(LeaderboardRow r, String key) => switch (key) {
        'games' => r.games,
        'points' => r.points,
        _ => r.tallies[key] ?? 0,
      };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Columns: MP W D L Pts always; stat columns when someone has a value.
    final cols = <(String, String, int Function(LeaderboardRow), String?)>[
      ('MP', 'Matches played', (r) => r.games, 'games'),
      ('W', 'Wins', (r) => r.wins, null),
      ('D', 'Draws', (r) => r.draws, null),
      ('L', 'Losses', (r) => r.losses, null),
      ('Pts', 'Points', (r) => r.points, 'points'),
      for (final (k, l, t) in const [
        ('goals', 'G', 'Goals'),
        ('assists', 'A', 'Assists'),
        ('ownGoals', 'OG', 'Own goals'),
        ('yellows', 'YC', 'Yellow cards'),
        ('reds', 'RC', 'Red cards'),
      ])
        if (rows.any((r) => (r.tallies[k] ?? 0) > 0))
          (
            l,
            t,
            (r) => r.tallies[k] ?? 0,
            (k == 'goals' || k == 'assists') ? k : null
          ),
    ];
    final sorted = [...rows]..sort((a, b) {
        final diff = _stat(b, sortKey) - _stat(a, sortKey);
        final primary = desc ? diff : -diff;
        if (primary != 0) return primary;
        final pts = b.points - a.points;
        if (pts != 0) return pts;
        final g = (b.tallies['goals'] ?? 0) - (a.tallies['goals'] ?? 0);
        if (g != 0) return g;
        final w = b.wins - a.wins;
        if (w != 0) return w;
        return a.displayName.compareTo(b.displayName);
      });
    // Movement is by points, so it only makes sense on the points order.
    final showMove = sortKey == 'points' && desc;

    Widget head(String label,
        {String? key, TextAlign align = TextAlign.center, double? width}) {
      final active = key != null && key == sortKey;
      final text = Row(
        mainAxisAlignment: align == TextAlign.left
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: active ? p.ink : p.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6)),
          if (key != null)
            Icon(
                active
                    ? (desc
                        ? Icons.arrow_drop_down_rounded
                        : Icons.arrow_drop_up_rounded)
                    : Icons.unfold_more_rounded,
                size: active ? 18 : 13,
                color: active ? p.ink : p.muted.withAlpha(120)),
        ],
      );
      return InkWell(
        onTap: key == null ? null : () => onSort(key),
        child: Container(
          width: width,
          height: _headH,
          alignment:
              align == TextAlign.left ? Alignment.centerLeft : Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: p.surface2,
          child: text,
        ),
      );
    }

    Widget rankCell(int n, LeaderboardRow r) {
      final top = n <= 3;
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        top
            ? Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: n == 1 ? p.orange : p.surface2,
                    shape: BoxShape.circle),
                child: Text('$n',
                    style: TextStyle(
                        color: n == 1 ? Colors.white : p.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              )
            : Text('$n',
                style: TextStyle(
                    color: p.muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
        if (showMove) _Move(move: r.move, isNew: r.isNew),
      ]);
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: cardShadow(context),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Frozen: # + Player.
        Container(
          width: 172,
          decoration: BoxDecoration(
            boxShadow: const [
              BoxShadow(
                  color: Color(0x220E1411),
                  blurRadius: 8,
                  offset: Offset(3, 0)),
            ],
            color: p.surface,
          ),
          child: Column(children: [
            Row(children: [
              head('#', width: 42),
              Expanded(child: head('Player', align: TextAlign.left)),
            ]),
            for (var i = 0; i < sorted.length; i++)
              PlayerTap(
                userId: sorted[i].playerId,
                borderRadius: 0,
                child: Container(
                  height: _rowH,
                  decoration: BoxDecoration(
                    color: sorted[i].playerId == me ? p.accentTint : p.surface,
                    border: Border(
                      top: BorderSide(color: p.surface2),
                      left: BorderSide(
                          color: sorted[i].playerId == me
                              ? p.accent
                              : Colors.transparent,
                          width: 3),
                    ),
                  ),
                  child: Row(children: [
                    SizedBox(width: 39, child: rankCell(i + 1, sorted[i])),
                    ClipOval(
                      child: Crest(
                          logoUrl: sorted[i].avatarUrl,
                          label: sorted[i].displayName,
                          size: 28),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              sorted[i].playerId == me
                                  ? 'You'
                                  : sorted[i].displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 13,
                                  fontWeight: sorted[i].playerId == me
                                      ? FontWeight.w800
                                      : FontWeight.w600)),
                          if ((sorted[i].username ?? '').isNotEmpty)
                            Text('@${sorted[i].username}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: p.muted, fontSize: 11)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ]),
                ),
              ),
          ]),
        ),
        // Scrolling stat columns.
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                for (final c in cols) head(c.$1, key: c.$4, width: 48),
              ]),
              for (final r in sorted)
                Container(
                  height: _rowH,
                  decoration: BoxDecoration(
                    color: r.playerId == me ? p.accentTint : p.surface,
                    border: Border(top: BorderSide(color: p.surface2)),
                  ),
                  child: Row(children: [
                    for (final c in cols)
                      Container(
                        width: 48,
                        alignment: Alignment.center,
                        color:
                            c.$4 != null && c.$4 == sortKey && r.playerId != me
                                ? p.surface2.withAlpha(110)
                                : null,
                        child: Text('${c.$3(r)}',
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 13.5,
                                fontWeight: c.$1 == 'Pts'
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ])),
                      ),
                  ]),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
