import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/tournaments/squad_models.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';

/// The tournament-scoped team profile: this team AS IT IS in THIS tournament.
/// Squad (called / accepted / declined, with times), the formation set for
/// this event, games played and per-player stats. Mirrors the web page at
/// /groups/[id]/tournaments/[eventId]/teams/[teamId].
class TournamentTeamScreen extends ConsumerStatefulWidget {
  const TournamentTeamScreen({
    super.key,
    required this.groupId,
    required this.eventId,
    required this.teamId,
    this.respond = false,
  });
  final String groupId;
  final String eventId;
  final String teamId;
  /// Deep link from a call-up notification — scroll the respond card into view.
  final bool respond;

  @override
  ConsumerState<TournamentTeamScreen> createState() => _TournamentTeamScreenState();
}

class _TournamentTeamScreenState extends ConsumerState<TournamentTeamScreen> {
  int _tab = 0; // 0 squad, 1 formation, 2 games, 3 stats
  bool _busy = false;

  String get _key => '${widget.eventId}|${widget.teamId}';

  void _refetch() {
    ref.invalidate(tournamentSquadProvider(_key));
    ref.invalidate(squadStatsProvider(_key));
    ref.invalidate(myCallsProvider);
    ref.invalidate(tournamentDetailProvider(widget.eventId));
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _run(Future<void> Function() fn, {String? success}) async {
    setState(() => _busy = true);
    try {
      await fn();
      if (success != null) _snack(success);
      _refetch();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _respond(TournamentSquad sq, bool accept) async {
    final id = sq.mySquadId;
    if (id == null) return;
    if (!accept && sq.myStatus == 'accepted') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Withdraw from this squad?'),
          content: Text("You'll be taken off ${sq.teamName}'s squad for ${sq.eventTitle}."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Withdraw')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _run(
      () => ref.read(tournamentsRepositoryProvider).respondCall(widget.eventId, id, accept: accept),
      success: accept ? "You're in the squad" : 'Response sent',
    );
  }

  Future<void> _callPlayers(TournamentSquad sq) async {
    final req = await showModalBottomSheet<CallRequest>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        // Lift the sheet above the keyboard while the remark is being typed.
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _CallPlayersSheet(squad: sq),
      ),
    );
    if (req == null) return;
    if (!req.all && req.playerIds.isEmpty) return;
    await _run(() async {
      final n = await ref.read(tournamentsRepositoryProvider).callPlayers(
            widget.eventId,
            sq.tournamentTeamId,
            playerIds: req.all ? null : req.playerIds,
            all: req.all,
            note: req.note,
          );
      _snack(n == 0
          ? 'Everyone picked had already been called.'
          : "Called $n player${n == 1 ? '' : 's'} — they've been notified.");
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sq = ref.watch(tournamentSquadProvider(_key));
    return Scaffold(
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Squad', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (sq.valueOrNull != null)
            Text(sq.valueOrNull!.eventTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 11.5)),
        ]),
      ),
      body: AsyncView(
        value: sq,
        onRetry: _refetch,
        data: (d) => RefreshIndicator(
          onRefresh: () async => ref.refresh(tournamentSquadProvider(_key).future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _header(d, p),
              if (d.mySquadId != null) ...[const SizedBox(height: 10), _myCard(d, p)],
              const SizedBox(height: 14),
              _tabs(d, p),
              const SizedBox(height: 12),
              if (_tab == 0) ..._squadTab(d, p),
              if (_tab == 1) _formationTab(d, p),
              if (_tab == 2) ..._gamesTab(d, p),
              if (_tab == 3)
                _StatsTab(keyId: _key, eventId: widget.eventId),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(TournamentSquad d, AppPalette p) {
    final starters = d.accepted.where((x) => x.isStarter).length;
    return GlassCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Crest(logoUrl: d.teamLogoUrl, kitPrimary: d.kitPrimary, kitSecondary: d.kitSecondary, label: d.teamName, size: 56),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, children: [
              SpBadge(d.kind, icon: Icons.emoji_events_outlined),
              if (d.role == 'host') const SpBadge('Host') else const SpBadge('Guest'),
              if (d.kickedOff)
                const SpBadge('Kicked off', tone: Color(0xFF0EA5E9)),
            ]),
            const SizedBox(height: 4),
            Text(d.teamName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
            if (d.teamUsername != null)
              Text('@${d.teamUsername}', style: TextStyle(color: p.muted, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              '${d.accepted.length} in squad'
              '${d.pending.isNotEmpty ? ' · ${d.pending.length} awaiting reply' : ''}'
              '${d.needsFormation ? ' · $starters/${d.maxStarters} starters' : ''}'
              '${d.formationName != null ? ' · ${d.formationName}' : ''}',
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: () => context.push('/teams/${d.teamId}'),
              child: Text('General team profile ›',
                  style: TextStyle(color: p.accent, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ]),
    );
  }

  /// The viewer's own call-up.
  Widget _myCard(TournamentSquad d, AppPalette p) {
    if (d.myStatus == 'called') {
      final blocked = d.myOtherTeamName != null;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: p.amber.withAlpha(18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.amber.withAlpha(110)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.campaign_rounded, color: p.amber, size: 20),
            const SizedBox(width: 6),
            Text("You've been called up",
                style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 4),
          Text(
            'Can you play for ${d.teamName} in ${d.eventTitle}?',
            style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4),
          ),
          // Nobody can answer "can you play?" from a title alone — put the
          // when / where / who in front of them, above the buttons.
          const SizedBox(height: 8),
          _detail(p, Icons.event_outlined, 'When', d.when.line,
              sub: d.when.viewerTime != null
                  ? '${d.when.viewerTime} your time'
                  : null),
          if (d.locationName != null)
            _detail(p, Icons.place_outlined, 'Where', d.locationName!),
          if (d.opponents.isNotEmpty)
            _detail(
                p,
                Icons.sports_kabaddi_outlined,
                d.opponents.length > 1 ? 'Teams' : 'Opponent',
                d.opponents.map((o) => o.name).join(', ')),
          _detail(
              p,
              Icons.groups_outlined,
              'Host',
              [
                d.hostGroupName,
                if (d.categoryName != null)
                  '${d.categoryEmoji ?? ''} ${d.categoryName}'.trim(),
              ].whereType<String>().join(' · ')),
          if (d.myCallNote != null && d.myCallNote!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: p.amber, width: 2.5)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${d.myCalledByName ?? 'Your coach'} says'.toUpperCase(),
                    style: TextStyle(
                        color: p.muted, fontSize: 9.5, letterSpacing: 0.6,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(d.myCallNote!.trim(),
                    style: TextStyle(color: p.ink, fontSize: 12, height: 1.35)),
              ]),
            ),
          ],
          if (d.eventDescription != null &&
              d.eventDescription!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              d.eventDescription!.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 12, height: 1.35),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Accepting locks you to this team for this ${d.kind.toLowerCase()}.',
            style: TextStyle(color: p.muted, fontSize: 11.5, height: 1.35),
          ),
          if (d.hostGroupId != null) ...[
            const SizedBox(height: 2),
            InkWell(
              onTap: () => context
                  .push('/groups/${d.hostGroupId}/tournaments/${d.eventId}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  'Full ${d.kind.toLowerCase()} details',
                  style: TextStyle(
                      color: p.accent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
          if (blocked) ...[
            const SizedBox(height: 6),
            Text(
              "You've already accepted for ${d.myOtherTeamName} — withdraw there first to switch.",
              style: TextStyle(color: p.danger, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: SpButton(
                label: "I'm in",
                icon: Icons.check_rounded,
                expand: true,
                onTap: _busy || blocked ? null : () => _respond(d, true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _respond(d, false),
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text("Can't make it"),
              ),
            ),
          ]),
        ]),
      );
    }
    if (d.myStatus == 'accepted') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: p.accent.withAlpha(18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.accent.withAlpha(90)),
        ),
        child: Row(children: [
          Icon(Icons.check_circle_rounded, color: p.accent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text("You're in this squad.",
                style: TextStyle(color: p.ink, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          if (!d.isOver)
            TextButton(
              onPressed: _busy ? null : () => _respond(d, false),
              child: Text('Withdraw', style: TextStyle(color: p.muted, fontSize: 12)),
            ),
        ]),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _tabs(TournamentSquad d, AppPalette p) {
    final items = <(String, int)>[
      ('Squad', 0),
      if (d.needsFormation) ('Formation', 1),
      ('Games', 2),
      ('Stats', 3),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final (label, i) in items)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(label),
              selected: _tab == i,
              onSelected: (_) => setState(() => _tab = i),
              selectedColor: p.accent.withAlpha(40),
              labelStyle: TextStyle(
                  color: _tab == i ? p.accent : p.muted, fontWeight: FontWeight.w700, fontSize: 12.5),
              side: BorderSide(color: _tab == i ? p.accent : p.line),
            ),
          ),
      ]),
    );
  }

