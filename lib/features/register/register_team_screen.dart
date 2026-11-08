import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/documents/documents_repository.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart';
import 'package:sportpadi_mobile/features/documents/team_documents.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/features/payments/checkout_flow.dart';
import 'package:sportpadi_mobile/shared/format/event_time.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// /register/<token> — a tournament's "call for teams" landing page (web
/// twin: app/register/[token]/page.tsx).
///
/// Anyone can read it. Signed in, you pick one of the teams you run (group
/// admin or coach) that fits the sport and grade — or build one on the spot —
/// and you're in: straight away when it's free and open, after paying when
/// there's an entry fee, or once the organiser approves when they vet teams.
class RegisterTeamScreen extends ConsumerStatefulWidget {
  const RegisterTeamScreen({super.key, required this.token});
  final String token;

  @override
  ConsumerState<RegisterTeamScreen> createState() => _RegisterTeamScreenState();
}

class _RegisterTeamScreenState extends ConsumerState<RegisterTeamScreen> {
  String? _teamId;
  bool _busy = false;
  bool _building = false;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _refresh() => ref.invalidate(registrationPageProvider(widget.token));

  Future<void> _register(String teamId) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(tournamentsRepositoryProvider);
      final r = await repo.register(widget.token, teamId);
      final status = r['status'];
      final ttId = r['tournamentTeamId'];
      if (status == 'payment_required' && ttId is String) {
        await _pay(ttId);
      } else if (status == 'approved') {
        _snack(l10n.tournament_youreIn);
      } else {
        _snack(l10n.tournament_registeredTheOrganiserWillConfirm);
      }
      _refresh();
      ref.invalidate(myTeamCardsProvider);
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay(String tournamentTeamId) async {
    final repo = ref.read(tournamentsRepositoryProvider);
    final url = await repo.payRegistration(widget.token, tournamentTeamId);
    if (!mounted) return;
    final paid = await runHostedCheckout(context, url);
    if (paid) {
      _snack(l10n.tournament_thanksConfirmingYourPayment);
      // The webhook settles the row a moment after; refetch a few times.
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        _refresh();
      }
    }
  }

  Future<void> _withdraw(String tournamentTeamId, bool paid) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tournament_withdrawRegistration2),
        content: Text(paid
            ? l10n.tournament_yourEntryFeeWillBe
            : l10n.tournament_yourTeamWillBeTaken),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.tournament_keep)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tournament_withdraw)),
        ],
      ),
    );
    if (sure != true) return;
    try {
      final refunded = await ref
          .read(tournamentsRepositoryProvider)
          .withdrawRegistration(widget.token, tournamentTeamId);
      _snack(refunded ? l10n.tournament_withdrawnYourEntryFeeIs : l10n.tournament_registrationWithdrawn);
      _refresh();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final page = ref.watch(registrationPageProvider(widget.token));
    final signedIn = ref.watch(authControllerProvider).value?.isAuthenticated ?? false;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(leading: const SpLeading(), title: Text(context.l10n.tournament_registerYourTeam)),
      body: AsyncView(
        value: page,
        onRetry: _refresh,
        data: (d) => _body(context, d, signedIn),
      ),
    );
  }

  Widget _body(BuildContext context, Map<String, dynamic> d, bool signedIn) {
    final p = context.palette;
    final event = Map<String, dynamic>.from(d['event'] as Map? ?? const {});
    final cat = event['category'] is Map ? Map<String, dynamic>.from(event['category'] as Map) : null;
    final group = d['group'] is Map ? Map<String, dynamic>.from(d['group'] as Map) : null;
    final state = d['state'] as String? ?? 'closed';
    final open = state == 'open';
    final maxTeams = (d['maxTeams'] as num?)?.toInt() ?? 0;
    final spotsLeft = (d['spotsLeft'] as num?)?.toInt() ?? 0;
    final feeMinor = (d['feeMinor'] as num?)?.toInt();
    final fee = feeMinor != null && feeMinor > 0 && d['feeCurrency'] is String
        ? formatMoney(feeMinor, d['feeCurrency'] as String, (d['feeCurrencyExponent'] as num?)?.toInt() ?? 2)
        : null;
    final manual = d['approval'] == 'manual';
    final when = formatEventTime(
      eventDate: parseDate(event['eventDate']),
      startTime: parseDate(event['startTime']),
      endTime: parseDate(event['endTime']),
      timezone: event['timezone'] as String?,
    );
    final myTeams = [
      for (final t in (d['myTeams'] as List? ?? const []))
        if (t is Map) Map<String, dynamic>.from(t),
    ];
    final isLeague = d['kind'] == 'league';
    final league = d['league'] is Map ? Map<String, dynamic>.from(d['league'] as Map) : null;
    final requiredDocs = [
      for (final x in (d['documents'] as List? ?? const []))
        if (x is Map) Map<String, dynamic>.from(x),
    ];
    // Eligible: fits, and either never registered or turned down (can apply again).
    final eligible = myTeams
        .where((t) => t['problem'] == null && (t['registration'] == null || t['registration']['status'] == 'rejected'))
        .toList();
    final blocked = myTeams.where((t) => t['problem'] != null).toList();
    final entered = myTeams.where((t) => t['registration'] is Map && t['registration']['status'] != 'rejected').toList();
    final rejected = myTeams.where((t) => t['registration'] is Map && t['registration']['status'] == 'rejected' && t['problem'] == null).toList();
    final pickedTeam = myTeams.where((t) => t['id'] == _teamId).firstOrNull;
    final checklist = [
      for (final c in (pickedTeam?['checklist'] as List? ?? const []))
        if (c is Map) DocumentItem.fromJson(Map<String, dynamic>.from(c)),
    ];
    final missingCount = checklist.where((c) => !c.ok).length;
    final teamsIn = [
      for (final t in (d['teams'] as List? ?? const []))
        if (t is Map) Map<String, dynamic>.from(t),
    ];
    if (_teamId == null && eligible.length == 1) _teamId = eligible.first['id'] as String?;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
      children: [
        // ── The tournament ──
        Container(
          decoration: BoxDecoration(color: p.hero, borderRadius: BorderRadius.circular(22)),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.l10n.tournament_callForTeams2,
                style: TextStyle(color: p.heroMuted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            const SizedBox(height: 4),
            Text(event['title'] as String? ?? context.l10n.tournament_tournament2,
                style: TextStyle(color: p.onHero, fontSize: 22, fontWeight: FontWeight.w800, height: 1.15)),
            const SizedBox(height: 4),
            Text(
                context.l10n.tournament_team4(cat?['emoji'] ?? '', cat?['name'] ?? '', maxTeams, (isLeague ? context.l10n.tournament_league2 : context.l10n.tournament_tournament), (group != null ? ' by ${group['name']}' : '')),
                style: TextStyle(color: p.heroMuted, fontSize: 13)),
            if (isLeague && league?['format'] is String)
              Text(league!['format'] as String, style: TextStyle(color: p.heroMuted, fontSize: 12)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              SpBadge(open ? context.l10n.tournament_ofPlacesLeft(spotsLeft, maxTeams) : (d['stateCopy'] as String? ?? context.l10n.tournament_closed),
                  tone: open ? p.accent : p.heroMuted),
              SpBadge(d['gradeLabel'] as String? ?? context.l10n.tournament_anyTeam, icon: Icons.groups_rounded, tone: p.heroMuted),
              SpBadge(fee != null ? context.l10n.tournament_perTeam(fee) : context.l10n.tournament_freeEntry, icon: Icons.confirmation_num_outlined, tone: p.heroMuted),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InfoRow(
                Icons.calendar_today_rounded,
                isLeague
                    ? (league?['seasonStartsOn'] is String
                        ? context.l10n.tournament_seasonStarts(league!['seasonStartsOn'])
                        : context.l10n.tournament_season(league?['season'] ?? ''))
                    : when.line),
            if ((event['locationName'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              InfoRow(Icons.place_outlined, event['locationName'] as String),
            ],
            if (d['closesAt'] != null) ...[
              const SizedBox(height: 8),
              InfoRow(Icons.schedule_rounded, context.l10n.tournament_registrationCloses2(formatEventTime(eventDate: parseDate(d['closesAt']), startTime: parseDate(d['closesAt'])).line)),
            ],
            if (manual) ...[
              const SizedBox(height: 8),
              InfoRow(Icons.verified_user_outlined, context.l10n.tournament_theOrganiserConfirmsEachTeam2((fee != null ? context.l10n.tournament_aTeamThatIsntTaken2 : ''))),
            ],
            if (requiredDocs.isNotEmpty) ...[
              const SizedBox(height: 8),
              InfoRow(Icons.description_outlined,
                  context.l10n.tournament_teamsMustHaveOnFile2(requiredDocs.map((x) => x['name']).join(', '))),
            ],
            if ((event['description'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(event['description'] as String, style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.4)),
            ],
          ]),
        ),
        if ((d['rules'] as String?)?.isNotEmpty == true) ...[
          const SizedBox(height: 12),
          GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Eyebrow(context.l10n.tournament_rules),
              const SizedBox(height: 6),
              Text(d['rules'] as String, style: TextStyle(color: p.ink, fontSize: 13.5, height: 1.4)),
            ]),
          ),
        ],

        // ── Register ──
        const SizedBox(height: 12),
        GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Eyebrow(context.l10n.tournament_registerYourTeam),
            for (final t in entered) ...[
              const SizedBox(height: 10),
              _EnteredRow(
                team: t,
                isLeague: isLeague,
                onPay: (id) async {
                  try {
                    await _pay(id);
                  } on ApiException catch (e) {
                    _snack(e.message);
                  }
                },
                onWithdraw: _withdraw,
              ),
            ],
            for (final t in rejected) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(16)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Crest(logoUrl: t['logoUrl'] as String?, kitPrimary: t['kitPrimary'] as String?, kitSecondary: t['kitSecondary'] as String?, label: t['name'] as String?, size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t['name'] as String? ?? context.l10n.tournament_team, style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
                        Text(context.l10n.tournament_theOrganiserDidntTakeThis, style: TextStyle(color: p.muted, fontSize: 11.5)),
                      ]),
                    ),
                  ]),
                  if (t['registration']['reviewNote'] is String) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
                      child: Text(context.l10n.tournament_organisersNote2(t['registration']['reviewNote']), style: TextStyle(color: p.ink, fontSize: 12.5)),
                    ),
                  ],
                  if (open) ...[
                    const SizedBox(height: 4),
                    Text(context.l10n.tournament_fixWhatWasAskedAnd(requiredDocs.isNotEmpty ? context.l10n.tournament_updateTheDocumentsBelow2 : ''),
                        style: TextStyle(color: p.muted, fontSize: 11.5)),
                  ],
                ]),
              ),
            ],
            const SizedBox(height: 10),
            if (!signedIn) ...[
              SpButton(
                label: context.l10n.tournament_logInOrSignUp,
                icon: Icons.arrow_forward_rounded,
                expand: true,
                tone: SpButtonTone.brand,
                onTap: () => context.push('/sign-in?redirect=${Uri.encodeComponent('/register/${widget.token}')}'),
              ),
              const SizedBox(height: 6),
              Text(context.l10n.tournament_youllComeRightBackHere,
                  style: TextStyle(color: p.muted, fontSize: 11.5)),
            ] else if (!open) ...[
              if (entered.isEmpty)
                Text('${d['stateCopy'] ?? 'Registration is closed'}.', style: TextStyle(color: p.muted, fontSize: 13.5)),
            ] else if (_building) ...[
              _BuildTeam(
                categoryId: cat?['id'] as String? ?? '',
                sportName: cat?['name'] as String? ?? 'team',
                grade: d['grade'] as String? ?? 'any',
                maxAge: (d['maxAge'] as num?)?.toInt(),
                onCancel: () => setState(() => _building = false),
                onBuilt: (id) {
                  setState(() {
                    _building = false;
                    _teamId = id;
                  });
                  _register(id);
                },
              ),
            ] else ...[
              if (eligible.isNotEmpty) ...[
                Text(context.l10n.tournament_whichTeam, style: TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                for (final t in eligible)
                  _PickRow(
                    team: t,
                    selected: _teamId == t['id'],
                    onTap: () => setState(() => _teamId = t['id'] as String?),
                  ),
                if (pickedTeam != null && checklist.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(context.l10n.tournament_documentsOnFile(checklist.where((c) => c.ok).length, checklist.length),
                      style: TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  for (final c in checklist)
                    TeamDocumentRow(
                      teamId: pickedTeam['id'] as String,
                      item: c,
                      required: true,
                      onChanged: _refresh,
                    ),
                ],
                const SizedBox(height: 10),
                SpButton(
                  label: _busy
                      ? context.l10n.tournament_registering
                      : missingCount > 0
                          ? context.l10n.tournament_addDocumentsToRegister(missingCount)
                          : pickedTeam?['registration'] != null
                              ? (fee != null ? context.l10n.tournament_applyAgainPay(fee) : context.l10n.tournament_applyAgain)
                              : (fee != null ? context.l10n.tournament_registerPay(fee) : context.l10n.tournament_registerTeam),
                  icon: Icons.emoji_events_outlined,
                  expand: true,
                  tone: SpButtonTone.brand,
                  onTap: _busy || _teamId == null || missingCount > 0 ? null : () => _register(_teamId!),
                ),
                const SizedBox(height: 8),
              ],
              for (final t in blocked)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.info_outline_rounded, size: 14, color: p.muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(context.l10n.tournament_cantEnter2(t['name'], t['problem']),
                          style: TextStyle(color: p.muted, fontSize: 12)),
                    ),
                  ]),
                ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: () => setState(() => _building = true),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(eligible.isNotEmpty ? context.l10n.tournament_registerANewTeamInstead : context.l10n.tournament_buildYourTeamAndRegister),
              ),
              if (fee != null) ...[
                const SizedBox(height: 6),
                Text(
                    context.l10n.tournament_theEntryFeeIsPaid2((manual ? context.l10n.tournament_ifTheOrganiserDoesntTake2 : '')),
                    style: TextStyle(color: p.muted, fontSize: 11.5)),
              ],
            ],
          ]),
        ),

        // ── Who's in ──
        if (teamsIn.isNotEmpty) ...[
          const SizedBox(height: 12),
          GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Eyebrow(context.l10n.tournament_teamsIn2(d['seated'] ?? teamsIn.length, maxTeams)),
              const SizedBox(height: 8),
              for (final t in teamsIn)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Crest(
                        logoUrl: t['logoUrl'] as String?,
                        kitPrimary: t['kitPrimary'] as String?,
                        kitSecondary: t['kitSecondary'] as String?,
                        label: t['name'] as String?,
                        size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t['name'] as String? ?? context.l10n.tournament_team,
                            style: TextStyle(color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w700)),
                        Text(t['groupName'] as String? ?? '', style: TextStyle(color: p.muted, fontSize: 11.5)),
                      ]),
                    ),
                  ]),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        Text(context.l10n.tournament_liveScoresMatchStatsRatings,
            textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 11.5)),
      ],
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({required this.team, required this.selected, required this.onTap});
  final Map<String, dynamic> team;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? p.accentTint : p.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? p.accent : Colors.transparent, width: 2),
        ),
        child: Row(children: [
          Crest(
              logoUrl: team['logoUrl'] as String?,
              kitPrimary: team['kitPrimary'] as String?,
              kitSecondary: team['kitSecondary'] as String?,
              label: team['name'] as String?,
              size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(team['name'] as String? ?? context.l10n.tournament_team,
                  style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
              Text('@${team['username']} · ${team['via'] == 'coach' ? 'you coach' : 'your group'}',
                  style: TextStyle(color: p.muted, fontSize: 11.5)),
            ]),
          ),
          if (selected) Icon(Icons.check_circle_rounded, color: p.greenText, size: 20),
        ]),
      ),
    );
  }
}

