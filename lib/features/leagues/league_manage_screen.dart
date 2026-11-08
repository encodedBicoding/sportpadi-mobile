import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/links/web_handoff.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/leagues/leagues_repository.dart';
import 'package:sportpadi_mobile/features/leagues/league_commercials.dart';
import 'package:sportpadi_mobile/features/leagues/league_sheets.dart';
import 'package:sportpadi_mobile/features/tournaments/registration_card.dart';
import 'package:sportpadi_mobile/features/leagues/league_venues.dart';
import 'package:sportpadi_mobile/features/leagues/league_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// The organiser's league console (web `/groups/[id]/leagues/[leagueId]`):
/// Overview · Teams · Fixtures · Table · MVPs · Eligibility & penalties.
class LeagueManageScreen extends ConsumerStatefulWidget {
  const LeagueManageScreen(
      {super.key, required this.groupId, required this.leagueId, this.initialTab});
  final String groupId;
  final String leagueId;
  final String? initialTab;

  @override
  ConsumerState<LeagueManageScreen> createState() => _LeagueManageScreenState();
}

List<(String, String)> get _tabs => [
      ('overview', l10n.league_overview),
      ('teams', l10n.league_teams),
      ('fixtures', l10n.league_fixtures),
      ('venues', l10n.league_venuesTab),
      ('table', l10n.league_table),
      ('mvps', l10n.league_mvps),
      ('integrity', l10n.league_p5EligibilityTab),
    ];

class _LeagueManageScreenState extends ConsumerState<LeagueManageScreen> {
  late String _tab;

  @override
  void initState() {
    super.initState();
    _tab = _tabs.any((t) => t.$1 == widget.initialTab)
        ? widget.initialTab!
        : 'overview';
  }

