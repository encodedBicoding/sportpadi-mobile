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
      const SpSheetHeader(
          title: 'Set fixture dates',
          subtitle: 'Round 1 on the start date, then a round every few days. Change any match after.',
          icon: Icons.calendar_month_rounded),
      const FieldLabel('Round 1'),
      PickField(
          text: _start == null ? 'Pick a date' : fixtureDay(ymdOf(_start!)),
          onTap: () async {
            final d = await pickDay(context, _start);
            if (d != null) setState(() => _start = d);
          }),
      const FieldLabel('Every'),
      Wrap(spacing: 8, children: [
        for (final n in [7, 14, 3, 1])
          ChoiceChip(
              label: Text(n == 1 ? 'Daily' : n == 7 ? 'Weekly' : n == 14 ? 'Fortnightly' : 'Every $n days'),
              selected: _every == n,
              onSelected: (_) => setState(() => _every = n)),
      ]),
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const FieldLabel('Kick-off'),
            PickField(
                icon: Icons.schedule_rounded,
                text: _time == null ? 'Any time' : formatTime12(_time!),
                onTap: () async {
                  final t = await pickHhmm(context, _time);
                  if (t != null) setState(() => _time = t);
                }),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const FieldLabel('Ends'),
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
      const FieldLabel('Venue'),
      VenueDropdown(venues: venues, value: _venueId, none: "Keep each fixture's venue", onChanged: (v) => setState(() => _venueId = v)),
      const VenueHint("Kick-off is local time at each fixture's venue. Pick one to put them all there."),
      const SizedBox(height: 18),
      SpButton(
        label: 'Apply',
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
                }, success: 'Fixtures scheduled', refresh: [leagueManageProvider(widget.leagueId)]);
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
    }, success: widget.f.b('published') ? 'Rescheduled — both teams were told' : 'Saved', refresh: [leagueManageProvider(widget.leagueId)]);
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
          title: '${f.o('home')?.str('name') ?? f.str('homeSlot', 'TBC')} vs ${f.o('away')?.str('name') ?? f.str('awaySlot', 'TBC')}',
          subtitle: f.s('label') ?? 'Round ${f.i('round')}',
          icon: Icons.sports_soccer_rounded),
      const FieldLabel('Date'),
      PickField(
          text: _date == null ? 'Pick a date' : fixtureDay(ymdOf(_date!)),
          onTap: () async {
            final d = await pickDay(context, _date);
            if (d != null) setState(() => _date = d);
          }),
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const FieldLabel('Kick-off'),
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
            const FieldLabel('Ends'),
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
      const FieldLabel('Venue'),
      VenueDropdown(
          venues: venues, value: _venueId, none: f.b('published') ? null : 'No venue yet', onChanged: (v) => setState(() => _venueId = v)),
      if (_venueId == null && f.s('venue') != null) VenueHint('Currently: ${f.str('venue')}'),
      VenueHint(picked?.timezone != null
          ? 'Kick-off is local time there (${picked!.timezone!.replaceAll('_', ' ')}).${f.b('published') && _venueId != f.s('venueId') ? ' Everyone in the match is told.' : ''}'
          : "Pick one of the season's venues — add more on the Venues tab."),
      const SizedBox(height: 18),
      Row(children: [
        if (!f.b('published')) ...[
          Expanded(
            child: SpPill(
                label: 'Swap home/away',
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
                label: 'Save',
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
          title: 'Forfeit this match',
          subtitle: 'The other team gets the win. The played score stays on record; you can revoke it later.',
          icon: Icons.gavel_rounded,
          iconBg: context.palette.liveTint,
          iconFg: context.palette.danger),
      const FieldLabel('Team that forfeits'),
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
      const FieldLabel('Reason'),
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (final (k, v) in [
          ('ineligible_player', 'Ineligible player'),
          ('no_show', "Didn't show up"),
          ('conduct', 'Conduct'),
          ('other', 'Other'),
        ])
          ChoiceChip(label: Text(v), selected: _reason == k, onSelected: (_) => setState(() => _reason = k)),
      ]),
      const FieldLabel('Public reason (on the league page)'),
      TextField(controller: _public, maxLength: 200, decoration: fieldDeco(context, 'Fielded an unregistered player')),
      const FieldLabel('Private note (organisers only)'),
      TextField(controller: _private, maxLines: 3, decoration: fieldDeco(context, 'Optional')),
      const SizedBox(height: 16),
      SpButton(
        label: 'Record forfeit',
        icon: Icons.gavel_rounded,
        expand: true,
        onTap: _busy || _team == null
            ? null
            : () async {
                if (_public.text.trim().length < 3) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a short public reason.')));
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
                }, success: 'Forfeit recorded — the table is updated', refresh: [leagueManageProvider(widget.leagueId)]);
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
      const SpSheetHeader(
          title: 'Invite teams', subtitle: 'Your own teams join straight away; others get an invitation.', icon: Icons.group_add_rounded),
      TextField(
        autofocus: true,
        decoration: fieldDeco(context, 'Search teams by name or @handle').copyWith(prefixIcon: const Icon(Icons.search_rounded)),
        onChanged: (v) => setState(() => _q = v.trim()),
      ),
      const SizedBox(height: 10),
      AsyncView(
        value: q,
        data: (list) => list.isEmpty
            ? Padding(padding: const EdgeInsets.all(16), child: Text('No teams found for this sport.', style: TextStyle(color: p.muted)))
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
                          Text('@${t.str('username')}${t.b('ownTeam') ? ' · your team' : ''}',
                              style: TextStyle(color: p.muted, fontSize: 11.5)),
                        ]),
                      ),
                      if (t.o('entry') != null)
                        SpBadge(t.o('entry')!.b('here') ? (t.o('entry')!.s('status') == 'approved' ? 'In' : 'Invited') : 'Elsewhere')
                      else
                        SpPill(
                          label: t.b('ownTeam') ? 'Add' : 'Invite',
                          height: 34,
                          onTap: _busy.contains(t.str('id'))
                              ? null
                              : () async {
                                  setState(() => _busy.add(t.str('id')));
                                  await leagueAction(context, ref, 'inviteTeam', {'leagueId': widget.leagueId, 'teamId': t.str('id')},
                                      success: t.b('ownTeam') ? 'Team added' : 'Invite sent',
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
        if (d == null) return const Padding(padding: EdgeInsets.all(20), child: Text('No stage is waiting.'));
        final list = _list ??
            [
              for (final e in d.list('entries'))
                {
                  'teamId': e.str('teamId'),
                  'origin': e.s('origin'),
                  'table': e.s('table'),
                  'position': e.iOrNull('position'),
                  'name': e.o('team')?.str('name') ?? 'Team',
                }
            ];
        final others = d.list('teams').where((t) => !list.any((x) => x['teamId'] == t.s('teamId'))).toList();
        void set(List<Map<String, dynamic>> v) => setState(() => _list = v);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          SpSheetHeader(
              title: 'Into the ${d.o('to')?.str('name').toLowerCase() ?? 'next stage'}',
              subtitle: 'Proposed from ${d.o('from')?.str('name').toLowerCase() ?? 'the last stage'}. Teams not listed are out. Order = seeding.',
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
                      Text('${e['origin'] ?? 'Added by you'}', style: TextStyle(color: p.muted, fontSize: 11.5)),
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
            const FieldLabel('Add a team'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in others)
                ActionChip(
                  label: Text('${t.str('name')}${t.s('finished') != null ? ' (${t.str('finished')})' : ''}'),
                  onPressed: () => set([
                    ...list,
                    {'teamId': t.str('teamId'), 'origin': 'Added by you', 'table': null, 'position': null, 'name': t.str('name')}
                  ]),
                ),
            ]),
          ],
          const SizedBox(height: 16),
          SpButton(
            label: 'Confirm ${list.length} teams & draw',
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
                    }, success: 'Drawn — set dates, then open the stage', refresh: [leagueManageProvider(widget.leagueId)]);
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
          title: 'Confirm the ${name.toLowerCase()} winners',
          subtitle: 'These teams move up the bracket. Wrong result? Fix the match (or record a forfeit) first.',
          icon: Icons.account_tree_rounded),
      SpListCard(children: [
        for (final f in ties)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.str('label'), style: TextStyle(color: p.muted, fontSize: 11.5)),
              Text(
                  '${f.o('home')?.str('name')} ${f.i('homeScore')}–${f.i('awayScore')} ${f.o('away')?.str('name')}'
                  '${f.s('decision') == 'shootout' ? ' (pens ${f.i('homeSo')}–${f.i('awaySo')})' : f.s('decision') == 'forfeit' ? ' (forfeit)' : ''}',
                  style: TextStyle(color: p.ink, fontSize: 13.5)),
              const SizedBox(height: 2),
              Text('✓ ${winner(f) ?? '—'} go through', style: TextStyle(color: p.greenText, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ]),
          ),
      ]),
      const SizedBox(height: 16),
      SpButton(
        label: 'Confirm & move them up',
        expand: true,
        onTap: () async {
          final ok = await leagueAction(ctx, ref, 'confirmRound', {'stageId': stageId, 'round': round},
              success: 'Through — give the next matches a date to create them', refresh: [leagueManageProvider(leagueId)]);
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
              const Expanded(
                child: Text("Scan the player's league pass",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
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
        ? 'Seeded: 1 meets the last seed, and the top two can only meet in the final.'
        : kind == 'groups'
            ? 'Seeded: teams are dealt in pots in this order, so the top seeds land in different groups.'
            : 'Seeded: unpicked teams are dealt in this order instead of at random.';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SpSheetHeader(
          title: _split ? 'Tables & seeding' : 'Seeding',
          subtitle: _split ? 'Pick which table each team starts in — "Draw" puts it in the smaller table.' : hint,
          icon: Icons.format_list_numbered_rounded),
      if (_split) ...[
        Row(children: [
          for (final (k, sp) in _splits.indexed) ...[
            if (k > 0) const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FieldLabel('Table ${k + 1} · ${_list.where((e) => e.split == sp.str('key')).length} picked'),
                TextField(controller: _names[k], maxLength: 30, decoration: const InputDecoration(counterText: '')),
              ]),
            ),
          ],
        ]),
        const SizedBox(height: 8),
      ],
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text('Seeded draw', style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
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
                child: Text(byId[e.teamId]?.str('name') ?? 'Team',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.ink, fontWeight: FontWeight.w600)),
              ),
              if (_split)
                DropdownButton<String?>(
                  value: e.split,
                  underline: const SizedBox.shrink(),
                  style: TextStyle(color: p.ink, fontSize: 12.5),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Draw')),
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
        label: 'Save',
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
                    success: 'Saved',
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what copied')));
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
      const SpSheetHeader(
          title: 'Share & embed',
          subtitle: "Send the link, post the table as an image, or put a live widget on your club's website.",
          icon: Icons.ios_share_rounded),
      SpListCard(children: [
        ListTile(
          leading: const Icon(Icons.link_rounded),
          title: const Text('Copy link'),
          subtitle: Text(link, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => _copy(link, 'Link'),
        ),
        ListTile(
          leading: const Icon(Icons.image_outlined),
          title: const Text('Table image'),
          subtitle: const Text('Opens it — save or share from there'),
          onTap: () => launchUrl(Uri.parse(image), mode: LaunchMode.externalApplication),
          trailing: IconButton(icon: const Icon(Icons.copy_rounded, size: 18), onPressed: () => _copy(image, 'Image link')),
        ),
      ]),
      const SizedBox(height: 14),
      const FieldLabel('Website widget'),
      Wrap(spacing: 6, children: [
        for (final (v, label) in [('table', 'Table'), ('fixtures', 'Next fixtures'), ('results', 'Results')])
          ChoiceChip(label: Text(label), selected: _view == v, onSelected: (_) => setState(() => _view = v)),
      ]),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(16)),
        child: SelectableText(code, style: TextStyle(color: p.ink, fontFamily: 'monospace', fontSize: 11.5)),
      ),
      const SizedBox(height: 10),
      SpButton(label: 'Copy embed code', icon: Icons.code_rounded, expand: true, onTap: () => _copy(code, 'Embed code')),
      const SizedBox(height: 6),
      Text('The widget updates itself as results come in.', style: TextStyle(color: p.muted, fontSize: 12)),
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
          child: Text('${t.str('name')}${inTable.contains(t.str('teamId')) || table == null ? '' : ' (other table)'}',
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
              decoration: fieldDeco(context, 'Pick…'),
            ),
          ],
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SpSheetHeader(
          title: 'Add a fixture',
          subtitle: '${widget.stage.str('name')}: you make the fixtures for this stage.',
          icon: Icons.add_circle_outline_rounded),
      if (_tables.length > 1) ...[
        const FieldLabel('Table'),
        Wrap(spacing: 6, children: [
          for (final t in _tables)
            ChoiceChip(label: Text(t.str('name')), selected: t.s('id') == table?.s('id'), onSelected: (_) => setState(() => _table = t.s('id'))),
        ]),
      ],
      Row(children: [
        Expanded(child: teamPick('Home', _home, _away, (v) => setState(() => _home = v))),
        const SizedBox(width: 10),
        Expanded(child: teamPick('Away', _away, _home, (v) => setState(() => _away = v))),
      ]),
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const FieldLabel('Round'),
            TextField(controller: _round, keyboardType: TextInputType.number, decoration: fieldDeco(context, '1')),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const FieldLabel('Date (optional)'),
            PickField(
              text: _date == null ? 'No date' : fixtureDay(ymdOf(_date!)),
              onClear: _date == null ? null : () => setState(() => _date = null),
              onTap: () async {
                final d = await pickDay(context, _date);
                if (d != null) setState(() => _date = d);
              },
            ),
          ]),
        ),
      ]),
      const FieldLabel('Venue'),
      VenueDropdown(
          venues: VenuesData.fromJson(ref.watch(leagueVenuesProvider(widget.data.o('league')!.str('id'))).valueOrNull?.raw ?? const {}).active,
          value: _venueId,
          none: "Default — the only venue, or the home team's",
          onChanged: (v) => setState(() => _venueId = v)),
      const VenueHint("Needed before the match goes live — it sets the match's local time zone. Add venues on the Venues tab."),
      const SizedBox(height: 16),
      SpButton(
        label: 'Add fixture',
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
                  success: 'Fixture added',
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
      Text('Add as many as you like — the sheet stays open.', style: TextStyle(color: p.muted, fontSize: 12)),
    ]);
  }
}
