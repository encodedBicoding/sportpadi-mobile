import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/leagues/leagues_repository.dart';
import 'package:sportpadi_mobile/features/leagues/league_widgets.dart';
import 'package:sportpadi_mobile/features/venues/venues.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart' show deviceTimezone;
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/info_tip.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/* ─── Small form bits ──────────────────────────────────────────────────── */

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.tip});
  final String text;

  /// What the field means — shown behind an ⓘ beside the label.
  final String? tip;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: tip == null ? 6 : 2, top: tip == null ? 10 : 6),
        child: TipText(text,
            tip: tip, style: TextStyle(color: context.palette.ink, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

/// The small print under a venue field.
class VenueHint extends StatelessWidget {
  const VenueHint(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text, style: TextStyle(color: context.palette.muted, fontSize: 11.5, height: 1.35)),
      );
}

/// A tappable field showing a value (date / time pickers).
class PickField extends StatelessWidget {
  const PickField({super.key, required this.text, required this.onTap, this.icon = Icons.event_rounded, this.onClear});
  final String text;
  final VoidCallback onTap;
  final IconData icon;
  final VoidCallback? onClear;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.surface2,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(children: [
            Icon(icon, size: 18, color: p.muted),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: p.ink, fontSize: 14))),
            if (onClear != null)
              GestureDetector(onTap: onClear, child: Icon(Icons.close_rounded, size: 18, color: p.muted)),
          ]),
        ),
      ),
    );
  }
}

Future<DateTime?> pickDay(BuildContext context, DateTime? initial) => showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );

Future<String?> pickHhmm(BuildContext context, String? initial) async {
  TimeOfDay init = const TimeOfDay(hour: 18, minute: 0);
  final m = initial == null ? null : RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(initial);
  if (m != null) init = TimeOfDay(hour: int.parse(m[1]!), minute: int.parse(m[2]!));
  final t = await showTimePicker(context: context, initialTime: init);
  if (t == null) return null;
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

DateTime? ymdToDate(String? ymd) {
  final m = ymd == null ? null : RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(ymd);
  return m == null ? null : DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

InputDecoration fieldDeco(BuildContext context, String hint) {
  final p = context.palette;
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: p.surface2,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
  );
}

/* ─── Schedule (bulk) ──────────────────────────────────────────────────── */

Future<void> showScheduleSheet(BuildContext context, WidgetRef ref,
    {required String leagueId, String? stageId, String? defaultStart}) {
  return showSpSheet<void>(context, builder: (ctx) => _ScheduleSheet(leagueId: leagueId, stageId: stageId, defaultStart: defaultStart));
}

class _ScheduleSheet extends ConsumerStatefulWidget {
  const _ScheduleSheet({required this.leagueId, this.stageId, this.defaultStart});
  final String leagueId;
  final String? stageId;
  final String? defaultStart;
  @override
  ConsumerState<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends ConsumerState<_ScheduleSheet> {
  DateTime? _start;
  int _every = 7;
  String? _time;
  String? _end;
  String? _venueId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start = ymdToDate(widget.defaultStart);
  }

  @override
  Widget build(BuildContext context) {
    final venues = VenuesData.fromJson(ref.watch(leagueVenuesProvider(widget.leagueId)).valueOrNull?.raw ?? const {}).active;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SpSheetHeader(
          title: context.l10n.league_setFixtureDates,
          subtitle: context.l10n.league_round1OnTheStart2,
          icon: Icons.calendar_month_rounded),
      FieldLabel(context.l10n.league_round1),
      PickField(
          text: _start == null ? context.l10n.league_pickADate : fixtureDay(ymdOf(_start!)),
          onTap: () async {
            final d = await pickDay(context, _start);
            if (d != null) setState(() => _start = d);
          }),
      FieldLabel(context.l10n.league_every),
      Wrap(spacing: 8, children: [
        for (final n in [7, 14, 3, 1])
          ChoiceChip(
              label: Text(n == 1 ? context.l10n.league_daily : n == 7 ? context.l10n.league_weekly : n == 14 ? context.l10n.league_fortnightly : context.l10n.league_everyDays2(n)),
              selected: _every == n,
              onSelected: (_) => setState(() => _every = n)),
      ]),
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FieldLabel(context.l10n.league_kickOff),
            PickField(
                icon: Icons.schedule_rounded,
                text: _time == null ? context.l10n.league_anyTime : formatTime12(_time!),
                onTap: () async {
                  final t = await pickHhmm(context, _time);
                  if (t != null) setState(() => _time = t);
                }),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FieldLabel(context.l10n.league_ends),
            PickField(
                icon: Icons.schedule_rounded,
                text: _end == null ? '—' : formatTime12(_end!),
                onTap: () async {
                  final t = await pickHhmm(context, _end ?? _time);
                  if (t != null) setState(() => _end = t);
                }),
          ]),
        ),
      ]),
      FieldLabel(context.l10n.league_venue),
      VenueDropdown(venues: venues, value: _venueId, none: context.l10n.league_keepEachFixturesVenue, onChanged: (v) => setState(() => _venueId = v)),
      VenueHint(context.l10n.league_kickOffIsLocalTime),
      const SizedBox(height: 18),
      SpButton(
        label: context.l10n.league_apply,
        expand: true,
        onTap: _start == null || _busy
            ? null
            : () async {
                setState(() => _busy = true);
                final ok = await leagueAction(context, ref, 'scheduleFixtures', {
                  'leagueId': widget.leagueId,
                  if (widget.stageId != null) 'stageId': widget.stageId,
                  'startDate': ymdOf(_start!),
                  'everyDays': _every,
                  'startTime': _time,
                  'endTime': _end,
                  'venueId': _venueId,
                }, success: context.l10n.league_fixturesScheduled2, refresh: [leagueManageProvider(widget.leagueId)]);
                if (!mounted) return;
                setState(() => _busy = false);
                if (ok) Navigator.of(this.context).pop();
              },
      ),
    ]);
  }
}

