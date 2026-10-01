import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/groups/group_models.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/verified_badge.dart';

/// Group invitations I've received (an admin asked me to join):
///  - [InvitationsTab]: Groups → Invites — what they are, then every pending
///    one, newest first, a page at a time as you scroll.
///  - [GroupInviteBanner]: on that group's own page.
/// The tab badge is [groupInvitationCountProvider].
/// Web twin: apps/web/src/components/GroupInvitations.tsx.

/// Accept (join) or decline; refreshes the count, my groups and the group.
/// Returns true when it went through.
Future<bool> respondToInvitation(
    BuildContext context, GroupInvitation inv, bool accept) async {
  final messenger = ScaffoldMessenger.of(context);
  // The row goes away once answered; the container outlives it.
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await container
        .read(groupsRepositoryProvider)
        .respondInvitation(inv.id, accept);
    messenger.showSnackBar(SnackBar(
        content: Text(accept
            ? "You've joined ${inv.groupName}!"
            : 'Invitation declined')));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
    return false;
  } finally {
    container.invalidate(groupInvitationCountProvider);
    container.invalidate(groupInviteForProvider(inv.groupId));
    if (accept) {
      container.invalidate(myGroupsProvider);
      container.invalidate(groupProvider(inv.groupId));
    }
  }
}

/// Groups → Invites. The Groups screen owns the scrolling; it calls
/// [InvitationsTabState.loadMore] near the bottom (pass a GlobalKey).
class InvitationsTab extends ConsumerStatefulWidget {
  const InvitationsTab({super.key, this.onLoaded});

  /// After each page lands — the screen checks whether the list still
  /// doesn't fill it and, if so, asks for the next page.
  final VoidCallback? onLoaded;

  @override
  ConsumerState<InvitationsTab> createState() => InvitationsTabState();
}

