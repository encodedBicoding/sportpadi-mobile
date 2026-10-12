import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/leagues/leagues_repository.dart';
import 'package:sportpadi_mobile/features/leagues/league_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// A team's squad for one league (web
/// `/groups/[id]/leagues/[leagueId]/roster/[teamId]`).
///
/// The coach calls team players onto the league roster — each accepts (and is
/// registered) or declines — or adds a player directly. Calls and answers
/// close at the organiser's roster cutoff; after it only the organiser can
/// change the roster. The season formation (starters / subs) is a tap away:
/// every fixture not yet kicked off lines up with it, and substitutions in a
/// match update it.
class LeagueRosterScreen extends ConsumerWidget {
  const LeagueRosterScreen({super.key, required this.leagueId, required this.teamId, this.groupId});
  final String leagueId;
  final String teamId;
  final String? groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final key = '$leagueId|$teamId';
    final q = ref.watch(leagueRosterProvider(key));
    final d = q.valueOrNull;
    final refresh = [leagueRosterProvider(key)];
    return SpSubPage(
      title: d?.o('team')?.str('name', 'Squad') ?? 'Squad',
      subtitle: d?.o('league')?.s('title'),
      body: AsyncView(
        value: q,
        onRetry: () => ref.invalidate(leagueRosterProvider(key)),
        data: (d) {
          final players = d.list('players');
          final registered = players.where((x) => x.s('status') == 'registered').toList();
          final removed = players.where((x) => x.s('status') == 'removed').toList();
          final canEdit = d.b('canEdit');
          final canCall = d.b('canCall');
          final lock = d.o('league')?.date('rosterLockAt');
          final min = d.i('min');
          final max = d.i('max');
          final calls = d.list('calls');
          final open = calls.where((c) => c.s('status') == 'called').toList();
          final answered = calls.where((c) => c.s('status') == 'declined' || c.s('status') == 'cancelled').toList();
          final available = d.list('available');
          final uncalled = available.where((a) => !a.b('called')).toList();
          final placements = d.o('formation')?.o('placements');
          final needsFormation = d.o('formation')?.o('config')?.b('needsFormation') ?? false;
          final starters = registered.where((r) => placements?.o(r.str('playerId'))?.b('isStarter') ?? false).length;
          final maxStarters = d.o('formation')?.o('config')?.i('maxStarters') ?? 0;
          final dateFmt = MaterialLocalizations.of(context);
          final lockNote = d.b('locked')
              ? (d.b('isOrganiser')
                  ? 'Rosters are locked and call-ups are closed. As the organiser you can still change it — those changes are marked as after the cutoff.'
                  : 'Rosters are locked and call-ups are closed. Ask the organiser for any change.')
              : lock != null
                  ? 'Call players until ${dateFmt.formatFullDate(lock)} — they\'re registered when they accept. After that, only the organiser can change the roster.'
                  : 'No cutoff set — call-ups stay open.';
          final full = registered.length >= max;

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(leagueRosterProvider(key)),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: d.b('locked') ? p.surface2 : p.accentTint, borderRadius: BorderRadius.circular(20)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.lock_clock_rounded, size: 20, color: d.b('locked') ? p.muted : p.greenText),
                    const SizedBox(width: 10),
                    Expanded(child: Text('$lockNote $min–$max players.', style: TextStyle(color: p.ink, fontSize: 12.5))),
                  ]),
                ),
                const SizedBox(height: 12),
                // Season formation — what the next fixture lines up with.
                if (needsFormation)
                  Material(
                    color: const Color(0xFF17873F),
                    borderRadius: BorderRadius.circular(22),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: groupId == null
                          ? null
                          : () async {
                              await context.push('/groups/$groupId/leagues/$leagueId/roster/$teamId/formation');
                              ref.invalidate(leagueRosterProvider(key));
                            },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                        child: Row(children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(color: Colors.white.withAlpha(36), borderRadius: BorderRadius.circular(14)),
                            child: const Icon(Icons.grid_view_rounded, color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('SEASON FORMATION',
                                  style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                              Text(d.o('formation')?.str('name', 'Not set') ?? 'Not set',
                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                              Text(
                                  registered.isEmpty
                                      ? 'Built from registered players — call players first'
                                      : '$starters of $maxStarters starting · subs update it',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12)),
                            ]),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: Colors.white),
                        ]),
                      ),
                    ),
                  ),
                if (needsFormation) const SizedBox(height: 12),
                if (canCall)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: p.orangeTint, borderRadius: BorderRadius.circular(22)),
                    child: Row(children: [
                      SpIconTile(Icons.campaign_rounded, bg: p.surface, fg: p.orangeInk, size: 40, iconSize: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Call players', style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
                          Text(
                              uncalled.isNotEmpty
                                  ? '${uncalled.length} team player${uncalled.length == 1 ? '' : 's'} not called yet.'
                                  : 'Everyone on the team has been called or is registered.',
                              style: TextStyle(color: p.muted, fontSize: 12)),
                        ]),
                      ),
                      SpPill(
                        label: 'Call',
                        icon: Icons.campaign_rounded,
                        height: 34,
                        onTap: uncalled.isEmpty
                            ? null
                            : () => showSpSheet<void>(context,
                                builder: (_) => _CallSheet(leagueId: leagueId, teamId: teamId, lock: lock, candidates: uncalled, answered: answered)),
                      ),
                    ]),
                  ),
                const SizedBox(height: 14),
                SpSectionTitle('Registered',
                    count: registered.length,
                    trailing: registered.length < min ? SpBadge('${min - registered.length} more needed', tone: p.orangeInk) : null),
                const SizedBox(height: 8),
                if (registered.isEmpty)
                  SpEmpty(icon: Icons.people_alt_rounded, text: canCall ? 'Nobody registered yet — call your players.' : 'Nobody registered yet.')
                else
                  SpListCard(children: [
                    for (final pl in registered)
                      ListTile(
                        leading: PersonAvatar(url: pl.s('avatarUrl'), name: pl.str('displayName', '?'), size: 38),
                        title: Text(pl.str('displayName', 'Player'), style: TextStyle(color: p.ink, fontWeight: FontWeight.w600)),
                        subtitle: Text([
                          if (pl.iOrNull('shirtNumber') != null) '#${pl.i('shirtNumber')}',
                          pl.s('position'),
                          if (needsFormation) (placements?.o(pl.str('playerId'))?.b('isStarter') ?? false) ? 'starter' : 'bench',
                          if (pl.b('afterLock')) 'added after cutoff',
                        ].whereType<String>().join(' · ')),
                        trailing: canEdit
                            ? PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'number') {
                                    final n = await _askNumber(context, pl.iOrNull('shirtNumber'));
                                    if (n == null || !context.mounted) return;
                                    await leagueAction(context, ref, 'updatePlayer', {
                                      'entryId': pl.str('id'),
                                      'leagueId': leagueId,
                                      'shirtNumber': n < 0 ? null : n,
                                      'position': pl.s('position'),
                                    }, refresh: refresh);
                                  } else if (v == 'remove') {
                                    await leagueAction(context, ref, 'removePlayer', {'entryId': pl.str('id'), 'leagueId': leagueId},
                                        success: 'Removed from the league roster', refresh: refresh);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'number', child: Text('Shirt number')),
                                  PopupMenuItem(value: 'remove', child: Text('Remove')),
                                ],
                              )
                            : null,
                      ),
                  ]),
                if (open.isNotEmpty || answered.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SpSectionTitle('Call-ups', count: open.length),
                  const SizedBox(height: 8),
                  SpListCard(children: [
                    for (final c in [...open, ...answered])
                      ListTile(
                        leading: PersonAvatar(url: c.s('avatarUrl'), name: c.str('name', '?'), size: 38),
                        title: Text(c.str('name', 'Player'), style: TextStyle(color: p.ink, fontWeight: FontWeight.w600)),
                        subtitle: Text(c.s('status') == 'called'
                            ? 'Called${c.date('calledAt') != null ? ' ${dateFmt.formatMediumDate(c.date('calledAt')!)}' : ''} · waiting'
                            : c.s('status') == 'declined'
                                ? "Can't play"
                                : 'Call withdrawn'),
                        trailing: !canCall
                            ? null
                            : c.s('status') == 'called'
                                ? IconButton(
                                    tooltip: 'Withdraw call',
                                    icon: Icon(Icons.close_rounded, color: p.muted),
                                    onPressed: () => leagueAction(context, ref, 'cancelCall', {'callId': c.str('id')},
                                        success: 'Call withdrawn', refresh: refresh),
                                  )
                                : IconButton(
                                    tooltip: 'Call again',
                                    icon: Icon(Icons.replay_rounded, color: p.muted),
                                    onPressed: () => leagueAction(context, ref, 'callPlayers',
                                        {'leagueId': leagueId, 'teamId': teamId, 'playerIds': [c.str('playerId')]},
                                        success: "Called again — they've been notified.", refresh: refresh),
                                  ),
                      ),
                  ]),
                ],
                if (canEdit) ...[
                  const SizedBox(height: 16),
                  SpSectionTitle('Team players not registered', count: available.length),
                  const SizedBox(height: 6),
                  if (available.isEmpty)
                    Text('Everyone on the team is registered. Add players to the team first to register more.',
                        style: TextStyle(color: p.muted, fontSize: 12.5))
                  else ...[
                    Text("Calling lets the player say yes. “Add” registers them straight away — use it when you've already asked.",
                        style: TextStyle(color: p.muted, fontSize: 12)),
                    const SizedBox(height: 8),
                    SpListCard(children: [
                      for (final a in available)
                        ListTile(
                          leading: PersonAvatar(url: a.s('avatarUrl'), name: a.str('name', '?'), size: 38),
                          title: Text(a.str('name'), style: TextStyle(color: p.ink, fontWeight: FontWeight.w600)),
                          subtitle: Text([
                            a.s('position'),
                            if (a.iOrNull('jerseyNumber') != null) '#${a.i('jerseyNumber')}',
                            if (a.b('called')) 'called',
                          ].whereType<String>().join(' · ')),
                          trailing: SpPill(
                            label: 'Add',
                            icon: Icons.add_rounded,
                            tone: SpPillTone.outline,
                            height: 32,
                            onTap: full
                                ? null
                                : () => leagueAction(context, ref, 'registerPlayer',
                                    {'leagueId': leagueId, 'teamId': teamId, 'playerId': a.str('playerId')},
                                    refresh: refresh),
                          ),
                        ),
                    ]),
                  ],
                ],
                if (d.b('isOrganiser') && removed.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SpSectionTitle('Removed', count: removed.length),
                  const SizedBox(height: 8),
                  SpListCard(children: [
                    for (final r in removed)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Text('${r.str('displayName', 'Player')}${r.s('note') != null ? ' · ${r.str('note')}' : ''}',
                            style: TextStyle(color: p.muted, fontSize: 13)),
                      ),
                  ]),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// Returns the number, -1 to clear, or null if cancelled.
  Future<int?> _askNumber(BuildContext context, int? current) async {
    final ctl = TextEditingController(text: current?.toString() ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Shirt number'),
        content: TextField(controller: ctl, keyboardType: TextInputType.number, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (v == null) return null;
    if (v.isEmpty) return -1;
    return int.tryParse(v);
  }
}

/// Pick team players to call (everyone not yet called is ticked), with an
/// optional remark that travels with the notification.
class _CallSheet extends ConsumerStatefulWidget {
  const _CallSheet({required this.leagueId, required this.teamId, required this.lock, required this.candidates, required this.answered});
  final String leagueId;
  final String teamId;
  final DateTime? lock;
  final List<J> candidates;
  final List<J> answered;

  @override
  ConsumerState<_CallSheet> createState() => _CallSheetState();
}

class _CallSheetState extends ConsumerState<_CallSheet> {
  late final Set<String> _sel;
  final _note = TextEditingController();
  bool _busy = false;

  bool _declined(String id) => widget.answered.any((c) => c.s('playerId') == id);

  @override
  void initState() {
    super.initState();
    _sel = {
      for (final c in widget.candidates)
        if (!_declined(c.str('playerId'))) c.str('playerId'),
    };
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _call({bool all = false}) async {
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    final ok = await leagueAction(
      context,
      ref,
      'callPlayers',
      {
        'leagueId': widget.leagueId,
        'teamId': widget.teamId,
        if (all) 'all': true else 'playerIds': _sel.toList(),
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      },
      success: "Called — they've been notified.",
      refresh: [leagueRosterProvider('${widget.leagueId}|${widget.teamId}')],
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final n = _sel.length;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SpSheetHeader(
        title: 'Call players',
        subtitle:
            'Each player is notified and answers; accepting registers them on the league roster${widget.lock != null ? ' (until ${MaterialLocalizations.of(context).formatMediumDate(widget.lock!)})' : ''}.',
        icon: Icons.campaign_rounded,
      ),
      Row(children: [
        Expanded(child: Text('$n of ${widget.candidates.length} selected', style: TextStyle(color: p.muted, fontSize: 12))),
        TextButton(
            onPressed: () => setState(() => _sel
              ..clear()
              ..addAll(widget.candidates.map((c) => c.str('playerId')))),
            child: const Text('Select all')),
        TextButton(onPressed: () => setState(_sel.clear), child: const Text('Clear')),
      ]),
      for (final c in widget.candidates)
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: _sel.contains(c.str('playerId')),
          onChanged: (v) => setState(() => v == true ? _sel.add(c.str('playerId')) : _sel.remove(c.str('playerId'))),
          secondary: PersonAvatar(url: c.s('avatarUrl'), name: c.str('name', '?'), size: 34),
          title: Text(c.str('name', 'Player'), style: TextStyle(color: p.ink, fontWeight: FontWeight.w600)),
          subtitle: Text(
              [c.s('position'), if (_declined(c.str('playerId'))) 'declined before — call again'].whereType<String>().join(' · '),
              style: TextStyle(color: p.muted, fontSize: 12)),
        ),
      const SizedBox(height: 8),
      TextField(
        controller: _note,
        maxLength: 300,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: 'Remark (optional)',
          hintText: 'Season starts in two weeks — training Tuesdays at 7.',
        ),
      ),
      const SizedBox(height: 8),
      SpButton(label: _busy ? 'Calling…' : 'Call $n player${n == 1 ? '' : 's'}', icon: Icons.campaign_rounded, expand: true, onTap: n == 0 || _busy ? null : _call),
      const SizedBox(height: 8),
      SpPill(label: 'Call everyone', icon: Icons.groups_rounded, tone: SpPillTone.outline, expand: true, onTap: _busy ? null : () => _call(all: true)),
    ]);
  }
}