/* ─── One fixture ──────────────────────────────────────────────────────── */

Future<void> showFixtureSheet(BuildContext context, WidgetRef ref, {required String leagueId, required J f}) {
  return showSpSheet<void>(context, builder: (_) => _FixtureSheet(leagueId: leagueId, f: f));
}

class _FixtureSheet extends ConsumerStatefulWidget {
  const _FixtureSheet({required this.leagueId, required this.f});
  final String leagueId;
  final J f;
  @override
  ConsumerState<_FixtureSheet> createState() => _FixtureSheetState();
}

class _FixtureSheetState extends ConsumerState<_FixtureSheet> {
  DateTime? _date;
  String? _time;
  String? _end;
  String? _venueId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _date = ymdToDate(widget.f.s('scheduledDate'));
    _time = widget.f.s('startTime');
    _end = widget.f.s('endTime');
    _venueId = widget.f.s('venueId');
  }

  Future<void> _save({bool swap = false}) async {
    setState(() => _busy = true);
    final ok = await leagueAction(context, ref, 'updateFixture', {
      'fixtureId': widget.f.str('id'),
      'scheduledDate': _date == null ? null : ymdOf(_date!),
      'startTime': _time,
      'endTime': _end,
      if (_venueId != widget.f.s('venueId')) 'venueId': _venueId,
      'timezone': deviceTimezone,
      'swapSides': swap,
    }, success: widget.f.b('published') ? context.l10n.league_rescheduledBothTeamsWereTold : context.l10n.league_saved, refresh: [leagueManageProvider(widget.leagueId)]);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    final venues = VenuesData.fromJson(ref.watch(leagueVenuesProvider(widget.leagueId)).valueOrNull?.raw ?? const {}).active;
    final picked = venues.where((v) => v.id == _venueId).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SpSheetHeader(
          title: context.l10n.league_vs(f.o('home')?.str('name') ?? f.str('homeSlot', context.l10n.league_tbc), f.o('away')?.str('name') ?? f.str('awaySlot', context.l10n.league_tbc)),
          subtitle: f.s('label') ?? context.l10n.league_round4(f.i('round')),
          icon: Icons.sports_soccer_rounded),
      FieldLabel(context.l10n.league_date),
      PickField(
          text: _date == null ? context.l10n.league_pickADate : fixtureDay(ymdOf(_date!)),
          onTap: () async {
            final d = await pickDay(context, _date);
            if (d != null) setState(() => _date = d);
          }),
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FieldLabel(context.l10n.league_kickOff),
            PickField(
                icon: Icons.schedule_rounded,
                text: _time == null ? '—' : formatTime12(_time!),
                onTap: () async {
                  final t = await pickHhmm(context, _time);
                  if (t != null) setState(() => _time = t);
                }),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FieldLabel(context.l10n.league_ends),
            PickField(
                icon: Icons.schedule_rounded,
                text: _end == null ? '—' : formatTime12(_end!),
                onTap: () async {
                  final t = await pickHhmm(context, _end ?? _time);
                  if (t != null) setState(() => _end = t);
                }),
          ]),
        ),
      ]),
      FieldLabel(context.l10n.league_venue),
      VenueDropdown(
          venues: venues, value: _venueId, none: f.b('published') ? null : context.l10n.league_noVenueYet, onChanged: (v) => setState(() => _venueId = v)),
      if (_venueId == null && f.s('venue') != null) VenueHint(context.l10n.league_currently2(f.str('venue'))),
      VenueHint(picked?.timezone != null
          ? (f.b('published') && _venueId != f.s('venueId')
              ? context.l10n.league_p5KickOffLocalTimeTold(picked!.timezone!.replaceAll('_', ' '))
              : context.l10n.league_p5KickOffLocalTime(picked!.timezone!.replaceAll('_', ' ')))
          : context.l10n.league_pickOneOfTheSeasons),
      const SizedBox(height: 18),
      Row(children: [
        if (!f.b('published')) ...[
          Expanded(
            child: SpPill(
                label: context.l10n.league_swapHomeAway,
                icon: Icons.swap_horiz_rounded,
                tone: SpPillTone.soft,
                expand: true,
                height: 46,
                onTap: _busy ? null : () => _save(swap: true)),
          ),
          const SizedBox(width: 8),
        ],
        // A published match always keeps a venue (it's where the teams turn up).
        Expanded(
            child: SpButton(
                label: context.l10n.league_save,
                expand: true,
                onTap: _busy || (f.b('published') && _venueId == null && f.s('venue') == null) ? null : () => _save())),
      ]),
    ]);
  }
}

