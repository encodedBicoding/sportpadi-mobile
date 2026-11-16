import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/games/game_models.dart';
import 'package:sportpadi_mobile/data/games/games_repository.dart';
import 'package:sportpadi_mobile/data/games/live_game_controller.dart';
import 'package:sportpadi_mobile/data/highlights/highlight_models.dart'
    show GameHighlightRef;
import 'package:sportpadi_mobile/data/highlights/highlights_repository.dart'
    show gameHighlightsProvider;
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/events/event_mvp_card.dart';
import 'package:sportpadi_mobile/features/games/basketball_widgets.dart';
import 'package:sportpadi_mobile/features/games/officiant_panel.dart';
import 'package:sportpadi_mobile/features/games/officiants_card.dart';
import 'package:sportpadi_mobile/features/games/post_match_cards.dart';
import 'package:sportpadi_mobile/features/games/scoreboard_widgets.dart';
import 'package:sportpadi_mobile/features/games/timeout_widgets.dart';
import 'package:sportpadi_mobile/features/games/volleyball_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/features/ads/ad_anchor.dart';
import 'package:sportpadi_mobile/shared/widgets/player_link.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// `?stat=` — and the stat a reel hands back on its pop — is an activity
/// uuid or nothing: anything else names no row, so nothing is walked. The
/// rule the web keeps (`isUuid(stat)`, `components/highlights/shared.ts`) and
/// the reel's own (`highlight_detail_screen.dart` `_reelUuid`), so one
/// grammar is read the same way on both clients (T8 review LOW-F).
final _statUuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false);

