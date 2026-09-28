import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/data/games/game_models.dart';
import 'package:sportpadi_mobile/data/games/games_repository.dart';
import 'package:sportpadi_mobile/data/games/live_game_controller.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Officiant jobs. Missing = both.
const kOfficiantRoles = <String, ({String label, String icon, String blurb})>{
  'timekeeper': (
    label: 'Timekeeper',
    icon: '⏱️',
    blurb: 'Runs the clock in officiant mode — kick-off, pauses, stoppage, full time.',
  ),
  'scorer': (
    label: 'Scorer',
    icon: '📋',
    blurb: 'Records what happens — the stats this sport tracks.',
  ),
  'both': (
    label: 'Clock + stats',
    icon: '🫡',
    blurb: 'Does both. Fine for small games with one officiant.',
  ),
};

/// Officiants on a game — flexible, any time (web: OfficiantsPanel).
///
/// Group admins and current officiants can CALL SOMEONE IN (a group member
/// for local games; anyone on SportPadi for a tournament, who accepts first)
/// and give them a job. Admins can change anyone's job or take them off;
/// officiants can change their own job or step down.
class OfficiantsCard extends ConsumerStatefulWidget {
  const OfficiantsCard({super.key, required this.gameId, required this.game});
  final String gameId;
  final GameDetail game;

  @override
  ConsumerState<OfficiantsCard> createState() => _OfficiantsCardState();
}

class _OfficiantsCardState extends ConsumerState<OfficiantsCard> {
  bool _busy = false;

  GameDetail get g => widget.game;

  Future<void> _run(Future<void> Function() op, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await op();
      await ref.read(liveGameProvider(widget.gameId).notifier).refresh();
      if (done != null) _snack(done);
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final myId = ref.watch(authControllerProvider).valueOrNull?.user?.id;
    final people = g.officiants;
    final off = g.officiating;
    if (people.isEmpty && !off.canCallIn) return const SizedBox.shrink();
    final records = g.profile.scorerRecords;

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.verified_user_outlined, size: 15, color: p.accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Officiants',
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
            if (_busy)
              const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else if (off.canCallIn)
              TextButton.icon(
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: _callIn,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                label: const Text('Call in', style: TextStyle(fontSize: 12.5)),
              ),
          ]),
          if (people.isEmpty)
            Text(
              'Group admins officiate by default. Call someone in to keep time '
              'or record stats — you can change this at any point in the game.',
              style: TextStyle(color: p.muted, fontSize: 11.5),
            )
          else
            for (final o in people) _row(o, myId),
          const SizedBox(height: 6),
          Text(
            '⏱️ Timekeepers run the clock in officiant mode · 📋 scorers record '
            '${records.isEmpty ? 'the stats' : records.take(4).join(', ').toLowerCase()}. '
            'Group admins can always do both.',
            style: TextStyle(color: p.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _row(GameOfficiant o, String? myId) {
    final p = context.palette;
    final self = o.userId == myId;
    final off = g.officiating;
    final canEdit = off.canAssign ||
        (self && off.role != null && off.role != 'admin');
    final meta = kOfficiantRoles[o.role] ?? kOfficiantRoles['both']!;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: canEdit ? () => _manage(o, self) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: p.surface2,
            backgroundImage:
                o.avatarUrl != null ? NetworkImage(o.avatarUrl!) : null,
            child: o.avatarUrl == null
                ? Text(
                    o.displayName.isNotEmpty
                        ? o.displayName[0].toUpperCase()
                        : '?',
                    style: TextStyle(color: p.ink, fontSize: 12))
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(
                      o.displayName + (self ? ' (you)' : ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (o.pending) ...[
                    const SizedBox(width: 6),
                    SpBadge('Invited', tone: p.muted),
                  ],
                ]),
                Text('${meta.icon} ${meta.label}',
                    style: TextStyle(color: p.muted, fontSize: 11.5)),
              ],
            ),
          ),
          if (canEdit) Icon(Icons.more_horiz_rounded, color: p.muted, size: 18),
        ]),
      ),
    );
  }

  Future<void> _manage(GameOfficiant o, bool self) async {
    final p = context.palette;
    final repo = ref.read(gamesRepositoryProvider);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(self ? 'Your job on this game' : '${o.displayName}\'s job',
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final e in kOfficiantRoles.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Text(e.value.icon, style: const TextStyle(fontSize: 20)),
                  title: Text(e.value.label,
                      style: TextStyle(
                          color: p.ink, fontWeight: FontWeight.w600)),
                  subtitle: Text(e.value.blurb,
                      style: TextStyle(color: p.muted, fontSize: 11.5)),
                  trailing: o.role == e.key
                      ? Icon(Icons.check_rounded, color: p.accent)
                      : null,
                  onTap: () => Navigator.pop(ctx, e.key),
                ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                    self ? Icons.logout_rounded : Icons.person_remove_outlined,
                    color: p.danger),
                title: Text(self ? 'Step down' : 'Take off officiating',
                    style: TextStyle(
                        color: p.danger, fontWeight: FontWeight.w600)),
                subtitle: Text(
                    self
                        ? 'The group admins get a heads-up to call someone else in.'
                        : 'They can be called back in any time.',
                    style: TextStyle(color: p.muted, fontSize: 11.5)),
                onTap: () => Navigator.pop(ctx, '__remove'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == '__remove') {
      await _run(() => repo.removeOfficiant(widget.gameId, o.userId),
          done: self ? 'You\'ve stepped down' : 'Officiant removed');
    } else if (choice != o.role) {
      await _run(() => repo.setOfficiantRole(widget.gameId, o.userId, choice),
          done: 'Now ${kOfficiantRoles[choice]!.label.toLowerCase()}');
    }
  }

  Future<void> _callIn() async {
    final res = await showModalBottomSheet<({List<String> ids, String role})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _CallInSheet(gameId: widget.gameId, isTournament: g.isTournament),
    );
    if (res == null || res.ids.isEmpty || !mounted) return;
    final repo = ref.read(gamesRepositoryProvider);
    ({int added, int requested})? out;
    await _run(() async {
      out = await repo.addOfficiants(widget.gameId, res.ids, res.role);
    });
    final r = out;
    if (r != null) {
      _snack(r.requested > 0
          ? 'Request sent to ${r.requested} ${r.requested == 1 ? 'person' : 'people'}'
          : '${r.added} called in');
    }
  }
}

