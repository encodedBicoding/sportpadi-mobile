import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/leagues/leagues_repository.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/features/documents/team_documents.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// Organiser's view of who can enter a multi-team tournament (web twin:
/// components/tournaments/RegistrationPanel.tsx): the registration link
/// (copy it, or copy the ready-made "call for teams" post), its settings,
/// and the teams that came in through it and still need a decision.
class RegistrationCard extends ConsumerStatefulWidget {
  const RegistrationCard({
    super.key,
    required this.eventId,
    required this.reg,
    required this.rows,
    required this.maxTeams,
    required this.ended,
    this.isLeague = false,
    this.categoryId,
  });

  /// The tournament's event id — or, with [isLeague], the league id.
  final String eventId;
  final bool isLeague;

  /// The sport, for the document catalogue.
  final String? categoryId;

  /// `registration` from GET /api/mobile/tournaments/:id.
  final Map<String, dynamic> reg;

  /// Every `teams` row (with `source`).
  final List<Map<String, dynamic>> rows;
  final int maxTeams;
  final bool ended;

  @override
  ConsumerState<RegistrationCard> createState() => _RegistrationCardState();
}

class _RegistrationCardState extends ConsumerState<RegistrationCard> {
  bool _busy = false;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _refresh() {
    if (widget.isLeague) {
      ref.invalidate(leagueManageProvider(widget.eventId));
    } else {
      ref.invalidate(tournamentDetailProvider(widget.eventId));
    }
  }

