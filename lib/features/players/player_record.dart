import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/sports/sport_artwork.dart';
import 'package:sportpadi_mobile/features/sports/sport_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// The per-sport record blocks, shared by the public player profile and the
/// per-group breakdown so the two can never drift apart.
///
/// These take raw JSON maps rather than typed models on purpose: the payload is
/// shaped entirely by the server's stat aggregation, and a typed mirror would
/// be one more thing to keep in step for no gain.

List<Map<String, dynamic>> listOf(dynamic v) => v is List
    ? [
        for (final e in v)
          if (e is Map) Map<String, dynamic>.from(e)
      ]
    : const [];

Map<String, dynamic> mapOf(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

int statInt(dynamic v) => parseInt(v) ?? 0;

/// The sport to open on: soccer when they play it, otherwise whichever they've
/// played most.
///
/// Matched on the category NAME rather than a hard-coded id, since categories
/// are rows an owner can rename or re-seed — and "football" and "soccer" are
/// the same game to different halves of the world.
String? defaultCategoryId(List<Map<String, dynamic>> categories) {
  if (categories.isEmpty) return null;
  final soccer = categories.cast<Map<String, dynamic>?>().firstWhere(
        (c) => RegExp('soccer|football', caseSensitive: false)
            .hasMatch(parseStr(c?['name']) ?? ''),
        orElse: () => null,
      );
  return parseStr((soccer ?? categories.first)['categoryId']);
}

/// The category control — the page's steering wheel.
///
/// A select listing EVERY active category on SportPadi (not just the ones this
/// player has touched): a visitor asks "how are they at tennis?", and the
/// honest answer is "no tennis record", not a missing option. Sports with a
/// record come first with their game count; the rest follow, marked.
///
/// Under an explicit label, with a sentence beneath naming the player and the
/// sport together, so the scope is stated rather than inferred.
class CategoryControl extends StatelessWidget {
  const CategoryControl({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelect,
    required this.playerName,
  });
  final List<Map<String, dynamic>> categories;
  final String? selectedId;
  final void Function(String id) onSelect;
  final String playerName;

  String _tag(Map<String, dynamic> c) {
    final games = statInt(mapOf(c['overall'])['games']);
    if (games > 0) return '· $games game${games == 1 ? '' : 's'}';
    final checkIns = statInt(mapOf(c['attendance'])['checkIns']);
    if (checkIns > 0) {
      return '· $checkIns check-in${checkIns == 1 ? '' : 's'}';
    }
    if (listOf(c['setup']).isNotEmpty) return '· profile only';
    return '· no record';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (categories.isEmpty) return const SizedBox.shrink();
    final current = categories.firstWhere(
      (c) => parseStr(c['categoryId']) == selectedId,
      orElse: () => categories.first,
    );
    final first = playerName.split(' ').first;
    final currentId = parseStr(current['categoryId']);

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Sport',
            style: TextStyle(
                color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: p.surface2,
            borderRadius: BorderRadius.circular(16),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currentId,
              isExpanded: true,
              borderRadius: BorderRadius.circular(16),
              dropdownColor: p.surface,
              menuMaxHeight: 360,
              icon: Icon(Icons.expand_more_rounded, color: p.muted),
              onChanged: (id) {
                if (id != null) onSelect(id);
              },
              // What the closed control shows.
              selectedItemBuilder: (_) => [
                for (final c in categories)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text:
                                '${parseStr(c['emoji']) ?? ''}  ${parseStr(c['name']) ?? 'Sport'}  ',
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w800)),
                        TextSpan(
                            text: _tag(c),
                            style: TextStyle(color: p.muted, fontSize: 12)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              items: [
                for (final c in categories)
                  DropdownMenuItem<String>(
                    value: parseStr(c['categoryId']),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text:
                                '${parseStr(c['emoji']) ?? ''}  ${parseStr(c['name']) ?? 'Sport'}  ',
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                        TextSpan(
                            text: _tag(c),
                            style: TextStyle(color: p.muted, fontSize: 12)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text("Showing $first's ${parseStr(current['name']) ?? 'sport'} record — switch sport any time.",
            style: TextStyle(color: p.muted, fontSize: 12, height: 1.4)),
      ]),
    );
  }
}

/// Shown instead of the record blocks when the player has neither set up nor
/// played this sport — one clear line, not three empty cards.
class NothingOnRecord extends StatelessWidget {
  const NothingOnRecord({super.key, required this.sportName});
  final String sportName;

  @override
  Widget build(BuildContext context) {
    return RecordEmpty(
      icon: Icons.sports_outlined,
      title: 'Nothing on record for $sportName',
      body:
          "They haven't set up a $sportName profile or played a $sportName game on SportPadi yet.",
    );
  }
}

/// True when a category has neither settings, games nor check-ins for this
/// player.
bool nothingOnRecord(Map<String, dynamic> cat) =>
    listOf(cat['setup']).isEmpty &&
    statInt(mapOf(cat['overall'])['games']) == 0 &&
    statInt(mapOf(cat['attendance'])['checkIns']) == 0;

/// What the player has SET UP for this sport — preferred positions, strong
/// foot, and whatever else the category's stat schema asks for (the same data
/// smart balancing reads).
///
/// Every sport asks for something different, which is why the page has to be
/// driven by the category rather than showing one profile with numbers bolted
/// on.
class SportSetup extends StatelessWidget {
  const SportSetup({super.key, required this.category});
  final Map<String, dynamic> category;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fields = listOf(category['setup']);
    if (fields.isEmpty) return const SizedBox.shrink();
    return CollapsibleStatCard(
      storageKey: 'setup',
      title:
          '${parseStr(category['emoji']) ?? ''} ${parseStr(category['name']) ?? 'Sport'} profile',
      summary: fields.map((f) => parseStr(f['value']) ?? '').where((v) => v.isNotEmpty).join(' · '),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final f in fields)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 110,
                child: Text(parseStr(f['label']) ?? '',
                    style: TextStyle(color: p.muted, fontSize: 12)),
              ),
              Expanded(
                child: Text(parseStr(f['value']) ?? '',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// One scope's full record — local games or tournaments — as its own block.
///
/// Deliberately NOT a side-by-side comparison: the two levels are different
/// competitions, and reading them as a race ("12 vs 3") says less than reading
/// each on its own terms.
///
/// 2026 sport records: a thin wrapper over the sport's own design — its
/// record block, then its stats block (and "More stats") — inside a card that
/// folds away (docs/design/sport-records.md §7).
class ScopeBlock extends StatelessWidget {
  const ScopeBlock({
    super.key,
    required this.title,
    required this.tally,
    required this.fields,
    required this.empty,
    this.family = SportFamily.generic,
    this.accent = false,
    this.rank = const {},
    this.collapseKey,
  });
  final String title;
  final Map<String, dynamic> tally;
  final List<Map<String, dynamic>> fields;
  final String empty;

  /// Which sport's design the numbers use.
  final SportFamily family;
  final bool accent;
  final Map<String, dynamic> rank;
  /// Which remembered fold state this card shares (defaults: local /
  /// tournament by `accent`).
  final String? collapseKey;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final games = statInt(tally['games']);
    return CollapsibleStatCard(
      // Remembered per card kind: fold "tournaments" once, it stays folded.
      storageKey: collapseKey ?? (accent ? 'tournament' : 'local'),
      title: title,
      accent: accent,
      trailing: rank.isNotEmpty
          ? SpBadge('#${statInt(rank['rank'])} of ${statInt(rank['of'])}',
              tone: p.accent)
          : null,
      summary: games == 0
          ? empty
          : [
              // Soccer ("P 23 …") and golf ("12 rounds …") already lead
              // their record line with the count.
              if (family != SportFamily.soccer && family != SportFamily.golf)
                gamesPhrase(family, games),
              recordLineFor(family, tally),
            ].join(' · '),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (games == 0)
          Text(empty, style: TextStyle(color: p.muted, fontSize: 12.5))
        else ...[
          SportRecordBlock(family: family, tally: tally),
          const BlockDivider(),
          SportStatsBlock(family: family, fields: fields, tally: tally),
        ],
      ]),
    );
  }
}

/// Tournaments the player took part in, each linking to their squad page.
class TournamentList extends StatelessWidget {
  const TournamentList({
    super.key,
    required this.rows,
    this.title,
    this.playerId,
  });
  final List<Map<String, dynamic>> rows;
  final String? title;

  /// When set, a row opens THIS player's record in that tournament (with the
  /// tournament itself as a secondary chip). Without it, rows open the squad
  /// page, as before.
  final String? playerId;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      RecordSectionTitle(title ?? 'Tournaments', count: rows.length),
      const SizedBox(height: 10),
      RecordList(children: [
        for (final t in rows)
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: playerId != null
                ? () => context
                    .push('/players/$playerId/tournaments/${t['eventId']}')
                : parseStr(t['hostGroupId']) != null
                    ? () => context.push(
                        '/groups/${t['hostGroupId']}/tournaments/${t['eventId']}/teams/${t['teamId']}')
                    : null,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
              child: Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      color: p.orangeTint,
                      borderRadius: BorderRadius.circular(14)),
                  child: Icon(Icons.emoji_events_outlined,
                      size: 20, color: p.orangeInk),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(parseStr(t['title']) ?? 'Tournament',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 1),
                        Text(
                          [
                            parseStr(t['teamName']),
                            if (parseDate(t['eventDate']) != null)
                              formatDayYear(t['eventDate']),
                          ].whereType<String>().join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.muted, fontSize: 12),
                        ),
                      ]),
                ),
                const SizedBox(width: 8),
                Text(
                  statInt(t['games']) > 0
                      ? '${statInt(t['wins'])}-${statInt(t['draws'])}-${statInt(t['losses'])}'
                      : 'Squad',
                  style: TextStyle(
                      color: statInt(t['games']) > 0 ? p.ink : p.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right_rounded, size: 20, color: p.muted),
              ]),
            ),
          ),
      ]),
    ]);
  }
}

