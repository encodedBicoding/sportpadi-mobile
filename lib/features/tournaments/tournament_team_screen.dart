import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/tournaments/squad_models.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/team_tile.dart'
    show kitGradient;
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// The tournament-scoped team profile: this team AS IT IS in THIS tournament.
/// Squad (called / accepted / declined, with times), the formation set for
/// this event, games played and per-player stats. Mirrors the web page at
/// /groups/[id]/tournaments/[eventId]/teams/[teamId].
class TournamentTeamScreen extends ConsumerStatefulWidget {
  const TournamentTeamScreen({
    super.key,
    required this.groupId,
    required this.eventId,
    required this.teamId,
    this.respond = false,
  });
  final String groupId;
  final String eventId;
  final String teamId;

  /// Deep link from a call-up notification — scroll the respond card into view.
  final bool respond;

  @override
  ConsumerState<TournamentTeamScreen> createState() =>
      _TournamentTeamScreenState();
}

class _TournamentTeamScreenState extends ConsumerState<TournamentTeamScreen> {
  int _tab = 0; // 0 squad, 1 formation, 2 games, 3 stats
  bool _busy = false;

  String get _key => '${widget.eventId}|${widget.teamId}';

  void _refetch() {
    ref.invalidate(tournamentSquadProvider(_key));
    ref.invalidate(squadStatsProvider(_key));
    ref.invalidate(myCallsProvider);
    ref.invalidate(tournamentDetailProvider(widget.eventId));
  }

