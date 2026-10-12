import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/leagues/leagues_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// The season's MVP poll on the public league page (web `MvpPolls`): one
/// card per match whose poll is open (or closed in the last few days). Pick a
/// player who appeared — changeable until it closes, never yourself. Results
/// show once you've voted, or when the poll closes. The vote feeds the
/// organiser's pick; they still choose and publish the MVP.

final mvpPollsProvider = FutureProvider.autoDispose
    .family<J, String>((ref, slug) => ref.watch(leaguesRepositoryProvider).obj('mvpPolls', {'slug': slug}));

class MvpPollsSection extends ConsumerWidget {
  const MvpPollsSection({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(mvpPollsProvider(slug)).valueOrNull;
    if (d == null || !d.b('enabled') || d.list('polls').isEmpty) return const SizedBox.shrink();
    final p = context.palette;
    final polls = d.list('polls');
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SpSectionTitle('Vote: match MVP'),
        Text(
            '${d.str('audience') == 'players' ? 'League players vote' : 'Anyone signed in can vote'}'
            " — the poll helps the organiser pick each match's MVP.",
            style: TextStyle(color: p.muted, fontSize: 12)),
        for (final poll in polls)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _PollCard(
              poll: poll,
              slug: slug,
              canVote: d.b('canVote'),
              signedIn: d.b('signedIn'),
              players: d.str('audience') == 'players',
            ),
          ),
      ]),
    );
  }
}

class _PollCard extends ConsumerStatefulWidget {
  const _PollCard({required this.poll, required this.slug, required this.canVote, required this.signedIn, required this.players});
  final J poll;
  final String slug;
  final bool canVote;
  final bool signedIn;
  final bool players;

  @override
  ConsumerState<_PollCard> createState() => _PollCardState();
}

class _PollCardState extends ConsumerState<_PollCard> {
  bool _busy = false;

  Future<void> _vote(String playerId) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(leaguesRepositoryProvider).mutate('voteMvp', {'fixtureId': widget.poll.str('fixtureId'), 'playerId': playerId});
      ref.invalidate(mvpPollsProvider(widget.slug));
      messenger.showSnackBar(const SnackBar(content: Text('Vote counted')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final poll = widget.poll;
    final f = poll.o('fixture');
    final open = poll.b('open');
    final closes = poll.date('closesAt');
    final myVote = poll.s('myVote');
    final mvpId = poll.o('mvp')?.s('playerId');
    final ballot = poll.list('ballot');
    final showResults = ballot.any((b) => b.has('votes'));
    final total = poll.i('total');
    final sides = [f?.o('home'), f?.o('away')].whereType<J>().toList();
    final loc = MaterialLocalizations.of(context);

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SpIconTile(Icons.how_to_vote_rounded, size: 32, iconSize: 17, bg: p.accentTint, fg: p.greenText),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  f == null
                      ? 'Match'
                      : '${f.o('home')?.str('name', 'Home')} ${f.iOrNull('homeScore') ?? ''}–${f.iOrNull('awayScore') ?? ''} ${f.o('away')?.str('name', 'Away')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
              Text(
                  '${open && closes != null ? 'Closes ${loc.formatShortMonthDay(closes)} ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(closes))}' : 'Poll closed'}'
                  '${showResults ? ' · $total vote${total == 1 ? '' : 's'}' : ''}',
                  style: TextStyle(color: p.muted, fontSize: 11.5)),
            ]),
          ),
          if (mvpId != null)
            SpBadge('MVP picked', tone: p.greenText)
          else if (open)
            SpBadge('Open', tone: p.orangeInk),
        ]),
        if (open && !widget.canVote) ...[
          const SizedBox(height: 8),
          Text(
              !widget.signedIn
                  ? 'Sign in to vote.'
                  : widget.players
                      ? 'Only players registered in this league can vote.'
                      : "You can't vote on this one.",
              style: TextStyle(color: p.muted, fontSize: 12)),
        ],
        for (final t in sides) ...[
          if (ballot.any((b) => b.s('teamId') == t.s('id'))) ...[
            const SizedBox(height: 10),
            Row(children: [
              Crest(logoUrl: t.s('logoUrl'), label: t.s('name'), kitPrimary: t.s('kitPrimary'), size: 16),
              const SizedBox(width: 6),
              Text(t.str('name').toUpperCase(),
                  style: TextStyle(color: p.muted, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
            ]),
            for (final b in ballot.where((b) => b.s('teamId') == t.s('id')))
              _row(p, b, mine: myVote == b.s('playerId'), picked: mvpId == b.s('playerId'), open: open, showResults: showResults, total: total),
          ],
        ],
      ]),
    );
  }

  Widget _row(AppPalette p, J b, {required bool mine, required bool picked, required bool open, required bool showResults, required int total}) {
    final disabled = !open || !widget.canVote || b.b('isMe') || _busy;
    final votes = b.i('votes');
    final pct = total > 0 ? (votes * 100 / total).round() : 0;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Material(
        color: mine ? p.accentTint : p.surface2,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: disabled ? null : () => _vote(b.str('playerId')),
          child: Stack(children: [
            if (showResults)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: total > 0 ? votes / total : 0,
                  child: ColoredBox(color: p.accent.withAlpha(30)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                SizedBox(
                  width: 24,
                  child: Text(b.iOrNull('shirtNumber')?.toString() ?? '',
                      textAlign: TextAlign.right, style: TextStyle(color: p.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      '${b.str('name')}${b.b('isMe') ? ' (you)' : ''}${picked ? ' · MVP' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.ink, fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                if (showResults) Text('$pct%', style: TextStyle(color: p.muted, fontSize: 12)),
                if (mine) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.check_rounded, size: 16, color: p.greenText),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