  AutoDisposeFutureProvider<J> get _prov => leagueManageProvider(widget.leagueId);
  void _refresh() => ref.invalidate(_prov);

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(_prov);
    final d = q.valueOrNull;
    final l = d?.o('league');
    return SpSubPage(
      title: l?.str('competitionName', context.l10n.league_league) ?? context.l10n.league_league,
      subtitle: l == null
          ? null
          : [l.s('season'), l.s('division')].whereType<String>().join(' · '),
      actions: [
        if (l != null && l.s('status') != 'draft')
          SpRoundButton(
              icon: Icons.open_in_new_rounded,
              tooltip: context.l10n.league_publicPage,
              onTap: () => context.push('/leagues/${l.str('slug')}')),
      ],
      body: AsyncView(
        value: q,
        onRetry: _refresh,
        data: (d) => RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              SizedBox(
                height: 40,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final t in _tabs)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(t.$1 == 'mvps' && d.i('mvpsToConfirm') > 0
                            ? '${t.$2} · ${d.i('mvpsToConfirm')}'
                            : t.$2),
                        selected: _tab == t.$1,
                        onSelected: (_) => setState(() => _tab = t.$1),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              ...switch (_tab) {
                'teams' => _teams(d),
                'fixtures' => _fixtures(d),
                'venues' => [
                    LeagueVenuesSection(leagueId: widget.leagueId, onChanged: _refresh),
                  ],
                'table' => _table(d),
                'mvps' => _mvps(d),
                'integrity' => _integrity(d),
                _ => _overview(d),
              },
            ],
          ),
        ),
      ),
    );
  }

  /* ── Overview ──────────────────────────────────────────────────────── */

  List<Widget> _overview(J d) {
    final p = context.palette;
    final l = d.o('league')!;
    final id = l.str('id');
    final status = l.str('status');
    final lock = l.date('rosterLockAt');
    return [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: p.hero, borderRadius: BorderRadius.circular(26)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((leagueStatusLabel[status] ?? status).toUpperCase(),
              style: TextStyle(
                  color: p.accent,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1)),
          const SizedBox(height: 6),
          Text(l.str('title'),
              style: TextStyle(
                  color: p.onHero, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(l.str('format'),
              style: TextStyle(color: p.heroMuted, fontSize: 12.5)),
          const SizedBox(height: 4),
          Text(
              lock == null
                  ? context.l10n.league_noRosterCutoffNoLeague
                  : l.b('rosterLocked')
                      ? context.l10n.league_p5RosterCutoffLocked(MaterialLocalizations.of(context).formatMediumDate(lock))
                      : context.l10n.league_p5RosterCutoffOn(MaterialLocalizations.of(context).formatMediumDate(lock)),
              style: TextStyle(color: p.heroMuted, fontSize: 12.5)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (status == 'draft')
              _heroBtn(
                  context.l10n.league_publishFixtures,
                  Icons.check_circle_rounded,
                  d.b('canPublish'),
                  () => leagueAction(context, ref, 'publish', {'leagueId': id},
                      success: context.l10n.league_publishedTeamsAndPlayersHaveBeenTold,
                      refresh: [_prov]),
                  primary: true),
            _heroBtn(context.l10n.league_settings, Icons.tune_rounded, true,
                () => _settingsSheet(d)),
            _heroBtn(
                context.l10n.league_recalculate,
                Icons.refresh_rounded,
                true,
                () => leagueAction(context, ref, 'recompute', {'leagueId': id},
                    success: context.l10n.league_tableRecalculated, refresh: [_prov])),
          ]),
        ]),
      ),
      if (status == 'draft') ...[
        const SizedBox(height: 14),
        GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SpSectionTitle(context.l10n.league_beforeYouPublish),
            const SizedBox(height: 8),
            for (final c in d.list('checklist'))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                          c.b('done')
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 20,
                          color: c.b('done') ? p.greenText : p.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.str('label'),
                                  style: TextStyle(
                                      color: p.ink,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600)),
                              if (c.s('detail') != null)
                                Text(c.str('detail'),
                                    style: TextStyle(
                                        color: p.muted, fontSize: 12)),
                            ]),
                      ),
                    ]),
              ),
          ]),
        ),
      ],
      if (status == 'completed') ..._seasonEnd(d),
      if (d.list('divisions').length > 1) ...[
        const SizedBox(height: 14),
        GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SpSectionTitle(context.l10n.league_divisions2(l.str('season'))),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final dv in d.list('divisions'))
                SpPill(
                    label: dv.str('division', context.l10n.league_main),
                    tone: dv.s('id') == id ? SpPillTone.ink : SpPillTone.soft,
                    onTap: dv.s('id') == id
                        ? null
                        : () => context.pushReplacement(
                            '/groups/${widget.groupId}/leagues/${dv.str('id')}')),
            ]),
          ]),
        ),
      ],
      // Sponsors & match tickets, set up right here.
      const SizedBox(height: 14),
      GlassCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          ListTile(
            leading: SpIconTile(Icons.handshake_rounded, size: 38, iconSize: 19, bg: p.surface2, fg: p.ink),
            title: Text(context.l10n.league_sponsors, style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
            subtitle: Text([
              if (d.o('sponsorTerms')?.b('accepted') != true) context.l10n.league_acceptTheSponsorshipTermsToStart,
              if (d.o('sponsorTerms')?.b('accepted') == true)
                context.l10n.league_p5SpotsUsed(d.o('spots')?.i('owned') ?? 0, d.list('sponsors').length),
              if (d.list('sponsors').isNotEmpty) d.list('sponsors').map((x) => x.str('name')).join(', '),
            ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Icon(Icons.chevron_right_rounded, color: p.muted),
            onTap: () => showSponsorsSheet(context, ref, data: d, groupId: widget.groupId),
          ),
          Divider(height: 1, color: p.surface2),
          ListTile(
            leading: SpIconTile(Icons.confirmation_number_outlined, size: 38, iconSize: 19, bg: p.surface2, fg: p.ink),
            title: Text(context.l10n.league_matchTickets, style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
            subtitle: Text(d.o('ticketing')?.b('enabled') == true
                ? context.l10n.league_onOnSale(d.o('tickets')?.i('withTicket') ?? 0)
                : context.l10n.league_offSellSpectatorTicketsFor),
            trailing: Icon(Icons.chevron_right_rounded, color: p.muted),
            onTap: () => showTicketsSheet(context, ref, data: d),
          ),
        ]),
      ),
    ];
  }

  Widget _heroBtn(String label, IconData icon, bool enabled, VoidCallback onTap,
      {bool primary = false}) {
    final p = context.palette;
    return Material(
      color: primary ? Colors.white : Colors.white.withAlpha(26),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: primary ? p.hero : Colors.white),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: primary ? p.hero : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _seasonEnd(J d) {
    final p = context.palette;
    final l = d.o('league')!;
    final awards = d.list('awards');
    final champion = awards.where((a) => a.s('kind') == 'champion').firstOrNull;
    final pos =
        awards.where((a) => a.s('key') == 'player_of_season').firstOrNull;
    return [
      const SizedBox(height: 14),
      GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SpSectionTitle(context.l10n.league_seasonAwards),
          if (champion?.o('team') != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                Icon(Icons.emoji_events_rounded, color: p.greenText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(context.l10n.league_champions3(champion!.o('team')!.str('name')),
                      style: TextStyle(
                          color: p.ink, fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
          for (final a in awards.where((a) => a.s('kind') == 'placing'))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${a.str('label')} — ${a.o('team')?.str('name') ?? ''}',
                  style: TextStyle(color: p.ink, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          for (final a in awards.where((a) => a.s('kind') == 'stat'))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  '${a.str('label')} — ${a.o('player')?.str('name') ?? ''} (${a.d('value')?.round() ?? 0})',
                  style: TextStyle(color: p.ink, fontSize: 13)),
            ),
        ]),
      ),
      if (pos != null) ...[
        const SizedBox(height: 12),
        GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SpSectionTitle(context.l10n.league_playerOfTheSeason,
                trailing: SpBadge(
                    pos.s('status') == 'published'
                        ? context.l10n.league_published
                        : pos.s('status') == 'none'
                            ? context.l10n.league_none
                            : context.l10n.league_yourCall,
                    tone: pos.s('status') == 'published'
                        ? p.greenText
                        : p.orangeInk)),
            const SizedBox(height: 4),
            Text(context.l10n.league_recommendedFromPublishedMatchMVPs2,
                style: TextStyle(color: p.muted, fontSize: 12)),
            const SizedBox(height: 8),
            for (final c in pos.list('candidates'))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                selected: pos.o('player')?.s('id') == c.s('playerId'),
                title: Text(c.str('name'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                    context.l10n.league_mVPsScore(c.str('teamName'), c.i('mvps'), c.d('score') ?? 0)),
                trailing: SpPill(
                  label: context.l10n.league_publish,
                  height: 32,
                  onTap: () => leagueAction(
                      context,
                      ref,
                      'setSeasonAward',
                      {
                        'leagueId': l.str('id'),
                        'playerId': c.str('playerId'),
                        'publish': true
                      },
                      success: context.l10n.league_playerOfTheSeasonPublished,
                      refresh: [_prov]),
                ),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      GlassCard(
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.l10n.league_nextSeason,
                  style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
              Text(context.l10n.league_startAgainWithTheseTeams(l.str('competitionName')),
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          ),
          SpPill(
            label: context.l10n.league_start,
            onTap: () async {
              // The season planner (placements per division) is on the web for now.
              final url = await signedInWebUriFor(
                  ref, '/groups/${widget.groupId}/leagues/${l.str('id')}');
              await launchUrl(url, mode: LaunchMode.inAppBrowserView);
            },
          ),
        ]),
      ),
    ];
  }

  // What each league setting means (the ⓘ beside its label; same copy as the web).
  static String get _tipTier => l10n.league_settingTipTier;
  static String get _tipGoUp => l10n.league_settingTipGoUp;
  static String get _tipGoDown => l10n.league_settingTipGoDown;
  static String get _tipRosterCutoff => l10n.league_settingTipRosterCutoff;

  Future<void> _settingsSheet(J d) async {
    final l = d.o('league')!;
    DateTime? lock = l.date('rosterLockAt');
    final tier = TextEditingController(
        text: l.iOrNull('divisionTier')?.toString() ?? '');
    final promote = TextEditingController(
        text: l.iOrNull('promoteCount')?.toString() ?? '');
    final relegate = TextEditingController(
        text: l.iOrNull('relegateCount')?.toString() ?? '');
    final division = TextEditingController(text: l.s('division') ?? '');
    var awayGoals = d.b('awayGoals');
    // Entry fee per invited team, in the group wallet's currency (major units in the box).
    final feeCur = d.o('entryFee')?.s('currency') ?? d.o('wallet')?.s('currency');
    final feeExp = d.o('entryFee')?.iOrNull('exponent') ?? d.o('wallet')?.iOrNull('exponent') ?? 2;
    var feeDiv = 1;
    for (var i = 0; i < feeExp; i++) {
      feeDiv *= 10;
    }
    final feeNow = d.o('entryFee')?.i('amountMinor');
    final fee = TextEditingController(
        text: feeNow == null ? '' : (feeNow % feeDiv == 0 ? '${feeNow ~/ feeDiv}' : (feeNow / feeDiv).toStringAsFixed(feeExp)));
    // Fan / player MVP poll.
    final pollNow = d.o('mvpPoll');
    var pollOn = pollNow?.b('enabled') ?? false;
    var pollAudience = pollNow?.s('audience') ?? 'players';
    var pollWeight = pollNow?.d('weight') ?? 0.25;
    var pollHours = pollNow?.i('hours', 48) ?? 48;
    // Fixed once a second leg has been played (it would change results).
    final secondLegPlayed = d
        .list('fixtures')
        .any((f) => f.i('leg') == 2 && f.s('bracketKey') != null && f.s('status') == 'completed');
    await showSpSheet<void>(context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setS) {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SpSheetHeader(
                  title: l10n.league_leagueSettings, icon: Icons.tune_rounded),
              if (l.b('usesDivisions')) ...[
                FieldLabel(l10n.league_division),
                TextField(
                    controller: division,
                    decoration: fieldDeco(ctx, l10n.league_division1)),
              ],
              if (l.b('usesPromotionRelegation'))
                Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FieldLabel(l10n.league_tier, tip: _tipTier),
                          TextField(
                              controller: tier,
                              keyboardType: TextInputType.number,
                              decoration: fieldDeco(ctx, '1')),
                        ]),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FieldLabel(l10n.league_goUp, tip: _tipGoUp),
                          TextField(
                              controller: promote,
                              keyboardType: TextInputType.number,
                              decoration: fieldDeco(ctx, '0')),
                        ]),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FieldLabel(l10n.league_goDown, tip: _tipGoDown),
                          TextField(
                              controller: relegate,
                              keyboardType: TextInputType.number,
                              decoration: fieldDeco(ctx, '0')),
                        ]),
                  ),
                ]),
              FieldLabel(l10n.league_rosterCutoff2, tip: _tipRosterCutoff),
              PickField(
                text: lock == null
                    ? l10n.league_noCutoff
                    : '${MaterialLocalizations.of(ctx).formatFullDate(lock!)}, '
                        '${MaterialLocalizations.of(ctx).formatTimeOfDay(TimeOfDay.fromDateTime(lock!))}',
                onClear: lock == null ? null : () => setS(() => lock = null),
                onTap: () async {
                  final day = await pickDay(ctx, lock);
                  if (day == null || !ctx.mounted) return;
                  final t = await pickHhmm(
                      ctx,
                      lock == null
                          ? '23:59'
                          : '${lock!.hour}:${lock!.minute.toString().padLeft(2, '0')}');
                  final hm = (t ?? '23:59').split(':');
                  setS(() => lock = DateTime(day.year, day.month, day.day,
                      int.parse(hm[0]), int.parse(hm[1])));
                },
              ),
              FieldLabel(l10n.league_entryFeePerTeam),
              if (feeCur != null)
                TextField(
                    controller: fee,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: fieldDeco(ctx, l10n.league_free).copyWith(prefixText: '$feeCur  '))
              else
                Text(l10n.league_activateYourGroupWalletTo,
                    style: TextStyle(color: ctx.palette.muted, fontSize: 12)),
              const SizedBox(height: 6),
              Text(
                  l10n.league_invitedTeamsPayItTo,
                  style: TextStyle(color: ctx.palette.muted, fontSize: 11.5)),
              if (l.b('mvpEnabled')) ...[
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.league_mvpPoll, style: TextStyle(color: ctx.palette.ink, fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      l10n.league_afterEachResultAVote,
                      style: TextStyle(color: ctx.palette.muted, fontSize: 11.5)),
                  value: pollOn,
                  onChanged: (v) => setS(() => pollOn = v),
                ),
                if (pollOn) ...[
                  FieldLabel(l10n.league_whoVotes),
                  Wrap(spacing: 6, children: [
                    for (final (v, t) in [('players', l10n.league_leaguePlayers), ('everyone', l10n.league_anyoneSignedIn)])
                      ChoiceChip(label: Text(t), selected: pollAudience == v, onSelected: (_) => setS(() => pollAudience = v)),
                  ]),
                  FieldLabel(l10n.league_countsFor),
                  Wrap(spacing: 6, children: [
                    for (final w in const [0.1, 0.25, 0.5])
                      ChoiceChip(label: Text('${(w * 100).round()}%'), selected: pollWeight == w, onSelected: (_) => setS(() => pollWeight = w)),
                  ]),
                  FieldLabel(l10n.league_openFor),
                  Wrap(spacing: 6, children: [
                    for (final (h, t) in [(24, l10n.league_t24Hours), (48, l10n.league_t48Hours), (72, l10n.league_t3Days)])
                      ChoiceChip(label: Text(t), selected: pollHours == h, onSelected: (_) => setS(() => pollHours = h)),
                  ]),
                ],
              ],
              if (d.b('hasTwoLegTies')) ...[
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.league_awayGoalsRule,
                      style: TextStyle(color: ctx.palette.ink, fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      secondLegPlayed
                          ? l10n.league_fixedForThisSeasonA
                          : l10n.league_twoLegTiesLevelOn2,
                      style: TextStyle(color: ctx.palette.muted, fontSize: 11.5)),
                  value: awayGoals,
                  onChanged: secondLegPlayed ? null : (v) => setS(() => awayGoals = v),
                ),
              ],
              const SizedBox(height: 16),
              SpButton(
                label: l10n.league_save,
                expand: true,
                onTap: () async {
                  final ok = await leagueAction(ctx, ref, 'update', {
                    'leagueId': l.str('id'),
                    if (l.b('usesDivisions'))
                      'division': division.text.trim().isEmpty
                          ? null
                          : division.text.trim(),
                    if (l.b('usesPromotionRelegation'))
                      'divisionTier': int.tryParse(tier.text.trim()),
                    if (l.b('usesPromotionRelegation'))
                      'promoteCount': int.tryParse(promote.text.trim()),
                    if (l.b('usesPromotionRelegation'))
                      'relegateCount': int.tryParse(relegate.text.trim()),
                    'rosterLockAt': lock?.toUtc().toIso8601String(),
                    if (d.b('hasTwoLegTies') && !secondLegPlayed) 'awayGoals': awayGoals,
                    if (feeCur != null)
                      'entryFeeMinor': fee.text.trim().isEmpty ? null : ((double.tryParse(fee.text.trim()) ?? 0) * feeDiv).round(),
                    if (l.b('mvpEnabled'))
                      'mvpPoll': {'enabled': pollOn, 'audience': pollAudience, 'weight': pollWeight, 'hours': pollHours},
                  }, success: l10n.league_saved, refresh: [_prov]);
                  if (ok && ctx.mounted) Navigator.of(ctx).pop();
                },
              ),
            ]);
      });
    });
  }

  /* ── Teams ─────────────────────────────────────────────────────────── */

  /// "Paid CAD 50" / "Fee CAD 50 due" for an invited team's entry fee.
  String? _feeText(J? f) {
    if (f == null) return null;
    final amount = spotMoney(f.i('amountMinor'), f.str('currency'), f.i('exponent', 2));
    return switch (f.str('status')) {
      'paid' => l10n.league_p5FeePaid(amount),
      'refunded' => l10n.league_p5FeeRefunded,
      'pending' => l10n.league_p5FeePaying,
      _ => l10n.league_p5FeeDue(amount),
    };
  }

  List<Widget> _teams(J d) {
    final p = context.palette;
    final l = d.o('league')!;
    final id = l.str('id');
    final status = l.str('status');
    final live = d
        .list('teams')
        .where((t) => t.s('status') == 'approved' || t.s('status') == 'pending')
        .toList();
    final otherDivs =
        d.list('divisions').where((x) => x.s('id') != id).toList();
    final reg = d.o('registration');
    return [
      // Who can enter: the registration link, its settings (documents,
      // approval, grade) and teams that registered and await a decision.
      if (reg != null) ...[
        RegistrationCard(
          eventId: id,
          isLeague: true,
          categoryId: l.s('categoryId'),
          reg: reg.raw,
          rows: [
            for (final t in d.list('teams'))
              {
                'id': t.s('id'),
                'status': t.s('status') == 'declined' ? 'rejected' : t.s('status'),
                'source': t.s('source') ?? 'invite',
                'feeStatus': t.o('fee')?.s('status') == 'due' ? 'pending' : (t.o('fee')?.s('status') ?? 'none'),
                'feeMinor': t.o('fee')?.iOrNull('amountMinor'),
                'feeCurrency': t.o('fee')?.s('currency'),
                'feeCurrencyExponent': t.o('fee')?.iOrNull('exponent'),
                'createdAt': t.s('createdAt'),
                'review': t.o('review')?.raw,
                'documents': t.raw['documents'],
                'team': {
                  'id': t.s('teamId'),
                  'name': t.s('name'),
                  'username': t.s('slug'),
                  'logoUrl': t.s('logoUrl'),
                  'kitPrimary': t.s('kitPrimary'),
                  'groupName': t.s('groupName'),
                },
              },
          ],
          maxTeams: l.i('teamsMax', 20),
          ended: status == 'completed' || status == 'cancelled',
        ),
        const SizedBox(height: 14),
      ],
      if (status != 'completed' && status != 'cancelled')
        SpButton(
            label: context.l10n.league_inviteTeams,
            icon: Icons.group_add_rounded,
            expand: true,
            onTap: () => showInviteTeamSheet(context, ref, leagueId: id)),
      const SizedBox(height: 12),
      SpSectionTitle(context.l10n.league_inThisLeague,
          count: live.where((t) => t.s('status') == 'approved').length),
      const SizedBox(height: 8),
      if (live.isEmpty)
        SpEmpty(
            icon: Icons.groups_rounded,
            text: context.l10n.league_inviteTeamsYourOwnTeams)
      else
        SpListCard(children: [
          for (final t in live)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Crest(
                    logoUrl: t.s('logoUrl'),
                    label: t.s('name'),
                    kitPrimary: t.s('kitPrimary'),
                    size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.str('name'),
                            style: TextStyle(
                                color: p.ink, fontWeight: FontWeight.w700)),
                        Text(
                            [
                              t.str('groupName'),
                              if (t.s('status') == 'approved') context.l10n.league_p5RegisteredCount(t.i('registered')),
                              _feeText(t.o('fee')),
                            ].whereType<String>().join(' · '),
                            style: TextStyle(color: p.muted, fontSize: 11.5)),
                      ]),
                ),
                SpBadge(
                    t.s('status') == 'approved'
                        ? context.l10n.league_inLabel
                        : t.s('source') == 'registration'
                            ? context.l10n.league_awaitingApproval
                            : context.l10n.league_invited,
                    tone: t.s('status') == 'approved'
                        ? p.greenText
                        : p.orangeInk),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'roster') {
                      context.push(
                          '/groups/${widget.groupId}/leagues/$id/roster/${t.str('teamId')}');
                    } else if (v == 'remove') {
                      final fee = t.o('fee');
                      if (fee?.str('status') == 'paid') {
                        final yes = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: Text(l10n.league_removeThisTeam),
                            content: Text(
                                l10n.league_theirEntryFeeIsRefunded(spotMoney(fee!.i('amountMinor'), fee.str('currency'), fee.i('exponent', 2)))),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l10n.league_keep)),
                              TextButton(onPressed: () => Navigator.pop(c, true), child: Text(l10n.league_removeRefund)),
                            ],
                          ),
                        );
                        if (yes != true || !mounted) return;
                      }
                      if (!mounted) return;
                      await leagueAction(context, ref, 'removeTeam',
                          {'entryId': t.str('id')},
                          success: fee?.str('status') == 'paid' ? l10n.league_removedEntryFeeRefunded : l10n.league_removed, refresh: [_prov]);
                    } else if (v.startsWith('move:')) {
                      await leagueAction(context, ref, 'moveTeam',
                          {'entryId': t.str('id'), 'toLeagueId': v.substring(5)},
                          success: l10n.league_teamMoved(''), refresh: [_prov]);
                    }
                  },
                  itemBuilder: (_) => [
                    if (t.s('status') == 'approved')
                      PopupMenuItem(value: 'roster', child: Text(context.l10n.league_roster)),
                    if (t.s('status') == 'approved')
                      for (final dv in otherDivs)
                        PopupMenuItem(
                            value: 'move:${dv.str('id')}',
                            child: Text(context.l10n.league_moveTo(dv.str('division', context.l10n.league_main)))),
                    if (t.s('status') == 'pending' || status == 'draft')
                      PopupMenuItem(
                          value: 'remove',
                          child: Text(t.s('status') == 'pending'
                              ? context.l10n.league_cancelInvite
                              : context.l10n.league_remove)),
                  ],
                ),
              ]),
            ),
        ]),
      if (d.b('fixturesStale') && status == 'draft')
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
              context.l10n.league_teamsChangedSinceTheFixtures2,
              style: TextStyle(color: p.orangeInk, fontSize: 12.5)),
        ),
    ];
  }

  /* ── Fixtures (stage panel + rounds / bracket) ─────────────────────── */

  List<Widget> _fixtures(J d) {
    final p = context.palette;
    final l = d.o('league')!;
    final id = l.str('id');
    final stages = d.list('stages');
    final fixtures = d.list('fixtures');
    Widget? actions(J f) {
      final editable =
          !['completed', 'live', 'cancelled'].contains(f.s('status'));
      if (!editable && !f.b('published')) return null;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        if (editable)
          IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.edit_rounded, size: 17, color: p.muted),
              onPressed: () =>
                  showFixtureSheet(context, ref, leagueId: id, f: f)),
        if (f.b('published') && f.s('status') != 'cancelled')
          IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.gavel_rounded, size: 17, color: p.muted),
              onPressed: () =>
                  showForfeitSheet(context, ref, leagueId: id, f: f)),
        // Hand-made draft fixtures can be taken out again.
        if (!f.b('published') &&
            f.s('bracketKey') == null &&
            stages.any((st) => st.s('id') == f.s('stageId') && st.b('manual')))
          IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.delete_outline_rounded, size: 17, color: p.danger),
              onPressed: () => leagueAction(context, ref, 'removeFixture', {'fixtureId': f.str('id')},
                  success: context.l10n.league_fixtureRemoved, refresh: [_prov])),
      ]);
    }

    return [
      if (fixtures.isNotEmpty) LeagueVenueNudge(leagueId: id, onOpen: () => setState(() => _tab = 'venues')),
      SpListCard(children: [
        for (final (i, st) in stages.indexed) _stageRow(d, st, i),
      ]),
      for (final st in stages)
        if (fixtures.any((f) => f.s('stageId') == st.s('id'))) ...[
          if (stages.length > 1)
            Padding(
                padding: const EdgeInsets.fromLTRB(2, 18, 2, 0),
                child: SpSectionTitle(st.str('name'))),
          if (st.s('kind') == 'knockout')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: BracketView(
                  padding: EdgeInsets.zero,
                  fixtures: fixtures
                      .where((f) => f.s('stageId') == st.s('id'))
                      .toList(),
                  actions: actions),
            )
          else
            RoundsView(
                fixtures:
                    fixtures.where((f) => f.s('stageId') == st.s('id')).toList(),
                trailing: actions),
        ],
      if (fixtures.isEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SpEmpty(
                icon: Icons.calendar_month_rounded,
                text: context.l10n.league_noFixturesYetDrawThe)),
    ];
  }

  Widget _stageRow(J d, J st, int i) {
    final p = context.palette;
    final l = d.o('league')!;
    final id = l.str('id');
    final firstDraft = i == 0 && l.s('status') == 'draft';
    final drawing = firstDraft || st.s('status') == 'drafting';
    final action = st.s('action');
    final cr = st.o('confirmRound');
    final manualTables = st.b('manual') &&
        d.list('standings').any((t) => t.s('stageId') == st.s('id'));
    final pills = <Widget>[
      if (drawing && manualTables)
        SpPill(
          label: context.l10n.league_addFixture,
          icon: Icons.add_rounded,
          height: 34,
          onTap: () => showAddFixtureSheet(context, ref, data: d, stage: st),
        ),
      if (drawing && !manualTables)
        SpPill(
          label: st.b('manual')
              ? (st.s('kind') == 'table' ? context.l10n.league_setUpTheTable : context.l10n.league_setUpTheTables)
              : st.i('fixtures') > 0
              ? context.l10n.league_redraw
              : st.s('kind') == 'knockout'
                  ? context.l10n.league_makeTheBracket
                  : st.s('kind') == 'groups'
                      ? context.l10n.league_drawTheGroups
                      : st.s('kind') == 'split'
                          ? context.l10n.league_drawTheTables
                          : context.l10n.league_drawFixtures,
          icon: Icons.casino_rounded,
          tone: st.i('fixtures') > 0 ? SpPillTone.soft : SpPillTone.ink,
          height: 34,
          onTap: () => leagueAction(context, ref, 'generateFixtures',
              {'leagueId': id, 'stageId': st.str('id')},
              success: context.l10n.league_p5Drawn, refresh: [_prov]),
        ),
      if (firstDraft && st.s('kind') != 'table')
        SpPill(
            label: st.s('kind') == 'split' ? context.l10n.league_pickTablesSeeds : context.l10n.league_seeding,
            icon: Icons.format_list_numbered_rounded,
            tone: SpPillTone.soft,
            height: 34,
            onTap: () => showDrawSetupSheet(context, ref,
                leagueId: id,
                stage: st,
                teams: d.list('teams').where((t) => t.s('status') == 'approved').toList())),
      if (drawing && manualTables)
        SpPill(
            label: context.l10n.league_redoTables,
            icon: Icons.shuffle_rounded,
            tone: SpPillTone.soft,
            height: 34,
            onTap: () async {
              if (st.i('fixtures') > 0) {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text(l10n.league_setTheTablesUpAgain2),
                    content: Text(l10n.league_theFixturesYouAddedTo),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l10n.league_cancel)),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: Text(l10n.league_redo)),
                    ],
                  ),
                );
                if (ok != true || !mounted) return;
              }
              if (!mounted) return;
              await leagueAction(context, ref, 'generateFixtures',
                  {'leagueId': id, 'stageId': st.str('id'), 'reshuffle': true},
                  success: l10n.league_tablesSetUp, refresh: [_prov]);
            }),
      if (drawing && st.i('fixtures') > 0 && !st.b('manual')) ...[
        SpPill(
            label: context.l10n.league_newDraw,
            icon: Icons.shuffle_rounded,
            tone: SpPillTone.soft,
            height: 34,
            onTap: () => leagueAction(context, ref, 'generateFixtures',
                {'leagueId': id, 'stageId': st.str('id'), 'reshuffle': true},
                success: context.l10n.league_p5Redrawn, refresh: [_prov])),
        SpPill(
            label: context.l10n.league_setDates,
            icon: Icons.calendar_month_rounded,
            tone: SpPillTone.soft,
            height: 34,
            onTap: () => showScheduleSheet(context, ref,
                leagueId: id,
                stageId: st.str('id'),
                defaultStart: i == 0 ? l.s('seasonStartsOn') : null)),
      ],
      if (action == 'open')
        SpPill(
            label: context.l10n.league_open2(st.str('name').toLowerCase()),
            icon: Icons.check_circle_rounded,
            height: 34,
            onTap: () => leagueAction(
                context, ref, 'openStage', {'stageId': st.str('id')},
                success: context.l10n.league_stageOpenedTeamsHaveBeen,
                refresh: [_prov])),
      if (action == 'confirm_round' && cr != null)
        SpPill(
          label: context.l10n.league_confirmWinners(cr.str('name').toLowerCase()),
          icon: Icons.account_tree_rounded,
          height: 34,
          onTap: () => showConfirmRoundSheet(context, ref,
              leagueId: id,
              stageId: st.str('id'),
              round: cr.i('round'),
              name: cr.str('name'),
              ties: d
                  .list('fixtures')
                  .where((f) =>
                      f.s('stageId') == st.s('id') &&
                      f.i('round') == cr.i('round') &&
                      f.s('status') != 'cancelled')
                  .toList()),
        ),
      if (action == 'close')
        SpPill(
            label: context.l10n.league_close(st.str('name').toLowerCase()),
            tone: st.b('allDone') ? SpPillTone.ink : SpPillTone.soft,
            height: 34,
            onTap: st.b('allDone')
                ? () => leagueAction(
                    context, ref, 'closeStage', {'stageId': st.str('id')},
                    success: context.l10n.league_stageClosed, refresh: [_prov])
                : null),
      if (action == 'advance')
        SpPill(
            label: context.l10n.league_chooseWhoGoesThrough,
            icon: Icons.swap_vert_rounded,
            height: 34,
            onTap: () => showAdvanceSheet(context, ref, leagueId: id)),
      if (action == 'finish')
        SpPill(
            label: context.l10n.league_closeTheSeason,
            icon: Icons.emoji_events_rounded,
            height: 34,
            onTap: () async {
              final yes = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                        title: Text(l10n.league_closeTheSeason2),
                        content: Text(
                            l10n.league_awardsAreWorkedOutFrom),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: Text(l10n.league_notYet)),
                          TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: Text(l10n.league_closeIt)),
                        ],
                      ));
              if (yes == true && mounted) {
                await leagueAction(
                    context, ref, 'complete', {'leagueId': id},
                    success: l10n.league_seasonClosedAwardsAreIn,
                    refresh: [_prov]);
              }
            }),
    ];
    final rounds = st.list('rounds');
    final waitingRound = st.s('kind') == 'knockout' &&
            st.s('status') == 'open' &&
            action != 'confirm_round'
        ? rounds
            .where((r) =>
                !r.b('isFinal') && !r.b('confirmed') && r.i('decided') < r.i('ties'))
            .firstOrNull
        : null;
    final hint = action == 'publish'
        ? context.l10n.league_publishFromOverviewWhenYoure
        : waitingRound != null
            ? context.l10n.league_p5RoundDecidedHint(waitingRound.str('name'), waitingRound.i('decided'), waitingRound.i('ties'))
            : action == 'close' && !st.b('allDone')
                ? context.l10n.league_closesOnceEveryMatchIs
                : null;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
              radius: 13,
              backgroundColor: p.surface2,
              child: Text('${i + 1}',
                  style: TextStyle(
                      color: p.ink, fontSize: 12, fontWeight: FontWeight.w800))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(st.str('name'),
                  style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
              Text(
                  [
                    stageKindLabel(st.s('kind')),
                    if (st.s('kind') == 'split')
                      st.list('splits').map((x) => x.str('name')).join(' v '),
                    if (st.s('pairingRule') == 'cross') context.l10n.league_p5GamesEach(st.iOrNull('matchesPerTeam') ?? 3),
                    if (i == 0 && st.o('setup')?.b('seeded') == true) context.l10n.league_p5Seeded,
                    if (st.i('fixtures') > 0)
                      context.l10n.league_p5PlayedOfTotal(st.i('done'), st.i('fixtures')),
                    if (st.o('advance')?.s('rule') == 'top_n_per_table')
                      context.l10n.league_p5TopGoThrough(st.o('advance')!.i('n')),
                  ].join(' · '),
                  style: TextStyle(color: p.muted, fontSize: 11.5)),
            ]),
          ),
          SpBadge(firstDraft
              ? context.l10n.league_draft
              : stageStatusLabel[st.s('status')] ?? st.str('status')),
        ]),
        if (pills.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: pills),
        ],
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(hint, style: TextStyle(color: p.muted, fontSize: 11.5)),
        ],
      ]),
    );
  }

  /* ── Table ─────────────────────────────────────────────────────────── */

  List<Widget> _table(J d) {
    final tables = d.list('standings');
    if (tables.isEmpty) {
      return [
        SpEmpty(
            icon: Icons.leaderboard_rounded,
            text: context.l10n.league_theTableAppearsOnceTeams)
      ];
    }
    return [
      for (final t in tables) ...[
        if (tables.length > 1)
          Padding(
              padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
              child: SpSectionTitle(t.str('name'))),
        StandingsTableView(rows: t.list('rows')),
        const SizedBox(height: 8),
      ],
    ];
  }

  /* ── MVPs ──────────────────────────────────────────────────────────── */

  List<Widget> _mvps(J d) {
    final p = context.palette;
    final l = d.o('league')!;
    if (!l.b('mvpEnabled')) {
      return [
        SpEmpty(
            icon: Icons.military_tech_rounded,
            text: context.l10n.league_thisLeagueFormatDoesntPick)
      ];
    }
    final list = [...d.list('mvps')]..sort((a, b) =>
        (b.s('status') == 'recommended' ? 1 : 0) -
        (a.s('status') == 'recommended' ? 1 : 0));
    if (list.isEmpty) {
      return [
        SpEmpty(
            icon: Icons.military_tech_rounded,
            text:
                context.l10n.league_onceAMatchFinishesIts)
      ];
    }
    final byId = {for (final f in d.list('fixtures')) f.str('id'): f};
    return [
      Text(
          context.l10n.league_recommendationsComeFromEachPlayers2,
          style: TextStyle(color: p.muted, fontSize: 12.5)),
      const SizedBox(height: 10),
      for (final m in list) ...[
        _MvpCard(m: m, f: byId[m.str('fixtureId')], leagueId: l.str('id')),
        const SizedBox(height: 10),
      ],
    ];
  }

  /* ── Eligibility & penalties ───────────────────────────────────────── */

  List<Widget> _integrity(J d) {
    final p = context.palette;
    final l = d.o('league')!;
    final id = l.str('id');
    final checks = ref.watch(leagueChecksProvider(id));
    final sanctions = d.list('sanctions');
    return [
      if (l.date('rosterLockAt') == null)
        GlassCard(
            child: Text(
                context.l10n.league_setARosterCutoffOverview))
      else
        GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SpSectionTitle(context.l10n.league_checkAPlayer),
            const SizedBox(height: 6),
            Text(
                context.l10n.league_scanThePlayersLeaguePass,
                style: TextStyle(color: p.muted, fontSize: 12.5)),
            const SizedBox(height: 12),
            SpButton(
                label: context.l10n.league_scanLeaguePass,
                icon: Icons.qr_code_scanner_rounded,
                expand: true,
                onTap: () => _scan(d)),
          ]),
        ),
      const SizedBox(height: 16),
      SpSectionTitle(context.l10n.league_forfeits,
          count: sanctions.where((s) => s.s('status') == 'active').length),
      const SizedBox(height: 8),
      if (sanctions.isEmpty)
        SpEmpty(
            icon: Icons.gavel_rounded,
            text: context.l10n.league_noPenaltiesUseTheGavel)
      else
        SpListCard(children: [
          for (final s in sanctions)
            ListTile(
              title: Text(
                  context.l10n.league_forfeited2(s.str('teamName'), s.str('publicReason')),
                  style: TextStyle(color: p.ink, fontSize: 13.5)),
              subtitle: Text(s.s('status') == 'revoked'
                  ? context.l10n.league_revoked2
                  : (s.s('privateNote') ?? '')),
              trailing: s.s('status') == 'active'
                  ? TextButton(
                      onPressed: () => leagueAction(context, ref,
                          'revokeSanction', {'sanctionId': s.str('id')},
                          success: context.l10n.league_forfeitRevoked, refresh: [_prov]),
                      child: Text(context.l10n.league_revoke))
                  : null,
            ),
        ]),
      const SizedBox(height: 16),
      SpSectionTitle(context.l10n.league_recentChecks),
      const SizedBox(height: 8),
      AsyncView(
        value: checks,
        data: (list) => list.isEmpty
            ? Text(context.l10n.league_noChecksYet, style: TextStyle(color: p.muted))
            : SpListCard(children: [
                for (final c in list.take(30))
                  ListTile(
                    dense: true,
                    leading: Icon(
                        c.s('result') == 'valid'
                            ? Icons.verified_rounded
                            : Icons.gpp_bad_rounded,
                        color:
                            c.s('result') == 'valid' ? p.greenText : p.danger),
                    title: Text(
                        '${c.str('playerName', context.l10n.league_unknownPlayer)}${c.s('teamName') != null ? ' · ${c.str('teamName')}' : ''}'),
                    subtitle: Text(_checkResultLabel(c.str('result'))),
                  ),
              ]),
      ),
    ];
  }

  /// A recent pass check's result, in words (the same titles as the scan sheet).
  String _checkResultLabel(String result) => switch (result) {
        'valid' => l10n.league_eligible,
        'not_registered' => l10n.league_notRegistered,
        'wrong_league' => l10n.league_differentLeague,
        'wrong_team' => l10n.league_notInThisMatch,
        'not_live' => l10n.league_passNotLiveYet,
        'expired' => l10n.league_expiredCode,
        'invalid' => l10n.league_invalid,
        'not_a_pass' => l10n.league_notALeaguePass,
        _ => result.replaceAll('_', ' '),
      };

  Future<void> _scan(J d) async {
    final raw = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const LeaguePassScanner()));
    if (raw == null || !mounted) return;
    final l = d.o('league')!;
    J res;
    try {
      res = J.of(await ref
          .read(leaguesRepositoryProvider)
          .mutate('verifyPass', {'leagueId': l.str('id'), 'raw': raw}));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
      return;
    }
    ref.invalidate(leagueChecksProvider(l.str('id')));
    if (!mounted) return;
    final p = context.palette;
    final titles = {
      'valid': (context.l10n.league_eligible, context.l10n.league_passValidHint),
      'not_registered': (
        context.l10n.league_notRegistered,
        context.l10n.league_passNotRegisteredHint
      ),
      'wrong_league': (context.l10n.league_differentLeague, context.l10n.league_passWrongLeagueHint),
      'wrong_team': (
        context.l10n.league_notInThisMatch,
        context.l10n.league_passWrongTeamHint
      ),
      'not_live': (
        context.l10n.league_passNotLiveYet,
        context.l10n.league_passNotLiveHint
      ),
      'expired': (
        context.l10n.league_expiredCode,
        context.l10n.league_passExpiredHint
      ),
      'invalid': (context.l10n.league_invalid, context.l10n.league_passInvalidHint),
      'not_a_pass': (context.l10n.league_notALeaguePass, context.l10n.league_passNotAPassHint),
    };
    final ok = res.s('result') == 'valid';
    final t = titles[res.s('result')] ?? titles['invalid']!;
    final player = res.o('player');
    await showSpSheet<void>(context, builder: (ctx) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SpSheetHeader(
              title: t.$1,
              subtitle: t.$2,
              icon: ok ? Icons.verified_rounded : Icons.gpp_bad_rounded,
              iconBg: ok ? p.accentTint : p.liveTint,
              iconFg: ok ? p.greenText : p.danger,
            ),
            if (player != null)
              GlassCard(
                child: Row(children: [
                  PersonAvatar(
                      url: player.s('avatarUrl'),
                      name: player.str('name', '?'),
                      size: 64),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(player.str('name'),
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800)),
                          Text(
                              [
                                player.o('team')?.s('name'),
                                if (player.iOrNull('shirtNumber') != null)
                                  '#${player.i('shirtNumber')}',
                                player.s('position'),
                              ].whereType<String>().join(' · '),
                              style: TextStyle(color: p.muted, fontSize: 12.5)),
                          if (player.b('afterLock'))
                            Text(l10n.league_addedAfterTheCutoff,
                                style: TextStyle(
                                    color: p.orangeInk, fontSize: 11.5)),
                        ]),
                  ),
                ]),
              ),
            if (!ok) ...[
              const SizedBox(height: 12),
              Text(
                  l10n.league_needToPenaliseATeam,
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ],
            const SizedBox(height: 14),
            SpButton(
                label: l10n.league_scanAnother,
                icon: Icons.qr_code_scanner_rounded,
                expand: true,
                onTap: () {
                  Navigator.of(ctx).pop();
                  _scan(d);
                }),
          ]);
    });
  }
}