/// A stat card whose body folds away. The header stays (title, an optional
/// badge) and, when folded, a one-line summary so the card still says
/// something. The choice is remembered per card kind for the session — fold
/// "tournaments" on one player and it stays folded on the next.
class CollapsibleStatCard extends StatefulWidget {
  const CollapsibleStatCard({
    super.key,
    required this.storageKey,
    required this.title,
    required this.child,
    this.accent = false,
    this.trailing,
    this.summary,
  });
  final String storageKey;
  final String title;
  final Widget child;
  final bool accent;
  final Widget? trailing;
  final String? summary;

  static final Map<String, bool> _remembered = {};

  @override
  State<CollapsibleStatCard> createState() => _CollapsibleStatCardState();
}

class _CollapsibleStatCardState extends State<CollapsibleStatCard> {
  late bool _open = CollapsibleStatCard._remembered[widget.storageKey] ?? true;

  void _toggle() {
    setState(() => _open = !_open);
    CollapsibleStatCard._remembered[widget.storageKey] = _open;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(12),
          child: Row(children: [
            if (widget.accent) ...[
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: p.accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(widget.title,
                  maxLines: 2,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 15.5,
                      height: 1.25,
                      fontWeight: FontWeight.w700)),
            ),
            if (widget.trailing != null) ...[
              widget.trailing!,
              const SizedBox(width: 8),
            ],
            Container(
              width: 30,
              height: 30,
              decoration:
                  BoxDecoration(color: p.surface2, shape: BoxShape.circle),
              child: AnimatedRotation(
                turns: _open ? 0 : -0.25,
                duration: const Duration(milliseconds: 150),
                child: Icon(Icons.expand_more_rounded,
                    size: 20, color: p.muted),
              ),
            ),
          ]),
        ),
        if (_open) ...[
          const SizedBox(height: 12),
          widget.child,
        ] else if ((widget.summary ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: _toggle,
            child: Text(widget.summary!,
                style: TextStyle(color: p.muted, fontSize: 12.5)),
          ),
        ],
      ]),
    );
  }
}