/* ─── Forfeit ──────────────────────────────────────────────────────────── */

Future<void> showForfeitSheet(BuildContext context, WidgetRef ref,
    {required String leagueId, required J f, String? teamId, String? evidenceCheckId}) {
  return showSpSheet<void>(context,
      builder: (_) => _ForfeitSheet(leagueId: leagueId, f: f, teamId: teamId, evidenceCheckId: evidenceCheckId));
}

class _ForfeitSheet extends ConsumerStatefulWidget {
  const _ForfeitSheet({required this.leagueId, required this.f, this.teamId, this.evidenceCheckId});
  final String leagueId;
  final J f;
  final String? teamId;
  final String? evidenceCheckId;
  @override
  ConsumerState<_ForfeitSheet> createState() => _ForfeitSheetState();
}

class _ForfeitSheetState extends ConsumerState<_ForfeitSheet> {
  String? _team;
  late String _reason;
  final _public = TextEditingController();
  final _private = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _team = widget.teamId ?? widget.f.o('home')?.s('id');
    _reason = widget.evidenceCheckId != null ? 'ineligible_player' : 'no_show';
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    final teams = [f.o('home'), f.o('away')].whereType<J>().toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SpSheetHeader(
          title: context.l10n.league_forfeitThisMatch,
          subtitle: context.l10n.league_theOtherTeamGetsThe,
          icon: Icons.gavel_rounded,
          iconBg: context.palette.liveTint,
          iconFg: context.palette.danger),
      FieldLabel(context.l10n.league_teamThatForfeits),
      Row(children: [
        for (final (i, t) in teams.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: SpPill(
                label: t.str('name'),
                tone: _team == t.s('id') ? SpPillTone.ink : SpPillTone.soft,
                expand: true,
                onTap: () => setState(() => _team = t.s('id'))),
          ),
        ],
      ]),
      FieldLabel(context.l10n.league_reason),
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (final (k, v) in [
          ('ineligible_player', context.l10n.league_ineligiblePlayer),
          ('no_show', context.l10n.league_didntShowUp),
          ('conduct', context.l10n.league_conduct),
          ('other', context.l10n.league_other),
        ])
          ChoiceChip(label: Text(v), selected: _reason == k, onSelected: (_) => setState(() => _reason = k)),
      ]),
      FieldLabel(context.l10n.league_publicReasonOnTheLeague),
      TextField(controller: _public, maxLength: 200, decoration: fieldDeco(context, context.l10n.league_fieldedAnUnregisteredPlayer)),
      FieldLabel(context.l10n.league_privateNoteOrganisersOnly),
      TextField(controller: _private, maxLines: 3, decoration: fieldDeco(context, context.l10n.league_optional2)),
      const SizedBox(height: 16),
      SpButton(
        label: context.l10n.league_recordForfeit,
        icon: Icons.gavel_rounded,
        expand: true,
        onTap: _busy || _team == null
            ? null
            : () async {
                if (_public.text.trim().length < 3) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.league_addAShortPublicReason)));
                  return;
                }
                setState(() => _busy = true);
                final ok = await leagueAction(context, ref, 'forfeit', {
                  'fixtureId': f.str('id'),
                  'teamId': _team,
                  'reasonCode': _reason,
                  'publicReason': _public.text.trim(),
                  'privateNote': _private.text.trim().isEmpty ? null : _private.text.trim(),
                  'evidenceCheckId': widget.evidenceCheckId,
                }, success: context.l10n.league_forfeitRecordedTheTableIs, refresh: [leagueManageProvider(widget.leagueId)]);
                if (!mounted) return;
                setState(() => _busy = false);
                if (ok) Navigator.of(this.context).pop();
              },
      ),
    ]);
  }
}

/* ─── Invite a team ────────────────────────────────────────────────────── */

Future<void> showInviteTeamSheet(BuildContext context, WidgetRef ref, {required String leagueId}) =>
    showSpSheet<void>(context, builder: (_) => _InviteSheet(leagueId: leagueId));