class InvitationsTabState extends ConsumerState<InvitationsTab> {
  final List<GroupInvitation> _items = [];
  int? _next;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  int _gen = 0;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final gen = ++_gen;
    setState(() {
      _loading = _items.isEmpty;
      _loadingMore = false;
      _error = null;
    });
    try {
      final page = await ref.read(groupsRepositoryProvider).invitationsPage();
      if (!mounted || gen != _gen) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _next = page.nextCursor;
        _total = page.total;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onLoaded?.call());
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// The next page, if there is one and none is loading.
  Future<void> loadMore() async {
    final cursor = _next;
    if (cursor == null || _loading || _loadingMore) return;
    final gen = _gen;
    setState(() => _loadingMore = true);
    try {
      final page =
          await ref.read(groupsRepositoryProvider).invitationsPage(cursor: cursor);
      if (!mounted || gen != _gen) return;
      setState(() {
        final have = {for (final i in _items) i.id};
        _items.addAll(page.items.where((i) => !have.contains(i.id)));
        _next = page.nextCursor;
        _total = page.total;
        _loadingMore = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onLoaded?.call());
    } catch (_) {
      if (mounted && gen == _gen) setState(() => _loadingMore = false);
    }
  }

  Future<void> _answer(GroupInvitation inv, bool accept) async {
    setState(() => _busyId = inv.id);
    final ok = await respondToInvitation(context, inv, accept);
    if (!mounted) return;
    setState(() {
      _busyId = null;
      if (ok) {
        _items.removeWhere((i) => i.id == inv.id);
        if (_total > 0) _total--;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // A new invitation (count changed: notification, resume) → fresh list.
    ref.listen<AsyncValue<int>>(groupInvitationCountProvider, (prev, next) {
      final a = prev?.valueOrNull, b = next.valueOrNull;
      if (b != null && a != null && a != b && b != _total) reload();
    });

    final intro = Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: p.accentTint, borderRadius: BorderRadius.circular(18)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.mail_outline_rounded, size: 20, color: p.greenText),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            "Invitations come from group admins who'd like you in their group. "
            "Accept to become a member — you'll see their events, can RSVP and "
            "check in, and get their announcements. Decline and it goes away; "
            "they can always invite you again. Not sure? Tap a group to look "
            "around first.",
            style: TextStyle(color: p.ink, fontSize: 12.5, height: 1.45),
          ),
        ),
      ]),
    );

    Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null && _items.isEmpty) {
      body = Column(children: [
        Text('Could not load your invitations.',
            style: TextStyle(color: p.muted)),
        TextButton(onPressed: reload, child: const Text('Try again')),
      ]);
    } else if (_items.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(children: [
          Icon(Icons.drafts_outlined, size: 34, color: p.muted),
          const SizedBox(height: 8),
          Text('No invitations',
              style: TextStyle(
                  color: p.ink, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('When a group admin invites you, it shows up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 13)),
        ]),
      );
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('$_total waiting',
              style: TextStyle(
                  color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        for (final inv in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _InvitationRow(
              inv: inv,
              busy: _busyId == inv.id,
              locked: _busyId != null,
              onAnswer: (accept) => _answer(inv, accept),
            ),
          ),
        if (_loadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
      ]);
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [intro, body]);
  }
}

class _InvitationRow extends StatelessWidget {
  const _InvitationRow({
    required this.inv,
    required this.busy,
    required this.locked,
    required this.onAnswer,
  });
  final GroupInvitation inv;
  final bool busy;
  final bool locked;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final when = inv.invitedAt != null ? timeAgo(inv.invitedAt) : '';
    final sub = [
      inv.inviterName != null ? 'Invited by ${inv.inviterName}' : 'Invited you to join',
      if (when.isNotEmpty) when,
      if (inv.memberCount != null)
        '${inv.memberCount} member${inv.memberCount == 1 ? '' : 's'}',
    ].join(' · ');
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      onTap: () => context.push('/groups/${inv.groupId}'),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child:
              Crest(logoUrl: inv.groupImageUrl, label: inv.groupName, size: 44),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(inv.groupName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
              if (inv.verified) ...[
                const SizedBox(width: 4),
                const VerifiedBadge(size: 15),
              ],
            ]),
            Text(sub,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 12)),
          ]),
        ),
        const SizedBox(width: 8),
        if (busy)
          const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2))
        else ...[
          _RoundAction(
            icon: Icons.check_rounded,
            tooltip: 'Accept',
            bg: p.accentDeep,
            fg: Colors.white,
            onTap: locked ? null : () => onAnswer(true),
          ),
          const SizedBox(width: 6),
          _RoundAction(
            icon: Icons.close_rounded,
            tooltip: 'Decline',
            bg: p.liveTint,
            fg: p.danger,
            onTap: locked ? null : () => onAnswer(false),
          ),
        ],
      ]),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.tooltip,
    required this.bg,
    required this.fg,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final Color bg;
  final Color fg;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: onTap == null ? bg.withAlpha(120) : bg,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
                width: 38, height: 38, child: Icon(icon, size: 19, color: fg)),
          ),
        ),
      );
}

/// On an invited group's page: "X invited you to join" with Accept /
/// Decline. Nothing when there's no pending invitation for this group.
class GroupInviteBanner extends ConsumerStatefulWidget {
  const GroupInviteBanner({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<GroupInviteBanner> createState() => _GroupInviteBannerState();
}

class _GroupInviteBannerState extends ConsumerState<GroupInviteBanner> {
  /// The answer being sent (true = accept), or null.
  bool? _sending;
  bool get _busy => _sending != null;

  Future<void> _go(GroupInvitation inv, bool accept) async {
    setState(() => _sending = accept);
    await respondToInvitation(context, inv, accept);
    if (mounted) setState(() => _sending = null);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final inv = ref.watch(groupInviteForProvider(widget.groupId)).valueOrNull;
    if (inv == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.accentTint,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.mail_outline_rounded, size: 18, color: p.greenText),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  inv.inviterName != null
                      ? '${inv.inviterName} invited you to join ${inv.groupName}'
                      : "You've been invited to join ${inv.groupName}",
                  style: TextStyle(
                      color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: SpButton(
                label: _sending == true ? 'Joining…' : 'Accept',
                icon: Icons.check_rounded,
                tone: SpButtonTone.brand,
                expand: true,
                onTap: _busy ? null : () => _go(inv, true),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _busy ? null : () => _go(inv, false),
              child: Text('Decline',
                  style: TextStyle(color: p.danger, fontWeight: FontWeight.w700)),
            ),
          ]),
        ]),
      ),
    );
  }
}