  Future<void> _set(Map<String, dynamic> patch, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await setRegistration(ref, isLeague: widget.isLeague, id: widget.eventId, patch: patch);
      if (done != null) _snack(done);
      _refresh();
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(Map<String, dynamic> row) async {
    final decided = await _ReviewSheet.show(context,
        row: row,
        required: [
          for (final x in (widget.reg['documents'] as List? ?? const []))
            if (x is Map) Map<String, dynamic>.from(x),
        ],
        decide: (approve, note) => respondRegistration(ref,
            isLeague: widget.isLeague, id: widget.eventId, entryId: row['id'] as String, approve: approve, note: note));
    if (decided != null) {
      _snack(decided);
      _refresh();
    }
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    _snack(context.l10n.tournament_copied(what));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final reg = widget.reg;
    final mode = parseStr(reg['mode']) ?? 'invite_only';
    final open = mode == 'open';
    final state = parseStr(reg['state']) ?? 'invite_only';
    final link = parseStr(reg['link']);
    final shareText = parseStr(reg['shareText']);
    final seated = (reg['seated'] as num?)?.toInt() ?? 0;
    final pending = widget.rows.where((r) => r['source'] == 'registration' && r['status'] == 'pending').toList();
    final viaLink = widget.rows.where((r) => r['source'] == 'registration' && r['status'] != 'rejected').length;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text(context.l10n.tournament_registration, style: TextStyle(color: p.ink, fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        SpBadge(
          open ? (state == 'open' ? context.l10n.tournament_open : parseStr(reg['stateCopy']) ?? context.l10n.tournament_closed) : (mode == 'closed' ? context.l10n.tournament_closed : context.l10n.tournament_inviteOnly),
          tone: state == 'open' ? p.accent : null,
        ),
        const Spacer(),
        if (!widget.ended)
          TextButton.icon(
            onPressed: () => _RegistrationSettingsSheet.show(context,
                eventId: widget.eventId, reg: reg, isLeague: widget.isLeague, categoryId: widget.categoryId),
            icon: const Icon(Icons.tune_rounded, size: 16),
            label: Text(context.l10n.tournament_settings),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: p.greenText),
          ),
      ]),
      const SizedBox(height: 10),
      GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!open) ...[
            Text(
                mode == 'closed'
                    ? context.l10n.tournament_theRegistrationLinkIsClosed
                    : context.l10n.tournament_onlyTeamsYouInviteCan2,
                style: TextStyle(color: p.muted, fontSize: 13, height: 1.35)),
            if (!widget.ended) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _busy ? null : () => _set({'registration': 'open'}, done: context.l10n.tournament_registrationIsOpenShare),
                icon: const Icon(Icons.link_rounded, size: 18),
                label: Text(mode == 'closed' ? context.l10n.tournament_reopenRegistration : context.l10n.tournament_openRegistration),
              ),
            ],
          ] else ...[
            Wrap(spacing: 6, runSpacing: 6, children: [
              SpBadge(parseStr(reg['gradeLabel']) ?? context.l10n.tournament_anyTeam, icon: Icons.groups_rounded),
              SpBadge(reg['approval'] == 'manual' ? context.l10n.tournament_youApproveEachTeam : context.l10n.tournament_inOnceRegisteredPaid),
              if ((reg['documents'] as List? ?? const []).isNotEmpty)
                SpBadge(context.l10n.tournament_documentsRequired((reg['documents'] as List).length),
                    icon: Icons.description_outlined),
              SpBadge('$seated/${widget.maxTeams} places · $viaLink via link'),
            ]),
            if (link != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Icon(Icons.link_rounded, size: 16, color: p.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(link.replaceFirst(RegExp(r'^https?://'), ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    onPressed: () => _copy(link, context.l10n.tournament_link),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    visualDensity: VisualDensity.compact,
                    tooltip: context.l10n.tournament_copyLink,
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: shareText == null ? null : () => _copy(shareText, context.l10n.tournament_callForTeamsPost),
                  icon: const Icon(Icons.campaign_rounded, size: 18),
                  label: Text(context.l10n.tournament_copyCallForTeams),
                ),
              ),
              if (!widget.ended) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _busy ? null : () => _set({'registration': 'closed'}, done: context.l10n.tournament_registrationClosed),
                  child: Text(context.l10n.tournament_close),
                ),
              ],
            ]),
            const SizedBox(height: 6),
            Text(
                context.l10n.tournament_thePostIncludesTheDate,
                style: TextStyle(color: p.muted, fontSize: 11.5, height: 1.35)),
          ],
        ]),
      ),
      if (pending.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(context.l10n.tournament_waitingOnYou2(pending.length),
            style: TextStyle(color: p.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
        const SizedBox(height: 6),
        SpListCard(children: [for (final r in pending) _pendingRow(context, r)]),
      ],
    ]);
  }

  Widget _pendingRow(BuildContext context, Map<String, dynamic> r) {
    final p = context.palette;
    final team = r['team'] is Map ? Map<String, dynamic>.from(r['team'] as Map) : null;
    final feeMinor = (r['feeMinor'] as num?)?.toInt() ?? 0;
    final fee = feeMinor > 0 && r['feeCurrency'] is String
        ? formatMoney(feeMinor, r['feeCurrency'] as String, (r['feeCurrencyExponent'] as num?)?.toInt() ?? 2)
        : null;
    final unpaid = fee != null && r['feeStatus'] != 'paid';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(children: [
        Crest(
          logoUrl: team != null ? parseStr(team['logoUrl']) : null,
          kitPrimary: team != null ? parseStr(team['kitPrimary']) : null,
          kitSecondary: team != null ? parseStr(team['kitSecondary']) : null,
          label: team != null ? parseStr(team['name']) : context.l10n.tournament_team,
          size: 40,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(team != null ? parseStr(team['name']) ?? context.l10n.tournament_team : context.l10n.tournament_team,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
            Text(
                '${team != null ? parseStr(team['groupName']) ?? '' : ''} · '
                '${unpaid ? "hasn't paid $fee yet" : fee != null ? 'paid $fee' : 'free entry'}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 11.5)),
          ]),
        ),
        if (unpaid)
          Text(context.l10n.tournament_awaitingPayment, style: TextStyle(color: p.muted, fontSize: 11, fontWeight: FontWeight.w600))
        else
          FilledButton.icon(
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            onPressed: _busy ? null : () => _review(r),
            icon: Icon((r['documents'] as List? ?? const []).isNotEmpty ? Icons.description_outlined : Icons.check_rounded, size: 16),
            label: Text(context.l10n.tournament_review),
          ),
      ]),
    );
  }
}

/// Who can enter: approval, grade rule, deadline, rules — and a fresh link.
class _RegistrationSettingsSheet extends ConsumerStatefulWidget {
  const _RegistrationSettingsSheet({required this.eventId, required this.reg, required this.isLeague, this.categoryId});
  final String eventId;
  final Map<String, dynamic> reg;
  final bool isLeague;
  final String? categoryId;

  static Future<void> show(BuildContext context,
          {required String eventId, required Map<String, dynamic> reg, bool isLeague = false, String? categoryId}) =>
      showSpSheet<void>(context,
          builder: (_) => _RegistrationSettingsSheet(eventId: eventId, reg: reg, isLeague: isLeague, categoryId: categoryId));