/// Live game screen — a faithful port of the web GameClient layout:
/// scoreboard card with the clock strip, draw-resolution + shootout cards,
/// officiants, admin controls, timeline, and side-by-side lineups.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, required this.gameId, this.stat});
  final String gameId;

  /// `?stat=<activityId>` — a timeline row to land on, not just the match.
  /// A match reel that had nothing to pop sends the viewer here with it, and
  /// the web writes the same parameter on the same path (`gameStatHref`), so
  /// both clients come back the same way (docs/wiki/highlights.md, "The
  /// match reel").
  final String? stat;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  /// The page's own scroller, so a stat's row can be brought into view.
  final _scroll = ScrollController();

  /// One key per timeline row, by stat id. The screen keeps them because a
  /// GlobalKey minted in `build` would be a new one every build; the rows
  /// themselves are `_TimelineCard`'s.
  final _rowKeys = <String, GlobalKey>{};

  /// `?stat=` is honoured once: the live subscription hands the match back
  /// on every score (the web's `jumpedToStat`, for the same reason).
  bool _jumpedToStat = false;

  /// Which walk owns the scroller. Two at once — a `?stat=` arrival and a
  /// reel's pop return, or two quick taps — fought over it, and the loser
  /// putting the offset back undid the winner's landing (T8 review LOW-H).
  /// The newest wins; an older one stops at its next step and restores
  /// nothing.
  int _walk = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Bring a stat's timeline row into view — where a match reel ends.
  ///
  /// Popping the reel restores the timeline's scroll OFFSET, not a row, so
  /// anything that changed height above the stat while they watched (a stat
  /// recorded, a stat voided) leaves them in the wrong place: the row itself
  /// is re-found. The page's list builds lazily, so a row off screen has no
  /// context yet — walk a screen at a time until it has one: DOWN from where
  /// they are (which also covers arriving at the top with `?stat=`), then
  /// back UP from there, because a timeline that SHRANK leaves the restored
  /// offset BELOW the row — the very case this was built for, and the one it
  /// used to miss (T8 review LOW-G). Bounded both ways: a timeline that
  /// never reaches the row is put back where they left it.
  Future<void> _scrollToStat(String activityId) async {
    if (!_statUuid.hasMatch(activityId)) return;
    final walk = ++_walk;
    // A `?stat=` arrival can land before the match has: there is no list to
    // walk yet.
    for (var wait = 0; wait < 24; wait++) {
      if (!mounted || walk != _walk) return;
      if (_scroll.hasClients || _rowKeys[activityId]?.currentContext != null) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted || walk != _walk) return;
    final from = _scroll.hasClients ? _scroll.position.pixels : null;
    var row = await _walkToStat(activityId, walk, down: true);
    if (row == null) {
      if (!mounted || walk != _walk) return;
      // Not below them, so try above: back to where they were first, or the
      // walk up would start from the bottom of the match.
      if (from != null && _scroll.hasClients) _scroll.jumpTo(from);
      row = await _walkToStat(activityId, walk, down: false);
    }
    if (!mounted || walk != _walk) return;
    // The context belongs to the ROW, not to this State: this State's
    // `mounted` says nothing about it (T8 review LOW-I).
    if (row != null && row.mounted) {
      await Scrollable.ensureVisible(row,
          alignment: 0.35, duration: const Duration(milliseconds: 250));
      return;
    }
    // The row never turned up — its stat was voided while they watched, say.
    // Leave the page where they left it, not at an end of the match.
    if (from != null && _scroll.hasClients) _scroll.jumpTo(from);
  }

  /// One direction of [_scrollToStat]'s walk: a bounded number of 80 %-of-a-
  /// viewport jumps, one per frame, until the row has a context. Answers that
  /// context — or null, the scroller having reached its edge, the list having
  /// gone, or a newer walk having taken over.
  Future<BuildContext?> _walkToStat(String activityId, int walk,
      {required bool down}) async {
    for (var step = 0; step < 24; step++) {
      if (!mounted || walk != _walk) return null;
      final row = _rowKeys[activityId]?.currentContext;
      if (row != null && row.mounted) return row;
      if (!_scroll.hasClients) return null;
      final pos = _scroll.position;
      final edge = down ? pos.maxScrollExtent : pos.minScrollExtent;
      if (down ? pos.pixels >= edge : pos.pixels <= edge) return null;
      final step80 = pos.viewportDimension * 0.8;
      final to = down ? pos.pixels + step80 : pos.pixels - step80;
      _scroll.jumpTo(down ? (to > edge ? edge : to) : (to < edge ? edge : to));
      await WidgetsBinding.instance.endOfFrame;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final gameId = widget.gameId;
    final p = context.palette;
    final game = ref.watch(liveGameProvider(gameId));
    final g0 = game.valueOrNull;
    // Coming back from a match reel with nothing to pop (a link that opened
    // straight into one): `?stat=` is the row whose badge opened it. Once
    // the match has loaded, and once only.
    final stat = widget.stat;
    if (!_jumpedToStat &&
        g0 != null &&
        stat != null &&
        _statUuid.hasMatch(stat)) {
      _jumpedToStat = true;
      // Named, so the closure takes a plain String and not a promoted one.
      final row = stat;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToStat(row));
    }
    final kind = g0 == null
        ? null
        : g0.leagueSlug != null
            ? (g0.firstLeg.isNotEmpty && g0.teams.length == 2
                ? context.l10n.game_leagueMatch2ndLegAgg(g0.aggregateFor(g0.teams[0].teamId), g0.aggregateFor(g0.teams[1].teamId))
                : context.l10n.game_leagueMatch)
            : g0.isTournament
                ? context.l10n.game_tournamentMatch
                : context.l10n.game_localGame;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: SpHeader(
              title: g0?.categoryName != null
                  ? '${g0!.categoryEmoji != null ? '${g0.categoryEmoji} ' : ''}${g0.categoryName}'
                  : context.l10n.game_match,
              subtitle: kind,
              actions: [
                if (g0?.leagueSlug != null)
                  SpRoundButton(
                    icon: Icons.format_list_numbered_rounded,
                    tooltip: context.l10n.game_leagueTable,
                    onTap: () => context.push('/leagues/${g0!.leagueSlug}'),
                  ),
                // The event this game belongs to, one tap away.
                if (g0 != null && !g0.isTournament && g0.eventSlug != null)
                  SpRoundButton(
                    icon: Icons.event_outlined,
                    tooltip: context.l10n.game_openEvent,
                    onTap: () => context.push('/events/${g0.eventSlug}'),
                  ),
              ],
            ),
          ),
          // Semantics for the whole app are excluded at the root (see
          // app.dart) to dodge this Flutter build's
          // '!semantics.parentDataDirty' bug.
          Expanded(
            child: AsyncView(
              value: game,
              onRetry: () => ref.invalidate(liveGameProvider(gameId)),
              data: (g) => RefreshIndicator(
                onRefresh: () {
                  // The timeline's highlight badges come from their own read.
                  ref.invalidate(gameHighlightsProvider(gameId));
                  return ref.read(liveGameProvider(gameId).notifier).refresh();
                },
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
                  children: [
                    _Scoreboard(game: g),
                    // Basketball shot clock + team timeouts (volleyball too).
                    if (g.isLive && g.basketball?.shotClock != null) ...[
                      const SizedBox(height: 12),
                      ShotClockPanel(
                        game: g,
                        onReset: g.canTime
                            ? (short) => _gameAct(
                                context,
                                ref,
                                gameId,
                                () => ref
                                    .read(gamesRepositoryProvider)
                                    .shotClock(gameId, short: short))
                            : null,
                      ),
                    ],
                    if (g.isLive && (g.isBasketball || g.isVolleyball)) ...[
                      const SizedBox(height: 12),
                      TimeoutBar(
                        game: g,
                        onAction: (g.isBasketball
                                ? g.canTime
                                : (g.canTime || g.canScore))
                            ? (teamId, action) => _gameAct(
                                context,
                                ref,
                                gameId,
                                () => ref
                                    .read(gamesRepositoryProvider)
                                    .timeout(gameId, teamId, action))
                            : null,
                      ),
                    ],
                    // Volleyball: change ends / start the next set / end it.
                    if (g.isLive &&
                        g.isVolleyball &&
                        (g.volleyball!.matchWinnerTeamId != null ||
                            g.volleyball!.currentSetDecided ||
                            g.volleyball!.switchSidesDue)) ...[
                      const SizedBox(height: 12),
                      VolleyballSetCard(
                        game: g,
                        onStartNext: g.canTime || g.canScore
                            ? () => _gameAct(
                                context,
                                ref,
                                gameId,
                                () => ref
                                    .read(gamesRepositoryProvider)
                                    .volleyballSet(gameId, 'startNext'))
                            : null,
                        onSwitched: g.canTime || g.canScore
                            ? () => _gameAct(
                                context,
                                ref,
                                gameId,
                                () => ref
                                    .read(gamesRepositoryProvider)
                                    .volleyballSet(gameId, 'sidesSwitched'))
                            : null,
                        onEnd: g.canTime
                            ? () => _gameAct(
                                context,
                                ref,
                                gameId,
                                () => ref
                                    .read(gamesRepositoryProvider)
                                    .complete(gameId))
                            : null,
                      ),
                    ],
                    // First-to-N basketball: someone has won — end it.
                    if (g.isBasketball &&
                        g.isLive &&
                        g.basketball!.targetWinnerTeamId != null) ...[
                      const SizedBox(height: 12),
                      TargetReachedCard(
                        game: g,
                        onEnd: g.canTime
                            ? () async {
                                try {
                                  await ref
                                      .read(gamesRepositoryProvider)
                                      .complete(gameId);
                                  await ref
                                      .read(liveGameProvider(gameId).notifier)
                                      .refresh();
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('$e')));
                                  }
                                }
                              }
                            : null,
                      ),
                    ],
                    // One ad at most, right after the scoreboard (and the
                    // live clock / timeout / set cards when there are any) —
                    // owner console anchor "game.detail_mid", placed like
                    // the other detail pages: after the lead card, not at
                    // the bottom. Never while THIS viewer is scoring a live
                    // match: the tap controls sit around it (accidental-
                    // click risk).
                    if (!(g.canScore && g.isLive))
                      AdAnchor(
                          anchor: 'game.detail_mid',
                          padding: const EdgeInsets.only(top: 12),
                          // Page links ({game.id}, {event.slug}) open THIS game / event.
                          context: {
                            'game': {'id': gameId},
                            if (g.eventSlug != null)
                              'event': {'slug': g.eventSlug!},
                          }),
                    if (g.status == 'completed') ...[
                      // Web order (GameClient): MVP vote + awards, then
                      // "Your match" for players, then the post-match
                      // summary, which replaces the lineups.
                      // Tournament / league matches: MVP vote (24h) then
                      // the awards — same card as a group event's.
                      const SizedBox(height: 12),
                      EventMvpCard(gameId: gameId),
                      // Your match — XP, your stats, unlocks (players only).
                      YourMatchCard(gameId: gameId),
                      const SizedBox(height: 12),
                      if (g.isBasketball)
                        BasketballSummary(game: g)
                      else if (g.isVolleyball)
                        VolleyballSummary(game: g)
                      else ...[
                        _SummaryCard(game: g),
                        // Per team: totals, scorers, contributions.
                        PostMatchTeamCards(game: g),
                      ],
                      // Kudos — tag a teammate for the work no stat records.
                      KudosCard(gameId: gameId, game: g),
                    ],
                    if (g.canTime && _awaitingDraw(g)) ...[
                      const SizedBox(height: 12),
                      _DrawCard(gameId: gameId, game: g),
                    ],
                    if (_penaltiesAdded(g) && g.isLive) ...[
                      const SizedBox(height: 12),
                      _ShootoutCard(gameId: gameId, game: g),
                    ],
                    // Officiants — call people in, split jobs, step down.
                    if (g.officiants.isNotEmpty || g.officiating.canCallIn) ...[
                      const SizedBox(height: 12),
                      OfficiantsCard(gameId: gameId, game: g),
                    ],
                    if (g.canManage) ...[
                      const SizedBox(height: 12),
                      OfficiantPanel(gameId: gameId, game: g),
                    ],
                    const SizedBox(height: 12),
                    _TimelineCard(
                      game: g,
                      gameId: gameId,
                      rowKeys: _rowKeys,
                      onStatReturn: _scrollToStat,
                    ),
                    // Basketball: line score + box score while it's played.
                    if (g.isBasketball && g.isLive) ...[
                      const SizedBox(height: 12),
                      BasketballSummary(game: g),
                    ],
                    if (g.isVolleyball && g.isLive) ...[
                      const SizedBox(height: 12),
                      VolleyballSummary(game: g),
                    ],
                    if (g.status != 'completed') ...[
                      const SizedBox(height: 20),
                      SpSectionTitle(g.isScheduled
                          ? context.l10n.game_lineUps
                          : g.isBasketball || g.isVolleyball
                              ? context.l10n.game_onTheCourt
                              : context.l10n.game_onThePitch),
                      const SizedBox(height: 10),
                      _Lineups(game: g),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  static bool _penaltiesAdded(GameDetail g) =>
      g.lifecycle?.phases.any((ph) => ph.kind == 'shootout') ?? false;

  static bool _awaitingDraw(GameDetail g) {
    final lc = g.lifecycle;
    if (lc == null || !g.isLive) return false;
    final ph = lc.current;
    final inTimed = ph != null && ph.isTimed && ph.status == 'live';
    final regulationDone = !inTimed && lc.nextTimed == null;
    // Web drawOpts: extra time is only an option while it hasn't been played.
    final hasOption =
        (lc.drawResolutions.contains('extra_time') && !lc.hasExtraPhases) ||
            lc.drawResolutions.contains('penalties') ||
            lc.drawResolutions.contains('overtime');
    return regulationDone && g.isDrawn && hasOption && !_penaltiesAdded(g);
  }
}

Color teamColor(String? hex, AppPalette p) {
  if (hex == null || hex.isEmpty) return const Color(0xFF888888);
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.tryParse(h, radix: 16) ?? 0xFF888888);
}

