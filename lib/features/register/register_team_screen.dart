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
        _snack("You're in! 🎉");
      } else {
        _snack('Registered — the organiser will confirm your place.');
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
      _snack('Thanks — confirming your payment…');
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
        title: const Text('Withdraw registration?'),
        content: Text(paid
            ? 'Your entry fee will be refunded in full.'
            : 'Your team will be taken out of the registration.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Withdraw')),
        ],
      ),
    );
    if (sure != true) return;
    try {
      final refunded = await ref
          .read(tournamentsRepositoryProvider)
          .withdrawRegistration(widget.token, tournamentTeamId);
      _snack(refunded ? 'Withdrawn — your entry fee is being refunded in full.' : 'Registration withdrawn.');
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
      appBar: AppBar(leading: const SpLeading(), title: const Text('Register your team')),
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
            Text('CALL FOR TEAMS',
                style: TextStyle(color: p.heroMuted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            const SizedBox(height: 4),
            Text(event['title'] as String? ?? 'Tournament',
                style: TextStyle(color: p.onHero, fontSize: 22, fontWeight: FontWeight.w800, height: 1.15)),
            const SizedBox(height: 4),
            Text(
                '${cat?['emoji'] ?? ''} ${cat?['name'] ?? ''} · $maxTeams-team ${isLeague ? 'league' : 'tournament'}'
                '${group != null ? ' by ${group['name']}' : ''}',
                style: TextStyle(color: p.heroMuted, fontSize: 13)),
            if (isLeague && league?['format'] is String)
              Text(league!['format'] as String, style: TextStyle(color: p.heroMuted, fontSize: 12)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              SpBadge(open ? '$spotsLeft of $maxTeams places left' : (d['stateCopy'] as String? ?? 'Closed'),
                  tone: open ? p.accent : p.heroMuted),
              SpBadge(d['gradeLabel'] as String? ?? 'Any team', icon: Icons.groups_rounded, tone: p.heroMuted),
              SpBadge(fee != null ? '$fee per team' : 'Free entry', icon: Icons.confirmation_num_outlined, tone: p.heroMuted),
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
                        ? 'Season starts ${league!['seasonStartsOn']}'
                        : 'Season ${league?['season'] ?? ''}')
                    : when.line),
            if ((event['locationName'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              InfoRow(Icons.place_outlined, event['locationName'] as String),
            ],
            if (d['closesAt'] != null) ...[
              const SizedBox(height: 8),
              InfoRow(Icons.schedule_rounded, 'Registration closes ${formatEventTime(eventDate: parseDate(d['closesAt']), startTime: parseDate(d['closesAt'])).line}'),
            ],
            if (manual) ...[
              const SizedBox(height: 8),
              InfoRow(Icons.verified_user_outlined, 'The organiser confirms each team'
                      "${fee != null ? " — a team that isn't taken is refunded in full" : ''}."),
            ],
            if (requiredDocs.isNotEmpty) ...[
              const SizedBox(height: 8),
              InfoRow(Icons.description_outlined,
                  'Teams must have on file: ${requiredDocs.map((x) => x['name']).join(', ')}. The organiser reviews them before confirming.'),
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
              const Eyebrow('Rules'),
              const SizedBox(height: 6),
              Text(d['rules'] as String, style: TextStyle(color: p.ink, fontSize: 13.5, height: 1.4)),
            ]),
          ),
        ],

        // ── Register ──
        const SizedBox(height: 12),
        GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Eyebrow('Register your team'),
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
                        Text(t['name'] as String? ?? 'Team', style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
                        Text("The organiser didn't take this registration", style: TextStyle(color: p.muted, fontSize: 11.5)),
                      ]),
                    ),
                  ]),
                  if (t['registration']['reviewNote'] is String) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
                      child: Text("Organiser's note: ${t['registration']['reviewNote']}", style: TextStyle(color: p.ink, fontSize: 12.5)),
                    ),
                  ],
                  if (open) ...[
                    const SizedBox(height: 4),
                    Text('Fix what was asked${requiredDocs.isNotEmpty ? ' (update the documents below)' : ''} and apply again.',
                        style: TextStyle(color: p.muted, fontSize: 11.5)),
                  ],
                ]),
              ),
            ],
            const SizedBox(height: 10),
            if (!signedIn) ...[
              SpButton(
                label: 'Log in or sign up to register',
                icon: Icons.arrow_forward_rounded,
                expand: true,
                tone: SpButtonTone.brand,
                onTap: () => context.push('/sign-in?redirect=${Uri.encodeComponent('/register/${widget.token}')}'),
              ),
              const SizedBox(height: 6),
              Text("You'll come right back here. New to SportPadi? Signing up is free, and you can build your team in a minute.",
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
                Text('Which team?', style: TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                for (final t in eligible)
                  _PickRow(
                    team: t,
                    selected: _teamId == t['id'],
                    onTap: () => setState(() => _teamId = t['id'] as String?),
                  ),
                if (pickedTeam != null && checklist.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Documents (${checklist.where((c) => c.ok).length}/${checklist.length} on file)',
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
                      ? 'Registering…'
                      : missingCount > 0
                          ? 'Add $missingCount document${missingCount == 1 ? '' : 's'} to register'
                          : pickedTeam?['registration'] != null
                              ? (fee != null ? 'Apply again & pay $fee' : 'Apply again')
                              : (fee != null ? 'Register & pay $fee' : 'Register team'),
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
                      child: Text("${t['name']} can't enter: ${t['problem']}",
                          style: TextStyle(color: p.muted, fontSize: 12)),
                    ),
                  ]),
                ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: () => setState(() => _building = true),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(eligible.isNotEmpty ? 'Register a new team instead' : 'Build your team and register'),
              ),
              if (fee != null) ...[
                const SizedBox(height: 6),
                Text(
                    'The entry fee is paid by card at checkout and goes to the organiser.'
                    "${manual ? " If the organiser doesn't take your team, you're refunded in full." : ''}",
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
              Eyebrow('Teams in (${d['seated'] ?? teamsIn.length}/$maxTeams)'),
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
                        Text(t['name'] as String? ?? 'Team',
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
        Text('Live scores, match stats, ratings and awards for every team — on SportPadi.',
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
              Text(team['name'] as String? ?? 'Team',
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
              Text(team['name'] as String? ?? 'Team',
                  style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
              Text(
                  approved
                      ? "You're in"
                      : unpaid
                          ? 'Entry fee not paid yet'
                          : 'Paid · waiting for the organiser to confirm',
                  style: TextStyle(color: p.muted, fontSize: 11.5)),
            ]),
          ),
          if (approved)
            Icon(Icons.check_circle_rounded, color: p.greenText, size: 22)
          else if (unpaid)
            FilledButton(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              onPressed: () => onPay(id),
              child: Text('Pay ${feeLabel ?? ''}'),
            )
          else
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.muted)),
        ]),
        if (approved)
          TextButton(
            onPressed: () => context.push(isLeague ? '/groups/${team['groupId']}/tournaments/mode/league' : '/tournaments/teams/${team['id']}'),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
            child: Text(isLeague ? 'Register your roster →' : 'Register your squad →'),
          )
        else
          TextButton(
            onPressed: () => onWithdraw(id, paid),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact, foregroundColor: p.muted),
            child: const Text('Withdraw registration'),
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
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Name your team');
    if (newGroup && _groupName.text.trim().isEmpty) return setState(() => _error = 'Name your club or group');
    if (!newGroup && _groupId == null) return setState(() => _error = 'Pick a group');
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
        setState(() => _error = 'Could not build the team.');
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not build the team.');
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
        Text('Club / group', style: label),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _groupId,
          items: [
            for (final g in adminGroups) DropdownMenuItem(value: g.id, child: Text(g.name)),
            const DropdownMenuItem(value: '__new', child: Text('+ New club / group')),
          ],
          onChanged: (v) => setState(() => _groupId = v),
          decoration: const InputDecoration(hintText: 'Which group owns this team?'),
        ),
        const SizedBox(height: 10),
      ],
      if (newGroup) ...[
        Text('Your club or group', style: label),
        const SizedBox(height: 6),
        TextField(controller: _groupName, decoration: const InputDecoration(hintText: 'e.g. Riverside FC')),
        const SizedBox(height: 4),
        Text('Teams live in a group on SportPadi — yours is created for free alongside the team.',
            style: TextStyle(color: p.muted, fontSize: 11.5)),
        const SizedBox(height: 10),
      ],
      Text('Team name', style: label),
      const SizedBox(height: 6),
      TextField(controller: _name, decoration: InputDecoration(hintText: 'e.g. Riverside ${widget.sportName} XI')),
      if (widget.grade == 'any') ...[
        const SizedBox(height: 10),
        Text('Level', style: label),
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
        Text('Age group', style: label),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final a in const [12, 16, 18])
            if (widget.maxAge == null || a <= widget.maxAge!)
              ChoiceChip(
                  label: Text('Under $a'),
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
        OutlinedButton(onPressed: _working ? null : widget.onCancel, child: const Text('Back')),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: _working ? null : () => _submit(adminGroups),
            icon: _working
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add_rounded, size: 18),
            label: const Text('Build team & register'),
          ),
        ),
      ]),
    ]);
  }
}