  /// Pull to refresh: everything [_refetch] does, holding the spinner until
  /// the squad (and the stats, when that tab is open) are back.
  Future<void> _pullRefresh() {
    final statsShown = _tab == 3 &&
        ref
            .read(tournamentSquadProvider(_key))
            .maybeWhen(data: (_) => true, orElse: () => false);
    _refetch();
    return settleAll([
      ref.read(tournamentSquadProvider(_key).future),
      if (statsShown) ref.read(squadStatsProvider(_key).future),
    ]);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _run(Future<void> Function() fn, {String? success}) async {
    setState(() => _busy = true);
    try {
      await fn();
      if (success != null) _snack(success);
      _refetch();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _respond(TournamentSquad sq, bool accept) async {
    final id = sq.mySquadId;
    if (id == null) return;
    if (!accept && sq.myStatus == 'accepted') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.tournament_withdrawFromThisSquad),
          content: Text(
              l10n.tournament_youllBeTakenOffS(sq.teamName, sq.eventTitle)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.tournament_cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.tournament_withdraw)),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _run(
      () => ref
          .read(tournamentsRepositoryProvider)
          .respondCall(widget.eventId, id, accept: accept),
      success: accept ? l10n.tournament_youreInTheSquad : l10n.tournament_responseSent,
    );
  }

  Future<void> _callPlayers(TournamentSquad sq) async {
    final req = await showSpSheet<CallRequest>(
      context,
      builder: (_) => _CallPlayersSheet(squad: sq),
    );
    if (req == null) return;
    if (!req.all && req.playerIds.isEmpty) return;
    await _run(() async {
      final n = await ref.read(tournamentsRepositoryProvider).callPlayers(
            widget.eventId,
            sq.tournamentTeamId,
            playerIds: req.all ? null : req.playerIds,
            all: req.all,
            note: req.note,
          );
      _snack(n == 0
          ? l10n.tournament_everyonePickedHadAlreadyBeen
          : l10n.tournament_calledPlayersTheyveBeenNotified(n));
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sq = ref.watch(tournamentSquadProvider(_key));
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Stack(children: [
          RefreshIndicator(
            onRefresh: _pullRefresh,
            // Loading / error aren't scrollable on their own.
            child: _pullable(sq, AsyncView(
            value: sq,
            onRetry: _refetch,
            data: (d) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 36),
                children: [
                  _header(d, p),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (d.mySquadId != null) ...[
                          const SizedBox(height: 12),
                          _myCard(d, p),
                        ],
                        const SizedBox(height: 14),
                        _tabs(d, p),
                        const SizedBox(height: 14),
                        if (_tab == 0) ..._squadTab(d, p),
                        if (_tab == 1) _formationTab(d, p),
                        if (_tab == 2) ..._gamesTab(d, p),
                        if (_tab == 3)
                          _StatsTab(keyId: _key, eventId: widget.eventId),
                      ],
                    ),
                  ),
                ],
              ),
          )),
          ),
          if (sq.valueOrNull == null)
            Positioned(
              left: 16,
              top: 12,
              child: SpRoundButton(
                icon: Icons.arrow_back_ios_new_rounded,
                iconSize: 18,
                tooltip: context.l10n.tournament_back,
                onTap: () =>
                    context.canPop() ? context.pop() : context.go('/home'),
              ),
            ),
        ]),
      ),
    );
  }

  static const double _bannerH = 160;
  static const double _overlap = 48;

  /// The kit banner with round back / team buttons, and the identity card
  /// over it: this team as it is in THIS tournament.
  Widget _header(TournamentSquad d, AppPalette p) {
    final starters = d.accepted.where((x) => x.isStarter).length;
    final canPop = context.canPop() || Navigator.of(context).canPop();

    Widget stat(String v, String l, {Color? tone}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: p.surface2,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: [
              Text(v,
                  style: TextStyle(
                      color: tone ?? p.ink,
                      fontSize: 18,
                      height: 1.1,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(l,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 11)),
            ]),
          ),
        );

    final card = GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: p.surface, width: 3),
            ),
            child: Crest(
                logoUrl: d.teamLogoUrl,
                kitPrimary: d.kitPrimary,
                kitSecondary: d.kitSecondary,
                label: d.teamName,
                size: 60),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.teamName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 19,
                      height: 1.2,
                      fontWeight: FontWeight.w800)),
              if (d.teamUsername != null)
                Text('@${d.teamUsername}',
                    style: TextStyle(color: p.muted, fontSize: 12.5)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        // Which competition, and in what capacity.
        InkWell(
          onTap: d.hostGroupId != null
              ? () => context
                  .push('/groups/${d.hostGroupId}/tournaments/${d.eventId}')
              : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: p.orangeTint,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              SpIconTile(Icons.emoji_events_outlined,
                  bg: p.surface, fg: p.orangeInk, size: 36, iconSize: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.eventTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      Text(
                          [
                            d.kind,
                            d.role == 'host' ? context.l10n.tournament_host : context.l10n.tournament_guest,
                            if (d.kickedOff) context.l10n.tournament_kickedOff,
                          ].join(' · '),
                          style: TextStyle(
                              color: p.orangeInk,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ]),
              ),
              if (d.hostGroupId != null)
                Icon(Icons.chevron_right_rounded, size: 20, color: p.orangeInk),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          stat('${d.accepted.length}', context.l10n.tournament_inSquad, tone: p.greenText),
          const SizedBox(width: 8),
          stat('${d.pending.length}', context.l10n.tournament_awaiting,
              tone: d.pending.isNotEmpty ? p.orangeInk : null),
          const SizedBox(width: 8),
          d.needsFormation
              ? stat('$starters/${d.maxStarters}', context.l10n.tournament_starters2)
              : stat('${d.games.length}', context.l10n.tournament_games),
        ]),
      ]),
    );

    return Stack(children: [
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: ClipRRect(
          borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(32)),
          child: Container(
            height: _bannerH,
            decoration: BoxDecoration(
                gradient: kitGradient(d.kitPrimary, d.kitSecondary)),
          ),
        ),
      ),
      Positioned(
        left: 16,
        top: 12,
        child: SpRoundButton(
          icon: canPop ? Icons.arrow_back_ios_new_rounded : Icons.home_outlined,
          iconSize: canPop ? 18 : 21,
          tooltip: canPop ? context.l10n.tournament_back : context.l10n.tournament_home,
          onTap: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
      ),
      Positioned(
        right: 16,
        top: 12,
        child: SpRoundButton(
          icon: Icons.shield_outlined,
          tooltip: context.l10n.tournament_generalTeamProfile,
          onTap: () => context.push('/teams/${d.teamId}'),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, _bannerH - _overlap, 16, 0),
        child: card,
      ),
    ]);
  }

  /// The viewer's own call-up.
  Widget _myCard(TournamentSquad d, AppPalette p) {
    if (d.myStatus == 'called') {
      final blocked = d.myOtherTeamName != null;
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.hero,
          borderRadius: BorderRadius.circular(26),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const SpIconTile(Icons.campaign_rounded,
                bg: Color(0x29FFB57D),
                fg: Color(0xFFFFB57D),
                size: 40,
                iconSize: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.tournament_youveBeenCalledUp,
                        style: TextStyle(
                            color: p.onHero,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                    Text(context.l10n.tournament_canYouPlayFor(d.teamName),
                        style: TextStyle(color: p.heroMuted, fontSize: 12.5)),
                  ]),
            ),
          ]),
          // Nobody can answer "can you play?" from a title alone — put the
          // when / where / who in front of them, above the buttons.
          const SizedBox(height: 14),
          _detail(p, Icons.event_outlined, context.l10n.tournament_when, d.when.line,
              sub: d.when.viewerTime != null
                  ? context.l10n.tournament_yourTime(d.when.viewerTime ?? '')
                  : null),
          if (d.locationName != null)
            _detail(p, Icons.place_outlined, context.l10n.tournament_where, d.locationName!),
          if (d.opponents.isNotEmpty)
            _detail(
                p,
                Icons.sports_kabaddi_outlined,
                d.opponents.length > 1 ? context.l10n.tournament_teams : context.l10n.tournament_opponent,
                d.opponents.map((o) => o.name).join(', ')),
          _detail(
              p,
              Icons.groups_outlined,
              context.l10n.tournament_host,
              [
                d.hostGroupName,
                if (d.categoryName != null)
                  '${d.categoryEmoji ?? ''} ${d.categoryName}'.trim(),
              ].whereType<String>().join(' · ')),
          if (d.myCallNote != null && d.myCallNote!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.onHero.withAlpha(18),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.tournament_says2(d.myCalledByName ?? context.l10n.tournament_yourCoach),
                        style: const TextStyle(
                            color: Color(0xFFFFB57D),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(d.myCallNote!.trim(),
                        style: TextStyle(
                            color: p.onHero, fontSize: 13, height: 1.4)),
                  ]),
            ),
          ],
          if (d.eventDescription != null &&
              d.eventDescription!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              d.eventDescription!.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.heroMuted, fontSize: 12.5, height: 1.4),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            context.l10n.tournament_acceptingLocksYouToThis3(d.kind.toLowerCase()),
            style: TextStyle(color: p.heroMuted, fontSize: 12, height: 1.35),
          ),
          if (blocked) ...[
            const SizedBox(height: 6),
            Text(
              context.l10n.tournament_youveAlreadyAcceptedForWithdraw(d.myOtherTeamName ?? ''),
              style: const TextStyle(color: Color(0xFFFF8A84), fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: Material(
                color: _busy || blocked ? p.onHero.withAlpha(30) : Colors.white,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: _busy || blocked ? null : () => _respond(d, true),
                  child: SizedBox(
                    height: 48,
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_rounded,
                              size: 18,
                              color: _busy || blocked
                                  ? p.heroMuted
                                  : const Color(0xFF0E1411)),
                          const SizedBox(width: 6),
                          Text(context.l10n.tournament_imIn,
                              style: TextStyle(
                                  color: _busy || blocked
                                      ? p.heroMuted
                                      : const Color(0xFF0E1411),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                        ]),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Material(
                color: p.onHero.withAlpha(24),
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: _busy ? null : () => _respond(d, false),
                  child: SizedBox(
                    height: 48,
                    child: Center(
                      child: Text(context.l10n.tournament_cantMakeIt,
                          style: TextStyle(
                              color: p.onHero,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ]),
      );
    }
    if (d.myStatus == 'accepted') {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: p.accentTint,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(children: [
          Icon(Icons.check_circle_rounded, color: p.greenText, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(context.l10n.tournament_youreInThisSquad,
                style: TextStyle(
                    color: p.greenText,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ),
          if (!d.isOver)
            TextButton(
              onPressed: _busy ? null : () => _respond(d, false),
              style: TextButton.styleFrom(foregroundColor: p.muted),
              child: Text(context.l10n.tournament_withdraw, style: const TextStyle(fontSize: 12.5)),
            ),
        ]),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _tabs(TournamentSquad d, AppPalette p) {
    final items = <(String, int)>[
      ('Squad', 0),
      if (d.needsFormation) ('Formation', 1),
      ('Games', 2),
      ('Stats', 3),
    ];
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final (label, i) in items)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: _tab == i ? p.hero : p.surface,
                shape: StadiumBorder(
                    side: _tab == i
                        ? BorderSide.none
                        : BorderSide(color: p.line)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => setState(() => _tab = i),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    child: Text(label,
                        style: TextStyle(
                            color: _tab == i ? p.onHero : p.ink,
                            fontSize: 13,
                            fontWeight:
                                _tab == i ? FontWeight.w700 : FontWeight.w600)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _squadTab(TournamentSquad d, AppPalette p) {
    final repo = ref.read(tournamentsRepositoryProvider);
    return [
      if (d.canManage && !d.isOver) ...[
        SpButton(
          label: context.l10n.tournament_callPlayersButton,
          icon: Icons.campaign_rounded,
          expand: true,
          onTap: _busy || (d.uncalled.isEmpty && d.notPlaying.isEmpty)
              ? null
              : () => _callPlayers(d),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.tournament_playersGetAnInApp2(d.kind.toLowerCase()),
          textAlign: TextAlign.center,
          style: TextStyle(color: p.muted, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 18),
      ],
      SpSectionTitle(context.l10n.tournament_inTheSquad, count: d.accepted.length),
      const SizedBox(height: 10),
      if (d.accepted.isEmpty)
        _empty(context.l10n.tournament_nobodyHasAcceptedYet, p)
      else
        SpListCard(children: [
          for (final m in d.accepted)
            _row(m, d, p,
                trailing: d.canManage && !d.isOver
                    ? IconButton(
                        tooltip: context.l10n.tournament_removeFromSquad,
                        icon: Icon(Icons.person_remove_outlined,
                            size: 18, color: p.muted),
                        onPressed: _busy
                            ? null
                            : () => _run(
                                () => repo.removeSquadPlayer(
                                    widget.eventId, m.id),
                                success: context.l10n.tournament_removedFromSquad),
                      )
                    : null),
        ]),
      if (d.pending.isNotEmpty) ...[
        const SizedBox(height: 20),
        SpSectionTitle(context.l10n.tournament_awaitingReply, count: d.pending.length),
        const SizedBox(height: 10),
        SpListCard(children: [
          for (final m in d.pending)
            _row(m, d, p,
                trailing: d.canManage && !d.isOver
                    ? TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                () => repo.addSquadPlayer(widget.eventId,
                                    d.tournamentTeamId, m.playerId),
                                success: context.l10n.tournament_addedToSquad),
                        style:
                            TextButton.styleFrom(foregroundColor: p.greenText),
                        child: Text(context.l10n.tournament_add,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                      )
                    : null),
        ]),
      ],
      if (d.notPlaying.isNotEmpty) ...[
        const SizedBox(height: 20),
        SpSectionTitle(context.l10n.tournament_notPlaying, count: d.notPlaying.length),
        const SizedBox(height: 10),
        // Removed by the coach, or declined: one tap puts them back in the
        // squad (accepted on the coach's behalf, like "Add" above).
        SpListCard(children: [
          for (final m in d.notPlaying)
            _row(m, d, p,
                trailing: d.canManage && !d.isOver
                    ? TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                () => repo.addSquadPlayer(widget.eventId,
                                    d.tournamentTeamId, m.playerId),
                                success: context.l10n.tournament_backInTheSquad),
                        style:
                            TextButton.styleFrom(foregroundColor: p.greenText),
                        child: Text(context.l10n.tournament_addBack,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                      )
                    : null),
        ]),
      ],
      if (d.coaches.isNotEmpty) ...[
        const SizedBox(height: 20),
        SpSectionTitle(context.l10n.tournament_coaches, count: d.coaches.length),
        const SizedBox(height: 10),
        GlassCard(
          padding: const EdgeInsets.all(14),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in d.coaches)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                    color: p.surface2,
                    borderRadius: BorderRadius.circular(999)),
                child: Text(c.displayName,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
      ],
    ];
  }

  Widget _row(SquadPlayer m, TournamentSquad d, AppPalette p,
      {Widget? trailing}) {
    final (String status, Color bg, Color fg) = switch (m.status) {
      'accepted' => (context.l10n.tournament_squadIn, p.accentTint, p.greenText),
      'called' => (context.l10n.tournament_awaiting, p.orangeTint, p.orangeInk),
      'removed' => (context.l10n.tournament_squadRemoved, p.liveTint, p.danger),
      'withdrawn' => (context.l10n.tournament_squadWithdrew, p.surface2, p.muted),
      _ => (context.l10n.tournament_declined, p.surface2, p.muted),
    };
    final sub = <String>[
      if (m.positions.isNotEmpty) m.positions.join(' · '),
      if (m.accepted)
        m.source == 'coach'
            ? context.l10n.tournament_addedByCoachAgo(timeAgo(m.acceptedAt))
            : context.l10n.tournament_acceptedAgo(timeAgo(m.acceptedAt))
      else if (m.pending)
        context.l10n.tournament_calledAgoCapital(timeAgo(m.calledAt))
      else
        context.l10n.tournament_statusAgo(status, timeAgo(m.respondedAt)),
    ].join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.push('/players/${m.playerId}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 4, 10),
        child: Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            ClipOval(
                child: Crest(
                    logoUrl: m.profile?.avatarUrl, label: m.name, size: 40)),
            if (m.jerseyNumber != null)
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: p.hero,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: p.surface, width: 2),
                  ),
                  child: Text('${m.jerseyNumber}',
                      style: TextStyle(
                          color: p.onHero,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800)),
                ),
              ),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(m.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ),
                if (m.isCaptain) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                        color: p.hero,
                        borderRadius: BorderRadius.circular(999)),
                    child: Text('C',
                        style: TextStyle(
                            color: p.onHero,
                            fontSize: 10,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
                if (m.accepted) ...[
                  const SizedBox(width: 5),
                  Text(m.isStarter ? context.l10n.tournament_starter : context.l10n.tournament_sub,
                      style: TextStyle(
                          color: m.isStarter ? p.greenText : p.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ],
              ]),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 12)),
              if (m.accepted && m.joinedAfterKickoff)
                Text(context.l10n.tournament_joinedAfterKickOff,
                    style: TextStyle(
                        color: p.orangeInk,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(999)),
            child: Text(status,
                style: TextStyle(
                    color: fg, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ),
          if (trailing != null) trailing,
        ]),
      ),
    );
  }

  Widget _formationTab(TournamentSquad d, AppPalette p) {
    final starters = d.accepted.where((x) => x.isStarter).length;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(26),
        boxShadow: cardShadow(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // A pitch, with the shape and how full it is.
        Container(
          height: 150,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF17873F), Color(0xFF0F6B34)],
            ),
          ),
          child: CustomPaint(
            painter: _MiniPitch(),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(d.formationName ?? context.l10n.tournament_noFormation,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5)),
                const SizedBox(height: 2),
                Text(context.l10n.tournament_ofOnThePitch(starters, d.maxStarters),
                    style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              d.accepted.isEmpty
                  ? context.l10n.tournament_theFormationIsBuiltFrom
                  : context.l10n.tournament_forOnlyThisIsWhat(d.eventTitle),
              style: TextStyle(color: p.muted, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 14),
            SpButton(
              label: d.canManage && !d.isOver
                  ? context.l10n.tournament_openFormationBoard
                  : context.l10n.tournament_viewFormation,
              icon: Icons.grid_on_rounded,
              expand: true,
              onTap: d.accepted.isEmpty
                  ? null
                  : () async {
                      await context.push(
                          '/groups/${widget.groupId}/tournaments/${widget.eventId}/teams/${widget.teamId}/formation');
                      _refetch();
                    },
            ),
          ]),
        ),
      ]),
    );
  }

  List<Widget> _gamesTab(TournamentSquad d, AppPalette p) {
    if (d.games.isEmpty) return [_empty(context.l10n.tournament_noGamesYet, p)];
    return [
      SpSectionTitle(context.l10n.tournament_games, count: d.games.length),
      const SizedBox(height: 10),
      SpListCard(children: [
        for (final g in d.games)
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => context.push('/games/${g.id}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final t in g.teams)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1.5),
                            child: Row(children: [
                              Expanded(
                                child: Text(t.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: t.result == 'loss'
                                            ? p.muted
                                            : p.ink,
                                        fontSize: 14,
                                        fontWeight: t.result == 'win'
                                            ? FontWeight.w800
                                            : FontWeight.w600)),
                              ),
                              Text('${t.score}',
                                  style: TextStyle(
                                      color:
                                          t.result == 'loss' ? p.muted : p.ink,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800)),
                            ]),
                          ),
                      ]),
                ),
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: g.status == 'live'
                        ? p.liveTint
                        : g.status == 'completed'
                            ? p.surface2
                            : p.accentTint,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                      g.status == 'live'
                          ? context.l10n.tournament_live4
                          : g.status == 'completed'
                              ? context.l10n.tournament_ft
                              : g.status == 'scheduled'
                                  ? context.l10n.tournament_upcoming
                                  : g.status,
                      style: TextStyle(
                          color: g.status == 'live'
                              ? p.danger
                              : g.status == 'completed'
                                  ? p.muted
                                  : p.greenText,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800)),
                ),
                Icon(Icons.chevron_right_rounded, size: 20, color: p.muted),
              ]),
            ),
          ),
      ]),
    ];
  }

  /// One "When / Where / Opponent" line in the call-up prompt (on the dark
  /// card). [sub] carries the viewer's own clock when their zone differs
  /// from the venue's.
  Widget _detail(AppPalette p, IconData icon, String label, String value,
      {String? sub}) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: p.onHero.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 15, color: p.heroMuted),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: p.heroMuted, fontSize: 11)),
            Text(value,
                style: TextStyle(
                    color: p.onHero,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            if (sub != null)
              Text(sub, style: TextStyle(color: p.heroMuted, fontSize: 11.5)),
          ]),
        ),
      ]),
    );
  }

  Widget _empty(String t, AppPalette p) => GlassCard(
        padding: const EdgeInsets.all(22),
        child: Column(children: [
          const SpIconTile(Icons.inbox_outlined, size: 50, iconSize: 24),
          const SizedBox(height: 10),
          Text(t,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 13)),
        ]),
      );
}

