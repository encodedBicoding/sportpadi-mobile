import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/manage/manage_models.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/data/teams/team_models.dart';
import 'package:sportpadi_mobile/data/teams/teams_repository.dart';
import 'package:sportpadi_mobile/features/manage/eligible_subtitle.dart';
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// "Add player" (group admins) — the web team page's Add player dialog as one
/// sheet: pick a group member, then their positions (at least one when the
/// sport has positions, up to 3) and jersey number (required when the sport
/// uses a formation), then Add. The server's rules, checked here first so
/// nothing fails half-way. A ward isn't added directly: their guardians get
/// an invitation. The roster is one pool — starters are picked per
/// tournament on the squad, so there's no Starter switch.
///
/// Used by the team page (header + Players tab) and the roster manager.
Future<void> addTeamPlayer(BuildContext context, WidgetRef ref,
    TeamDetail team, {VoidCallback? onChanged}) async {
  // Captured up front: the page under the sheet may be gone when it closes.
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final message = await showSpSheet<String>(
    context,
    builder: (_) => _AddPlayerSheet(team: team),
  );
  if (message == null) return;
  container.invalidate(teamDetailProvider(team.id));
  container.invalidate(eligibleMembersProvider(team.id));
  container.invalidate(teamWardInvitesProvider(team.id));
  if (context.mounted) onChanged?.call();
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

class _AddPlayerSheet extends ConsumerStatefulWidget {
  const _AddPlayerSheet({required this.team});
  final TeamDetail team;

  @override
  ConsumerState<_AddPlayerSheet> createState() => _AddPlayerSheetState();
}

class _AddPlayerSheetState extends ConsumerState<_AddPlayerSheet> {
  final _search = TextEditingController();
  final _jersey = TextEditingController();
  SimpleUser? _picked;
  final Set<String> _positions = {};
  bool _busy = false;
  String? _error;

  TeamDetail get team => widget.team;
  List<String> get _options => team.positionOptions;
  bool get _needsJersey => team.formation.needsFormation;

  @override
  void dispose() {
    _search.dispose();
    _jersey.dispose();
    super.dispose();
  }

  void _pick(SimpleUser? u) => setState(() {
        _picked = u;
        _positions.clear();
        _jersey.clear();
        _error = null;
      });

  void _togglePosition(String pos) => setState(() {
        _error = null;
        if (!_positions.remove(pos) && _positions.length < 3) {
          _positions.add(pos);
        }
      });

  Future<void> _submit() async {
    final u = _picked;
    if (u == null || _busy) return;
    // Same checks as the server, so the admin hears about them here.
    if (_options.isNotEmpty && _positions.isEmpty) {
      setState(() => _error = 'Pick at least one position (up to 3).');
      return;
    }
    final jerseyText = _jersey.text.trim();
    final jersey = jerseyText.isEmpty ? null : int.tryParse(jerseyText);
    if (jerseyText.isNotEmpty && (jersey == null || jersey < 0 || jersey > 999)) {
      setState(() => _error = 'Jersey numbers go from 0 to 999.');
      return;
    }
    if (_needsJersey && jersey == null) {
      setState(() => _error = 'Give this player a jersey number.');
      return;
    }
    if (jersey != null && team.members.any((m) => m.jerseyNumber == jersey)) {
      setState(() => _error = 'Jersey #$jersey is taken.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref.read(manageRepositoryProvider).addMember(
            team.id,
            playerId: u.userId,
            positions: _positions.isEmpty
                ? null
                : [for (final o in _options) if (_positions.contains(o)) o],
            jerseyNumber: jersey,
          );
      if (!mounted) return;
      Navigator.of(context).pop(r.wardMessage ?? '${u.displayName} added');
    } catch (e) {
      // e.g. "Jersey #10 is taken." — stay open so it can be fixed.
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is ApiException ? e.message : '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _picked;
    // Keep the member list alive across steps, so "Change" is instant.
    ref.watch(eligibleMembersProvider(team.id));
    // No closing mid-request: the add would land with no confirmation.
    return PopScope(
      canPop: !_busy,
      child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSheetHeader(
          icon: Icons.person_add_alt_1_outlined,
          title: 'Add player',
          subtitle: u == null
              ? 'Pick a member of the group.'
              : _options.isNotEmpty || _needsJersey
                  ? 'Set their ${[
                      if (_options.isNotEmpty) 'positions',
                      if (_needsJersey) 'jersey number',
                    ].join(' and ')}.'
                  : 'Add them to ${team.name}.',
        ),
        if (u == null) _memberList(context) else ..._details(context, u),
      ],
      ),
    );
  }

  // Step 1 — the group's members who aren't on the team yet.
  Widget _memberList(BuildContext context) {
    final p = context.palette;
    final eligible = ref.watch(eligibleMembersProvider(team.id));
    return AsyncView<List<SimpleUser>>(
      value: eligible,
      onRetry: () => ref.invalidate(eligibleMembersProvider(team.id)),
      data: (all) {
        if (all.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('Every group member is already on this team.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 13.5)),
          );
        }
        final q = _search.text.trim().toLowerCase();
        final list = q.isEmpty
            ? all
            : [
                for (final m in all)
                  if (m.displayName.toLowerCase().contains(q) ||
                      (m.username ?? '').toLowerCase().contains(q))
                    m,
              ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (all.length > 6) ...[
              SpSearchCard(
                controller: _search,
                hint: 'Search members',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
            ],
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text('No members match “${_search.text.trim()}”.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.muted, fontSize: 13)),
              )
            else
              SpListCard(children: [
                for (final m in list) _memberRow(context, m),
              ]),
          ],
        );
      },
    );
  }

  Widget _memberRow(BuildContext context, SimpleUser m) {
    final p = context.palette;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: m.invitePending ? null : () => _pick(m),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Row(children: [
            Opacity(
              opacity: m.invitePending ? 0.5 : 1,
              child: PersonAvatar(url: m.avatarUrl, name: m.displayName, size: 40),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(m.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: m.invitePending ? p.muted : p.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ),
                      if (m.isWard) ...[
                        const SizedBox(width: 6),
                        const WardBadge(),
                      ],
                    ]),
                    if (eligibleSubtitle(p, m, team.ageLimit, showHandle: true)
                        case final sub?)
                      sub,
                  ]),
            ),
            const SizedBox(width: 8),
            if (m.invitePending)
              const SpBadge('Invited', icon: Icons.hourglass_top_rounded)
            else
              Icon(Icons.chevron_right_rounded, size: 20, color: p.muted),
          ]),
        ),
      ),
    );
  }

  // Step 2 — the picked member: positions, jersey, and Add.
  List<Widget> _details(BuildContext context, SimpleUser u) {
    final p = context.palette;
    final over = u.overAgeLimit && team.ageLimit != null;
    return [
      GlassCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Row(children: [
          PersonAvatar(url: u.avatarUrl, name: u.displayName, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(u.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700)),
                ),
                if (u.isWard) ...[
                  const SizedBox(width: 6),
                  const WardBadge(),
                ],
              ]),
              if (eligibleSubtitle(p, u, team.ageLimit,
                      showHandle: true, showWardNote: false)
                  case final sub?)
                sub,
            ]),
          ),
          TextButton(
            onPressed: _busy ? null : () => _pick(null),
            child: const Text('Change'),
          ),
        ]),
      ),
      if (over) ...[
        const SizedBox(height: 10),
        _note(p,
            '${u.displayName} is ${u.age != null ? '${u.age} — ' : ''}older than this Under ${team.ageLimit} team. You can still add them.',
            bg: p.orangeTint,
            fg: p.orangeInk),
      ],
      if (u.isWard) ...[
        const SizedBox(height: 10),
        _note(p,
            "Wards join through a guardian: we'll send their guardians an invitation, and they're on the team once one accepts.",
            bg: p.accentTint,
            fg: p.ink),
      ],
      if (_options.isNotEmpty) ...[
        const SizedBox(height: 16),
        Row(children: [
          Text('Positions',
              style: TextStyle(
                  color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Text('pick up to 3',
              style: TextStyle(color: p.muted, fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in _options)
            FilterChip(
              label: Text(o),
              selected: _positions.contains(o),
              // Three picked: the rest wait until one is cleared.
              onSelected: _busy ||
                      (_positions.length >= 3 && !_positions.contains(o))
                  ? null
                  : (_) => _togglePosition(o),
              showCheckmark: false,
              selectedColor: p.accentTint,
              labelStyle: TextStyle(
                  color: _positions.contains(o) ? p.greenText : p.ink,
                  fontWeight: FontWeight.w600),
              shape: StadiumBorder(
                  side: BorderSide(
                      color: _positions.contains(o) ? p.accent : p.line)),
            ),
        ]),
      ],
      const SizedBox(height: 16),
      TextField(
        controller: _jersey,
        enabled: !_busy,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(3),
        ],
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          labelText:
              _needsJersey ? 'Jersey number' : 'Jersey number (optional)',
          hintText: 'e.g. 10',
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 10),
        Text(_error!, style: TextStyle(color: p.danger, fontSize: 13)),
      ],
      const SizedBox(height: 18),
      SpButton(
        label: _busy
            ? (u.isWard ? 'Inviting…' : 'Adding…')
            : (u.isWard ? 'Invite guardians' : 'Add player'),
        icon: u.isWard ? Icons.mail_outline_rounded : Icons.person_add_alt_1_rounded,
        expand: true,
        tone: SpButtonTone.brand,
        onTap: _busy ? null : _submit,
      ),
    ];
  }

  Widget _note(AppPalette p, String text, {required Color bg, required Color fg}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 12.5, height: 1.4)),
      );
}