// ---------------------------------------------------------------------------
// Scoreboard — the web card: two halves with a top colour bar, VS/FT circle,
// then the clock strip on a muted band.
// ---------------------------------------------------------------------------

class _Scoreboard extends StatelessWidget {
  const _Scoreboard({required this.game});
  final GameDetail game;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final g = game;
    final vsMode = g.teams.length == 2 && g.maxTeamsPerGame <= 2;
    // Sport-aware wording + court markings (goals / points / runs; Full time /
    // Final / Match over…).
    final board = boardSpec(g.profile.family);
    // Volleyball, live: the big numbers are the CURRENT set's points.
    final vbPts = vsMode ? currentSetPoints(g) : null;
    final unit = Text(
        (vbPts != null && vsMode
                ? context.l10n.game_setSets(g.volleyball!.currentSet, g.teams[0].score, g.teams[1].score)
                : board.unit)
            .toUpperCase(),
        style: TextStyle(
            color: p.heroMuted,
            fontSize: 10,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w700));
    final status = g.isLive
        ? context.l10n.game_live
        : g.status == 'completed'
            ? board.finalLabel.toUpperCase()
            : g.isScheduled
                ? context.l10n.game_notStarted
                : g.status.replaceAll('_', ' ').toUpperCase();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.hero,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(children: [
        Positioned.fill(child: CourtLines(family: g.profile.family)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (g.isLive) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                      color: Color(0xFFFF5A52), shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Text(status,
                  style: TextStyle(
                      color: g.isLive
                          ? const Color(0xFFFF8A84)
                          : const Color(0xFF6EDC9E),
                      fontSize: 11.5,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 14),
            if (vsMode)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _ScoreTeam(team: g.teams[0])),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(children: [
                    Text(
                      vbPts != null
                          ? '${vbPts[g.teams[0].teamId] ?? 0}–${vbPts[g.teams[1].teamId] ?? 0}'
                          : '${g.teams[0].score}–${g.teams[1].score}',
                      style: TextStyle(
                        color: p.onHero,
                        fontSize: 46,
                        height: 1,
                        letterSpacing: -1,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 6),
                    unit,
                  ]),
                ),
                Expanded(child: _ScoreTeam(team: g.teams[1])),
              ])
            else
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in g.teams)
                    SizedBox(
                      width: 96,
                      child: _ScoreTeam(team: t, compact: true),
                    ),
                  SizedBox(width: double.infinity, child: Center(child: unit)),
                ],
              ),
            _ClockStrip(game: g),
            if (g.isBasketball &&
                g.startedAt != null &&
                g.status != 'completed')
              TeamFoulsStrip(game: g),
            if (g.isVolleyball && g.startedAt != null && vsMode)
              SetScoresStrip(
                  game: g, order: [g.teams[0].teamId, g.teams[1].teamId]),
          ]),
        ),
      ]),
    );
  }
}