class _InviteSheet extends ConsumerStatefulWidget {
  const _InviteSheet({required this.leagueId});
  final String leagueId;
  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  String _q = '';
  final Set<String> _busy = {};

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final q = ref.watch(leagueTeamSearchProvider('${widget.leagueId}|$_q'));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SpSheetHeader(
          title: context.l10n.league_inviteTeams, subtitle: context.l10n.league_yourOwnTeamsJoinStraight2, icon: Icons.group_add_rounded),
      TextField(
        autofocus: true,
        decoration: fieldDeco(context, context.l10n.league_searchTeamsByNameOr).copyWith(prefixIcon: const Icon(Icons.search_rounded)),
        onChanged: (v) => setState(() => _q = v.trim()),
      ),
      const SizedBox(height: 10),
      AsyncView(
        value: q,
        data: (list) => list.isEmpty
            ? Padding(padding: const EdgeInsets.all(16), child: Text(context.l10n.league_noTeamsFoundForThis, style: TextStyle(color: p.muted)))
            : SpListCard(children: [
                for (final t in list)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(children: [
                      Crest(logoUrl: t.s('logoUrl'), label: t.s('name'), size: 32),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t.str('name'), style: TextStyle(color: p.ink, fontWeight: FontWeight.w700, fontSize: 13.5)),
                          Text(['@${t.str('username')}', if (t.b('ownTeam')) context.l10n.league_p5YourTeamLower].join(' · '),
                              style: TextStyle(color: p.muted, fontSize: 11.5)),
                        ]),
                      ),
                      if (t.o('entry') != null)
                        SpBadge(t.o('entry')!.b('here') ? (t.o('entry')!.s('status') == 'approved' ? context.l10n.league_inLabel : context.l10n.league_invited) : context.l10n.league_elsewhere)
                      else
                        SpPill(
                          label: t.b('ownTeam') ? context.l10n.league_add : context.l10n.league_invite,
                          height: 34,
                          onTap: _busy.contains(t.str('id'))
                              ? null
                              : () async {
                                  setState(() => _busy.add(t.str('id')));
                                  await leagueAction(context, ref, 'inviteTeam', {'leagueId': widget.leagueId, 'teamId': t.str('id')},
                                      success: t.b('ownTeam') ? context.l10n.league_teamAdded : context.l10n.league_inviteSent,
                                      refresh: [leagueManageProvider(widget.leagueId), leagueTeamSearchProvider('${widget.leagueId}|$_q')]);
                                  if (mounted) setState(() => _busy.remove(t.str('id')));
                                },
                        ),
                    ]),
                  ),
              ]),
      ),
    ]);
  }
}

/* ─── Advancement & knockout rounds ────────────────────────────────────── */

Future<void> showAdvanceSheet(BuildContext context, WidgetRef ref, {required String leagueId}) =>
    showSpSheet<void>(context, builder: (_) => _AdvanceSheet(leagueId: leagueId));

class _AdvanceSheet extends ConsumerStatefulWidget {
  const _AdvanceSheet({required this.leagueId});
  final String leagueId;
  @override
  ConsumerState<_AdvanceSheet> createState() => _AdvanceSheetState();
}

class _AdvanceSheetState extends ConsumerState<_AdvanceSheet> {
  List<Map<String, dynamic>>? _list;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final q = ref.watch(leagueAdvancementProvider(widget.leagueId));
    return AsyncView(
      value: q,
      data: (d) {
        if (d == null) return Padding(padding: const EdgeInsets.all(20), child: Text(context.l10n.league_noStageIsWaiting));
        final list = _list ??
            [
              for (final e in d.list('entries'))
                {
                  'teamId': e.str('teamId'),
                  'origin': e.s('origin'),
                  'table': e.s('table'),
                  'position': e.iOrNull('position'),
                  'name': e.o('team')?.str('name') ?? context.l10n.league_team,
                }
            ];
        final others = d.list('teams').where((t) => !list.any((x) => x['teamId'] == t.s('teamId'))).toList();
        void set(List<Map<String, dynamic>> v) => setState(() => _list = v);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          SpSheetHeader(
              title: d.o('to') != null
                  ? context.l10n.league_intoThe(d.o('to')!.str('name').toLowerCase())
                  : context.l10n.league_p5IntoTheNextStage,
              subtitle: d.o('from') != null
                  ? context.l10n.league_proposedFromTeamsNotListed(d.o('from')!.str('name').toLowerCase())
                  : context.l10n.league_p5ProposedFromLastStage,
              icon: Icons.swap_vert_rounded),
          if (d.s('note') != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(d.str('note'), style: TextStyle(color: p.muted, fontSize: 12))),
          SpListCard(children: [
            for (final (i, e) in list.indexed)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                child: Row(children: [
                  SizedBox(width: 22, child: Text('${i + 1}', style: TextStyle(color: p.muted, fontWeight: FontWeight.w700))),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${e['name']}', style: TextStyle(color: p.ink, fontWeight: FontWeight.w600)),
                      Text('${e['origin'] ?? context.l10n.league_addedByYou}', style: TextStyle(color: p.muted, fontSize: 11.5)),
                    ]),
                  ),
                  IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                      onPressed: i == 0 ? null : () => set([...list]..insert(i - 1, list[i])..removeAt(i + 1))),
                  IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.close_rounded, size: 18, color: p.danger),
                      onPressed: () => set([...list]..removeAt(i))),
                ]),
              ),
          ]),
          if (others.isNotEmpty) ...[
            FieldLabel(context.l10n.league_addATeam2),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in others)
                ActionChip(
                  label: Text('${t.str('name')}${t.s('finished') != null ? ' (${t.str('finished')})' : ''}'),
                  onPressed: () => set([
                    ...list,
                    {'teamId': t.str('teamId'), 'origin': context.l10n.league_addedByYou, 'table': null, 'position': null, 'name': t.str('name')}
                  ]),
                ),
            ]),
          ],
          const SizedBox(height: 16),
          SpButton(
            label: context.l10n.league_confirmTeamsDraw(list.length),
            expand: true,
            onTap: list.length < 2 || _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    final ok = await leagueAction(context, ref, 'confirmAdvancement', {
                      'leagueId': widget.leagueId,
                      'entries': [
                        for (final e in list) {'teamId': e['teamId'], 'origin': e['origin'], 'table': e['table'], 'position': e['position']}
                      ],
                    }, success: context.l10n.league_drawnSetDatesThenOpenTheStage, refresh: [leagueManageProvider(widget.leagueId)]);
                    if (!mounted) return;
                    setState(() => _busy = false);
                    if (ok) Navigator.of(this.context).pop();
                  },
          ),
        ]);
      },
    );
  }
}