  @override
  ConsumerState<_RegistrationSettingsSheet> createState() => _RegistrationSettingsSheetState();
}

class _RegistrationSettingsSheetState extends ConsumerState<_RegistrationSettingsSheet> {
  late String _approval = parseStr(widget.reg['approval']) ?? 'auto';
  late String _grade = parseStr(widget.reg['grade']) ?? 'any';
  late int? _maxAge = (widget.reg['maxAge'] as num?)?.toInt();
  late DateTime? _closes = parseDate(widget.reg['closesAt'])?.toLocal();
  late final _rules = TextEditingController(text: parseStr(widget.reg['rules']) ?? '');
  late List<String> _docIds = [
    for (final x in (widget.reg['documents'] as List? ?? const []))
      if (x is Map && x['id'] is String) x['id'] as String,
  ];
  bool _busy = false;

  @override
  void dispose() {
    _rules.dispose();
    super.dispose();
  }

  Future<void> _pickCloses() async {
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context, initialDate: _closes ?? now, firstDate: now.subtract(const Duration(days: 1)), lastDate: now.add(const Duration(days: 730)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_closes ?? now));
    if (!mounted) return;
    setState(() => _closes = DateTime(d.year, d.month, d.day, t?.hour ?? 23, t?.minute ?? 59));
  }

  Future<void> _save({bool rotate = false}) async {
    setState(() => _busy = true);
    try {
      await setRegistration(ref, isLeague: widget.isLeague, id: widget.eventId, patch: {
        if (rotate) 'rotateLink': true,
        if (!rotate) ...{
          'approval': _docIds.isNotEmpty ? 'manual' : _approval,
          'grade': _grade,
          'maxAge': _grade == 'kids' ? _maxAge : null,
          'registrationClosesAt': _closes?.toUtc().toIso8601String(),
          'rules': _rules.text.trim().isEmpty ? null : _rules.text.trim(),
          'documentTypeIds': _docIds,
        },
      });
      if (widget.isLeague) {
        ref.invalidate(leagueManageProvider(widget.eventId));
      } else {
        ref.invalidate(tournamentDetailProvider(widget.eventId));
      }
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final label = TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w700);
    Widget chip(String text, bool on, VoidCallback onTap) => ChoiceChip(label: Text(text), selected: on, onSelected: (_) => onTap());
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      SpSheetHeader(title: context.l10n.tournament_whoCanEnter, icon: Icons.how_to_reg_rounded),
      const SizedBox(height: 12),
      Text(context.l10n.tournament_openTo, style: label),
      const SizedBox(height: 6),
      Wrap(spacing: 8, children: [
        chip(context.l10n.tournament_anyTeam, _grade == 'any', () => setState(() => _grade = 'any')),
        chip(context.l10n.tournament_adults, _grade == 'adults', () => setState(() => _grade = 'adults')),
        chip(context.l10n.tournament_kids, _grade == 'kids', () => setState(() => _grade = 'kids')),
      ]),
      if (_grade == 'kids') ...[
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final a in const [null, 12, 16, 18]) chip(a == null ? context.l10n.tournament_anyAge : 'U$a', _maxAge == a, () => setState(() => _maxAge = a)),
        ]),
      ],
      const SizedBox(height: 4),
      Text(context.l10n.tournament_tighteningThisDoesntRemoveTeams, style: TextStyle(color: p.muted, fontSize: 11.5)),
      const SizedBox(height: 14),
      DocumentPicker(categoryId: widget.categoryId, value: _docIds, onChanged: (v) => setState(() => _docIds = v)),
      if (_docIds.isNotEmpty) const SizedBox(height: 14),
      Text(context.l10n.tournament_approval, style: label),
      const SizedBox(height: 6),
      if (_docIds.isNotEmpty)
        Text(context.l10n.tournament_requiredDocumentsMeanYouReview, style: TextStyle(color: p.muted, fontSize: 11.5))
      else ...[
        Wrap(spacing: 8, children: [
          chip(context.l10n.tournament_automatic, _approval == 'auto', () => setState(() => _approval = 'auto')),
          chip(context.l10n.tournament_iApproveEachTeam, _approval == 'manual', () => setState(() => _approval = 'manual')),
        ]),
        const SizedBox(height: 4),
        Text(
            _approval == 'auto'
                ? context.l10n.tournament_aTeamIsInAs
                : context.l10n.tournament_registrationsWaitForYouTurning,
            style: TextStyle(color: p.muted, fontSize: 11.5)),
      ],
      const SizedBox(height: 14),
      Text(context.l10n.tournament_registrationClosesOptional, style: label),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _pickCloses,
            icon: const Icon(Icons.schedule_rounded, size: 16),
            label: Text(_closes == null ? context.l10n.tournament_noDeadline : _closes.toString().substring(0, 16)),
          ),
        ),
        if (_closes != null)
          IconButton(onPressed: () => setState(() => _closes = null), icon: const Icon(Icons.close_rounded, size: 18)),
      ]),
      const SizedBox(height: 14),
      Text(context.l10n.tournament_rulesWhatTeamsShouldKnow2, style: label),
      const SizedBox(height: 6),
      TextField(
        controller: _rules,
        minLines: 3,
        maxLines: 6,
        maxLength: 2000,
        decoration: InputDecoration(hintText: context.l10n.tournament_formatSquadSizeKitKick, counterText: ''),
      ),
      if (widget.reg['mode'] == 'open') ...[
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  final sure = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(l10n.tournament_makeANewLink),
                      content: Text(l10n.tournament_theOldLinkWillStop),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.tournament_cancel)),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tournament_replace)),
                      ],
                    ),
                  );
                  if (sure == true) await _save(rotate: true);
                },
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: Text(context.l10n.tournament_replaceTheLink),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: p.muted),
        ),
      ],
      const SizedBox(height: 12),
      SpButton(label: _busy ? context.l10n.tournament_saving : context.l10n.tournament_save, expand: true, tone: SpButtonTone.brand, onTap: _busy ? null : () => _save()),
    ]);
  }
}