/// [child] as is when [value] renders its (scrollable) data branch, else
/// wrapped so the loader / error can still be pulled.
Widget _pullable(AsyncValue<Object?> value, Widget child) => value.maybeWhen(
      data: (_) => child,
      orElse: () => PullableState(child: child),
    );

/// Faint pitch lines behind the formation name.
class _MiniPitch extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0x2EFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final r = Rect.fromLTWH(14, 12, size.width - 28, size.height - 24);
    canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(8)), line);
    canvas.drawLine(
        Offset(size.width / 2, r.top), Offset(size.width / 2, r.bottom), line);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 30, line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Pick roster players to call up (uncalled + anyone who declined/withdrew).
class _CallPlayersSheet extends StatefulWidget {
  const _CallPlayersSheet({required this.squad});
  final TournamentSquad squad;
  @override
  State<_CallPlayersSheet> createState() => _CallPlayersSheetState();
}

/// What the sheet hands back: who to call (or the whole roster) plus the
/// coach's optional remark.
typedef CallRequest = ({List<String> playerIds, bool all, String? note});

class _CallPlayersSheetState extends State<_CallPlayersSheet> {
  late final Set<String> _sel = {
    for (final u in widget.squad.uncalled) u.playerId
  };
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String? get _noteText => _note.text.trim().isEmpty ? null : _note.text.trim();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sq = widget.squad;
    final rows = <({String id, String name, String sub, String? avatar})>[
      for (final u in sq.uncalled)
        (
          id: u.playerId,
          name: u.name,
          sub: u.positions.join(' · '),
          avatar: u.profile?.avatarUrl
        ),
      for (final m in sq.notPlaying)
        (
          id: m.playerId,
          name: m.name,
          sub: [
            if (m.positions.isNotEmpty) m.positions.join(' · '),
            'call again'
          ].join(' · '),
          avatar: m.profile?.avatarUrl
        ),
    ];
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpSheetHeader(
            icon: Icons.campaign_rounded,
            iconBg: p.orangeTint,
            iconFg: p.orangeInk,
            title: context.l10n.tournament_callPlayersButton,
            subtitle:
                context.l10n.tournament_eachPlayerGetsAnIn2,
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text(context.l10n.tournament_ofSelected2(_sel.length, rows.length),
                    style: TextStyle(color: p.muted, fontSize: 11.5)),
              ),
              TextButton(
                onPressed: () =>
                    setState(() => _sel.addAll(rows.map((r) => r.id))),
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: Text(context.l10n.tournament_selectAll, style: const TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: () => setState(_sel.clear),
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: Text(context.l10n.tournament_clear, style: const TextStyle(fontSize: 12)),
              ),
            ]),
          ],
          const SizedBox(height: 2),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(context.l10n.tournament_everyoneOnTheRosterHas,
                    style: TextStyle(color: p.muted, fontSize: 13)),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final r in rows)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _sel.contains(r.id),
                      onChanged: (v) => setState(
                          () => v == true ? _sel.add(r.id) : _sel.remove(r.id)),
                      title: Text(r.name,
                          style: TextStyle(color: p.ink, fontSize: 13.5)),
                      subtitle: r.sub.isEmpty
                          ? null
                          : Text(r.sub,
                              style: TextStyle(color: p.muted, fontSize: 11.5)),
                      secondary: ClipOval(
                          child: Crest(
                              logoUrl: r.avatar, label: r.name, size: 32)),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          // Optional remark — meeting point, kit, what the game is for. It
          // travels with the call-up into the notification, the email and the
          // player's accept/decline prompt.
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 3,
            maxLength: 300,
            style: TextStyle(color: p.ink, fontSize: 13),
            decoration: InputDecoration(
              labelText: context.l10n.tournament_remarkOptional,
              hintText:
                  context.l10n.tournament_meetAtTheClubhouse45,
              hintStyle: TextStyle(color: p.muted, fontSize: 12),
              counterStyle: TextStyle(color: p.muted, fontSize: 10),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(height: 6),
          SpButton(
            label: context.l10n.tournament_callPlayers2(_sel.length),
            icon: Icons.campaign_rounded,
            expand: true,
            onTap: _sel.isEmpty
                ? null
                : () => Navigator.pop<CallRequest>(context,
                    (playerIds: _sel.toList(), all: false, note: _noteText)),
          ),
          const SizedBox(height: 8),
          Material(
            color: p.surface,
            shape: StadiumBorder(side: BorderSide(color: p.line)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => Navigator.pop<CallRequest>(context,
                  (playerIds: const <String>[], all: true, note: _noteText)),
              child: SizedBox(
                height: 48,
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.groups_2_outlined, size: 17, color: p.ink),
                  const SizedBox(width: 6),
                  Text(context.l10n.tournament_callWholeRoster,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        ]);
  }
}