/// One side on the dark scoreboard: a crest in the team colour, the name,
/// and (multi-team) its score, then the result once decided.
class _ScoreTeam extends StatelessWidget {
  const _ScoreTeam({required this.team, this.compact = false});
  final GameTeam team;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = team;
    final won = t.result == 'win';
    final lost = t.result == 'loss';
    // Logo first (tournament teams), kit colour as a shirt on its corner;
    // no logo → the kit-colour tile with initials.
    final kit =
        (t.color == null || t.color!.isEmpty) ? null : teamColor(t.color, p);
    return Opacity(
      opacity: lost ? 0.6 : 1,
      child: Column(children: [
        ScoreCrest(
          name: t.name,
          color: kit,
          logoUrl: t.logoUrl,
          size: compact ? 44 : 54,
          radius: compact ? 15 : 18,
          won: won,
          outline: p.hero,
        ),
        const SizedBox(height: 8),
        Text(
          t.name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: p.onHero,
            fontSize: 13,
            height: 1.25,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (compact) ...[
          const SizedBox(height: 2),
          Text('${t.score}',
              style: TextStyle(
                color: p.onHero,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ],
        if (t.result != null) ...[
          const SizedBox(height: 4),
          Text(
            t.result!.toUpperCase(),
            style: TextStyle(
              color: won
                  ? const Color(0xFF6EDC9E)
                  : lost
                      ? const Color(0xFFFF8A84)
                      : p.heroMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ]),
    );
  }
}

/// The clock under the scores — timer, phase, Paused.
class _ClockStrip extends ConsumerStatefulWidget {
  const _ClockStrip({required this.game});
  final GameDetail game;
  @override
  ConsumerState<_ClockStrip> createState() => _ClockStripState();
}

class _ClockStripState extends ConsumerState<_ClockStrip> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final g = widget.game;
    if (g.startedAt == null) return const SizedBox.shrink();
    final info = clockInfo(g);
    if (info == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: p.onHero.withAlpha(18),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.timer_outlined,
            size: 17,
            color: info.paused ? p.heroMuted : const Color(0xFF6EDC9E)),
        const SizedBox(width: 7),
        Text(
          info.display,
          style: TextStyle(
            color: info.paused ? p.heroMuted : p.onHero,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (info.label != null) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              info.label!.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: p.heroMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
        if (info.paused) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0x29FFB57D),
                borderRadius: BorderRadius.circular(999),
              ),
              // "Paused · by Ade" — whoever paused it, from any device.
              child: Text(
                  pausedLabel(
                      g,
                      ref.watch(authControllerProvider
                          .select((s) => s.valueOrNull?.user?.id))),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Color(0xFFFFB57D),
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ]),
    );
  }
}

class ClockInfo {
  const ClockInfo(this.display, {this.label, this.paused = false});
  final String display;
  final String? label;
  final bool paused;
}

/// Shared clock math (also used to stamp minutes on recorded activities).
ClockInfo? clockInfo(GameDetail g) {
  if (!g.isLive) {
    if (g.status == 'completed') {
      return ClockInfo(boardSpec(g.profile.family).finalShort);
    }
    return null;
  }
  // Offset anchored at FETCH time (serverNow vs fetchedAt) — computing it
  // against the current instant would freeze the clock at the fetch moment.
  final offset = (g.serverNow != null && g.fetchedAt != null)
      ? g.serverNow!.difference(g.fetchedAt!)
      : Duration.zero;
  final now = DateTime.now().add(offset);

  final lc = g.lifecycle;
  if (lc != null) {
    final ph = lc.current;
    if (ph == null) return null;
    if (ph.kind == 'shootout') {
      return ClockInfo(l10n.game_pens2, label: l10n.game_penaltyShootout);
    }
    if (ph.kind == 'interval' || ph.status != 'live') {
      return ClockInfo('--:--', label: ph.label, paused: true);
    }
    final anchor = ph.startedAt;
    if (anchor == null) return ClockInfo('00:00', label: ph.label);
    final end = ph.timer.pausedAt ?? now;
    var elapsed = end.difference(anchor).inMilliseconds - ph.timer.pausedMs;
    if (elapsed < 0) elapsed = 0;
    if (g.profile.countsDown && ph.nominalMinutes != null) {
      // Basketball: time LEFT in the quarter.
      final left = ((ph.nominalMinutes! * 60000 - elapsed) / 1000).ceil();
      return ClockInfo(
        mmss(left < 0 ? 0 : left),
        label: ph.label,
        paused: ph.timer.pausedAt != null,
      );
    }
    final total = ph.nominalOffset * 60000 + elapsed;
    return ClockInfo(
      _fmt(total),
      label: ph.timer.stoppageMin > 0
          ? "${ph.label} · +${ph.timer.stoppageMin}'"
          : ph.label,
      paused: ph.timer.pausedAt != null,
    );
  }

  final started = g.startedAt;
  if (started == null) return null;
  final end = g.timer.pausedAt ?? now;
  var elapsed = end.difference(started).inMilliseconds - g.timer.pausedMs;
  if (elapsed < 0) elapsed = 0;
  return ClockInfo(
    _fmt(elapsed),
    // Untimed sports (volleyball, racket, cricket…): reference clock only.
    label: g.timer.stoppageMin > 0
        ? l10n.game_stoppage3(g.timer.stoppageMin)
        : g.profile.clock == 'elapsed'
            ? l10n.game_elapsed
            : null,
    paused: g.timer.pausedAt != null,
  );
}

/// Minute to stamp on an activity right now: null for phased games (the
/// server derives it from the phase), 1-based elapsed minutes otherwise.
int? activityMinute(GameDetail g) {
  if (g.lifecycle != null) return null;
  final started = g.startedAt;
  if (started == null || !g.isLive) return null;
  final offset = (g.serverNow != null && g.fetchedAt != null)
      ? g.serverNow!.difference(g.fetchedAt!)
      : Duration.zero;
  final now = DateTime.now().add(offset);
  final end = g.timer.pausedAt ?? now;
  var elapsed = end.difference(started).inMilliseconds - g.timer.pausedMs;
  if (elapsed < 0) elapsed = 0;
  final min = (elapsed / 60000).ceil();
  return min < 1 ? 1 : min;
}

String _fmt(int ms) {
  final totalSec = ms ~/ 1000;
  final m = totalSec ~/ 60;
  final s = totalSec % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Draw resolution — offered when a knockout ends level (amber card).
// ---------------------------------------------------------------------------

class _DrawCard extends ConsumerWidget {
  const _DrawCard({required this.gameId, required this.game});
  final String gameId;
  final GameDetail game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final lc = game.lifecycle!;
    final etAdded = lc.hasExtraPhases;
    Future<void> act(String action) async {
      try {
        await ref.read(gamesRepositoryProvider).phase(gameId, action);
        await ref.read(liveGameProvider(gameId).notifier).refresh();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color.fromRGBO(245, 167, 10, 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            game.isBasketball
                ? context.l10n.game_tiedAtTheBuzzer
                : context.l10n.game_levelAt(game.firstLeg.isNotEmpty ? context.l10n.game_onAggregate : '', (etAdded ? context.l10n.game_theEndOfExtraTime : context.l10n.game_fullTime)),
            style: TextStyle(
                color: p.ink, fontSize: 14, fontWeight: FontWeight.w700),
          ),
          Text(
              game.isBasketball
                  ? context.l10n.game_playOvertimeAsManyPeriods
                  : context.l10n.game_chooseHowToDecideThe,
              style: TextStyle(color: p.muted, fontSize: 12)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (lc.drawResolutions.contains('overtime'))
              SpButton(
                label: context.l10n.game_overtime,
                icon: Icons.timelapse_rounded,
                onTap: () => act('overtime'),
              ),
            if (lc.drawResolutions.contains('extra_time') && !etAdded)
              SpButton(
                label: context.l10n.game_extraTime,
                icon: Icons.timelapse_rounded,
                onTap: () => act('extraTime'),
              ),
            if (lc.drawResolutions.contains('penalties'))
              SpButton(
                label: context.l10n.game_straightToPenalties,
                icon: Icons.flag_outlined,
                onTap: () => act('penalties'),
              ),
            // Always offered: accept the level scoreline and finish the match.
            SpButton(
              label: context.l10n.game_endAsDraw,
              icon: Icons.handshake_outlined,
              onTap: () async {
                try {
                  await ref.read(gamesRepositoryProvider).complete(gameId);
                  await ref.read(liveGameProvider(gameId).notifier).refresh();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('$e')));
                  }
                }
              },
            ),
          ]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Penalty shootout — web card: per-team rows, "to take" highlight, inline
// Scored / Missed / Undo with strict alternation.
// ---------------------------------------------------------------------------

class _ShootoutCard extends ConsumerWidget {
  const _ShootoutCard({required this.gameId, required this.game});
  final String gameId;
  final GameDetail game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final g = game;
    final lc = g.lifecycle!;
    final tally = lc.shootoutTally;
    final order = lc.shootoutOrder;
    final history = lc.shootoutHistory;
    final turnTeam = order.length == 2 ? order[history.length % 2] : null;
    final lastTaker = history.isNotEmpty ? history.last.teamId : null;

    Future<void> attempt(String teamId, String outcome) async {
      try {
        await ref
            .read(gamesRepositoryProvider)
            .shootout(gameId, teamId, outcome);
        await ref.read(liveGameProvider(gameId).notifier).refresh();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }

    Widget mini(String label, VoidCallback? onTap, {bool outline = false}) {
      return Material(
        color: onTap == null
            ? p.surface2
            : outline
                ? p.surface
                : p.accent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: outline
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: p.line),
                  )
                : null,
            child: Text(
              label,
              style: TextStyle(
                color: onTap == null
                    ? p.muted
                    : outline
                        ? p.ink
                        : Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.flag_outlined, size: 15, color: p.accent),
            const SizedBox(width: 6),
            Text(context.l10n.game_penaltyShootout,
                style: TextStyle(
                    color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          if (turnTeam == null)
            Text(
              context.l10n.game_recordTheFirstPenaltyTo,
              style: TextStyle(color: p.muted, fontSize: 11.5),
            ),
          const SizedBox(height: 8),
          for (final t in g.teams)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: turnTeam == t.teamId
                    ? const Color.fromRGBO(23, 166, 94, 0.06)
                    : null,
                border: turnTeam == t.teamId
                    ? Border.all(color: const Color.fromRGBO(23, 166, 94, 0.3))
                    : null,
              ),
              child: Row(children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: teamColor(t.color, p), shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(children: [
                    Flexible(
                      child: Text(t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
                    if (turnTeam == t.teamId)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(context.l10n.game_toTake2,
                            style: TextStyle(
                                color: p.accent,
                                fontSize: 9,
                                fontWeight: FontWeight.w800)),
                      ),
                  ]),
                ),
                Text('${tally[t.teamId]?.scored ?? 0}',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w900)),
                const SizedBox(width: 4),
                Text(context.l10n.game_of(tally[t.teamId]?.taken ?? 0),
                    style: TextStyle(color: p.muted, fontSize: 10.5)),
                if (g.canScore) ...[
                  const SizedBox(width: 8),
                  mini(
                      context.l10n.game_scored,
                      (turnTeam == null || turnTeam == t.teamId)
                          ? () => attempt(t.teamId, 'scored')
                          : null),
                  const SizedBox(width: 4),
                  mini(
                      context.l10n.game_missed,
                      (turnTeam == null || turnTeam == t.teamId)
                          ? () => attempt(t.teamId, 'missed')
                          : null,
                      outline: true),
                  const SizedBox(width: 4),
                  mini(
                      context.l10n.game_undo,
                      lastTaker == t.teamId
                          ? () => attempt(t.teamId, 'undo')
                          : null,
                      outline: true),
                ],
              ]),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Timeline — web rows: minute, icon, team dot, "#7 Name — Goal (with #10)".
// ---------------------------------------------------------------------------

class _TimelineCard extends ConsumerWidget {
  const _TimelineCard({
    required this.game,
    required this.gameId,
    required this.rowKeys,
    required this.onStatReturn,
  });
  final GameDetail game;
  final String gameId;

  /// The screen's key per stat id, so the reel can come back to a row
  /// (`_GameScreenState._scrollToStat`).
  final Map<String, GlobalKey> rowKeys;

  /// A reel pushed from a row here has handed back the stat it started on.
  final ValueChanged<String> onStatReturn;

  String _jn(int? jersey) => jersey != null ? '#$jersey ' : '';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final g = game;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(g.status == 'completed' ? context.l10n.game_keyMoments : context.l10n.game_timeline,
              style: TextStyle(
                  color: p.ink, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (g.activities.isEmpty)
            Row(children: [
              const SpIconTile(Icons.timeline_rounded, size: 38, iconSize: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    g.isScheduled
                        ? context.l10n.game_nothingYetItHasntKicked
                        : context.l10n.game_noActivityYet,
                    style: TextStyle(color: p.muted, fontSize: 13)),
              ),
            ])
          else
            for (final a in g.activities) _row(context, ref, a),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, GameActivity a) {
    final p = context.palette;
    final g = game;
    final def = g.defFor(a.type);
    final team = g.teams.where((t) => t.teamId == a.teamId).toList();
    final isSub = a.type == 'substitution';
    // Highlights pinned to this stat — one per player on it, so at most two
    // (docs/wiki/highlights.md). Nothing until the read lands, or if it fails.
    final clips = ref.watch(gameHighlightsProvider(gameId)).valueOrNull?[a.id] ??
        const <GameHighlightRef>[];
    return Padding(
      // What the way back out of a reel scrolls to (the web's `data-stat`).
      key: rowKeys.putIfAbsent(a.id, () => GlobalKey()),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: g.isBasketball || g.isVolleyball ? 56 : 32,
            child: Text(
              g.isBasketball
                  ? bbStamp(a)
                  : g.isVolleyball
                      ? setStamp(a.phase)
                      : a.minute != null
                          ? "${a.minute}'"
                          : (a.phase ?? ''),
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: p.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          const SizedBox(width: 8),
          Text(def?.icon ?? '•', style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 7),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: teamColor(team.isNotEmpty ? team.first.color : null, p),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Plain wrapped Texts — inline TextSpans trip this Flutter build's
          // semantics compiler (same family as Badge / *.icon buttons).
          Expanded(
            child: isSub
                ? Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      PlayerTap(
                        userId: a.playerId,
                        borderRadius: 6,
                        child: Text('${_jn(a.jersey)}${a.playerName}',
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ),
                      Text(context.l10n.game_onLabel,
                          style: TextStyle(color: p.accent, fontSize: 13)),
                      if (a.relatedPlayerName != null) ...[
                        Text(' · ',
                            style: TextStyle(color: p.muted, fontSize: 13)),
                        PlayerTap(
                          userId: a.relatedPlayerId,
                          borderRadius: 6,
                          child: Text(a.relatedPlayerName!,
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Text(context.l10n.game_off,
                            style: TextStyle(color: p.danger, fontSize: 13)),
                      ],
                    ],
                  )
                : Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      PlayerTap(
                        userId: a.playerId,
                        borderRadius: 6,
                        child: Text('${_jn(a.jersey)}${a.playerName}',
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ),
                      Text(' — ${def?.label ?? a.type}',
                          style: TextStyle(color: p.muted, fontSize: 13)),
                      if (a.relatedPlayerName != null)
                        PlayerTap(
                          userId: a.relatedPlayerId,
                          borderRadius: 6,
                          child: Text(context.l10n.game_withLabel2(a.relatedPlayerName ?? ''),
                              style: TextStyle(color: p.muted, fontSize: 13)),
                        ),
                    ],
                  ),
          ),
          // A play badge per highlight. It opens that post — and says
          // where it came from, so the post is the first of the whole
          // EVENT's reel and scrolling off its end comes back to this
          // timeline, on this row (docs/wiki/highlights.md). The same
          // address the web makes (`highlightReelHref`).
          for (final clip in clips)
            Tooltip(
              message: context.l10n.highlights_watchHighlight,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () async {
                  // The timeline underneath is still scrolled to where
                  // they tapped, but an OFFSET is not a row — a match that
                  // gained or lost stats meanwhile has moved it. The reel's
                  // own way out hands the stat back on its pop; an exit that
                  // does not go through it — the iOS back-swipe, Android's
                  // predictive back — pops with no result, and the row is
                  // then the one this badge opened. Either way it is known,
                  // so no exit can leave the timeline on an offset alone
                  // (T8 review LOW-E, T10 review MED-1).
                  final from = await context.push<String>(
                      '/highlights/${clip.id}?gameId=$gameId&activityId=${a.id}');
                  onStatReturn(from ?? a.id);
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 2, 4),
                  child: Icon(Icons.play_circle_fill_rounded,
                      size: 19, color: p.accent),
                ),
              ),
            ),
          // ✎ corrects who it was (keeps the stat and its minute); 🗑 deletes.
          if (g.canScore && (g.isLive || g.status == 'completed')) ...[
            if (!isSub)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _edit(context, ref, a),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 1, 4, 4),
                  child: Icon(Icons.edit_outlined, size: 15, color: p.muted),
                ),
              ),
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _void(context, ref, a),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 1, 2, 4),
                child: Icon(Icons.delete_outline_rounded,
                    size: 15, color: p.muted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _edit(
      BuildContext context, WidgetRef ref, GameActivity a) async {
    final saved = await showSpSheet<bool>(
      context,
      builder: (_) => _EditActivitySheet(game: game, gameId: gameId, activity: a),
    );
    if (saved == true) {
      await ref.read(liveGameProvider(gameId).notifier).refresh();
    }
  }

  Future<void> _void(
      BuildContext context, WidgetRef ref, GameActivity a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.game_deleteThisEntry2),
        content: Text(
            l10n.game_isRemovedAndTheScore(game.defFor(a.type)?.label ?? a.type, a.playerName)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.game_keep)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.game_delete)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(gamesRepositoryProvider).voidActivity(gameId, a.id);
      await ref.read(liveGameProvider(gameId).notifier).refresh();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Lineups — the web's side-by-side team cards: "On the pitch" and
// "Bench & out", with ▲ On / ▼ Subbed off / Sent off / SUB badges.
// ---------------------------------------------------------------------------

class _Lineups extends StatelessWidget {
  const _Lineups({required this.game});
  final GameDetail game;

  @override
  Widget build(BuildContext context) {
    final g = game;
    // Pre-kickoff the roster is the lineup; after, the participant snapshot.
    final started = !g.isScheduled;
    final subbedIn = <String>{};
    final subbedOff = <String>{};
    for (final a in g.activities) {
      if (a.type == 'substitution') {
        subbedIn.add(a.playerId);
        if (a.relatedPlayerId != null) subbedOff.add(a.relatedPlayerId!);
      }
    }
    final cards = [
      for (final t in g.teams)
        Expanded(
          child: _LineupCard(
            game: g,
            team: t,
            started: started,
            subbedIn: subbedIn,
            subbedOff: subbedOff,
          ),
        ),
    ];
    if (cards.length <= 2) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            cards[i],
            if (i < cards.length - 1) const SizedBox(width: 10),
          ],
        ],
      );
    }
    return Column(children: [
      for (final t in g.teams)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _LineupCard(
            game: g,
            team: t,
            started: started,
            subbedIn: subbedIn,
            subbedOff: subbedOff,
          ),
        ),
    ]);
  }
}