Future<void> showConfirmRoundSheet(BuildContext context, WidgetRef ref,
    {required String leagueId, required String stageId, required int round, required String name, required List<J> ties}) {
  return showSpSheet<void>(context, builder: (ctx) {
    final p = ctx.palette;
    String? winner(J f) {
      final w = f.s('winnerTeamId');
      if (w == null) return null;
      return f.o('home')?.s('id') == w ? f.o('home')?.s('name') : f.o('away')?.s('name');
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SpSheetHeader(
          title: context.l10n.league_confirmTheWinners2(name.toLowerCase()),
          subtitle: context.l10n.league_theseTeamsMoveUpThe,
          icon: Icons.account_tree_rounded),
      SpListCard(children: [
        for (final f in ties)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.str('label'), style: TextStyle(color: p.muted, fontSize: 11.5)),
              Text(
                  switch (f.s('decision')) {
                    'shootout' => context.l10n.league_p5ResultLinePens(f.o('home')?.str('name') ?? '', f.i('homeScore'), f.i('awayScore'), f.o('away')?.str('name') ?? '', f.i('homeSo'), f.i('awaySo')),
                    'forfeit' => context.l10n.league_p5ResultLineForfeit(f.o('home')?.str('name') ?? '', f.i('homeScore'), f.i('awayScore'), f.o('away')?.str('name') ?? ''),
                    _ => context.l10n.league_p5ResultLine(f.o('home')?.str('name') ?? '', f.i('homeScore'), f.i('awayScore'), f.o('away')?.str('name') ?? ''),
                  },
                  style: TextStyle(color: p.ink, fontSize: 13.5)),
              const SizedBox(height: 2),
              Text(context.l10n.league_goThrough2(winner(f) ?? '—'), style: TextStyle(color: p.greenText, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ]),
          ),
      ]),
      const SizedBox(height: 16),
      SpButton(
        label: context.l10n.league_confirmMoveThemUp,
        expand: true,
        onTap: () async {
          final ok = await leagueAction(ctx, ref, 'confirmRound', {'stageId': stageId, 'round': round},
              success: ctx.l10n.league_throughGiveTheNextMatchesADate, refresh: [leagueManageProvider(leagueId)]);
          if (ok && ctx.mounted) Navigator.of(ctx).pop();
        },
      ),
    ]);
  });
}

/* ─── League pass scanner ──────────────────────────────────────────────── */

/// Full-screen camera that returns the first QR it reads (or null).
class LeaguePassScanner extends StatefulWidget {
  const LeaguePassScanner({super.key});
  @override
  State<LeaguePassScanner> createState() => _LeaguePassScannerState();
}