// ── 2026 record-page pieces ─────────────────────────────────────────────────
// Shared by the three "record in …" pages (event, group, tournament) so they
// read as one family: a dark summary card, pill actions, a titled list.

/// A small pill on the dark hero card.
Widget recordHeroPill(String label, Color bg, Color fg, {IconData? icon}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: fg, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ),
      ]),
    );

const Color recordMint = Color(0xFF6EDC9E);

/// The dark summary card at the top of a record page: who, what, where, and
/// the headline numbers.
class RecordHero extends StatelessWidget {
  const RecordHero({
    super.key,
    required this.name,
    required this.title,
    this.avatarUrl,
    this.nameSub,
    this.onPlayerTap,
    this.status,
    this.statusLive = false,
    this.eyebrow,
    this.meta,
    this.stats = const [],
    this.pills = const [],
    this.family,
    this.emoji,
  });
  final String name;
  final String? avatarUrl;
  final String? nameSub;
  final VoidCallback? onPlayerTap;
  final String? status;
  final bool statusLive;
  final String? eyebrow;
  final String title;
  final String? meta;

  /// (value, label). The first one is highlighted.
  final List<(String, String)> stats;
  final List<Widget> pills;

  /// The sport of the record shown: paints its artwork (design §4) behind
  /// the card. Null keeps the plain dark card.
  final SportFamily? family;

