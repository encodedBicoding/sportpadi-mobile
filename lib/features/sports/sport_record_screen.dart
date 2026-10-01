import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/players/player_profile_screen.dart';
import 'package:sportpadi_mobile/features/players/player_record.dart';
import 'package:sportpadi_mobile/features/sports/attendance_blocks.dart';
import 'package:sportpadi_mobile/features/sports/form_strip.dart';
import 'package:sportpadi_mobile/features/sports/personal_bests.dart';
import 'package:sportpadi_mobile/features/sports/recent_games.dart';
import 'package:sportpadi_mobile/features/sports/scope_switch.dart';
import 'package:sportpadi_mobile/features/sports/sport_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_hero.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// One player's record in ONE sport (design §3) — `/players/:id/records/:cat`
/// for anyone, `/profile/records/:cat` for the signed-in player.
///
/// Shared layout, bespoke content: the hero, the scope switch, then the
/// sport's own record and stats blocks, form, recent games, personal bests
/// and where they play. Hiking and running (§8) lead with their check-ins
/// instead: twelve months of outings, then recent outings, then any races.
class SportRecordScreen extends ConsumerStatefulWidget {
  const SportRecordScreen({
    super.key,
    required this.userId,
    required this.categoryId,
    this.isMe = false,
  });
  final String userId;
  final String categoryId;

  /// The owner's own view: "View as others see it" and "Edit my … profile".
  final bool isMe;

  @override
  ConsumerState<SportRecordScreen> createState() => _SportRecordScreenState();
}

class _SportRecordScreenState extends ConsumerState<SportRecordScreen> {
  RecordScope _scope = RecordScope.all;

  String get _userId => widget.userId;