class _StatsTab extends ConsumerWidget {
  const _StatsTab({required this.keyId, required this.eventId});
  final String keyId;
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final s = ref.watch(squadStatsProvider(keyId));
    return s.when(
      loading: () => Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(context.l10n.tournament_loadingStats,
                  style: TextStyle(color: p.muted, fontSize: 13)))),
      error: (e, _) => Center(
          child: Text('$e', style: TextStyle(color: p.muted, fontSize: 13))),
      data: (d) {
        final games = (d['games'] as num?)?.toInt() ?? 0;
        final players =
            d['players'] is List ? (d['players'] as List) : const [];
        // Columns come from the category's own activity schema — goals,
        // assists, yellows and reds for soccer, whatever another sport
        // declares for itself.
        final fields = [
          for (final f
              in (d['fields'] is List ? d['fields'] as List : const []))
            if (f is Map) Map<String, dynamic>.from(f)
        ];
        final cats = [
          for (final c
              in (d['categories'] is List ? d['categories'] as List : const []))
            if (c is Map) Map<String, dynamic>.from(c)
        ];
        if (games == 0 || players.isEmpty) {
          return GlassCard(
            padding: const EdgeInsets.all(22),
            child: Column(children: [
              const SpIconTile(Icons.bar_chart_rounded, size: 50, iconSize: 24),
              const SizedBox(height: 10),
              Text(
                  context.l10n.tournament_statsAppearOnceThisSquad,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.muted, fontSize: 13)),
            ]),
          );
        }
        final rows = [
          for (final x in players) Map<String, dynamic>.from(x as Map)
        ];

        Widget cell(String text,
                {bool dim = false, bool bold = false, double width = 34}) =>
            SizedBox(
              width: width,
              child: Text(text,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: dim ? p.muted.withAlpha(120) : p.ink,
                      fontSize: 12,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
            );

        Widget head(String text, {double width = 34}) => SizedBox(
              width: width,
              child: Text(text,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4)),
            );

        // One horizontal scroller for the whole grid: the name column stays
        // readable on a phone and the stat columns run off to the right.
        return GlassCard(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.l10n.tournament_playerStats,
                style: TextStyle(
                    color: p.ink, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        SizedBox(
                            width: 140,
                            child: Text(context.l10n.tournament_player3,
                                style: TextStyle(
                                    color: p.muted,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4))),
                        head('GP'),
                        head('ST'),
                        head(context.l10n.tournament_wDL2, width: 52),
                        for (final f in fields)
                          head(
                              '${parseStr(f['icon']) ?? ''}${parseStr(f['label']) ?? parseStr(f['key']) ?? ''}',
                              width: 58),
                      ]),
                    ),
                    for (final r in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: InkWell(
                          onTap: parseStr(r['playerId']) != null
                              ? () => context.push(
                                  '/players/${parseStr(r['playerId'])}/tournaments/$eventId')
                              : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              border:
                                  Border(top: BorderSide(color: p.surface2)),
                            ),
                            child: Row(children: [
                              SizedBox(
                                width: 140,
                                child: Row(children: [
                                  if (parseInt(r['jerseyNumber']) != null) ...[
                                    Text('#${parseInt(r['jerseyNumber'])}',
                                        style: TextStyle(
                                            color: p.muted, fontSize: 11)),
                                    const SizedBox(width: 4),
                                  ],
                                  Expanded(
                                    child: Text(
                                      (r['profile'] is Map
                                              ? parseStr((r['profile']
                                                  as Map)['displayName'])
                                              : null) ??
                                          context.l10n.tournament_player2,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: p.ink,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ]),
                              ),
                              cell('${parseInt(r['games']) ?? 0}'),
                              cell('${parseInt(r['starts']) ?? 0}'),
                              cell(
                                  '${parseInt(r['wins']) ?? 0}-${parseInt(r['draws']) ?? 0}-${parseInt(r['losses']) ?? 0}',
                                  width: 52),
                              for (final f in fields)
                                () {
                                  final v = parseInt((r['counts'] as Map?)?[
                                          parseStr(f['key']) ?? '']) ??
                                      0;
                                  return cell('$v',
                                      dim: v == 0, bold: v > 0, width: 58);
                                }(),
                            ]),
                          ),
                        ),
                      ),
                  ]),
            ),
            const SizedBox(height: 2),
            Text(
              context.l10n.tournament_countPluralOneAcrossGame(games, cats.isEmpty ? '' : ' · ${cats.map((c) => '${parseStr(c['emoji']) ?? ''}${parseStr(c['name']) ?? ''}').join(', ')} stats'),
              style: TextStyle(color: p.muted, fontSize: 10.5),
            ),
          ]),
        );
      },
    );
  }
}