  List<Widget> _squadTab(TournamentSquad d, AppPalette p) {
    final repo = ref.read(tournamentsRepositoryProvider);
    return [
      if (d.canManage && !d.isOver) ...[
        SpButton(
          label: 'Call players',
          icon: Icons.campaign_rounded,
          expand: true,
          onTap: _busy || (d.uncalled.isEmpty && d.notPlaying.isEmpty) ? null : () => _callPlayers(d),
        ),
        const SizedBox(height: 6),
        Text(
          'Players get an in-app, push and email call-up and accept or decline. They can only accept for one team per ${d.kind.toLowerCase()}.',
          style: TextStyle(color: p.muted, fontSize: 11.5, height: 1.4),
        ),
        const SizedBox(height: 12),
      ],
      _sectionTitle('In the squad (${d.accepted.length})', p),
      if (d.accepted.isEmpty)
        _empty('Nobody has accepted yet.', p)
      else
        for (final m in d.accepted)
          _row(m, d, p,
              trailing: d.canManage && !d.isOver
                  ? IconButton(
                      tooltip: 'Remove from squad',
                      icon: Icon(Icons.person_remove_outlined, size: 18, color: p.muted),
                      onPressed: _busy
                          ? null
                          : () => _run(() => repo.removeSquadPlayer(widget.eventId, m.id),
                              success: 'Removed from squad'),
                    )
                  : null),
      if (d.pending.isNotEmpty) ...[
        const SizedBox(height: 12),
        _sectionTitle('Awaiting reply (${d.pending.length})', p),
        for (final m in d.pending)
          _row(m, d, p,
              trailing: d.canManage && !d.isOver
                  ? TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => repo.addSquadPlayer(widget.eventId, d.tournamentTeamId, m.playerId),
                              success: 'Added to squad'),
                      child: const Text('Add', style: TextStyle(fontSize: 12)),
                    )
                  : null),
      ],
      if (d.notPlaying.isNotEmpty) ...[
        const SizedBox(height: 12),
        _sectionTitle('Not playing (${d.notPlaying.length})', p),
        for (final m in d.notPlaying) _row(m, d, p),
      ],
      if (d.coaches.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Coaches: ${d.coaches.map((c) => c.displayName).join(', ')}',
            style: TextStyle(color: p.muted, fontSize: 11.5)),
      ],
    ];
  }

  Widget _row(SquadPlayer m, TournamentSquad d, AppPalette p, {Widget? trailing}) {
    final (String status, Color tone) = switch (m.status) {
      'accepted' => ('In', p.accent),
      'called' => ('Awaiting', p.amber),
      'removed' => ('Removed', p.danger),
      'withdrawn' => ('Withdrew', p.muted),
      _ => ('Declined', p.muted),
    };
    final sub = <String>[
      if (m.positions.isNotEmpty) m.positions.join(' · '),
      if (m.accepted)
        '${m.source == 'coach' ? 'Added by coach' : 'Accepted'} ${timeAgo(m.acceptedAt)}'
      else if (m.pending)
        'Called ${timeAgo(m.calledAt)}'
      else
        '$status ${timeAgo(m.respondedAt)}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onTap: () => context.push('/players/${m.playerId}'),
        child: Row(children: [
          ClipOval(child: Crest(logoUrl: m.profile?.avatarUrl, label: m.name, size: 36)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (m.jerseyNumber != null)
                  Text('#${m.jerseyNumber} ',
                      style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w700)),
                Flexible(
                  child: Text(m.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
                if (m.isCaptain)
                  Text(' C', style: TextStyle(color: p.amber, fontSize: 11, fontWeight: FontWeight.w900)),
                if (m.accepted) ...[
                  const SizedBox(width: 6),
                  SpBadge(m.isStarter ? 'Starter' : 'Sub', tone: m.isStarter ? p.accent : p.muted),
                ],
              ]),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 11.5)),
              if (m.accepted && m.joinedAfterKickoff)
                const Text('Joined after kick-off',
                    style: TextStyle(color: Color(0xFF0EA5E9), fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(width: 6),
          SpBadge(status, tone: tone),
          if (trailing != null) trailing,
        ]),
      ),
    );
  }

  Widget _formationTab(TournamentSquad d, AppPalette p) {
    final starters = d.accepted.where((x) => x.isStarter).length;
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(d.formationName ?? 'No formation set',
            style: TextStyle(color: p.ink, fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          d.accepted.isEmpty
              ? 'The formation is built from players who accepted the call-up. Call players first.'
              : 'For ${d.eventTitle} only — $starters of ${d.maxStarters} on the pitch. This is what the match line-up is built from.',
          style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4),
        ),
        const SizedBox(height: 12),
        SpButton(
          label: d.canManage && !d.isOver ? 'Open formation board' : 'View formation',
          icon: Icons.grid_on_rounded,
          expand: true,
          onTap: d.accepted.isEmpty
              ? null
              : () async {
                  await context.push('/groups/${widget.groupId}/tournaments/${widget.eventId}/teams/${widget.teamId}/formation');
                  _refetch();
                },
        ),
      ]),
    );
  }

  List<Widget> _gamesTab(TournamentSquad d, AppPalette p) {
    if (d.games.isEmpty) return [_empty('No games yet.', p)];
    return [
      for (final g in d.games)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            onTap: () => context.push('/games/${g.id}'),
            child: Row(children: [
              Expanded(
                child: Text(
                  g.teams.map((t) => '${t.name} ${t.score}').join('  vs  '),
                  maxLines: 2,
                  style: TextStyle(color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
              SpBadge(g.status),
            ]),
          ),
        ),
    ];
  }

  /// One "When / Where / Opponent" line in the call-up prompt. [sub] carries
  /// the viewer's own clock when their zone differs from the venue's.
  Widget _detail(AppPalette p, IconData icon, String label, String value,
      {String? sub}) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: p.muted),
        const SizedBox(width: 6),
        SizedBox(
          width: 62,
          child: Text(label,
              style: TextStyle(color: p.muted, fontSize: 11.5)),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                style: TextStyle(
                    color: p.ink, fontSize: 11.5, fontWeight: FontWeight.w700)),
            if (sub != null)
              Text(sub, style: TextStyle(color: p.muted, fontSize: 11)),
          ]),
        ),
      ]),
    );
  }

  Widget _sectionTitle(String t, AppPalette p) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t.toUpperCase(),
            style: TextStyle(color: p.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      );

  Widget _empty(String t, AppPalette p) => GlassCard(
        padding: const EdgeInsets.all(18),
        child: Center(child: Text(t, style: TextStyle(color: p.muted, fontSize: 13))),
      );
}