  /// The category's emoji — the generic artwork's watermark.
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final art = family;
    final accent = art == null ? recordMint : sportTheme(art).accent;
    final content = _content(p, accent, art != null);
    if (art != null) {
      return SportArtPanel(
        family: art,
        emoji: emoji,
        padding: const EdgeInsets.all(18),
        child: content,
      );
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.hero,
        borderRadius: BorderRadius.circular(28),
      ),
      child: content,
    );
  }

  Widget _content(AppPalette p, Color accent, bool painted) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          InkWell(
            onTap: onPlayerTap,
            customBorder: const CircleBorder(),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: accent, width: 2),
              ),
              child: ClipOval(
                child: Crest(
                    logoUrl: avatarUrl,
                    label: name.split(' ').first,
                    size: 40),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.onHero,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  Text(nameSub ?? 'View profile',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.heroMuted, fontSize: 12)),
                ]),
          ),
          if (status != null)
            recordHeroPill(
                status!,
                statusLive ? const Color(0xFFE02424) : p.onHero.withAlpha(28),
                p.onHero),
        ]),
        const SizedBox(height: 16),
        if (eyebrow != null && eyebrow!.isNotEmpty) ...[
          Text(eyebrow!.toUpperCase(),
              style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
        ],
        Text(title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: p.onHero,
                fontSize: 20,
                height: 1.25,
                fontWeight: FontWeight.w800)),
        if (meta != null && meta!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(meta!,
              style:
                  TextStyle(color: p.heroMuted, fontSize: 12.5, height: 1.4)),
        ],
        if (stats.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(children: [
            for (var i = 0; i < stats.length; i++)
              Expanded(
                child: Container(
                  margin: EdgeInsets.only(left: i == 0 ? 0 : 8),
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                  decoration: BoxDecoration(
                    color: painted
                        ? const Color(0x38000000)
                        : p.onHero.withAlpha(18),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(stats[i].$1,
                          maxLines: 1,
                          style: TextStyle(
                              color: i == 0 ? accent : p.onHero,
                              fontSize: 22,
                              fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 2),
                    Text(stats[i].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.heroMuted, fontSize: 11)),
                  ]),
                ),
              ),
          ]),
        ],
        if (pills.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: pills),
        ],
      ]);
  }
}

/// The hero's numbers for a tally: W–D–L, then the sport's first two stats
/// (goals, assists… whatever it defines), or win rate when it defines none.
List<(String, String)> recordHeroStats(
    Map<String, dynamic> tally, List<Map<String, dynamic>> fields) {
  final counts = mapOf(tally['counts']);
  return [
    (
      '${statInt(tally['wins'])}-${statInt(tally['draws'])}-${statInt(tally['losses'])}',
      'W–D–L'
    ),
    for (final f in fields.take(2))
      ('${statInt(counts[parseStr(f['key'])])}', parseStr(f['label']) ?? ''),
    if (fields.isEmpty) ('${statInt(tally['winRate'])}%', 'Win rate'),
  ];
}

/// A full-width pill action under the hero ("Open event", "Squad"…).
class RecordAction extends StatelessWidget {
  const RecordAction(
      {super.key,
      required this.label,
      required this.icon,
      required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: p.line),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: p.ink),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Up to two actions side by side.
Widget recordActions(List<RecordAction> actions) => Row(children: [
      for (var i = 0; i < actions.length; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(child: actions[i]),
      ],
    ]);

/// "Games  3" — a section title with a count chip.
class RecordSectionTitle extends StatelessWidget {
  const RecordSectionTitle(this.title, {super.key, this.count, this.trailing});
  final String title;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // The title shrinks (ellipsis) before anything overflows — titles carry
    // sport names ("American football tournaments") on a 360dp screen.
    return Row(children: [
      Expanded(
        child: Row(children: [
          Flexible(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: p.ink, fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: p.surface2, borderRadius: BorderRadius.circular(999)),
              child: Text('$count',
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
      ),
      if (trailing != null) trailing!,
    ]);
  }
}

/// One white card of rows separated by hairlines.
class RecordList extends StatelessWidget {
  const RecordList({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Divider(
                height: 1,
                thickness: 1,
                indent: 12,
                endIndent: 12,
                color: p.surface2),
          children[i],
        ],
      ]),
    );
  }
}