class _CallInSheet extends ConsumerStatefulWidget {
  const _CallInSheet({required this.gameId, required this.isTournament});
  final String gameId;
  final bool isTournament;

  @override
  ConsumerState<_CallInSheet> createState() => _CallInSheetState();
}

class _CallInSheetState extends ConsumerState<_CallInSheet> {
  String _role = 'scorer';
  final _q = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  String? _error;
  List<OfficiantCandidate> _list = const [];
  final Set<String> _picked = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref
          .read(gamesRepositoryProvider)
          .officiantCandidates(widget.gameId, q: _q.text.trim());
      if (mounted) setState(() => _list = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final role = kOfficiantRoles[_role]!;
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Call someone in',
                style: TextStyle(
                    color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              widget.isTournament
                  ? 'Anyone on SportPadi can officiate a tournament match — they\'ll get a request to accept.'
                  : 'Anyone in the group can step in. They\'re added straight away and get a notification.',
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final e in kOfficiantRoles.entries)
                ChoiceChip(
                  label: Text('${e.value.icon} ${e.value.label}'),
                  selected: _role == e.key,
                  onSelected: (_) => setState(() => _role = e.key),
                ),
            ]),
            const SizedBox(height: 6),
            Text(role.blurb, style: TextStyle(color: p.muted, fontSize: 11.5)),
            const SizedBox(height: 10),
            TextField(
              controller: _q,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                hintText: widget.isTournament
                    ? 'Search anyone on SportPadi'
                    : 'Search the group',
              ),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), _load);
              },
            ),
            const SizedBox(height: 8),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(_error!,
                              style: TextStyle(color: p.danger)),
                        )
                      : _list.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                widget.isTournament &&
                                        _q.text.trim().length < 2
                                    ? 'Type a name to search the whole platform.'
                                    : 'No one matches.',
                                style: TextStyle(color: p.muted),
                              ),
                            )
                          : ListView(
                              shrinkWrap: true,
                              children: [
                                for (final c in _list) _candidate(c),
                              ],
                            ),
            ),
            const SizedBox(height: 10),
            SpButton(
              label: _picked.isEmpty
                  ? 'Pick someone'
                  : widget.isTournament
                      ? 'Send ${_picked.length} request${_picked.length == 1 ? '' : 's'}'
                      : 'Call in ${_picked.length}',
              icon: Icons.sports_rounded,
              expand: true,
              onTap: _picked.isEmpty
                  ? null
                  : () => Navigator.pop(
                      context, (ids: _picked.toList(), role: _role)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _candidate(OfficiantCandidate c) {
    final p = context.palette;
    final taken = c.status != null;
    final checked = _picked.contains(c.userId);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      enabled: !taken,
      leading: CircleAvatar(
        radius: 15,
        backgroundColor: p.surface2,
        backgroundImage:
            c.avatarUrl != null ? NetworkImage(c.avatarUrl!) : null,
        child: c.avatarUrl == null
            ? Text(c.displayName.isNotEmpty ? c.displayName[0].toUpperCase() : '?',
                style: TextStyle(color: p.ink, fontSize: 12))
            : null,
      ),
      title: Text(c.displayName,
          style: TextStyle(color: p.ink, fontWeight: FontWeight.w600)),
      subtitle: Text(
        c.status == 'officiating'
            ? 'Already officiating'
            : c.status == 'pending'
                ? 'Already invited'
                : c.groupAdmin
                    ? 'Group admin${c.username != null ? ' · @${c.username}' : ''}'
                    : (c.username != null ? '@${c.username}' : ''),
        style: TextStyle(color: p.muted, fontSize: 11.5),
      ),
      trailing: taken
          ? null
          : Icon(
              checked
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: checked ? p.accent : p.muted),
      onTap: taken
          ? null
          : () => setState(() {
                if (checked) {
                  _picked.remove(c.userId);
                } else {
                  _picked.add(c.userId);
                }
              }),
    );
  }
}
