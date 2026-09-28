import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
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

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: p.accent.withAlpha(16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.accent.withAlpha(70)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('VIEWING RECORD FOR',
            style: TextStyle(
                color: p.accent,
                fontSize: 9.5,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.accent.withAlpha(120)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currentId,
              isExpanded: true,
              borderRadius: BorderRadius.circular(12),
              dropdownColor: p.surface,
              menuMaxHeight: 360,
              icon: Icon(Icons.expand_more_rounded, color: p.accent),
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
        Text.rich(
          TextSpan(children: [
            TextSpan(
                text: "$first's ${parseStr(current['name']) ?? 'sport'} record",
                style: TextStyle(
                    color: p.ink, fontSize: 13, fontWeight: FontWeight.w700)),
            TextSpan(
                text: " — pick any sport above to see $first's record in it.",
                style: TextStyle(color: p.muted, fontSize: 12.5)),
          ]),
        ),
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
    final p = context.palette;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(children: [
        Text('Nothing on record for $sportName',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          "They haven't set up a $sportName profile or played a $sportName game on SportPadi yet.",
          textAlign: TextAlign.center,
          style: TextStyle(color: p.muted, fontSize: 12, height: 1.35),
        ),
      ]),
    );
  }
}

/// True when a category has neither settings nor games for this player.
bool nothingOnRecord(Map<String, dynamic> cat) =>
    listOf(cat['setup']).isEmpty && statInt(mapOf(cat['overall'])['games']) == 0;

Widget _tile(AppPalette p, String label, String value, {String? hint}) =>
    Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.line),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: p.ink, fontSize: 17, fontWeight: FontWeight.w900)),
        Text(label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: p.muted,
                fontSize: 9,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w700)),
        if (hint != null)
          Text(hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 9.5)),
      ]),
    );

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
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            '${parseStr(category['emoji']) ?? ''} ${parseStr(category['name']) ?? 'Sport'} PROFILE'
                .toUpperCase(),
            style: TextStyle(
                color: p.muted,
                fontSize: 9.5,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
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
/// each on its own terms. Every metric the sport defines is shown, zeros
/// included — no cards is a fact worth seeing, not an absence to hide.
class ScopeBlock extends StatelessWidget {
  const ScopeBlock({
    super.key,
    required this.title,
    required this.tally,
    required this.fields,
    required this.empty,
    this.accent = false,
    this.rank = const {},
  });
  final String title;
  final Map<String, dynamic> tally;
  final List<Map<String, dynamic>> fields;
  final String empty;
  final bool accent;
  final Map<String, dynamic> rank;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final counts = mapOf(tally['counts']);
    final games = statInt(tally['games']);
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(title.toUpperCase(),
                maxLines: 2,
                style: TextStyle(
                    color: accent ? p.accent : p.muted,
                    fontSize: 9.5,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w800)),
          ),
          if (rank.isNotEmpty)
            SpBadge('#${statInt(rank['rank'])} of ${statInt(rank['of'])}',
                tone: p.accent),
        ]),
        const SizedBox(height: 8),
        if (games == 0)
          Text(empty, style: TextStyle(color: p.muted, fontSize: 12.5))
        else ...[
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            childAspectRatio: 1.5,
            children: [
              _tile(p, 'Games', '$games'),
              _tile(p, 'Starts', '${statInt(tally['starts'])}'),
              // W–D–L as ONE tile, not three: it reads as a record, and
              // separate boxes beside it would state the same thing twice.
              _tile(p, 'W–D–L',
                  '${statInt(tally['wins'])}-${statInt(tally['draws'])}-${statInt(tally['losses'])}'),
              _tile(p, 'Win rate', '${statInt(tally['winRate'])}%'),
              _tile(p, 'Points', '${statInt(tally['points'])}', hint: '3/1/0'),
            ],
          ),
          if (fields.isNotEmpty) ...[
            const SizedBox(height: 6),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 1.5,
              children: [
                for (final f in fields)
                  _tile(
                    p,
                    '${parseStr(f['icon']) != null ? '${f['icon']} ' : ''}${parseStr(f['label']) ?? ''}',
                    '${statInt(counts[parseStr(f['key'])])}',
                  ),
              ],
            ),
          ],
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
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${title ?? 'TOURNAMENTS'} (${rows.length})',
            style: TextStyle(
                color: p.muted,
                fontSize: 9.5,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final t in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: p.line),
              ),
              child: Row(children: [
                Expanded(
                  child: InkWell(
                    onTap: playerId != null
                        ? () => context.push(
                            '/players/$playerId/tournaments/${t['eventId']}')
                        : parseStr(t['hostGroupId']) != null
                            ? () => context.push(
                                '/groups/${t['hostGroupId']}/tournaments/${t['eventId']}/teams/${t['teamId']}')
                            : null,
                    child: Row(children: [
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
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  parseStr(t['teamName']),
                                  parseStr(t['hostGroupName']),
                                  if (parseDate(t['eventDate']) != null)
                                    formatDayYear(t['eventDate']),
                                ].whereType<String>().join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: p.muted, fontSize: 11),
                              ),
                              if (playerId != null)
                                Text('See their record here',
                                    style: TextStyle(color: p.muted, fontSize: 10.5)),
                            ]),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        statInt(t['games']) > 0
                            ? '${statInt(t['games'])} gm\n${statInt(t['wins'])}W ${statInt(t['draws'])}D ${statInt(t['losses'])}L'
                            : 'squad',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: p.muted, fontSize: 10.5),
                      ),
                    ]),
                  ),
                ),
                if (playerId != null && parseStr(t['hostGroupId']) != null) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => context.push(
                        '/groups/${t['hostGroupId']}/tournaments/${t['eventId']}'),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: p.line),
                      ),
                      child: Icon(Icons.north_east_rounded, size: 14, color: p.muted),
                    ),
                  ),
                ],
              ]),
            ),
          ),
      ]),
    );
  }
}