class _LeaguePassScannerState extends State<LeaguePassScanner> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.normal, formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        MobileScanner(
          controller: _controller,
          onDetect: (cap) {
            if (_done) return;
            final v = cap.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
            if (v == null) return;
            _done = true;
            Navigator.of(context).pop(v);
          },
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              IconButton.filledTonal(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(context.l10n.league_scanThePlayersLeaguePass2,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// First-stage draw setup (web DrawSetupDialog): a seed order and, for split
/// tables, which table each team starts in plus the tables' names. Unpicked
/// teams are drawn into the smaller table.
Future<void> showDrawSetupSheet(BuildContext context, WidgetRef ref,
        {required String leagueId, required J stage, required List<J> teams}) =>
    showSpSheet<void>(context, builder: (_) => _DrawSetupSheet(leagueId: leagueId, stage: stage, teams: teams));

class _DrawSetupSheet extends ConsumerStatefulWidget {
  const _DrawSetupSheet({required this.leagueId, required this.stage, required this.teams});
  final String leagueId;
  final J stage;
  final List<J> teams;
  @override
  ConsumerState<_DrawSetupSheet> createState() => _DrawSetupSheetState();
}

class _DrawSetupSheetState extends ConsumerState<_DrawSetupSheet> {
  late bool _seeded;
  late List<({String teamId, String? split})> _list;
  late List<TextEditingController> _names;
  bool _busy = false;

  List<J> get _splits => widget.stage.list('splits');
  bool get _split => widget.stage.s('kind') == 'split' && _splits.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final setup = widget.stage.o('setup');
    _seeded = setup?.b('seeded') ?? false;
    final ids = {for (final t in widget.teams) t.str('teamId')};
    final saved = [
      for (final e in setup?.list('entries') ?? const <J>[])
        if (ids.contains(e.str('teamId'))) (teamId: e.str('teamId'), split: e.s('split')),
    ];
    _list = [
      ...saved,
      for (final t in widget.teams)
        if (!saved.any((e) => e.teamId == t.str('teamId'))) (teamId: t.str('teamId'), split: null),
    ];
    _names = [for (final sp in _splits) TextEditingController(text: sp.str('name'))];
  }

  @override
  void dispose() {
    for (final c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  void _move(int i, int by) {
    final j = (i + by).clamp(0, _list.length - 1);
    if (j == i) return;
    setState(() {
      final x = _list.removeAt(i);
      _list.insert(j, x);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final kind = widget.stage.s('kind');
    final byId = {for (final t in widget.teams) t.str('teamId'): t};
    final hint = kind == 'knockout'
        ? context.l10n.league_seeded1MeetsTheLast2
        : kind == 'groups'
            ? context.l10n.league_seededTeamsAreDealtIn2
            : context.l10n.league_seededUnpickedTeamsAreDealt;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SpSheetHeader(
          title: _split ? context.l10n.league_tablesSeeding : context.l10n.league_seeding,
          subtitle: _split ? context.l10n.league_pickWhichTableEachTeam2 : hint,
          icon: Icons.format_list_numbered_rounded),
      if (_split) ...[
        Row(children: [
          for (final (k, sp) in _splits.indexed) ...[
            if (k > 0) const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FieldLabel(context.l10n.league_tablePicked(k + 1, _list.where((e) => e.split == sp.str('key')).length)),
                TextField(controller: _names[k], maxLength: 30, decoration: const InputDecoration(counterText: '')),
              ]),
            ),
          ],
        ]),
        const SizedBox(height: 8),
      ],
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(context.l10n.league_seededDraw, style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
        subtitle: _split ? Text(hint, style: TextStyle(color: p.muted, fontSize: 12)) : null,
        value: _seeded,
        onChanged: (v) => setState(() => _seeded = v),
      ),
      SpListCard(children: [
        for (final (i, e) in _list.indexed)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(children: [
              if (_seeded) SizedBox(width: 22, child: Text('${i + 1}', style: TextStyle(color: p.muted, fontWeight: FontWeight.w700))),
              Crest(
                  logoUrl: byId[e.teamId]?.s('logoUrl'),
                  label: byId[e.teamId]?.s('name'),
                  kitPrimary: byId[e.teamId]?.s('kitPrimary'),
                  size: 26),
              const SizedBox(width: 8),
              Expanded(
                child: Text(byId[e.teamId]?.str('name') ?? context.l10n.league_team,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.ink, fontWeight: FontWeight.w600)),
              ),
              if (_split)
                DropdownButton<String?>(
                  value: e.split,
                  underline: const SizedBox.shrink(),
                  style: TextStyle(color: p.ink, fontSize: 12.5),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text(context.l10n.league_draw)),
                    for (final (k, sp) in _splits.indexed)
                      DropdownMenuItem<String?>(
                          value: sp.str('key'),
                          child: Text(_names[k].text.trim().isEmpty ? sp.str('name') : _names[k].text.trim())),
                  ],
                  onChanged: (v) => setState(() => _list[i] = (teamId: e.teamId, split: v)),
                ),
              if (_seeded) ...[
                IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                    onPressed: i == 0 ? null : () => _move(i, -1)),
                IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                    onPressed: i == _list.length - 1 ? null : () => _move(i, 1)),
              ],
            ]),
          ),
      ]),
      const SizedBox(height: 16),
      SpButton(
        label: context.l10n.league_save,
        expand: true,
        onTap: _busy
            ? null
            : () async {
                setState(() => _busy = true);
                final ok = await leagueAction(
                    context,
                    ref,
                    'drawSetup',
                    {
                      'stageId': widget.stage.str('id'),
                      'seeded': _seeded,
                      'entries': [
                        for (final e in _list) {'teamId': e.teamId, 'split': e.split}
                      ],
                      if (_split)
                        'splitNames': [
                          for (final (k, sp) in _splits.indexed)
                            _names[k].text.trim().isEmpty ? sp.str('name') : _names[k].text.trim()
                        ],
                    },
                    success: context.l10n.league_saved,
                    refresh: [leagueManageProvider(widget.leagueId)]);
                if (!mounted) return;
                setState(() => _busy = false);
                if (ok) Navigator.of(this.context).pop();
              },
      ),
    ]);
  }
}