/// One game in a record: a W/D/L tile, who played whom, what the player did,
/// the score. [pendingLabel] is what a game that hasn't started says.
class RecordMatchRow extends StatelessWidget {
  const RecordMatchRow({
    super.key,
    required this.match,
    required this.fields,
    this.pendingLabel = 'Not started',
    this.opponentFallback = 'Field',
  });
  final Map<String, dynamic> match;
  final List<Map<String, dynamic>> fields;
  final String pendingLabel;
  final String opponentFallback;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final m = match;
    final us = mapOf(m['us']);
    final them = m['them'] is Map ? mapOf(m['them']) : null;
    final status = parseStr(m['status']) ?? 'scheduled';
    final result = parseStr(m['result']);
    final counts = mapOf(m['counts']);
    final contrib = [
      for (final f in fields)
        if (statInt(counts[parseStr(f['key'])]) > 0)
          '${statInt(counts[parseStr(f['key'])])} ${(parseStr(f['label']) ?? '').toLowerCase()}'
    ].join(' · ');
    final sub = [
      status == 'completed'
          ? (m['started'] == true ? 'Started' : 'From the bench')
          : status == 'live'
              ? 'Live now'
              : pendingLabel,
      if (contrib.isNotEmpty) contrib,
    ].join(' · ');

    final (tileBg, tileFg, tileText) = switch (result) {
      'win' => (p.accentTint, p.greenText, 'W'),
      'loss' => (p.liveTint, p.danger, 'L'),
      'draw' => (p.surface2, p.muted, 'D'),
      _ => status == 'live'
          ? (p.liveTint, p.danger, '•')
          : (p.surface2, p.muted, '–'),
    };

    return InkWell(
      onTap: () => context.push('/games/${m['gameId']}'),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: tileBg, borderRadius: BorderRadius.circular(14)),
            child: Text(tileText,
                style: TextStyle(
                    color: tileFg, fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      '${parseStr(us['name']) ?? 'Us'} vs ${parseStr(them?['name']) ?? opponentFallback}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 1),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontSize: 12)),
                ]),
          ),
          const SizedBox(width: 8),
          Text(
              status == 'scheduled'
                  ? '–'
                  : '${statInt(us['score'])}–${statInt(them?['score'])}',
              style: TextStyle(
                  color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(width: 2),
          Icon(Icons.chevron_right_rounded, size: 20, color: p.muted),
        ]),
      ),
    );
  }
}

/// A centred empty state inside a card: icon tile, title, one line.
class RecordEmpty extends StatelessWidget {
  const RecordEmpty(
      {super.key, required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GlassCard(
      padding: const EdgeInsets.all(22),
      child: Column(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
              color: p.surface2, borderRadius: BorderRadius.circular(18)),
          child: Icon(icon, size: 25, color: p.muted),
        ),
        const SizedBox(height: 12),
        Text(title,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: p.ink, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(body,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.45)),
      ]),
    );
  }
}

/// The stats routes answer 403 when the player is a ward whose guardians
/// keep their record private from this viewer.
bool isPrivateRecordError(Object? e) =>
    e is ApiException && e.statusCode == 403;

/// What a record page shows instead of numbers the viewer may not see.
class PlayerPrivateView extends StatelessWidget {
  const PlayerPrivateView({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
      children: [
        SpHeader(title: title),
        const SizedBox(height: 40),
        Center(
          child: SpIconTile(Icons.lock_outline_rounded,
              bg: p.wardTint, fg: p.wardInk, size: 56, iconSize: 26),
        ),
        const SizedBox(height: 14),
        Text('This record is private',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: p.ink, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text("Their guardians manage who can see this player's stats.",
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.4)),
      ],
    );
  }
}