class _LineupCard extends ConsumerStatefulWidget {
  const _LineupCard({
    required this.game,
    required this.team,
    required this.started,
    required this.subbedIn,
    required this.subbedOff,
  });
  final GameDetail game;
  final GameTeam team;
  final bool started;
  final Set<String> subbedIn;
  final Set<String> subbedOff;

  @override
  ConsumerState<_LineupCard> createState() => _LineupCardState();
}

class _LineupCardState extends ConsumerState<_LineupCard> {
  bool _busy = false;

  /// Move a player between the starting line-up and the bench BEFORE kick-off.
  /// Nothing is written to the match timeline — a scheduled game has no
  /// participants yet, so this edits the team sheet the kick-off seeds from.
  Future<void> _move(String teamId, GamePlayer x) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(gamesRepositoryProvider).setLineup(
            widget.game.id,
            teamId: teamId,
            playerOffId: x.onField ? x.playerId : null,
            playerOnId: x.onField ? null : x.playerId,
          );
      await ref.read(liveGameProvider(widget.game.id).notifier).refresh();
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final g = widget.game;
    final t = widget.team;
    final started = widget.started;
    final subbedIn = widget.subbedIn;
    final subbedOff = widget.subbedOff;
    // Before kick-off a group admin picks the side player by player. Once the
    // whistle goes, changes are match substitutions and go through the
    // officiant panel (which records the minute).
    final canPick = !started && g.canManageLineup;
    final lineup = started
        ? g.participants.where((x) => x.teamId == t.teamId).toList()
        : [
            for (final r in g.roster.where((r) => r.teamId == t.teamId))
              GamePlayer(
                playerId: r.playerId,
                teamId: r.teamId,
                displayName: r.displayName,
                onField: !r.isSub,
                avatarUrl: r.avatarUrl,
                jersey: r.jersey,
              ),
          ];
    final onPitch = lineup.where((x) => x.onField && !x.sentOff).toList();
    final offPitch = lineup.where((x) => !(x.onField && !x.sentOff)).toList();