class _EnteredRow extends StatelessWidget {
  const _EnteredRow({required this.team, required this.isLeague, required this.onPay, required this.onWithdraw});
  final Map<String, dynamic> team;
  final bool isLeague;
  final Future<void> Function(String tournamentTeamId) onPay;
  final Future<void> Function(String tournamentTeamId, bool paid) onWithdraw;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = Map<String, dynamic>.from(team['registration'] as Map);
    final id = r['id'] as String;
    final approved = r['status'] == 'approved';
    final feeMinor = (r['feeMinor'] as num?)?.toInt() ?? 0;
    final paid = r['feeStatus'] == 'paid';
    final unpaid = feeMinor > 0 && !paid;
    final feeLabel = feeMinor > 0 && r['feeCurrency'] is String
        ? formatMoney(feeMinor, r['feeCurrency'] as String, (r['feeCurrencyExponent'] as num?)?.toInt() ?? 2)
        : null;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Crest(
              logoUrl: team['logoUrl'] as String?,
              kitPrimary: team['kitPrimary'] as String?,
              kitSecondary: team['kitSecondary'] as String?,
              label: team['name'] as String?,
              size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(team['name'] as String? ?? context.l10n.tournament_team,
                  style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
              Text(
                  approved
                      ? context.l10n.tournament_youreIn2
                      : unpaid
                          ? context.l10n.tournament_entryFeeNotPaidYet
                          : context.l10n.tournament_paidWaitingForTheOrganiser,
                  style: TextStyle(color: p.muted, fontSize: 11.5)),
            ]),
          ),
          if (approved)
            Icon(Icons.check_circle_rounded, color: p.greenText, size: 22)
          else if (unpaid)
            FilledButton(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              onPressed: () => onPay(id),
              child: Text(context.l10n.tournament_pay(feeLabel ?? '')),
            )
          else
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.muted)),
        ]),
        if (approved)
          TextButton(
            onPressed: () => context.push(isLeague ? '/groups/${team['groupId']}/tournaments/mode/league' : '/tournaments/teams/${team['id']}'),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
            child: Text(isLeague ? context.l10n.tournament_registerYourRoster2 : context.l10n.tournament_registerYourSquad2),
          )
        else
          TextButton(
            onPressed: () => onWithdraw(id, paid),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact, foregroundColor: p.muted),
            child: Text(context.l10n.tournament_withdrawRegistration),
          ),
      ]),
    );
  }
}