/// Share & embed a league (web ShareLeagueDialog): its link, the table image
/// for socials, and the website widget's embed code.
Future<void> showShareLeagueSheet(BuildContext context, {required String base, required String slug, required String title}) =>
    showSpSheet<void>(context, builder: (_) => _ShareLeagueSheet(base: base, slug: slug, title: title));

class _ShareLeagueSheet extends StatefulWidget {
  const _ShareLeagueSheet({required this.base, required this.slug, required this.title});
  final String base;
  final String slug;
  final String title;
  @override
  State<_ShareLeagueSheet> createState() => _ShareLeagueSheetState();
}

class _ShareLeagueSheetState extends State<_ShareLeagueSheet> {
  String _view = 'table';

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.league_copied(what))));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final link = '${widget.base}/leagues/${widget.slug}';
    final image = '${widget.base}/api/leagues/${widget.slug}/table-image';
    final src = '${widget.base}/embed/leagues/${widget.slug}?view=$_view';
    final code = '<iframe src="$src" title="${widget.title.replaceAll('"', '&quot;')}" width="100%" '
        'height="${_view == 'table' ? 560 : 420}" style="border:0;border-radius:16px;max-width:640px" loading="lazy"></iframe>';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SpSheetHeader(
          title: context.l10n.league_shareEmbed,
          subtitle: context.l10n.league_sendTheLinkPostThe,
          icon: Icons.ios_share_rounded),
      SpListCard(children: [
        ListTile(
          leading: const Icon(Icons.link_rounded),
          title: Text(context.l10n.league_copyLink),
          subtitle: Text(link, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => _copy(link, context.l10n.league_link),
        ),
        ListTile(
          leading: const Icon(Icons.image_outlined),
          title: Text(context.l10n.league_tableImage),
          subtitle: Text(context.l10n.league_opensItSaveOrShare),
          onTap: () => launchUrl(Uri.parse(image), mode: LaunchMode.externalApplication),
          trailing: IconButton(icon: const Icon(Icons.copy_rounded, size: 18), onPressed: () => _copy(image, context.l10n.league_imageLink)),
        ),
      ]),
      const SizedBox(height: 14),
      FieldLabel(context.l10n.league_websiteWidget),
      Wrap(spacing: 6, children: [
        for (final (v, label) in [('table', context.l10n.league_table), ('fixtures', context.l10n.league_nextFixtures), ('results', context.l10n.league_results2)])
          ChoiceChip(label: Text(label), selected: _view == v, onSelected: (_) => setState(() => _view = v)),
      ]),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(16)),
        child: SelectableText(code, style: TextStyle(color: p.ink, fontFamily: 'monospace', fontSize: 11.5)),
      ),
      const SizedBox(height: 10),
      SpButton(label: context.l10n.league_copyEmbedCode, icon: Icons.code_rounded, expand: true, onTap: () => _copy(code, context.l10n.league_embedCode)),
      const SizedBox(height: 6),
      Text(context.l10n.league_theWidgetUpdatesItselfAs2, style: TextStyle(color: p.muted, fontSize: 12)),
    ]);
  }
}

/// Manual pairing (web AddFixtureDialog): the organiser adds a fixture to a
/// stage — table (its teams first; any league team can be the opponent),
/// round and an optional date.
Future<void> showAddFixtureSheet(BuildContext context, WidgetRef ref, {required J data, required J stage}) =>
    showSpSheet<void>(context, builder: (_) => _AddFixtureSheet(data: data, stage: stage));

class _AddFixtureSheet extends ConsumerStatefulWidget {
  const _AddFixtureSheet({required this.data, required this.stage});
  final J data;
  final J stage;
  @override
  ConsumerState<_AddFixtureSheet> createState() => _AddFixtureSheetState();
}

class _AddFixtureSheetState extends ConsumerState<_AddFixtureSheet> {
  String? _table;
  String? _home;
  String? _away;
  DateTime? _date;
  late final TextEditingController _round;
  String? _venueId;
  bool _busy = false;
  // Bumped after each add so the team pickers reset.
  int _gen = 0;

  List<J> get _tables => widget.data.list('standings').where((t) => t.s('stageId') == widget.stage.s('id')).toList();