    Widget badge(String text, Color tone) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: tone.withAlpha(30),
          ),
          child: Text(text,
              style: TextStyle(
                  color: tone, fontSize: 8.5, fontWeight: FontWeight.w800)),
        );

    Widget row(GamePlayer x) {
      final dimmed =
          x.sentOff || (!x.onField && subbedOff.contains(x.playerId));
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: PlayerTap(
                userId: x.playerId,
                borderRadius: 6,
                child: Text(
                  '${x.jersey != null ? '#${x.jersey} ' : ''}${x.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: dimmed ? p.muted : p.ink,
                    fontSize: 12,
                    decoration: x.sentOff ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ),
          ),
          if (x.onField && !x.sentOff && subbedIn.contains(x.playerId))
            badge('▲ ON', p.accent)
          else if (x.sentOff)
            badge(g.isBasketball ? context.l10n.game_fouledOut2 : context.l10n.game_sentOff2, p.danger)
          else if (!x.onField && subbedOff.contains(x.playerId))
            badge('▼ OFF', p.muted)
          else if (!x.onField && !canPick)
            badge('SUB', p.muted),
          if (canPick) ...[
            const SizedBox(width: 2),
            InkWell(
              onTap: _busy ? null : () => _move(t.teamId, x),
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                child: Text(
                  x.onField ? context.l10n.game_bench5 : context.l10n.game_start3,
                  style: TextStyle(
                      color: _busy ? p.muted : p.accent,
                      fontSize: 9,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(22),
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: p.line)
            : null,
        boxShadow: cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: t.groupTeamId != null
                ? () => context.push('/teams/${t.groupTeamId}')
                : null,
            child: Row(children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                    color: teamColor(t.color, p),
                    borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(t.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
              if (t.groupTeamId != null)
                Icon(Icons.chevron_right_rounded, size: 18, color: p.muted),
            ]),
          ),
          const SizedBox(height: 8),
          Text(
              started
                  ? '${g.isBasketball || g.isVolleyball ? 'ON THE COURT' : 'ON THE PITCH'} (${onPitch.length})'
                  : context.l10n.game_startingLineUp2(onPitch.length, g.maxPlayersPerTeam),
              style: TextStyle(
                  color: p.muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6)),
          const SizedBox(height: 3),
          if (onPitch.isEmpty && lineup.isEmpty && g.isTournament)
            // Tournament sides are the SQUAD only: accepted call-ups and
            // coach adds. Nobody in it → nobody here.
            Text(
                context.l10n.game_noOneInTheSquad,
                style: TextStyle(color: p.muted, fontSize: 11, height: 1.35))
          else if (onPitch.isEmpty)
            Text(context.l10n.game_noOneOnYet,
                style: TextStyle(color: p.muted, fontSize: 11))
          else
            for (final x in onPitch) row(x),
          if (offPitch.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
                started
                    ? context.l10n.game_benchOut2(offPitch.length)
                    : context.l10n.game_bench6(offPitch.length),
                style: TextStyle(
                    color: p.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6)),
            const SizedBox(height: 3),
            for (final x in offPitch) row(x),
          ],
          if (canPick) ...[
            const SizedBox(height: 8),
            Text(
                context.l10n.game_setTheSideBeforeKick,
                style: TextStyle(color: p.muted, fontSize: 10, height: 1.35)),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Post-match summary — web's PostMatchSummary essentials: the result line
// ("Full time / After extra time / Penalties — X won") and per-team scorers.
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.game});
  final GameDetail game;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final g = game;
    final wentPens =
        g.lifecycle?.phases.any((ph) => ph.kind == 'shootout') ?? false;
    final wentEt = g.lifecycle?.hasExtraPhases ?? false;
    final label = wentPens
        ? context.l10n.game_penalties2
        : wentEt
            ? context.l10n.game_afterExtraTime
            : context.l10n.game_fullTime2;
    // The recorded result first (a shootout winner can be level on goals),
    // then the score.
    GameTeam? winner;
    for (final t in g.teams) {
      if (t.result == 'win') winner = t;
    }
    if (winner == null && !g.teams.any((t) => t.result == 'draw')) {
      for (final t in g.teams) {
        if (winner == null || t.score > winner.score) winner = t;
      }
      if (g.teams.length > 1 &&
          g.teams.every((t) => t.score == g.teams.first.score)) {
        winner = null;
      }
    }
    final drawn = winner == null;
    final result = winner == null ? 'Draw' : '${winner.name} won';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Result pill — mirrors the web "🏆 Full time · X won" line.
      GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          SpIconTile(Icons.emoji_events_outlined,
              bg: drawn ? p.surface2 : p.orangeTint,
              fg: drawn ? p.muted : p.orangeInk),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(color: p.muted, fontSize: 12)),
              Text(result,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

/// Run a game action, refresh the live game, and toast a failure.
Future<void> _gameAct(BuildContext context, WidgetRef ref, String gameId,
    Future<void> Function() f) async {
  try {
    await f();
    await ref.read(liveGameProvider(gameId).notifier).refresh();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}


// ---------------------------------------------------------------------------
// Edit a recorded stat — the type and the moment stay; the team, the player,
// the assist / second player and (minute-clock sports) the minute change.
// ---------------------------------------------------------------------------

class _EditActivitySheet extends ConsumerStatefulWidget {
  const _EditActivitySheet(
      {required this.game, required this.gameId, required this.activity});
  final GameDetail game;
  final String gameId;
  final GameActivity activity;

  @override
  ConsumerState<_EditActivitySheet> createState() =>
      _EditActivitySheetState();
}

class _EditActivitySheetState extends ConsumerState<_EditActivitySheet> {
  late String _teamId = widget.activity.teamId;
  late String? _playerId = widget.activity.playerId;
  late String? _relatedId = widget.activity.relatedPlayerId;
  late final TextEditingController _minute = TextEditingController(
      text: widget.activity.minute?.toString() ?? '');
  bool _busy = false;

  bool get _minuteEditable =>
      !widget.game.isBasketball && !widget.game.isVolleyball;

  @override
  void dispose() {
    _minute.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pid = _playerId;
    if (pid == null) return;
    setState(() => _busy = true);
    try {
      final def = widget.game.defFor(widget.activity.type);
      final wantsRelated =
          (def?.assistAllowed ?? false) || (def?.requiresRelated ?? false);
      await ref.read(gamesRepositoryProvider).editActivity(
            widget.gameId,
            widget.activity.id,
            teamId: _teamId,
            playerId: pid,
            relatedPlayerId: wantsRelated ? _relatedId : widget.activity.relatedPlayerId,
            minute: int.tryParse(_minute.text.trim()),
            minuteEditable: _minuteEditable,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.game_updated)));
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final g = widget.game;
    final def = g.defFor(widget.activity.type);
    final needsRelated = def?.requiresRelated ?? false;
    final wantsRelated = (def?.assistAllowed ?? false) || needsRelated;
    final side = g.participants
        .where((x) => x.teamId == _teamId && !x.sentOff)
        .toList()
      ..sort((a, b) => (b.onField ? 1 : 0) - (a.onField ? 1 : 0));
    final everyone = g.participants.where((x) => !x.sentOff).toList();
    final relatedPool = needsRelated ? everyone : side;

    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 12),
          child: Text(t,
              style: TextStyle(
                  color: p.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0)),
        );
    Widget chip(String text, bool selected, VoidCallback onTap) => Material(
          color: selected ? p.accent : p.surface,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: _busy ? null : onTap,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: selected ? p.accent : p.line),
              ),
              child: Text(text,
                  style: TextStyle(
                      color: selected ? Colors.white : p.ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        );
    String name(GamePlayer x) =>
        '${x.jersey != null ? '#${x.jersey} ' : ''}${x.displayName}${x.onField ? '' : ' · bench'}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSheetHeader(
          title: context.l10n.game_edit2((def?.label ?? 'entry').toLowerCase()),
          subtitle: context.l10n.game_keepsTheStatAndWhen,
          icon: Icons.edit_outlined,
        ),
        label(context.l10n.game_team3),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in g.teams)
            chip(t.name, _teamId == t.teamId, () => setState(() {
                  if (_teamId != t.teamId) {
                    _teamId = t.teamId;
                    _playerId = null;
                    if (!needsRelated) _relatedId = null;
                  }
                })),
        ]),
        label(context.l10n.game_player2),
        if (side.isEmpty)
          Text(context.l10n.game_noPlayersInTheGame,
              style: TextStyle(color: p.muted, fontSize: 12.5))
        else
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final x in side)
              chip(name(x), _playerId == x.playerId, () => setState(() {
                    _playerId = x.playerId;
                    if (_relatedId == x.playerId) _relatedId = null;
                  })),
          ]),
        if (wantsRelated) ...[
          label(needsRelated ? context.l10n.game_secondPlayer2 : context.l10n.game_assistOptional2),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (!needsRelated)
              chip(context.l10n.game_noAssist, _relatedId == null,
                  () => setState(() => _relatedId = null)),
            for (final x in relatedPool)
              if (x.playerId != _playerId)
                chip(name(x), _relatedId == x.playerId,
                    () => setState(() => _relatedId = x.playerId)),
          ]),
        ],
        if (_minuteEditable) ...[
          label(context.l10n.game_minute2),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _minute,
              keyboardType: TextInputType.number,
              maxLength: 3,
              decoration: InputDecoration(
                counterText: '',
                hintText: context.l10n.game_eG34,
                filled: true,
                fillColor: p.surface2,
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        SpButton(
          label: _busy ? context.l10n.game_saving : context.l10n.game_save,
          icon: Icons.check_rounded,
          expand: true,
          onTap: _busy ||
                  _playerId == null ||
                  (needsRelated && _relatedId == null)
              ? null
              : _save,
        ),
      ],
    );
  }
}
