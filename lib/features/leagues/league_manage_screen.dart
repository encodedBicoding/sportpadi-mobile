import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/links/web_handoff.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/leagues/leagues_repository.dart';
import 'package:sportpadi_mobile/features/leagues/league_commercials.dart';
import 'package:sportpadi_mobile/features/leagues/league_sheets.dart';
import 'package:sportpadi_mobile/features/leagues/league_venues.dart';
import 'package:sportpadi_mobile/features/leagues/league_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

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

const _tabs = [
  ('overview', 'Overview'),
  ('teams', 'Teams'),
  ('fixtures', 'Fixtures'),
  ('venues', 'Venues'),
  ('table', 'Table'),
  ('mvps', 'MVPs'),
  ('integrity', 'Eligibility'),
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
      title: l?.str('competitionName', 'League') ?? 'League',
      subtitle: l == null
          ? null
          : [l.s('season'), l.s('division')].whereType<String>().join(' · '),
      actions: [
        if (l != null && l.s('status') != 'draft')
          SpRoundButton(
              icon: Icons.open_in_new_rounded,
              tooltip: 'Public page',
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
                  ? 'No roster cutoff (no league pass)'
                  : 'Roster cutoff ${MaterialLocalizations.of(context).formatMediumDate(lock)}${l.b('rosterLocked') ? ' — locked' : ''}',
              style: TextStyle(color: p.heroMuted, fontSize: 12.5)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (status == 'draft')
              _heroBtn(
                  'Publish fixtures',
                  Icons.check_circle_rounded,
                  d.b('canPublish'),
                  () => leagueAction(context, ref, 'publish', {'leagueId': id},
                      success: 'Published — teams and players have been told',
                      refresh: [_prov]),
                  primary: true),
            _heroBtn('Settings', Icons.tune_rounded, true,
                () => _settingsSheet(d)),
            _heroBtn(
                'Recalculate',
                Icons.refresh_rounded,
                true,
                () => leagueAction(context, ref, 'recompute', {'leagueId': id},
                    success: 'Table recalculated', refresh: [_prov])),
          ]),
        ]),
      ),
      if (status == 'draft') ...[
        const SizedBox(height: 14),
        GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SpSectionTitle('Before you publish'),
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
            SpSectionTitle('${l.str('season')} divisions'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final dv in d.list('divisions'))
                SpPill(
                    label: dv.str('division', 'Main'),
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
            title: Text('Sponsors', style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
            subtitle: Text([
              if (d.o('sponsorTerms')?.b('accepted') != true) 'Accept the Sponsorship Terms to start',
              if (d.o('sponsorTerms')?.b('accepted') == true)
                '${d.list('sponsors').length} of ${d.o('spots')?.i('owned') ?? 0} spots used',
              if (d.list('sponsors').isNotEmpty) d.list('sponsors').map((x) => x.str('name')).join(', '),
            ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Icon(Icons.chevron_right_rounded, color: p.muted),
            onTap: () => showSponsorsSheet(context, ref, data: d, groupId: widget.groupId),
          ),
          Divider(height: 1, color: p.surface2),
          ListTile(
            leading: SpIconTile(Icons.confirmation_number_outlined, size: 38, iconSize: 19, bg: p.surface2, fg: p.ink),
            title: Text('Match tickets', style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
            subtitle: Text(d.o('ticketing')?.b('enabled') == true
                ? 'On · ${d.o('tickets')?.i('withTicket') ?? 0} on sale'
                : 'Off — sell spectator tickets for each match'),
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
          const SpSectionTitle('Season awards'),
          if (champion?.o('team') != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                Icon(Icons.emoji_events_rounded, color: p.greenText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Champions: ${champion!.o('team')!.str('name')}',
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
            SpSectionTitle('Player of the Season',
                trailing: SpBadge(
                    pos.s('status') == 'published'
                        ? 'Published'
                        : pos.s('status') == 'none'
                            ? 'None'
                            : 'Your call',
                    tone: pos.s('status') == 'published'
                        ? p.greenText
                        : p.orangeInk)),
            const SizedBox(height: 4),
            Text('Recommended from published match MVPs, then match MVP scores.',
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
                    '${c.str('teamName')} · ${c.i('mvps')} MVPs · score ${c.d('score') ?? 0}'),
                trailing: SpPill(
                  label: 'Publish',
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
                      success: 'Player of the Season published',
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
              Text('Next season',
                  style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
              Text('Start ${l.str('competitionName')} again with these teams.',
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          ),
          SpPill(
            label: 'Start',
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
  static const _tipTier =
      'Where this division sits in the competition: 1 is the top division, 2 the one below, and so on. '
      'Promotion and relegation move teams between neighbouring tiers.';
  static const _tipGoUp =
      "How many teams at the top of the final table go up to the division above next season. They're marked as a "
      'promotion zone on the table — nothing moves until you start the next season.';
  static const _tipGoDown =
      'How many teams at the bottom of the final table go down to the division below next season. They\'re marked as a '
      'relegation zone — you confirm the moves when you start the next season.';
  static const _tipRosterCutoff =
      "After this, only you can change registered players — coaches can't add or remove anyone. Players get their "
      'league pass once it passes. Leave it empty to keep rosters open all season (no league passes).';

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
              const SpSheetHeader(
                  title: 'League settings', icon: Icons.tune_rounded),
              if (l.b('usesDivisions')) ...[
                const FieldLabel('Division'),
                TextField(
                    controller: division,
                    decoration: fieldDeco(ctx, 'Division 1')),
              ],
              if (l.b('usesPromotionRelegation'))
                Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const FieldLabel('Tier', tip: _tipTier),
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
                          const FieldLabel('Go up', tip: _tipGoUp),
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
                          const FieldLabel('Go down', tip: _tipGoDown),
                          TextField(
                              controller: relegate,
                              keyboardType: TextInputType.number,
                              decoration: fieldDeco(ctx, '0')),
                        ]),
                  ),
                ]),
              const FieldLabel('Roster cutoff', tip: _tipRosterCutoff),
              PickField(
                text: lock == null
                    ? 'No cutoff'
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
              const FieldLabel('Entry fee per team'),
              if (feeCur != null)
                TextField(
                    controller: fee,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: fieldDeco(ctx, 'Free').copyWith(prefixText: '$feeCur  '))
              else
                Text('Activate your group wallet to charge an entry fee.',
                    style: TextStyle(color: ctx.palette.muted, fontSize: 12)),
              const SizedBox(height: 6),
              Text(
                  "Invited teams pay it to accept, by card, into your group wallet. Teams from your own group don't pay. "
                  'A team you remove before the season starts gets the fee back.',
                  style: TextStyle(color: ctx.palette.muted, fontSize: 11.5)),
              if (l.b('mvpEnabled')) ...[
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text('MVP poll', style: TextStyle(color: ctx.palette.ink, fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      'After each result, a vote on the match MVP. It feeds your recommendation — you still pick and publish.',
                      style: TextStyle(color: ctx.palette.muted, fontSize: 11.5)),
                  value: pollOn,
                  onChanged: (v) => setS(() => pollOn = v),
                ),
                if (pollOn) ...[
                  const FieldLabel('Who votes'),
                  Wrap(spacing: 6, children: [
                    for (final (v, t) in const [('players', 'League players'), ('everyone', 'Anyone signed in')])
                      ChoiceChip(label: Text(t), selected: pollAudience == v, onSelected: (_) => setS(() => pollAudience = v)),
                  ]),
                  const FieldLabel('Counts for'),
                  Wrap(spacing: 6, children: [
                    for (final w in const [0.1, 0.25, 0.5])
                      ChoiceChip(label: Text('${(w * 100).round()}%'), selected: pollWeight == w, onSelected: (_) => setS(() => pollWeight = w)),
                  ]),
                  const FieldLabel('Open for'),
                  Wrap(spacing: 6, children: [
                    for (final (h, t) in const [(24, '24 hours'), (48, '48 hours'), (72, '3 days')])
                      ChoiceChip(label: Text(t), selected: pollHours == h, onSelected: (_) => setS(() => pollHours = h)),
                  ]),
                ],
              ],
              if (d.b('hasTwoLegTies')) ...[
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Away goals rule',
                      style: TextStyle(color: ctx.palette.ink, fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      secondLegPlayed
                          ? 'Fixed for this season — a second leg has been played.'
                          : 'Two-leg ties level on aggregate go to the side that scored more away; still level → extra time / penalties.',
                      style: TextStyle(color: ctx.palette.muted, fontSize: 11.5)),
                  value: awayGoals,
                  onChanged: secondLegPlayed ? null : (v) => setS(() => awayGoals = v),
                ),
              ],
              const SizedBox(height: 16),
              SpButton(
                label: 'Save',
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
                  }, success: 'Saved', refresh: [_prov]);
                  if (ok && ctx.mounted) Navigator.of(ctx).pop();
                },
              ),
            ]);
      });
    });
  }

  /* ── Teams ─────────────────────────────────────────────────────────── */

  /// " · Paid CAD 50" / " · Fee CAD 50 due" for an invited team's entry fee.
  String _feeText(J? f) {
    if (f == null) return '';
    final amount = spotMoney(f.i('amountMinor'), f.str('currency'), f.i('exponent', 2));
    return switch (f.str('status')) {
      'paid' => ' · Paid $amount',
      'refunded' => ' · Fee refunded',
      'pending' => ' · Paying…',
      _ => ' · Fee $amount due',
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
    return [
      if (status != 'completed' && status != 'cancelled')
        SpButton(
            label: 'Invite teams',
            icon: Icons.group_add_rounded,
            expand: true,
            onTap: () => showInviteTeamSheet(context, ref, leagueId: id)),
      const SizedBox(height: 12),
      SpSectionTitle('In this league',
          count: live.where((t) => t.s('status') == 'approved').length),
      const SizedBox(height: 8),
      if (live.isEmpty)
        const SpEmpty(
            icon: Icons.groups_rounded,
            text: 'Invite teams — your own teams join straight away.')
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
                            '${t.str('groupName')}${t.s('status') == 'approved' ? ' · ${t.i('registered')} registered' : ''}${_feeText(t.o('fee'))}',
                            style: TextStyle(color: p.muted, fontSize: 11.5)),
                      ]),
                ),
                SpBadge(t.s('status') == 'approved' ? 'In' : 'Invited',
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
                            title: const Text('Remove this team?'),
                            content: Text(
                                "Their entry fee (${spotMoney(fee!.i('amountMinor'), fee.str('currency'), fee.i('exponent', 2))}) is refunded — SportPadi's processing fee isn't."),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
                              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove & refund')),
                            ],
                          ),
                        );
                        if (yes != true || !mounted) return;
                      }
                      if (!mounted) return;
                      await leagueAction(context, ref, 'removeTeam',
                          {'entryId': t.str('id')},
                          success: fee?.str('status') == 'paid' ? 'Removed — entry fee refunded' : 'Removed', refresh: [_prov]);
                    } else if (v.startsWith('move:')) {
                      await leagueAction(context, ref, 'moveTeam',
                          {'entryId': t.str('id'), 'toLeagueId': v.substring(5)},
                          success: 'Team moved', refresh: [_prov]);
                    }
                  },
                  itemBuilder: (_) => [
                    if (t.s('status') == 'approved')
                      const PopupMenuItem(value: 'roster', child: Text('Roster')),
                    if (t.s('status') == 'approved')
                      for (final dv in otherDivs)
                        PopupMenuItem(
                            value: 'move:${dv.str('id')}',
                            child: Text('Move to ${dv.str('division', 'Main')}')),
                    if (t.s('status') == 'pending' || status == 'draft')
                      PopupMenuItem(
                          value: 'remove',
                          child: Text(t.s('status') == 'pending'
                              ? 'Cancel invite'
                              : 'Remove')),
                  ],
                ),
              ]),
            ),
        ]),
      if (d.b('fixturesStale') && status == 'draft')
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
              'Teams changed since the fixtures were drawn — redraw them on Fixtures.',
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
                  success: 'Fixture removed', refresh: [_prov])),
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
        const Padding(
            padding: EdgeInsets.only(top: 12),
            child: SpEmpty(
                icon: Icons.calendar_month_rounded,
                text: 'No fixtures yet — draw the first stage above.')),
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
          label: 'Add fixture',
          icon: Icons.add_rounded,
          height: 34,
          onTap: () => showAddFixtureSheet(context, ref, data: d, stage: st),
        ),
      if (drawing && !manualTables)
        SpPill(
          label: st.b('manual')
              ? (st.s('kind') == 'table' ? 'Set up the table' : 'Set up the tables')
              : st.i('fixtures') > 0
              ? 'Redraw'
              : st.s('kind') == 'knockout'
                  ? 'Make the bracket'
                  : st.s('kind') == 'groups'
                      ? 'Draw the groups'
                      : st.s('kind') == 'split'
                          ? 'Draw the tables'
                          : 'Draw fixtures',
          icon: Icons.casino_rounded,
          tone: st.i('fixtures') > 0 ? SpPillTone.soft : SpPillTone.ink,
          height: 34,
          onTap: () => leagueAction(context, ref, 'generateFixtures',
              {'leagueId': id, 'stageId': st.str('id')},
              success: 'Drawn', refresh: [_prov]),
        ),
      if (firstDraft && st.s('kind') != 'table')
        SpPill(
            label: st.s('kind') == 'split' ? 'Pick tables & seeds' : 'Seeding',
            icon: Icons.format_list_numbered_rounded,
            tone: SpPillTone.soft,
            height: 34,
            onTap: () => showDrawSetupSheet(context, ref,
                leagueId: id,
                stage: st,
                teams: d.list('teams').where((t) => t.s('status') == 'approved').toList())),
      if (drawing && manualTables)
        SpPill(
            label: 'Redo tables',
            icon: Icons.shuffle_rounded,
            tone: SpPillTone.soft,
            height: 34,
            onTap: () async {
              if (st.i('fixtures') > 0) {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Set the tables up again?'),
                    content: const Text('The fixtures you added to this stage are removed.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Redo')),
                    ],
                  ),
                );
                if (ok != true || !mounted) return;
              }
              if (!mounted) return;
              await leagueAction(context, ref, 'generateFixtures',
                  {'leagueId': id, 'stageId': st.str('id'), 'reshuffle': true},
                  success: 'Tables set up', refresh: [_prov]);
            }),
      if (drawing && st.i('fixtures') > 0 && !st.b('manual')) ...[
        SpPill(
            label: 'New draw',
            icon: Icons.shuffle_rounded,
            tone: SpPillTone.soft,
            height: 34,
            onTap: () => leagueAction(context, ref, 'generateFixtures',
                {'leagueId': id, 'stageId': st.str('id'), 'reshuffle': true},
                success: 'Redrawn', refresh: [_prov])),
        SpPill(
            label: 'Set dates',
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
            label: 'Open ${st.str('name').toLowerCase()}',
            icon: Icons.check_circle_rounded,
            height: 34,
            onTap: () => leagueAction(
                context, ref, 'openStage', {'stageId': st.str('id')},
                success: 'Stage opened — teams have been told',
                refresh: [_prov])),
      if (action == 'confirm_round' && cr != null)
        SpPill(
          label: 'Confirm ${cr.str('name').toLowerCase()} winners',
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
            label: 'Close ${st.str('name').toLowerCase()}',
            tone: st.b('allDone') ? SpPillTone.ink : SpPillTone.soft,
            height: 34,
            onTap: st.b('allDone')
                ? () => leagueAction(
                    context, ref, 'closeStage', {'stageId': st.str('id')},
                    success: 'Stage closed', refresh: [_prov])
                : null),
      if (action == 'advance')
        SpPill(
            label: 'Choose who goes through',
            icon: Icons.swap_vert_rounded,
            height: 34,
            onTap: () => showAdvanceSheet(context, ref, leagueId: id)),
      if (action == 'finish')
        SpPill(
            label: 'Close the season',
            icon: Icons.emoji_events_rounded,
            height: 34,
            onTap: () async {
              final yes = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                        title: const Text('Close the season?'),
                        content: const Text(
                            'Awards are worked out from the final results.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Not yet')),
                          TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('Close it')),
                        ],
                      ));
              if (yes == true && mounted) {
                await leagueAction(
                    context, ref, 'complete', {'leagueId': id},
                    success: 'Season closed — awards are in',
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
        ? "Publish from Overview when you're ready."
        : waitingRound != null
            ? '${waitingRound.str('name')}: ${waitingRound.i('decided')}/${waitingRound.i('ties')} decided — you confirm who goes through once all are in.'
            : action == 'close' && !st.b('allDone')
                ? 'Closes once every match is played, forfeited or cancelled.'
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
                    if (st.s('pairingRule') == 'cross') '${st.iOrNull('matchesPerTeam') ?? 3} games each',
                    if (i == 0 && st.o('setup')?.b('seeded') == true) 'seeded',
                    if (st.i('fixtures') > 0)
                      '${st.i('done')}/${st.i('fixtures')} played',
                    if (st.o('advance')?.s('rule') == 'top_n_per_table')
                      'top ${st.o('advance')!.i('n')} go through',
                  ].join(' · '),
                  style: TextStyle(color: p.muted, fontSize: 11.5)),
            ]),
          ),
          SpBadge(firstDraft
              ? 'Draft'
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
        const SpEmpty(
            icon: Icons.leaderboard_rounded,
            text: 'The table appears once teams are in.')
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
        const SpEmpty(
            icon: Icons.military_tech_rounded,
            text: "This league format doesn't pick match MVPs.")
      ];
    }
    final list = [...d.list('mvps')]..sort((a, b) =>
        (b.s('status') == 'recommended' ? 1 : 0) -
        (a.s('status') == 'recommended' ? 1 : 0));
    if (list.isEmpty) {
      return [
        const SpEmpty(
            icon: Icons.military_tech_rounded,
            text:
                'Once a match finishes, its recommended MVP shows up here for you to confirm.')
      ];
    }
    final byId = {for (final f in d.list('fixtures')) f.str('id'): f};
    return [
      Text(
          "Recommendations come from each player's match stats. Nothing is public until you publish it.",
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
        const GlassCard(
            child: Text(
                'Set a roster cutoff (Overview → Settings) to give every registered player a league pass you can scan here.'))
      else
        GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SpSectionTitle('Check a player'),
            const SizedBox(height: 6),
            Text(
                "Scan the player's league pass, then check the photo matches the person in front of you.",
                style: TextStyle(color: p.muted, fontSize: 12.5)),
            const SizedBox(height: 12),
            SpButton(
                label: 'Scan league pass',
                icon: Icons.qr_code_scanner_rounded,
                expand: true,
                onTap: () => _scan(d)),
          ]),
        ),
      const SizedBox(height: 16),
      SpSectionTitle('Forfeits',
          count: sanctions.where((s) => s.s('status') == 'active').length),
      const SizedBox(height: 8),
      if (sanctions.isEmpty)
        const SpEmpty(
            icon: Icons.gavel_rounded,
            text: 'No penalties. Use the gavel on a fixture to forfeit a match.')
      else
        SpListCard(children: [
          for (final s in sanctions)
            ListTile(
              title: Text(
                  '${s.str('teamName')} forfeited · ${s.str('publicReason')}',
                  style: TextStyle(color: p.ink, fontSize: 13.5)),
              subtitle: Text(s.s('status') == 'revoked'
                  ? 'Revoked'
                  : (s.s('privateNote') ?? '')),
              trailing: s.s('status') == 'active'
                  ? TextButton(
                      onPressed: () => leagueAction(context, ref,
                          'revokeSanction', {'sanctionId': s.str('id')},
                          success: 'Forfeit revoked', refresh: [_prov]),
                      child: const Text('Revoke'))
                  : null,
            ),
        ]),
      const SizedBox(height: 16),
      const SpSectionTitle('Recent checks'),
      const SizedBox(height: 8),
      AsyncView(
        value: checks,
        data: (list) => list.isEmpty
            ? Text('No checks yet.', style: TextStyle(color: p.muted))
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
                        '${c.str('playerName', 'Unknown player')}${c.s('teamName') != null ? ' · ${c.str('teamName')}' : ''}'),
                    subtitle: Text(c.str('result').replaceAll('_', ' ')),
                  ),
              ]),
      ),
    ];
  }

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
    const titles = {
      'valid': ('Eligible', 'Registered for this league and live.'),
      'not_registered': (
        'Not registered',
        "This pass isn't on a current roster for this league."
      ),
      'wrong_league': ('Different league', 'This is a pass for another league.'),
      'wrong_team': (
        'Not in this match',
        'Registered, but not with either team in this match.'
      ),
      'not_live': (
        'Pass not live yet',
        'Passes go live when the roster cutoff passes.'
      ),
      'expired': (
        'Expired code',
        'Ask the player to open their pass again — screenshots stop working.'
      ),
      'invalid': ('Invalid', "This code wasn't issued by SportPadi."),
      'not_a_pass': ('Not a league pass', "That QR isn't a league pass."),
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
                            Text('Added after the cutoff',
                                style: TextStyle(
                                    color: p.orangeInk, fontSize: 11.5)),
                        ]),
                  ),
                ]),
              ),
            if (!ok) ...[
              const SizedBox(height: 12),
              Text(
                  'Need to penalise a team? Use the gavel on the match in Fixtures — this scan is logged as evidence.',
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ],
            const SizedBox(height: 14),
            SpButton(
                label: 'Scan another',
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
            'MVP poll · $total vote${total == 1 ? '' : 's'}'
            '${poll.b('open') && closes != null ? ' · closes ${MaterialLocalizations.of(context).formatShortMonthDay(closes)} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(closes))}' : ' · closed'}'
            '${poll.b('counts') ? '' : ' · too few votes to count yet'}',
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
                        TextSpan(text: '  Suggested', style: TextStyle(color: p.greenText, fontWeight: FontWeight.w800, fontSize: 11)),
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
            ? 'MVP published'
            : player == null
                ? 'No MVP for this match'
                : 'Saved (not public)',
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
                      ? 'Match'
                      : '${f.o('home')?.str('name')} ${f.i('homeScore')}–${f.i('awayScore')} ${f.o('away')?.str('name')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
              Text(
                  (status == 'published'
                          ? 'Published: ${m.o('player')?.str('displayName') ?? '—'}'
                          : status == 'none'
                              ? 'No MVP'
                              : 'Waiting for you') +
                      (m.b('statsChanged')
                          ? ' · stats changed since — check the pick'
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
              label: 'Publish MVP',
              height: 34,
              onTap: _pick == null ? null : () => set(_pick, true)),
          if (status == 'published')
            SpPill(
                label: 'Unpublish',
                tone: SpPillTone.soft,
                height: 34,
                onTap: () => set(_pick, false)),
          SpPill(
              label: 'No MVP',
              tone: SpPillTone.outline,
              height: 34,
              onTap: () => set(null, false)),
        ]),
      ]),
    );
  }
}
