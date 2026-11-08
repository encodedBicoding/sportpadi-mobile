import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/data/teams/team_models.dart';
import 'package:sportpadi_mobile/data/teams/teams_repository.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/features/documents/team_documents.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart' show deviceTimezone;
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// New tournament (2026 design — web twin: groups/TournamentsTab
/// CreateTournamentDialog). One page, four cards: format, the basics, who's
/// playing, the teams (+ entry fee when the wallet is live), with the CTA
/// pinned under them.
class CreateTournamentScreen extends ConsumerStatefulWidget {
  const CreateTournamentScreen({super.key, required this.groupId, this.initialMode});
  final String groupId;

  /// friendly | multi_team — preselected when opened from a mode's page.
  final String? initialMode;
  @override
  ConsumerState<CreateTournamentScreen> createState() =>
      _CreateTournamentScreenState();
}

class _CreateTournamentScreenState
    extends ConsumerState<CreateTournamentScreen> {
  final _title = TextEditingController();
  final _search = TextEditingController();
  final _fee = TextEditingController();
  final _venue = TextEditingController();
  final _rules = TextEditingController();
  String? _categoryId;

  /// Who can enter (web twin: RegistrationPanel GradePicker/ApprovalPicker).
  /// Open registration mints a link any team registers through — the
  /// "call for teams" post; the grade rule applies to invited teams too.
  bool _openReg = false;
  String _approval = 'auto';
  String _grade = 'any';
  int? _maxAge;
  List<String> _docIds = const [];
  DateTime? _date;
  late String _mode = widget.initialMode == 'multi_team' ? 'multi_team' : 'friendly';
  String? _hostTeamId;

  /// The group runs the event without fielding a team of its own — most
  /// organisers are just bringing teams together: a draw of invited teams,
  /// or a friendly between two invited teams.
  bool _organiserOnly = false;

  /// Neutral friendly / multi-team: teams are picked into [_guests].
  bool get _pickMany => _isMulti || _organiserOnly;

  /// Neutral friendly: which of the two is the home side (the match's
  /// "host" — not necessarily a team the organiser created). Null = first.
  String? _homeId;
  int get _seats => _isMulti ? _maxTeams : 2;
  final List<TeamSummary> _guests = [];
  int _maxTeams = 8;

  List<TeamSummary> _results = const [];
  bool _searching = false;
  int _searchToken = 0;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _search.dispose();
    _fee.dispose();
    _venue.dispose();
    _rules.dispose();
    super.dispose();
  }

  bool get _isMulti => _mode != 'friendly';
  bool get _neutralFriendly => !_isMulti && _organiserOnly;
  String? get _homeIdEffective =>
      _homeId ?? (_guests.isNotEmpty ? _guests.first.id : null);

  int? _feeMinor() {
    final wallet = ref.read(groupWalletProvider(widget.groupId)).valueOrNull;
    if (wallet == null || !wallet.active) return null;
    final v = double.tryParse(_fee.text.trim());
    if (v == null || v <= 0) return null;
    var mult = 1;
    for (var i = 0; i < wallet.exponent; i++) {
      mult *= 10;
    }
    return (v * mult).round();
  }

  Future<void> _runSearch(String q) async {
    if (_categoryId == null || q.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    final token = ++_searchToken;
    setState(() => _searching = true);
    try {
      final res = await ref.read(manageRepositoryProvider).searchTeams(
            q.trim(),
            categoryId: _categoryId,
            // Organising only: any team may play; a friendly WE play in
            // needs an outsider.
            excludeGroupId: _organiserOnly ? null : widget.groupId,
          );
      if (token == _searchToken && mounted) {
        setState(() => _results = res);
      }
    } catch (_) {
      if (mounted) setState(() => _results = const []);
    } finally {
      if (mounted && token == _searchToken) setState(() => _searching = false);
    }
  }

  void _addTeam(TeamSummary r) => setState(() {
        if (_pickMany) {
          final used = _guests.length + (_organiserOnly ? 0 : 1);
          if (used < _seats) {
            _guests.add(r);
          } else {
            _error = _isMulti
                ? context.l10n.manage_thisTournamentHoldsTeams(_maxTeams, (_organiserOnly ? '' : context.l10n.manage_includingYours))
                : context.l10n.manage_aFriendlyIsTwoTeams;
          }
        } else {
          _guests
            ..clear()
            ..add(r);
        }
        _search.clear();
        _results = const [];
      });

  void _removeTeam(TeamSummary g) => setState(() {
        _guests.remove(g);
        if (_homeId == g.id) _homeId = null;
      });

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 3),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) {
      return setState(() => _error = l10n.manage_addATitle);
    }
    if (_categoryId == null) return setState(() => _error = l10n.manage_pickASport);
    if (_date == null) return setState(() => _error = l10n.manage_pickADate);
    final noOwnTeam = _organiserOnly;
    if (!noOwnTeam && _hostTeamId == null) {
      return setState(
          () => _error = l10n.manage_chooseYourTeamOrSay);
    }
    if (!_isMulti && !noOwnTeam && _guests.isEmpty) {
      return setState(() => _error = l10n.manage_inviteAnOpponent);
    }
    if (_neutralFriendly && _guests.length != 2) {
      return setState(() => _error = l10n.manage_pickTheTwoTeamsThat);
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ref.read(manageRepositoryProvider).createTournament({
        'groupId': widget.groupId,
        'categoryId': _categoryId,
        'title': _title.text.trim(),
        'mode': _mode,
        'eventDate': DateTime.utc(_date!.year, _date!.month, _date!.day)
            .toIso8601String(),
        'hostTeamId': noOwnTeam ? null : _hostTeamId,
        'guestTeamId': _pickMany ? null : _guests.first.id,
        'guestTeamIds': _pickMany ? _guests.map((g) => g.id).toList() : null,
        'homeTeamId': _neutralFriendly ? _homeIdEffective : null,
        'maxTeams': _isMulti ? _maxTeams : null,
        // Multi-team: the main venue becomes the tournament's first venue
        // (pinned once — matches take its time zone).
        if (_isMulti && _venue.text.trim().isNotEmpty) 'locationName': _venue.text.trim(),
        'timezone': deviceTimezone,
        'feeMinor': _feeMinor(),
        if (_mode == 'multi_team')
          'registration': _openReg ? 'open' : 'invite_only',
        'grade': _grade,
        'maxAge': _grade == 'kids' ? _maxAge : null,
        'approval': _docIds.isNotEmpty ? 'manual' : _approval,
        if (_rules.text.trim().isNotEmpty) 'rules': _rules.text.trim(),
        if (_openReg && _mode == 'multi_team') 'documentTypeIds': _docIds,
      });
      ref.invalidate(groupTournamentsProvider(widget.groupId));
      final eventId = res['eventId'];
      if (!mounted) return;
      if (eventId is String && eventId.isNotEmpty) {
        context.pushReplacement('/tournaments/$eventId');
      } else {
        context.pop();
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final teams = ref.watch(groupTeamsProvider(widget.groupId));
    final hostTeams = teams.maybeWhen(
      data: (list) => list
          .where((t) => _categoryId == null || t.categoryId == _categoryId)
          .toList(),
      orElse: () => const <TeamSummary>[],
    );
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final wallet = ref.watch(groupWalletProvider(widget.groupId)).valueOrNull;

    return SpSubPage(
      title: context.l10n.manage_newTournament,
      subtitle: _isMulti
          ? context.l10n.manage_aDrawOfUpTo(_maxTeams)
          : context.l10n.manage_oneMatchBetweenTwoTeams,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          // ── Format ────────────────────────────────────────────────────
          Row(children: [
            Expanded(
              child: _ChoiceCard(
                icon: Icons.sports_soccer_rounded,
                title: context.l10n.manage_t1V1Friendly,
                sub: context.l10n.manage_oneMatchYoursVsA,
                selected: !_isMulti,
                onTap: () => setState(() {
                  _mode = 'friendly';
                  _guests.clear();
                  _homeId = null;
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ChoiceCard(
                icon: Icons.emoji_events_rounded,
                title: context.l10n.manage_multiTeam,
                sub: context.l10n.manage_severalTeamsADrawWith,
                selected: _isMulti,
                onTap: () => setState(() {
                  _mode = 'multi_team';
                  _guests.clear();
                  _homeId = null;
                }),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          // League: a season of fixtures with a table — its own flow.
          _ChoiceCard(
            icon: Icons.format_list_numbered_rounded,
            title: context.l10n.manage_league,
            sub: context.l10n.manage_aSeasonOfFixturesLive,
            selected: false,
            onTap: () => context.pushReplacement('/groups/${widget.groupId}/new-league'),
          ),

          // ── The basics ────────────────────────────────────────────────
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Eyebrow(context.l10n.manage_theBasics),
                  const SizedBox(height: 10),
                  _FieldLabel(context.l10n.manage_title),
                  TextField(
                    controller: _title,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                        hintText: _isMulti
                            ? context.l10n.manage_eGSummerCup2026
                            : context.l10n.manage_eGSundayFriendly),
                  ),
                  if (_isMulti) ...[
                    const SizedBox(height: 14),
                    _FieldLabel(context.l10n.manage_mainVenueOptional),
                    TextField(
                      controller: _venue,
                      decoration: InputDecoration(hintText: context.l10n.manage_streetParkAndCityE),
                    ),
                    const SizedBox(height: 4),
                    Text(context.l10n.manage_becomesTheFirstVenueAdd,
                        style: TextStyle(color: p.muted, fontSize: 11.5)),
                  ],
                  const SizedBox(height: 14),
                  _FieldLabel(context.l10n.manage_sport),
                  if (cats.isEmpty)
                    Text(context.l10n.manage_loadingSports,
                        style: TextStyle(color: p.muted, fontSize: 13))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in cats)
                          _Chip(
                            label: '${c.emoji ?? ''} ${c.name}'.trim(),
                            selected: _categoryId == c.id,
                            onTap: () => setState(() {
                              _categoryId = c.id;
                              _hostTeamId = null;
                              _guests.clear();
                              _homeId = null;
                              _results = const [];
                            }),
                          ),
                      ],
                    ),
                  const SizedBox(height: 14),
                  _FieldLabel(context.l10n.manage_date),
                  _TapRow(
                    icon: Icons.calendar_today_rounded,
                    text: _date == null
                        ? context.l10n.manage_chooseADate
                        : DateFormat('EEE, d MMM yyyy').format(_date!),
                    placeholder: _date == null,
                    onTap: _pickDate,
                  ),
                ]),
          ),

          // ── Who's playing ─────────────────────────────────────────────
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Eyebrow(context.l10n.manage_whosPlaying),
                  const SizedBox(height: 4),
                  Text(context.l10n.manage_isOneOfYourTeams,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: _ChoiceCard(
                        title: context.l10n.manage_yesOurTeamPlays,
                        sub: _isMulti
                            ? context.l10n.manage_pickWhichOneBelow
                            : context.l10n.manage_pickItBelowThenThe,
                        selected: !_organiserOnly,
                        onTap: () => setState(() {
                          _organiserOnly = false;
                          _guests.clear();
                          _homeId = null;
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ChoiceCard(
                        title: context.l10n.manage_noJustOrganizing,
                        sub: _isMulti
                            ? context.l10n.manage_inviteTeamsNoneOfOurs
                            : context.l10n.manage_pickTheTwoTeamsThat2,
                        selected: _organiserOnly,
                        onTap: () => setState(() {
                          _organiserOnly = true;
                          _guests.clear();
                          _homeId = null;
                        }),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  if (_organiserOnly)
                    SpTipCard(
                      _isMulti
                          ? context.l10n.manage_youllRunTheFixturesOfficials
                          : context.l10n.manage_youHostTheMatchVenue,
                      icon: Icons.campaign_rounded,
                    )
                  else if (_categoryId == null)
                    Text(context.l10n.manage_pickASportFirst,
                        style: TextStyle(color: p.muted, fontSize: 13))
                  else if (hostTeams.isEmpty)
                    SpTipCard(
                      context.l10n.manage_youHaveNoTeamFor,
                      icon: Icons.shield_outlined,
                    )
                  else ...[
                    _FieldLabel(context.l10n.manage_yourTeam),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in hostTeams)
                          _Chip(
                            label: t.name,
                            selected: _hostTeamId == t.id,
                            onTap: () => setState(() => _hostTeamId = t.id),
                          ),
                      ],
                    ),
                  ],
                ]),
          ),

          // ── The teams ─────────────────────────────────────────────────
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Eyebrow(_isMulti
                          ? context.l10n.manage_inviteTeams
                          : _organiserOnly
                              ? context.l10n.manage_theTwoTeams
                              : context.l10n.manage_opponent),
                    ),
                    if (_pickMany)
                      SpBadge(
                          _isMulti
                              ? context.l10n.manage_invitedAddMoreLater(_guests.length)
                              : context.l10n.manage_of2Picked(_guests.length),
                          tone: _neutralFriendly && _guests.length == 2
                              ? p.accent
                              : null),
                  ]),
                  if (_guests.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    for (final (k, g) in _guests.indexed) ...[
                      if (k > 0) Divider(height: 1, color: p.surface2),
                      _TeamRow(
                        team: g,
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (_neutralFriendly && _guests.length == 2)
                            _homeIdEffective == g.id
                                ? SpBadge(context.l10n.manage_home, tone: p.accent)
                                : SpPill(
                                    label: context.l10n.manage_makeHome,
                                    tone: SpPillTone.soft,
                                    height: 30,
                                    onTap: () =>
                                        setState(() => _homeId = g.id)),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => _removeTeam(g),
                            child: Icon(Icons.close_rounded,
                                size: 20, color: p.muted),
                          ),
                        ]),
                      ),
                    ],
                    if (_neutralFriendly && _guests.length == 2) ...[
                      const SizedBox(height: 4),
                      Text(
                          context.l10n.manage_homeIsListedFirstAnd,
                          style: TextStyle(color: p.muted, fontSize: 11.5)),
                    ],
                  ],
                  const SizedBox(height: 12),
                  SpSearchCard(
                    controller: _search,
                    hint: _categoryId == null
                        ? context.l10n.manage_pickASportFirst2
                        : context.l10n.manage_searchTeamHandleOrName,
                    onChanged: _runSearch,
                    onClear: () => setState(() => _results = const []),
                  ),
                  if (_searching)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  for (final r in _results
                      .where((r) => !_guests.any((g) => g.id == r.id)))
                    _TeamRow(
                      team: r,
                      trailing: SpPill(
                          label: context.l10n.manage_add,
                          icon: Icons.add_rounded,
                          height: 30,
                          onTap: () => _addTeam(r)),
                      onTap: () => _addTeam(r),
                    ),
                  if (_isMulti) ...[
                    const SizedBox(height: 12),
                    Divider(height: 1, color: p.surface2),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(context.l10n.manage_maxTeams,
                                  style: TextStyle(
                                      color: p.ink,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700)),
                              Text(
                                  _organiserOnly
                                      ? context.l10n.manage_youCanInviteUpTo(_maxTeams)
                                      : context.l10n.manage_includingYoursInviteUpTo(_maxTeams - 1),
                                  style: TextStyle(
                                      color: p.muted, fontSize: 11.5)),
                            ]),
                      ),
                      _Stepper(
                        value: _maxTeams,
                        onChanged: (v) =>
                            setState(() => _maxTeams = v.clamp(2, 32)),
                      ),
                    ]),
                  ],
                ]),
          ),

          // ── Who can enter ─────────────────────────────────────────────
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Eyebrow(context.l10n.manage_whoCanEnter),
                  const SizedBox(height: 10),
                  _FieldLabel(context.l10n.manage_openTo),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final g in [
                      ('any', context.l10n.manage_anyTeam),
                      ('adults', context.l10n.manage_adults),
                      ('kids', context.l10n.manage_kids),
                    ])
                      _Chip(
                          label: g.$2,
                          selected: _grade == g.$1,
                          onTap: () => setState(() => _grade = g.$1)),
                  ]),
                  if (_grade == 'kids') ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final a in const [null, 12, 16, 18])
                        _Chip(
                            label: a == null ? context.l10n.manage_anyAge : context.l10n.manage_u(a),
                            selected: _maxAge == a,
                            onTap: () => setState(() => _maxAge = a)),
                    ]),
                  ],
                  const SizedBox(height: 4),
                  Text(
                      _grade == 'any'
                          ? context.l10n.manage_adultsAndKidsTeamsCan
                          : _grade == 'adults'
                              ? context.l10n.manage_kidsTeamsCantEnterOr
                              : context.l10n.manage_onlyKidsTeamsCanEnter((_maxAge != null ? ' up to under-$_maxAge' : '')),
                      style: TextStyle(color: p.muted, fontSize: 11.5)),
                  if (_mode == 'multi_team') ...[
                    const SizedBox(height: 12),
                    _FieldLabel(context.l10n.manage_howDoTeamsGetIn),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(
                        child: _ChoiceCard(
                          title: context.l10n.manage_teamsIInvite,
                          sub: context.l10n.manage_onlyTeamsYouAddTake,
                          selected: !_openReg,
                          onTap: () => setState(() => _openReg = false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ChoiceCard(
                          title: context.l10n.manage_openRegistration,
                          sub: context.l10n.manage_shareALinkAnyTeam,
                          selected: _openReg,
                          onTap: () => setState(() => _openReg = true),
                        ),
                      ),
                    ]),
                    if (_openReg) ...[
                      const SizedBox(height: 6),
                      Text(
                          context.l10n.manage_youGetARegistrationLink,
                          style: TextStyle(color: p.muted, fontSize: 11.5)),
                      const SizedBox(height: 12),
                      DocumentPicker(
                          categoryId: _categoryId,
                          value: _docIds,
                          onChanged: (v) => setState(() => _docIds = v)),
                      if (_docIds.isNotEmpty) const SizedBox(height: 12),
                      _FieldLabel(context.l10n.manage_approval),
                      const SizedBox(height: 6),
                      if (_docIds.isNotEmpty)
                        Text(context.l10n.manage_requiredDocumentsMeanYouReview,
                            style: TextStyle(color: p.muted, fontSize: 11.5))
                      else
                        Row(children: [
                          Expanded(
                            child: _ChoiceCard(
                              title: context.l10n.manage_automatic,
                              sub: context.l10n.manage_aTeamIsInAs,
                              selected: _approval == 'auto',
                              onTap: () => setState(() => _approval = 'auto'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ChoiceCard(
                              title: context.l10n.manage_iApproveEachTeam,
                              sub: context.l10n.manage_turningAPaidTeamDown,
                              selected: _approval == 'manual',
                              onTap: () => setState(() => _approval = 'manual'),
                            ),
                          ),
                        ]),
                      const SizedBox(height: 12),
                      _FieldLabel(context.l10n.manage_rulesWhatTeamsShouldKnow),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _rules,
                        maxLines: 4,
                        minLines: 2,
                        maxLength: 2000,
                        decoration: InputDecoration(
                          hintText: context.l10n.manage_formatSquadSizeKitKick,
                          counterText: '',
                        ),
                      ),
                    ],
                  ],
                ]),
          ),

          // ── Entry fee ─────────────────────────────────────────────────
          if (wallet != null && wallet.active) ...[
            const SizedBox(height: 14),
            GlassCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow(context.l10n.manage_entryFee),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _fee,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        prefixText: '${wallet.currency ?? ''} ',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                        _openReg
                            ? context.l10n.manage_optionalEachTeamPaysThis
                            : _pickMany
                                ? context.l10n.manage_optionalEachInvitedTeamPays
                                : context.l10n.manage_optionalTheInvitedTeamPays,
                        style: TextStyle(color: p.muted, fontSize: 11.5)),
                  ]),
            ),
          ],
        ],
      ),
      footer: Container(
        decoration: BoxDecoration(
          color: p.bg,
          border: Border(top: BorderSide(color: p.line)),
        ),
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, 12 + MediaQuery.paddingOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_error != null) ...[
            Row(children: [
              Icon(Icons.error_outline_rounded, size: 16, color: p.danger),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_error!,
                    style: TextStyle(color: p.danger, fontSize: 12.5)),
              ),
            ]),
            const SizedBox(height: 10),
          ],
          SpButton(
            label: _busy
                ? context.l10n.manage_creating
                : _openReg && _mode == 'multi_team'
                    ? context.l10n.manage_createGetLink
                    : _pickMany
                        ? context.l10n.manage_createInviteTeams(_guests.length)
                        : context.l10n.manage_createInvite,
            icon: Icons.arrow_forward_rounded,
            expand: true,
            tone: SpButtonTone.brand,
            onTap: _busy ? null : _submit,
          ),
        ]),
      ),
    );
  }
}

