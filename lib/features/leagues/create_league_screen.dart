import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/leagues/leagues_repository.dart';
import 'package:sportpadi_mobile/features/documents/team_documents.dart';
import 'package:sportpadi_mobile/data/teams/teams_repository.dart';
import 'package:sportpadi_mobile/features/leagues/league_sheets.dart';
import 'package:sportpadi_mobile/features/leagues/league_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// New tournament → League (web CreateLeagueDialog): sport chips, format
/// (the owner's standards for that sport), competition, season, division,
/// promotion / relegation, roster cutoff.
class CreateLeagueScreen extends ConsumerStatefulWidget {
  const CreateLeagueScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<CreateLeagueScreen> createState() => _CreateLeagueScreenState();
}

class _CreateLeagueScreenState extends ConsumerState<CreateLeagueScreen> {
  String? _sport; // null = the default
  String? _standard;
  String _competitionId = '';
  final _competitionName = TextEditingController();
  final _season = TextEditingController();
  final _division = TextEditingController();
  final _promote = TextEditingController();
  final _relegate = TextEditingController();
  DateTime? _starts;
  DateTime? _ends;
  DateTime? _lock;
  bool _awayGoals = false;
  bool _twoLegTies = false;
  bool _busy = false;

  /// Who can enter (leagues/registration.ts): open registration link,
  /// approval, grade rule, rules, required documents.
  bool _openReg = false;
  String _approval = 'auto';
  String _grade = 'any';
  int? _maxAge;
  List<String> _docIds = const [];
  final _rules = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final q = ref.watch(leagueSetupProvider(widget.groupId));
    final teams = ref.watch(groupTeamsProvider(widget.groupId)).valueOrNull ?? const [];
    return SpSubPage(
      title: context.l10n.league_newLeague,
      subtitle: context.l10n.league_aSeasonOfFixturesWith,
      body: AsyncView(
        value: q,
        onRetry: () => ref.invalidate(leagueSetupProvider(widget.groupId)),
        data: (setup) {
          if (!setup.b('enabled')) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: SpEmpty(
                  icon: Icons.lock_rounded,
                  title: context.l10n.league_leaguesAreAPlanFeature,
                  text: context.l10n.league_yourGroupsPlanDoesntInclude),
            );
          }
          final sports = setup.list('sports');
          if (sports.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: SpEmpty(icon: Icons.emoji_events_rounded, text: context.l10n.league_noLeagueFormatsAreAvailable),
            );
          }
          // Default sport: the one most of the group's teams play.
          final offered = {for (final s in sports) s.str('id')};
          final tally = <String, int>{};
          for (final t in teams) {
            final c = t.categoryId;
            if (c != null && offered.contains(c)) tally[c] = (tally[c] ?? 0) + 1;
          }
          final top = (tally.entries.toList()..sort((a, b) => b.value - a.value)).firstOrNull?.key;
          final sportId = _sport ?? top ?? sports.first.str('id');
          final formats = setup.list('standards').where((s) => s.o('category')?.s('id') == sportId).toList();
          final std = formats.where((f) => f.s('id') == _standard).firstOrNull ?? formats.firstOrNull;
          final comps = setup.list('competitions').where((c) => c.s('categoryId') == sportId).toList();
          final lockRequired = std?.o('rosters')?.b('lockRequired') ?? false;
          final canSubmit = std != null &&
              _season.text.trim().length >= 2 &&
              (_competitionId.isNotEmpty || _competitionName.text.trim().length >= 2) &&
              (!lockRequired || _lock != null) &&
              !_busy;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              GlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Eyebrow(context.l10n.league_sport),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final s in sports)
                      ChoiceChip(
                        label: Text('${s.str('emoji')} ${s.str('name')}'),
                        selected: s.s('id') == sportId,
                        onSelected: (_) => setState(() {
                          _sport = s.s('id');
                          _standard = null;
                          _competitionId = '';
                        }),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  Eyebrow(context.l10n.league_format),
                  const SizedBox(height: 8),
                  for (final f in formats)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: f.s('id') == std?.s('id') ? p.accentTint : p.surface2,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => setState(() => _standard = f.s('id')),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(f.str('name'), style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text(f.s('description') ?? f.str('summary'), style: TextStyle(color: p.muted, fontSize: 12)),
                              const SizedBox(height: 2),
                              Text(f.str('summary'), style: TextStyle(color: p.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
              if (std != null) ...[
                const SizedBox(height: 14),
                GlassCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Eyebrow(context.l10n.league_theSeason),
                    if (comps.isNotEmpty) ...[
                      FieldLabel(context.l10n.league_competition),
                      DropdownButtonFormField<String>(
                        key: ValueKey('comp-$sportId'),
                        initialValue: _competitionId,
                        decoration: fieldDeco(context, ''),
                        items: [
                          DropdownMenuItem(value: '', child: Text(context.l10n.league_newCompetition)),
                          for (final c in comps) DropdownMenuItem(value: c.str('id'), child: Text(c.str('name'))),
                        ],
                        onChanged: (v) => setState(() => _competitionId = v ?? ''),
                      ),
                    ] else
                      FieldLabel(context.l10n.league_competition),
                    if (_competitionId.isEmpty) ...[
                      if (comps.isNotEmpty) const SizedBox(height: 8),
                      TextField(
                        controller: _competitionName,
                        textCapitalization: TextCapitalization.words,
                        decoration: fieldDeco(context, context.l10n.league_eGSurreySundayLeague),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                    FieldLabel(context.l10n.league_season),
                    TextField(
                        controller: _season,
                        decoration: fieldDeco(context, context.l10n.league_fall20262027),
                        onChanged: (_) => setState(() {})),
                    if (std.b('usesDivisions')) ...[
                      FieldLabel(context.l10n.league_divisionOptional),
                      TextField(
                          controller: _division, decoration: fieldDeco(context, context.l10n.league_division1), onChanged: (_) => setState(() {})),
                    ],
                    if (std.b('usesDivisions') && std.b('usesPromotionRelegation') && _division.text.trim().isNotEmpty)
                      Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            FieldLabel(context.l10n.league_goUp),
                            TextField(controller: _promote, keyboardType: TextInputType.number, decoration: fieldDeco(context, '0')),
                          ]),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            FieldLabel(context.l10n.league_goDown),
                            TextField(controller: _relegate, keyboardType: TextInputType.number, decoration: fieldDeco(context, '0')),
                          ]),
                        ),
                      ]),
                    Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          FieldLabel(context.l10n.league_starts),
                          PickField(
                              text: _starts == null ? '—' : fixtureDay(ymdOf(_starts!)),
                              onTap: () async {
                                final d = await pickDay(context, _starts);
                                if (d != null) setState(() => _starts = d);
                              }),
                        ]),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          FieldLabel(context.l10n.league_ends),
                          PickField(
                              text: _ends == null ? '—' : fixtureDay(ymdOf(_ends!)),
                              onTap: () async {
                                final d = await pickDay(context, _ends ?? _starts);
                                if (d != null) setState(() => _ends = d);
                              }),
                        ]),
                      ),
                    ]),
                    FieldLabel(lockRequired ? context.l10n.league_rosterCutoff2 : context.l10n.league_rosterCutoffOptional),
                    PickField(
                      icon: Icons.lock_clock_rounded,
                      text: _lock == null ? context.l10n.league_noCutoff : MaterialLocalizations.of(context).formatFullDate(_lock!),
                      onClear: _lock == null ? null : () => setState(() => _lock = null),
                      onTap: () async {
                        final d = await pickDay(context, _lock);
                        if (d != null) setState(() => _lock = DateTime(d.year, d.month, d.day, 23, 59));
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                        context.l10n.league_afterItCoachesCantChange,
                        style: TextStyle(color: p.muted, fontSize: 11.5)),
                    if (std.b('twoLegTies')) ...[
                      const SizedBox(height: 10),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(context.l10n.league_awayGoalsRule, style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            context.l10n.league_inTwoLegTiesLevel2,
                            style: TextStyle(color: p.muted, fontSize: 11.5)),
                        value: _awayGoals,
                        onChanged: (v) => setState(() => _awayGoals = v),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: 14),
                GlassCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Eyebrow(context.l10n.league_whoCanEnter2),
                    const SizedBox(height: 10),
                    Text(context.l10n.league_openTo, style: TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final g in [('any', context.l10n.league_anyTeam), ('adults', context.l10n.league_adults), ('kids', context.l10n.league_kids)])
                        ChoiceChip(label: Text(g.$2), selected: _grade == g.$1, onSelected: (_) => setState(() => _grade = g.$1)),
                    ]),
                    if (_grade == 'kids') ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final a in const [null, 12, 16, 18])
                          ChoiceChip(label: Text(a == null ? context.l10n.league_anyAge : context.l10n.league_u(a)), selected: _maxAge == a, onSelected: (_) => setState(() => _maxAge = a)),
                      ]),
                    ],
                    const SizedBox(height: 12),
                    Text(context.l10n.league_howDoTeamsGetIn, style: TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, children: [
                      ChoiceChip(label: Text(context.l10n.league_teamsIInvite), selected: !_openReg, onSelected: (_) => setState(() => _openReg = false)),
                      ChoiceChip(label: Text(context.l10n.league_openRegistration), selected: _openReg, onSelected: (_) => setState(() => _openReg = true)),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                        _openReg
                            ? context.l10n.league_youGetARegistrationLink
                            : context.l10n.league_onlyTeamsYouInviteTake,
                        style: TextStyle(color: p.muted, fontSize: 11.5)),
                    if (_openReg) ...[
                      const SizedBox(height: 12),
                      DocumentPicker(categoryId: sportId, value: _docIds, onChanged: (v) => setState(() => _docIds = v)),
                      if (_docIds.isNotEmpty) const SizedBox(height: 12),
                      Text(context.l10n.league_approval, style: TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      if (_docIds.isNotEmpty)
                        Text(context.l10n.league_requiredDocumentsMeanYouReview,
                            style: TextStyle(color: p.muted, fontSize: 11.5))
                      else
                        Wrap(spacing: 8, children: [
                          ChoiceChip(label: Text(context.l10n.league_automatic), selected: _approval == 'auto', onSelected: (_) => setState(() => _approval = 'auto')),
                          ChoiceChip(label: Text(context.l10n.league_iApproveEachTeam), selected: _approval == 'manual', onSelected: (_) => setState(() => _approval = 'manual')),
                        ]),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _rules,
                        minLines: 2,
                        maxLines: 4,
                        maxLength: 2000,
                        decoration: InputDecoration(
                          labelText: context.l10n.league_rulesWhatTeamsShouldKnow2,
                          hintText: context.l10n.league_matchDaysSquadSizeKit,
                          counterText: '',
                        ),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: 18),
                SpButton(
                  label: _openReg ? context.l10n.league_createGetLink : context.l10n.league_createLeague,
                  expand: true,
                  onTap: canSubmit
                      ? () {
                          _twoLegTies = std.b('twoLegTies');
                          _create(sportId, std.str('id'));
                        }
                      : null,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _create(String sportId, String standardId) async {
    setState(() => _busy = true);
    try {
      final r = J.of(await ref.read(leaguesRepositoryProvider).mutate('create', {
        'groupId': widget.groupId,
        'categoryId': sportId,
        'standardId': standardId,
        'competitionId': _competitionId.isEmpty ? null : _competitionId,
        'competitionName': _competitionId.isEmpty ? _competitionName.text.trim() : null,
        'season': _season.text.trim(),
        'division': _division.text.trim().isEmpty ? null : _division.text.trim(),
        'promoteCount': int.tryParse(_promote.text.trim()),
        'relegateCount': int.tryParse(_relegate.text.trim()),
        'seasonStartsOn': _starts == null ? null : ymdOf(_starts!),
        'seasonEndsOn': _ends == null ? null : ymdOf(_ends!),
        'rosterLockAt': _lock?.toUtc().toIso8601String(),
        if (_twoLegTies) 'awayGoals': _awayGoals,
        'registration': _openReg ? 'open' : 'invite_only',
        'grade': _grade,
        'maxAge': _grade == 'kids' ? _maxAge : null,
        'approval': _docIds.isNotEmpty ? 'manual' : _approval,
        if (_rules.text.trim().isNotEmpty) 'rules': _rules.text.trim(),
        if (_openReg) 'documentTypeIds': _docIds,
      }));
      ref.invalidate(groupLeaguesProvider(widget.groupId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_openReg ? l10n.league_leagueCreatedYourRegistrationLink : l10n.league_leagueCreatedInviteTeamsNext)));
      context.pushReplacement('/groups/${widget.groupId}/leagues/${r.str('id')}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : l10n.league_couldNotCreateTheLeague)));
      setState(() => _busy = false);
    }
  }
}