  @override
  void initState() {
    super.initState();
    final rounds = widget.data.list('fixtures').where((f) => f.s('stageId') == widget.stage.s('id')).map((f) => f.i('round'));
    _round = TextEditingController(text: '${rounds.isEmpty ? 1 : rounds.reduce((a, b) => a > b ? a : b)}');
    _table = _tables.firstOrNull?.s('id');
  }

  @override
  void dispose() {
    _round.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final table = _tables.where((t) => t.s('id') == _table).firstOrNull ?? _tables.firstOrNull;
    final inTable = {for (final r in table?.list('rows') ?? const <J>[]) r.str('teamId')};
    final approved = widget.data.list('teams').where((t) => t.s('status') == 'approved').toList();
    final ordered = [...approved.where((t) => inTable.contains(t.str('teamId'))), ...approved.where((t) => !inTable.contains(t.str('teamId')))];
    DropdownMenuItem<String> item(J t) => DropdownMenuItem(
          value: t.str('teamId'),
          child: Text(inTable.contains(t.str('teamId')) || table == null ? t.str('name') : context.l10n.league_p5NameOtherTable(t.str('name')),
              overflow: TextOverflow.ellipsis),
        );
    Widget teamPick(String label, String? value, String? other, ValueChanged<String?> set) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FieldLabel(label),
            DropdownButtonFormField<String>(
              key: ValueKey('$label-$_gen-${other ?? ''}'),
              initialValue: value,
              isExpanded: true,
              items: [for (final t in ordered.where((t) => t.str('teamId') != other)) item(t)],
              onChanged: set,
              decoration: fieldDeco(context, context.l10n.league_pick),
            ),
          ],
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SpSheetHeader(
          title: context.l10n.league_addAFixture,
          subtitle: context.l10n.league_youMakeTheFixturesFor2(widget.stage.str('name')),
          icon: Icons.add_circle_outline_rounded),
      if (_tables.length > 1) ...[
        FieldLabel(context.l10n.league_table),
        Wrap(spacing: 6, children: [
          for (final t in _tables)
            ChoiceChip(label: Text(t.str('name')), selected: t.s('id') == table?.s('id'), onSelected: (_) => setState(() => _table = t.s('id'))),
        ]),
      ],
      Row(children: [
        Expanded(child: teamPick(context.l10n.league_home, _home, _away, (v) => setState(() => _home = v))),
        const SizedBox(width: 10),
        Expanded(child: teamPick(context.l10n.league_away, _away, _home, (v) => setState(() => _away = v))),
      ]),
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FieldLabel(context.l10n.league_round2),
            TextField(controller: _round, keyboardType: TextInputType.number, decoration: fieldDeco(context, '1')),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FieldLabel(context.l10n.league_dateOptional),
            PickField(
              text: _date == null ? context.l10n.league_noDate : fixtureDay(ymdOf(_date!)),
              onClear: _date == null ? null : () => setState(() => _date = null),
              onTap: () async {
                final d = await pickDay(context, _date);
                if (d != null) setState(() => _date = d);
              },
            ),
          ]),
        ),
      ]),
      FieldLabel(context.l10n.league_venue),
      VenueDropdown(
          venues: VenuesData.fromJson(ref.watch(leagueVenuesProvider(widget.data.o('league')!.str('id'))).valueOrNull?.raw ?? const {}).active,
          value: _venueId,
          none: context.l10n.league_defaultTheOnlyVenueOrHome,
          onChanged: (v) => setState(() => _venueId = v)),
      VenueHint(context.l10n.league_neededBeforeTheMatchGoes),
      const SizedBox(height: 16),
      SpButton(
        label: context.l10n.league_addFixture,
        icon: Icons.add_rounded,
        expand: true,
        onTap: _busy || _home == null || _away == null || (int.tryParse(_round.text.trim()) ?? 0) < 1
            ? null
            : () async {
                setState(() => _busy = true);
                final ok = await leagueAction(
                  context,
                  ref,
                  'addFixture',
                  {
                    'leagueId': widget.data.o('league')!.str('id'),
                    'stageId': widget.stage.str('id'),
                    'tableId': table?.s('id'),
                    'homeTeamId': _home,
                    'awayTeamId': _away,
                    'round': int.parse(_round.text.trim()),
                    'scheduledDate': _date == null ? null : ymdOf(_date!),
                    'venueId': _venueId,
                  },
                  success: context.l10n.league_fixtureAdded,
                  refresh: [leagueManageProvider(widget.data.o('league')!.str('id'))],
                );
                if (!mounted) return;
                setState(() {
                  _busy = false;
                  if (ok) {
                    _home = null;
                    _away = null;
                    _gen++;
                  }
                });
              },
      ),
      const SizedBox(height: 6),
      Text(context.l10n.league_addAsManyAsYou, style: TextStyle(color: p.muted, fontSize: 12)),
    ]);
  }
}