/// Build a team to register with. Someone who already runs a group picks
/// which; someone brand new names a group (their club) and it is created on
/// the way — the free plan includes one team per sport, so nothing is gated.
class _BuildTeam extends ConsumerStatefulWidget {
  const _BuildTeam({
    required this.categoryId,
    required this.sportName,
    required this.grade,
    required this.maxAge,
    required this.onCancel,
    required this.onBuilt,
  });
  final String categoryId;
  final String sportName;
  final String grade; // any | adults | kids
  final int? maxAge;
  final VoidCallback onCancel;
  final void Function(String teamId) onBuilt;

  @override
  ConsumerState<_BuildTeam> createState() => _BuildTeamState();
}

class _BuildTeamState extends ConsumerState<_BuildTeam> {
  final _name = TextEditingController();
  final _groupName = TextEditingController();
  String? _groupId; // '__new' = create one
  late String _teamGrade = widget.grade == 'kids' ? 'kids' : 'adults';
  late int _ageLimit = (widget.maxAge == 12 || widget.maxAge == 16 || widget.maxAge == 18) ? widget.maxAge! : 16;
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _groupName.dispose();
    super.dispose();
  }

  Future<void> _submit(List<dynamic> adminGroups) async {
    final newGroup = adminGroups.isEmpty || _groupId == '__new';
    if (_name.text.trim().isEmpty) return setState(() => _error = l10n.tournament_nameYourTeam);
    if (newGroup && _groupName.text.trim().isEmpty) return setState(() => _error = l10n.tournament_nameYourClubOrGroup);
    if (!newGroup && _groupId == null) return setState(() => _error = l10n.tournament_pickAGroup);
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      var gid = _groupId;
      if (newGroup) {
        gid = await ref.read(groupsRepositoryProvider).createGroup(_groupName.text.trim(), null);
        ref.invalidate(myGroupsProvider);
      }
      final team = await ref.read(manageRepositoryProvider).createTeam(gid!, {
        'categoryId': widget.categoryId,
        'name': _name.text.trim(),
        'grade': _teamGrade,
        'ageLimit': _teamGrade == 'kids' ? _ageLimit : null,
      });
      final id = team['id'];
      if (id is String && id.isNotEmpty) {
        widget.onBuilt(id);
      } else {
        setState(() => _error = l10n.tournament_couldNotBuildTheTeam2);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = l10n.tournament_couldNotBuildTheTeam2);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final groups = ref.watch(myGroupsProvider).valueOrNull ?? const [];
    final adminGroups = groups.where((g) => g.role == 'admin').toList();
    if (_groupId == null && adminGroups.length == 1) _groupId = adminGroups.first.id;
    final newGroup = adminGroups.isEmpty || _groupId == '__new';
    final label = TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w700);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (adminGroups.isNotEmpty) ...[
        Text(context.l10n.tournament_clubGroup, style: label),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _groupId,
          items: [
            for (final g in adminGroups) DropdownMenuItem(value: g.id, child: Text(g.name)),
            DropdownMenuItem(value: '__new', child: Text(context.l10n.tournament_newClubGroup)),
          ],
          onChanged: (v) => setState(() => _groupId = v),
          decoration: InputDecoration(hintText: context.l10n.tournament_whichGroupOwnsThisTeam),
        ),
        const SizedBox(height: 10),
      ],
      if (newGroup) ...[
        Text(context.l10n.tournament_yourClubOrGroup, style: label),
        const SizedBox(height: 6),
        TextField(controller: _groupName, decoration: InputDecoration(hintText: context.l10n.tournament_eGRiversideFc)),
        const SizedBox(height: 4),
        Text(context.l10n.tournament_teamsLiveInAGroup,
            style: TextStyle(color: p.muted, fontSize: 11.5)),
        const SizedBox(height: 10),
      ],
      Text(context.l10n.tournament_teamName, style: label),
      const SizedBox(height: 6),
      TextField(controller: _name, decoration: InputDecoration(hintText: context.l10n.tournament_eGRiversideXi(widget.sportName))),
      if (widget.grade == 'any') ...[
        const SizedBox(height: 10),
        Text(context.l10n.tournament_level, style: label),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final g in const ['adults', 'kids'])
            ChoiceChip(
                label: Text(g[0].toUpperCase() + g.substring(1)),
                selected: _teamGrade == g,
                onSelected: (_) => setState(() => _teamGrade = g)),
        ]),
      ],
      if (_teamGrade == 'kids') ...[
        const SizedBox(height: 10),
        Text(context.l10n.tournament_ageGroup, style: label),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final a in const [12, 16, 18])
            if (widget.maxAge == null || a <= widget.maxAge!)
              ChoiceChip(
                  label: Text(context.l10n.tournament_under(a)),
                  selected: _ageLimit == a,
                  onSelected: (_) => setState(() => _ageLimit = a)),
        ]),
      ],
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: TextStyle(color: p.danger, fontSize: 12.5)),
      ],
      const SizedBox(height: 12),
      Row(children: [
        OutlinedButton(onPressed: _working ? null : widget.onCancel, child: Text(context.l10n.tournament_back)),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: _working ? null : () => _submit(adminGroups),
            icon: _working
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add_rounded, size: 18),
            label: Text(context.l10n.tournament_buildTeamRegister),
          ),
        ),
      ]),
    ]);
  }
}
