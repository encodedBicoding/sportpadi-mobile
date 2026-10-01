import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/manage/manage_models.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/features/payments/checkout_flow.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';

/// Tournament invitations as a dense list rather than a stack of cards.
///
/// A group admin can be sitting on a dozen invites in one week; the original
/// full-width amber card meant nine of them buried the tournaments the team had
/// actually committed to. One invite = one row, sorted by kick-off.

/// A single invitation: who's asking, when, what it costs, accept / decline.
class InvitationRow extends ConsumerStatefulWidget {
  const InvitationRow({super.key, required this.invite, this.onDone});
  final TournamentInvite invite;

  /// Called after a successful accept/decline, for screens that want to pop
  /// themselves once the last invitation is cleared.
  final VoidCallback? onDone;

  @override
  ConsumerState<InvitationRow> createState() => _InvitationRowState();
}

class _InvitationRowState extends ConsumerState<InvitationRow> {
  bool _busy = false;

  TournamentInvite get iv => widget.invite;

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _accept() => _run('approve');

  Future<void> _decline() async {
    // Declining can't be undone, and the button sits beside Accept — ask first.
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Decline ${iv.eventTitle}?'),
        content: Text(
          '${iv.hostGroupName ?? 'The host'} will be told '
          '${iv.guestTeamName ?? 'your team'} isn\'t playing. '
          "They'd have to invite you again to reverse it.",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (sure == true) await _run('reject');
  }

  Future<void> _run(String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(manageRepositoryProvider);
      final status = await repo.respondInvite(iv.id, action);
      // A paid tournament can't be accepted until the entry fee clears, so
      // hand straight off to checkout rather than reporting a failure.
      if (status == 'payment_required') {
        final url = await repo.payInvite(iv.id);
        if (!mounted) return;
        final paid = await runHostedCheckout(context, url);
        if (!paid) return;
      } else if (mounted) {
        _snack(status == 'approved'
            ? '${iv.guestTeamName ?? 'Your team'} is in — call your players'
            : 'Invitation declined');
      }
      ref.invalidate(myTournamentInvitesProvider);
      ref.invalidate(myTournamentsProvider);
      ref.invalidate(myTeamCardsProvider);
      ref.invalidate(myTeamTournamentsProvider);
      if (iv.eventId != null) {
        ref.invalidate(tournamentDetailProvider(iv.eventId!));
      }
      widget.onDone?.call();
      // Saying yes is the start of the work, not the end of it: the squad
      // still has to be called and a formation set. Go there.
      if (action == 'approve' && mounted) {
        final squad = iv.squadRoute;
        if (squad != null) context.push(squad);
      }
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final owes = iv.owesFee;
    // categoryLabel is built server-side as "<emoji> <name>", so the leading
    // token is the emoji. Split rather than take a code unit: an emoji is
    // several UTF-16 units and slicing one would render a broken glyph.
    final labelParts = (iv.categoryLabel ?? '').trim().split(RegExp(r'\s+'));
    final emoji = labelParts.isNotEmpty && labelParts.first.isNotEmpty
        ? labelParts.first
        : '🏆';

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: iv.eventId != null && iv.hostGroupId != null
          ? () => context
              .push('/groups/${iv.hostGroupId}/tournaments/${iv.eventId}')
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.orangeTint,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 19)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(iv.eventTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 1),
                Text(
                  [
                    iv.eventDate != null ? formatDay(iv.eventDate) : 'Date TBC',
                    '${iv.hostTeamName ?? iv.hostGroupName ?? 'Host'} → ${iv.guestTeamName ?? 'your team'}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
                if (iv.feeLabel != null) ...[
                  const SizedBox(height: 5),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: owes ? p.orangeTint : p.accentTint,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      owes ? '${iv.feeLabel} entry' : '${iv.feeLabel} · paid',
                      style: TextStyle(
                          color: owes ? p.orangeInk : p.greenText,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            // Decline: a quiet round button; accept: the ink pill.
            Tooltip(
              message: 'Decline',
              child: Material(
                color: p.surface2,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _decline,
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: Icon(Icons.close_rounded, size: 18, color: p.muted),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: p.hero,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: _accept,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(owes ? 'Pay' : 'Accept',
                      style: TextStyle(
                          color: p.onHero,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// The rows in one white card, divided.
class InvitationListBox extends StatelessWidget {
  const InvitationListBox({super.key, required this.invites, this.onDone});
  final List<TournamentInvite> invites;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (invites.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(24),
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: p.line)
            : null,
        boxShadow: cardShadow(context),
      ),
      child: Column(children: [
        for (var i = 0; i < invites.length; i++) ...[
          if (i > 0)
            Divider(
                height: 1,
                thickness: 1,
                indent: 12,
                endIndent: 12,
                color: p.surface2),
          InvitationRow(
              key: ValueKey(invites[i].id), invite: invites[i], onDone: onDone),
        ],
      ]),
    );
  }
}