/* ── Shared plumbing: the two routers behind one card ── */

Future<void> setRegistration(WidgetRef ref,
    {required bool isLeague, required String id, required Map<String, dynamic> patch}) async {
  if (isLeague) {
    await ref.read(leaguesRepositoryProvider).mutate('setRegistration', {'leagueId': id, ...patch});
  } else {
    await ref.read(tournamentsRepositoryProvider).setRegistration(id, patch);
  }
}

/// Returns the snack text for the decision.
Future<String> respondRegistration(WidgetRef ref,
    {required bool isLeague, required String id, required String entryId, required bool approve, String? note}) async {
  Map<String, dynamic> r;
  if (isLeague) {
    final v = await ref.read(leaguesRepositoryProvider).mutate('respondRegistration', {
      'entryId': entryId,
      'action': approve ? 'approve' : 'reject',
      'note': note,
    });
    r = v is Map ? Map<String, dynamic>.from(v) : const {};
  } else {
    r = await ref.read(tournamentsRepositoryProvider).act(id, {
      'action': 'respondRegistration',
      'tournamentTeamId': entryId,
      'decision': approve ? 'approve' : 'reject',
      'note': note,
    });
  }
  return approve
      ? l10n.tournament_teamApproved
      : r['refunded'] == true
          ? l10n.tournament_turnedDownEntryFeeRefunded
          : l10n.tournament_turnedDown;
}