class _MvpCard extends ConsumerStatefulWidget {
  const _MvpCard({required this.m, required this.f, required this.leagueId});
  final J m;
  final J? f;
  final String leagueId;
  @override
  ConsumerState<_MvpCard> createState() => _MvpCardState();
}

class _MvpCardState extends ConsumerState<_MvpCard> {
  String? _pick;

  @override
  void initState() {
    super.initState();
    // Undecided match with a poll that counts: start from the blended suggestion.
    final poll = widget.m.o('poll');
    _pick = widget.m.s('status') == 'recommended' && poll?.b('counts') == true && poll?.s('suggestedPlayerId') != null
        ? poll!.s('suggestedPlayerId')
        : widget.m.s('playerId');
  }

  /// The fan / player poll: tally, and the blended suggestion (tap a row to pick).
  Widget _poll(AppPalette p, J poll) {
    final total = poll.i('total');
    final closes = poll.date('closesAt');
    final suggested = poll.b('counts') ? poll.s('suggestedPlayerId') : null;
    final rows = poll.list('ranked').where((r) => r.i('votes') > 0 || r.s('playerId') == suggested).toList();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
            [
              context.l10n.league_mvpPollVotes(total),
              poll.b('open') && closes != null
                  ? context.l10n.league_p5PollCloses(MaterialLocalizations.of(context).formatShortMonthDay(closes), MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(closes)))
                  : context.l10n.league_p5PollClosed,
              if (!poll.b('counts')) context.l10n.league_p5TooFewVotes,
            ].join(' · '),
            style: TextStyle(color: p.ink, fontWeight: FontWeight.w700, fontSize: 12)),
        for (final r in rows)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _pick = r.s('playerId')),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: r.str('name')),
                      if (r.s('playerId') == suggested)
                        TextSpan(text: context.l10n.league_suggested, style: TextStyle(color: p.greenText, fontWeight: FontWeight.w800, fontSize: 11)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink, fontWeight: _pick == r.s('playerId') ? FontWeight.w800 : FontWeight.w600, fontSize: 12.5),
                  ),
                ),
                Text('${r.i('votes')} · ${((r.d('share') ?? 0) * 100).round()}%',
                    style: TextStyle(color: p.muted, fontSize: 12)),
                if (_pick == r.s('playerId')) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.check_rounded, size: 16, color: p.greenText),
                ],
              ]),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final m = widget.m;
    final f = widget.f;
    final status = m.s('status');
    Future<void> set(String? player, bool publish) => leagueAction(
        context,
        ref,
        'setMvp',
        {'fixtureId': m.str('fixtureId'), 'playerId': player, 'publish': publish},
        success: publish
            ? context.l10n.league_mvpPublished
            : player == null
                ? context.l10n.league_noMvpForThisMatch
                : context.l10n.league_savedNotPublic,
        refresh: [leagueManageProvider(widget.leagueId)]);
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SpIconTile(Icons.military_tech_rounded,
              size: 34,
              iconSize: 18,
              bg: status == 'published' ? p.accentTint : p.orangeTint,
              fg: status == 'published' ? p.greenText : p.orangeInk),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  f == null
                      ? context.l10n.league_match
                      : '${f.o('home')?.str('name')} ${f.i('homeScore')}–${f.i('awayScore')} ${f.o('away')?.str('name')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
              Text(
                  (status == 'published'
                          ? context.l10n.league_published2(m.o('player')?.str('displayName') ?? '—')
                          : status == 'none'
                              ? context.l10n.league_noMvp
                              : context.l10n.league_waitingForYou) +
                      (m.b('statsChanged')
                          ? context.l10n.league_statsChangedSinceCheckThe
                          : ''),
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        for (final (i, c) in m.list('candidates').indexed)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              color: _pick == c.s('playerId') ? p.accentTint : p.surface2,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => _pick = c.s('playerId')),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(children: [
                    SizedBox(
                        width: 18,
                        child: Text('${i + 1}',
                            style: TextStyle(
                                color: p.muted, fontWeight: FontWeight.w700))),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.str('name'),
                                style: TextStyle(
                                    color: p.ink, fontWeight: FontWeight.w600)),
                            Text(
                                [
                                  c.s('teamName'),
                                  for (final e in (c.o('breakdown')?.raw ??
                                          const <String, dynamic>{})
                                      .entries)
                                    '${e.value} ${e.key}',
                                ].whereType<String>().join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    TextStyle(color: p.muted, fontSize: 11.5)),
                          ]),
                    ),
                    Text('${c.d('score') ?? 0}',
                        style: TextStyle(
                            color: p.ink, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ),
          ),
        if (m.o('poll') != null) _poll(p, m.o('poll')!),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          SpPill(
              label: context.l10n.league_publishMvp,
              height: 34,
              onTap: _pick == null ? null : () => set(_pick, true)),
          if (status == 'published')
            SpPill(
                label: context.l10n.league_unpublish,
                tone: SpPillTone.soft,
                height: 34,
                onTap: () => set(_pick, false)),
          SpPill(
              label: context.l10n.league_noMvp,
              tone: SpPillTone.outline,
              height: 34,
              onTap: () => set(null, false)),
        ]),
      ]),
    );
  }
}
