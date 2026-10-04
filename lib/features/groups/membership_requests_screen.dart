import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/groups/group_models.dart';
import 'package:sportpadi_mobile/data/groups/membership_requests_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/features/settings/timezone_provider.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/player_link.dart';

/// The group OWNER's membership requests (`/groups/:id/requests`, also where
/// the "X asked to join" notification lands): Pending, Approved and
/// Declined, and Approve / Decline on the pending ones. Nobody else can see
/// the queue — the server answers 403, and this screen says so.
class MembershipRequestsScreen extends ConsumerStatefulWidget {
  const MembershipRequestsScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<MembershipRequestsScreen> createState() =>
      _MembershipRequestsScreenState();
}

class _MembershipRequestsScreenState
    extends ConsumerState<MembershipRequestsScreen> {
  static const _statuses = ['pending', 'approved', 'declined'];
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final group = ref.watch(groupProvider(widget.groupId)).valueOrNull;
    // Known not to be the owner: don't even ask the server.
    final notOwner = group != null && !group.isOwner;
    final pending = notOwner
        ? 0
        : ref
                .watch(membershipRequestCountProvider(widget.groupId))
                .valueOrNull ??
            0;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SpHeader(
              title: 'Membership requests',
              subtitle: group?.name,
            ),
          ),
          if (notOwner)
            const Expanded(child: _OwnerOnly())
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: SpSegmented(
                options: [
                  pending > 0 ? 'Pending · $pending' : 'Pending',
                  'Approved',
                  'Declined',
                ],
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ),
            Expanded(
              child: _RequestsList(
                // A fresh list (and busy state) per tab.
                key: ValueKey(_statuses[_tab]),
                groupId: widget.groupId,
                status: _statuses[_tab],
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// One tab of the queue.
class _RequestsList extends ConsumerStatefulWidget {
  const _RequestsList({super.key, required this.groupId, required this.status});
  final String groupId;
  final String status;

  @override
  ConsumerState<_RequestsList> createState() => _RequestsListState();
}

class _RequestsListState extends ConsumerState<_RequestsList> {
  final Set<String> _busy = {};

  MembershipRequestsKey get _key =>
      (groupId: widget.groupId, status: widget.status);

  Future<void> _decide(MembershipRequestItem r, bool approve) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve
            ? 'Let ${r.displayName} join?'
            : 'Decline ${r.displayName}’s request?'),
        content: Text(approve
            ? 'They become a member of the group and are told so.'
            : "They're told it wasn't approved, and can keep following the "
                'group.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(approve ? 'Approve' : 'Decline')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy.add(r.id));
    // Both outlive this list if the owner leaves before the answer lands.
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final groupId = widget.groupId;
    try {
      await ref
          .read(membershipRequestsRepositoryProvider)
          .decide(groupId, requestId: r.id, approve: approve);
      messenger.showSnackBar(SnackBar(
          content: Text(approve
              ? '${r.displayName} is now a member.'
              : 'Request declined.')));
      // The member count on the group page.
      if (approve) container.invalidate(groupProvider(groupId));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      // Every tab and the owner's badge (also after "already handled").
      container.invalidate(membershipRequestsProvider);
      container.invalidate(membershipRequestCountProvider(groupId));
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    ref.watch(viewerTimezoneProvider); // repaint stamps on a zone change
    final provider = membershipRequestsProvider(_key);
    final list = ref.watch(provider);
    final error = list.error;
    if (!list.hasValue && error is ApiException && error.statusCode == 403) {
      return const _OwnerOnly();
    }
    // Loading / error aren't scrollable on their own: keep them pullable.
    final bare = list.when(
        data: (_) => false, error: (_, __) => true, loading: () => true);
    return RefreshIndicator(
      // This tab, the Pending count and the header's group name.
      onRefresh: () {
        ref.invalidate(provider);
        ref.invalidate(membershipRequestCountProvider(widget.groupId));
        ref.invalidate(groupProvider(widget.groupId));
        return settleAll([
          ref.read(provider.future),
          ref.read(membershipRequestCountProvider(widget.groupId).future),
          ref.read(groupProvider(widget.groupId).future),
        ]);
      },
      child: _pullable(bare, AsyncView<List<MembershipRequestItem>>(
        value: list,
        onRetry: () => ref.invalidate(provider),
        data: (items) {
          if (items.isEmpty) {
            final (IconData icon, String text) = switch (widget.status) {
              'approved' => (Icons.how_to_reg_outlined, 'No approved requests'),
              'declined' => (Icons.block_rounded, 'No declined requests'),
              _ => (Icons.inbox_outlined, 'No one is waiting to join'),
            };
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
              children: [
                Center(child: SpIconTile(icon, size: 60, iconSize: 28)),
                const SizedBox(height: 14),
                Text(text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                if (widget.status == 'pending') ...[
                  const SizedBox(height: 6),
                  Text(
                      'Followers can ask to join from the group page — '
                      "you'll get a notification.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.muted, fontSize: 13)),
                ],
              ],
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final r = items[i];
              return _RequestCard(
                request: r,
                busy: _busy.contains(r.id),
                onApprove: () => _decide(r, true),
                onDecline: () => _decide(r, false),
              );
            },
          );
        },
      )),
    );
  }

  Widget _pullable(bool bare, Widget view) =>
      bare ? PullableState(child: view) : view;
}

/// One request: who, their note, how long they've followed, when — and, while
/// pending, Decline / Approve.
class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.busy,
    required this.onApprove,
    required this.onDecline,
  });
  final MembershipRequestItem request;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = request;
    final message = r.message?.trim() ?? '';
    final since = r.followingSince;
    final decided = r.decidedAt;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            // Avatar + name open the requester's profile.
            Expanded(
              child: PlayerTap(
                userId: r.userId,
                borderRadius: 14,
                child: Row(children: [
                  ClipOval(
                    child: Crest(
                        logoUrl: r.avatarUrl, label: r.displayName, size: 42),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700)),
                        if (r.username != null)
                          Text('@${r.username}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: p.muted, fontSize: 12)),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            Text(fmtRelative(r.createdAt),
                style: TextStyle(color: p.muted, fontSize: 11.5)),
          ]),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: p.surface2,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text('“$message”',
                  style: TextStyle(color: p.ink, fontSize: 13.5, height: 1.4)),
            ),
          ],
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.favorite_border_rounded, size: 14, color: p.muted),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                  since != null
                      ? 'Following since ${fmtInstant(since, style: InstantStyle.date)}'
                      : 'Not following the group',
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ),
            if (!r.isPending)
              SpBadge(
                decided != null
                    ? '${_statusLabel(r.status)} ${timeAgo(decided)}'
                    : _statusLabel(r.status),
                tone: r.status == 'approved' ? p.greenText : p.muted,
              ),
          ]),
          if (r.isPending) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _DeclineButton(onTap: busy ? null : onDecline),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SpButton(
                  label: 'Approve',
                  icon: Icons.check_rounded,
                  tone: SpButtonTone.brand,
                  expand: true,
                  onTap: busy ? null : onApprove,
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  static String _statusLabel(String status) => switch (status) {
        'approved' => 'Approved',
        'declined' => 'Declined',
        'cancelled' => 'Withdrawn',
        _ => 'Pending',
      };
}

/// The quiet half of the decision pair.
class _DeclineButton extends StatelessWidget {
  const _DeclineButton({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.surface2,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.close_rounded,
                size: 18, color: onTap != null ? p.ink : p.muted),
            const SizedBox(width: 6),
            Text('Decline',
                style: TextStyle(
                    color: onTap != null ? p.ink : p.muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

/// For anyone but the owner.
class _OwnerOnly extends StatelessWidget {
  const _OwnerOnly();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 80, 32, 32),
      children: [
        const Center(
            child:
                SpIconTile(Icons.lock_outline_rounded, size: 60, iconSize: 28)),
        const SizedBox(height: 14),
        Text('Only the group owner can see membership requests',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: p.ink, fontSize: 16, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