/// The organiser's decision on one registration: the team, what it paid,
/// the documents it had on file when it registered (a snapshot — open each
/// and judge it yourself) and a note the team will see.
class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.row, required this.required, required this.decide});
  final Map<String, dynamic> row;
  final List<Map<String, dynamic>> required;
  final Future<String> Function(bool approve, String? note) decide;

  static Future<String?> show(BuildContext context,
          {required Map<String, dynamic> row,
          required List<Map<String, dynamic>> required,
          required Future<String> Function(bool approve, String? note) decide}) =>
      showSpSheet<String>(context, builder: (_) => _ReviewSheet(row: row, required: required, decide: decide));

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late final _note = TextEditingController(
      text: widget.row['review'] is Map ? (widget.row['review']['note'] as String? ?? '') : '');
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _go(bool approve) async {
    final team = widget.row['team'] is Map ? Map<String, dynamic>.from(widget.row['team'] as Map) : null;
    final name = team != null ? parseStr(team['name']) ?? 'this team' : 'this team';
    if (!approve) {
      final paid = widget.row['feeStatus'] == 'paid';
      final sure = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.tournament_turnDown2(name)),
          content: Text(l10n.tournament_theyCanFixThingsAnd((paid ? l10n.tournament_theirEntryFeeWillBe2 : ''))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.tournament_keep)),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tournament_turnDown)),
          ],
        ),
      );
      if (sure != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final msg = await widget.decide(approve, _note.text.trim().isEmpty ? null : _note.text.trim());
      if (mounted) Navigator.of(context).pop(msg);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final row = widget.row;
    final team = row['team'] is Map ? Map<String, dynamic>.from(row['team'] as Map) : null;
    final docs = [
      for (final x in (row['documents'] as List? ?? const []))
        if (x is Map) Map<String, dynamic>.from(x),
    ];
    final feeMinor = (row['feeMinor'] as num?)?.toInt() ?? 0;
    final fee = feeMinor > 0 && row['feeCurrency'] is String
        ? formatMoney(feeMinor, row['feeCurrency'] as String, (row['feeCurrencyExponent'] as num?)?.toInt() ?? 2)
        : null;
    final missing = widget.required.where((r) => !docs.any((d) => d['documentTypeId'] == r['id'] || d['name'] == r['name'])).toList();
    final label = TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w700);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      SpSheetHeader(title: context.l10n.tournament_reviewRegistration, icon: Icons.fact_check_outlined),
      const SizedBox(height: 12),
      Row(children: [
        Crest(
            logoUrl: team != null ? parseStr(team['logoUrl']) : null,
            kitPrimary: team != null ? parseStr(team['kitPrimary']) : null,
            kitSecondary: team != null ? parseStr(team['kitSecondary']) : null,
            label: team != null ? parseStr(team['name']) : context.l10n.tournament_team,
            size: 44),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(team != null ? parseStr(team['name']) ?? context.l10n.tournament_team : context.l10n.tournament_team, style: TextStyle(color: p.ink, fontSize: 15, fontWeight: FontWeight.w800)),
            Text(
                '${team != null ? parseStr(team['groupName']) ?? '' : ''}'
                '${fee != null ? ' · ${row['feeStatus'] == 'paid' ? 'paid' : 'unpaid'} $fee' : ' · free entry'}',
                style: TextStyle(color: p.muted, fontSize: 12)),
          ]),
        ),
      ]),
      if (widget.required.isNotEmpty || docs.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(context.l10n.tournament_documentsOnFileWhenThey, style: label),
        const SizedBox(height: 6),
        if (docs.isEmpty) Text(context.l10n.tournament_noneAttached, style: TextStyle(color: p.muted, fontSize: 12.5)),
        for (final d in docs)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d['name'] as String? ?? context.l10n.tournament_document2, style: TextStyle(color: p.ink, fontSize: 13, fontWeight: FontWeight.w700)),
              if (d['fileUrl'] is String)
                GestureDetector(
                  onTap: () => launchUrl(Uri.parse(d['fileUrl'] as String), mode: LaunchMode.inAppBrowserView),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.open_in_new_rounded, size: 12, color: p.greenText),
                    const SizedBox(width: 4),
                    Flexible(child: Text(d['fileName'] as String? ?? context.l10n.tournament_openFile, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.greenText, fontSize: 12.5, fontWeight: FontWeight.w600))),
                  ]),
                ),
              if (d['textValue'] is String) Text(d['textValue'] as String, style: TextStyle(color: p.ink, fontSize: 12.5)),
              if (d['note'] is String) Text(context.l10n.tournament_teamsNote2(d['note']), style: TextStyle(color: p.muted, fontSize: 11.5)),
            ]),
          ),
        if (missing.isNotEmpty)
          Text(context.l10n.tournament_notOnFile2(missing.map((m) => m['name']).join(', ')), style: TextStyle(color: p.orangeInk, fontSize: 12)),
        Text(context.l10n.tournament_checkDatesAndValidityYourself, style: TextStyle(color: p.muted, fontSize: 11)),
      ],
      const SizedBox(height: 14),
      Text(context.l10n.tournament_noteToTheTeamOptional, style: label),
      const SizedBox(height: 6),
      TextField(
        controller: _note,
        minLines: 2,
        maxLines: 5,
        maxLength: 1000,
        decoration: InputDecoration(
          hintText: context.l10n.tournament_eGInsuranceCertificateHas,
          counterText: '',
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _go(false),
          icon: const Icon(Icons.close_rounded, size: 16),
          label: Text(context.l10n.tournament_turnDown),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: _busy ? null : () => _go(true),
            icon: _busy
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(context.l10n.tournament_approve),
          ),
        ),
      ]),
    ]);
  }
}