/// A bold 12-px label above a field (web `<Label>`).
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                color: context.palette.ink,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      );
}

/// Selectable pill (sport, your team).
class _Chip extends StatelessWidget {
  const _Chip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? p.ink : p.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? p.ink : p.line),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? p.bg : p.ink,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// A field-shaped row that opens a picker (date).
class _TapRow extends StatelessWidget {
  const _TapRow({
    required this.icon,
    required this.text,
    required this.onTap,
    this.placeholder = false,
  });
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final bool placeholder;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.line),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: p.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: placeholder ? p.muted : p.ink,
                    fontSize: 14.5,
                    fontWeight:
                        placeholder ? FontWeight.w400 : FontWeight.w500)),
          ),
          Icon(Icons.chevron_right_rounded, color: p.muted),
        ]),
      ),
    );
  }
}

/// Crest · name · @handle, with a trailing control.
class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.team, required this.trailing, this.onTap});
  final TeamSummary team;
  final Widget trailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Crest(
              logoUrl: team.logoUrl,
              kitPrimary: team.kitPrimary,
              kitSecondary: team.kitSecondary,
              label: team.name,
              size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(team.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  if (team.username != null)
                    Text('@${team.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 11.5)),
                ]),
          ),
          const SizedBox(width: 8),
          trailing,
        ]),
      ),
    );
  }
}

/// − n + for the team cap.
class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget b(IconData i, VoidCallback f) => GestureDetector(
          onTap: f,
          child: Container(
            width: 34,
            height: 34,
            decoration:
                BoxDecoration(color: p.surface2, shape: BoxShape.circle),
            child: Icon(i, size: 18, color: p.ink),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      b(Icons.remove_rounded, () => onChanged(value - 1)),
      SizedBox(
        width: 40,
        child: Text('$value',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
      ),
      b(Icons.add_rounded, () => onChanged(value + 1)),
    ]);
  }
}

/// Selectable card with a title and a line under it (format, who's
/// playing).
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.title,
    required this.sub,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  final String title;
  final String sub;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? p.accentTint : p.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: selected ? p.accent : p.line, width: selected ? 2 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[
            SpIconTile(icon!,
                bg: selected ? p.surface : p.surface2,
                fg: selected ? p.greenText : p.ink,
                size: 34,
                iconSize: 17),
            const SizedBox(height: 8),
          ],
          Text(title,
              style: TextStyle(
                  color: p.ink, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(color: p.muted, fontSize: 11.5)),
        ]),
      ),
    );
  }
}