/// Pick roster players to call up (uncalled + anyone who declined/withdrew).
class _CallPlayersSheet extends StatefulWidget {
  const _CallPlayersSheet({required this.squad});
  final TournamentSquad squad;
  @override
  State<_CallPlayersSheet> createState() => _CallPlayersSheetState();
}

/// What the sheet hands back: who to call (or the whole roster) plus the
/// coach's optional remark.
typedef CallRequest = ({List<String> playerIds, bool all, String? note});

class _CallPlayersSheetState extends State<_CallPlayersSheet> {
  late final Set<String> _sel = {for (final u in widget.squad.uncalled) u.playerId};
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String? get _noteText =>
      _note.text.trim().isEmpty ? null : _note.text.trim();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sq = widget.squad;
    final rows = <({String id, String name, String sub, String? avatar})>[
      for (final u in sq.uncalled)
        (id: u.playerId, name: u.name, sub: u.positions.join(' · '), avatar: u.profile?.avatarUrl),
      for (final m in sq.notPlaying)
        (
          id: m.playerId,
          name: m.name,
          sub: [if (m.positions.isNotEmpty) m.positions.join(' · '), 'call again'].join(' · '),
          avatar: m.profile?.avatarUrl
        ),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Call players', style: TextStyle(color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'Each player gets an in-app, push and email call-up and replies in the app. Only roster members can be called.',
            style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4),
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text('${_sel.length} of ${rows.length} selected',
                    style: TextStyle(color: p.muted, fontSize: 11.5)),
              ),
              TextButton(
                onPressed: () =>
                    setState(() => _sel.addAll(rows.map((r) => r.id))),
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text('Select all', style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: () => setState(_sel.clear),
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text('Clear', style: TextStyle(fontSize: 12)),
              ),
            ]),
          ],
          const SizedBox(height: 2),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Everyone on the roster has already been called.',
                    style: TextStyle(color: p.muted, fontSize: 13)),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final r in rows)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _sel.contains(r.id),
                      onChanged: (v) => setState(() => v == true ? _sel.add(r.id) : _sel.remove(r.id)),
                      title: Text(r.name, style: TextStyle(color: p.ink, fontSize: 13.5)),
                      subtitle: r.sub.isEmpty ? null : Text(r.sub, style: TextStyle(color: p.muted, fontSize: 11.5)),
                      secondary: ClipOval(child: Crest(logoUrl: r.avatar, label: r.name, size: 32)),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          // Optional remark — meeting point, kit, what the game is for. It
          // travels with the call-up into the notification, the email and the
          // player's accept/decline prompt.
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 3,
            maxLength: 300,
            style: TextStyle(color: p.ink, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Remark (optional)',
              hintText:
                  'Meet at the clubhouse 45 minutes before kick-off — bring the away kit.',
              hintStyle: TextStyle(color: p.muted, fontSize: 12),
              counterStyle: TextStyle(color: p.muted, fontSize: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 6),
          SpButton(
            label: 'Call ${_sel.length} player${_sel.length == 1 ? '' : 's'}',
            icon: Icons.campaign_rounded,
            expand: true,
            onTap: _sel.isEmpty
                ? null
                : () => Navigator.pop<CallRequest>(context,
                    (playerIds: _sel.toList(), all: false, note: _noteText)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop<CallRequest>(
                context, (playerIds: const <String>[], all: true, note: _noteText)),
            icon: const Icon(Icons.groups_2_outlined, size: 16),
            label: const Text('Call whole roster'),
          ),
        ]),
      ),
    );
  }
}