  Future<void> _refresh() async {
    ref
      ..invalidate(playerProfileProvider(_userId))
      ..invalidate(playerRecordsProvider(_userId));
    // Errors show on the page itself; the spinner just stops.
    await ref
        .read(playerRecordsProvider(_userId).future)
        .then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final profileAsync = ref.watch(playerProfileProvider(_userId));
    final statsAsync = ref.watch(playerRecordsProvider(_userId));
    // A ward whose guardians keep their record private from this viewer.
    final restricted = profileAsync.valueOrNull?['restricted'] == true;

    if (restricted || isPrivateRecordError(statsAsync.error)) {
      return Scaffold(
        backgroundColor: p.bg,
        body: const SafeArea(
          bottom: false,
          child: PlayerPrivateView(title: 'Record'),
        ),
      );
    }

    final stats = statsAsync.valueOrNull;
    if (stats == null) {
      // Loading, or failed: a plain header over the spinner / retry.
      return Scaffold(
        backgroundColor: p.bg,
        body: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            children: [
              const SpHeader(title: 'Record'),
              const SizedBox(height: 32),
              AsyncView(
                value: statsAsync,
                onRetry: () => ref.invalidate(playerRecordsProvider(_userId)),
                data: (_) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }

    Map<String, dynamic>? cat;
    for (final c in listOf(stats['categories'])) {
      if (parseStr(c['categoryId']) == widget.categoryId) {
        cat = c;
        break;
      }
    }
    if (cat == null) {
      return Scaffold(
        backgroundColor: p.bg,
        body: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            children: const [
              SpHeader(title: 'Record'),
              SizedBox(height: 24),
              RecordEmpty(
                icon: Icons.sports_outlined,
                title: 'Sport not found',
                body: "This sport isn't on SportPadi any more.",
              ),
            ],
          ),
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The hero is dark in both themes.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: p.bg,
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: _body(context, p, stats, cat,
              mapOf(profileAsync.valueOrNull?['profile'])),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppPalette p, Map<String, dynamic> stats,
      Map<String, dynamic> cat, Map<String, dynamic> profile) {
    final isMe = widget.isMe;
    final family = familyOf(cat);
    final name = parseStr(cat['name']) ?? 'Sport';
    final catId = parseStr(cat['categoryId']) ?? widget.categoryId;
    final overall = tallyOf(cat, RecordScope.all);
    final hasGames = gamesOf(overall) > 0;
    // Check-ins to the sport's events (§8): hikes and runs lead with them;
    // every other sport shows them as a "Showing up" strip.
    final att = attendanceOf(cat);
    final checkIns = statInt(att['checkIns']);
    final outings = listOf(att['recent']);
    final attendanceSport = isAttendanceDesign(family);
    final hasRecord = hasGames || checkIns > 0;
    final counts = {
      for (final s in RecordScope.values) s: gamesOf(tallyOf(cat, s)),
    };
    // A scope that has emptied (after a refresh) falls back to All.
    final scope = (counts[_scope] ?? 0) > 0 ? _scope : RecordScope.all;
    final tally = tallyOf(cat, scope);
    final recent = recentOf(cat, scope);
    final rawFields = listOf(cat['fields']);
    final fields = statFields(cat['fields'], family);
    final groups = listOf(cat['groups']);
    final tournaments = [
      for (final t in listOf(stats['tournaments']))
        if (parseStr(t['categoryId']) == catId) t
    ];

    final me =
        isMe ? ref.watch(authControllerProvider).valueOrNull?.user : null;
    final playerName =
        parseStr(profile['displayName']) ?? parseStr(me?.name) ?? 'Player';
    final avatarUrl = parseStr(profile['avatarUrl']) ?? me?.image;
    final they = isMe ? 'you' : 'they';

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        SportHero(
          category: cat,
          family: family,
          tally: overall,
          recent: recentOf(cat, RecordScope.all),
          playerName: playerName,
          avatarUrl: avatarUrl,
          onPlayerTap: () => context.push('/players/$_userId'),
          onViewAsOthers: isMe
              ? () => context.push('/players/$_userId/records/$catId')
              : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!hasRecord)
                RecordEmpty(
                  icon: Icons.sports_outlined,
                  title: attendanceSport
                      ? 'No $name outings on record yet.'
                      : 'No $name games on record yet.',
                  body: attendanceSport
                      ? (isMe
                          ? 'Check in to a $name event and it starts counting here.'
                          : 'Their outings appear here once they check in to a $name event.')
                      : (isMe
                          ? 'Finish a $name game on SportPadi and your numbers start here.'
                          : "Their numbers appear here once they've finished a $name game."),
                )
              else ...[
                // Hikes and runs lead with showing up: twelve months of
                // check-ins, then the outings themselves.
                if (attendanceSport && checkIns > 0) ...[
                  GlassCard(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          BlockHeading(
                              family == SportFamily.running
                                  ? 'Runs by month'
                                  : 'Hikes by month',
                              trailing: Text(
                                  plural(checkIns, outingNoun(family)),
                                  style: TextStyle(
                                      color: p.muted,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600))),
                          const SizedBox(height: 14),
                          AttendanceBlock(family: family, attendance: att),
                        ]),
                  ),
                  if (outings.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    RecentOutings(family: family, outings: outings),
                  ],
                  if (hasGames) ...[
                    const SizedBox(height: 24),
                    RecordSectionTitle(
                        family == SportFamily.running ? 'Races' : 'Games',
                        count: gamesOf(overall)),
                    const SizedBox(height: 10),
                  ],
                ],
                if (hasGames) ...[
                  SportScopeSwitch(
                    value: scope,
                    counts: counts,
                    onChanged: (s) => setState(() => _scope = s),
                  ),
                  const SizedBox(height: 16),

                  // The sport's own way of writing a record.
                  GlassCard(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          BlockHeading(recordBlockTitle(family),
                              trailing: Text(
                                  '${scope.label} · ${gamesPhrase(family, gamesOf(tally))}',
                                  style: TextStyle(
                                      color: p.muted,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600))),
                          const SizedBox(height: 14),
                          SportRecordBlock(
                              family: family, tally: tally, recent: recent),
                        ]),
                  ),
                  const SizedBox(height: 12),

                  // What they do, the way the sport reads it.
                  GlassCard(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                    child: SportStatsBlock(
                        family: family, fields: rawFields, tally: tally),
                  ),

                  // Showing up, for a sport whose record leads with games.
                  if (!attendanceSport && checkIns > 0) ...[
                    const SizedBox(height: 12),
                    ShowingUpStrip(attendance: att),
                  ],

                  if (recent.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    FormStrip(
                        recent: recent, chess: family == SportFamily.chess),
                    const SizedBox(height: 24),
                    RecentGames(
                      family: family,
                      games: recent,
                      fields: fields,
                      playerId: _userId,
                    ),
                  ],

                  PersonalBests(
                    family: family,
                    bests: bestsOf(cat, scope),
                    fields: fields,
                    top: 24,
                  ),
                ] else if (!attendanceSport) ...[
                  // Check-ins to this sport's events, but no games yet.
                  ShowingUpStrip(attendance: att),
                  if (outings.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    RecentOutings(
                        family: family,
                        outings: outings,
                        title: 'Recent check-ins'),
                  ],
                ],

                // Where they play: their groups (local and all), or the
                // tournaments in Tournaments.
                if (scope != RecordScope.tournament && groups.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  RecordSectionTitle('Where $they play', count: groups.length),
                  const SizedBox(height: 10),
                  RecordList(children: [
                    for (final g in groups)
                      _GroupRow(
                        name: parseStr(g['name']) ?? 'Group',
                        sub: isMe ? 'Your record here' : 'Their record here',
                        onTap: () => context.push(
                            '/players/$_userId/groups/${parseStr(g['id'])}'),
                      ),
                  ]),
                ],
                if (hasGames &&
                    scope == RecordScope.tournament &&
                    tournaments.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  TournamentList(
                      rows: tournaments,
                      title: '$name tournaments',
                      playerId: _userId),
                ],
              ],
              if (isMe) ...[
                const SizedBox(height: 24),
                SpButton(
                  label: 'Edit my $name profile',
                  icon: Icons.tune_rounded,
                  expand: true,
                  onTap: () => context.push('/profile/sports'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.name, required this.sub, required this.onTap});
  final String name;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(children: [
          SpIconTile(Icons.groups_rounded,
              bg: p.accentTint, fg: p.greenText, size: 40, iconSize: 19),
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
          Icon(Icons.chevron_right_rounded, size: 20, color: p.muted),
        ]),
      ),
    );
  }
}