class _StatsTab extends ConsumerWidget {
  const _StatsTab({required this.keyId, required this.eventId});
  final String keyId;
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final s = ref.watch(squadStatsProvider(keyId));
    return s.when(
      loading: () => Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Loading stats…',
                  style: TextStyle(color: p.muted, fontSize: 13)))),
      error: (e, _) =>
          Center(child: Text('$e', style: TextStyle(color: p.muted, fontSize: 13))),
      data: (d) {
        final games = (d['games'] as num?)?.toInt() ?? 0;
        final players = d['players'] is List ? (d['players'] as List) : const [];
        // Columns come from the category's own activity schema — goals,
        // assists, yellows and reds for soccer, whatever another sport
        // declares for itself.
        final fields = [
          for (final f in (d['fields'] is List ? d['fields'] as List : const []))
            if (f is Map) Map<String, dynamic>.from(f)
        ];
        final cats = [
          for (final c
              in (d['categories'] is List ? d['categories'] as List : const []))
            if (c is Map) Map<String, dynamic>.from(c)
        ];
        if (games == 0 || players.isEmpty) {
          return GlassCard(
            padding: const EdgeInsets.all(18),
            child: Center(
              child: Text(
                  'Stats appear once this squad has played a game in this tournament.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.muted, fontSize: 13)),
            ),
          );
        }
        final rows = [
          for (final x in players) Map<String, dynamic>.from(x as Map)
        ];

        Widget cell(String text,
                {bool dim = false, bool bold = false, double width = 34}) =>
            SizedBox(
              width: width,
              child: Text(text,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: dim ? p.muted.withAlpha(120) : p.ink,
                      fontSize: 12,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
            );

        Widget head(String text, {double width = 34}) => SizedBox(
              width: width,
              child: Text(text,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4)),
            );

        // One horizontal scroller for the whole grid: the name column stays
        // readable on a phone and the stat columns run off to the right.
        return GlassCard(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    SizedBox(
                        width: 140,
                        child: Text('PLAYER',
                            style: TextStyle(
                                color: p.muted,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4))),
                    head('GP'),
                    head('ST'),
                    head('W-D-L', width: 52),
                    for (final f in fields)
                      head(
                          '${parseStr(f['icon']) ?? ''}${parseStr(f['label']) ?? parseStr(f['key']) ?? ''}',
                          width: 58),
                  ]),
                ),
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: InkWell(
                      onTap: parseStr(r['playerId']) != null
                          ? () => context.push(
                              '/players/${parseStr(r['playerId'])}/tournaments/$eventId')
                          : null,
                      child: Row(children: [
                        SizedBox(
                          width: 140,
                          child: Row(children: [
                            if (parseInt(r['jerseyNumber']) != null) ...[
                              Text('#${parseInt(r['jerseyNumber'])}',
                                  style: TextStyle(
                                      color: p.muted, fontSize: 11)),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                (r['profile'] is Map
                                        ? parseStr(
                                            (r['profile'] as Map)['displayName'])
                                        : null) ??
                                    'Player',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: p.ink,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ]),
                        ),
                        cell('${parseInt(r['games']) ?? 0}'),
                        cell('${parseInt(r['starts']) ?? 0}'),
                        cell(
                            '${parseInt(r['wins']) ?? 0}-${parseInt(r['draws']) ?? 0}-${parseInt(r['losses']) ?? 0}',
                            width: 52),
                        for (final f in fields)
                          () {
                            final v = parseInt(
                                    (r['counts'] as Map?)?[parseStr(f['key']) ?? '']) ??
                                0;
                            return cell('$v',
                                dim: v == 0, bold: v > 0, width: 58);
                          }(),
                      ]),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 2),
            Text(
              'Across $games game${games == 1 ? '' : 's'}'
              '${cats.isEmpty ? '' : ' · ${cats.map((c) => '${parseStr(c['emoji']) ?? ''}${parseStr(c['name']) ?? ''}').join(', ')} stats'}'
              '. Tap a player for their match-by-match.',
              style: TextStyle(color: p.muted, fontSize: 10.5),
            ),
          ]),
        );
      },
    );
  }
}
