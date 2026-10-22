import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/groups/group_admin_repository.dart';
import 'package:sportpadi_mobile/data/wallet/fee_terms.dart';
import 'package:sportpadi_mobile/data/wallet/wallet_repository.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart';
import 'package:sportpadi_mobile/data/groups/member_models.dart';
import 'package:sportpadi_mobile/data/teams/teams_repository.dart'
    show teamAllowanceProvider;
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/features/groups/pro_offer.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Transfer group ownership — the web dialog.
///
/// The owner searches the platform for a person, picks them, then confirms,
/// handing over the creator flag. The current owner stays on as an admin.
Future<void> showTransferOwnershipSheet(BuildContext context, String groupId) {
  return showSpSheet<void>(
    context,
    builder: (_) => _TransferOwnershipSheet(groupId: groupId),
  );
}

class _TransferOwnershipSheet extends ConsumerStatefulWidget {
  const _TransferOwnershipSheet({required this.groupId});
  final String groupId;

  @override
  ConsumerState<_TransferOwnershipSheet> createState() =>
      _TransferOwnershipSheetState();
}

class _TransferOwnershipSheetState
    extends ConsumerState<_TransferOwnershipSheet> {
  final _search = TextEditingController();
  List<GroupMemberItem> _results = const [];
  GroupMemberItem? _selected;
  Timer? _debounce;
  bool _searching = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    final query = q.trim();
    if (query.length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searching = true);
      try {
        final rows =
            await ref.read(groupsRepositoryProvider).searchUsers(query);
        if (mounted) setState(() => _results = rows);
      } catch (_) {
        if (mounted) setState(() => _results = const []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _confirm() async {
    final who = _selected;
    if (who == null) return;
    final group = ref.read(groupProvider(widget.groupId)).valueOrNull;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Transfer ownership?'),
        content: Text(
            '${who.displayName} will become the owner of ${group?.name ?? 'this group'}. '
            'You\'ll stay on as an admin, but only they can transfer it again or '
            'delete the group.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Transfer')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(groupAdminRepositoryProvider)
          .transferOwnership(widget.groupId, who.userId);
      ref.invalidate(groupProvider(widget.groupId));
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${who.displayName} now owns this group.')));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SpSheetHeader(
            icon: Icons.swap_horiz_rounded,
            title: 'Transfer ownership',
            subtitle:
                'Hand this group to someone else. You stay on as an admin.',
          ),
          if (_selected != null)
            GlassCard(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: p.surface2,
                  backgroundImage: _selected!.avatarUrl != null
                      ? NetworkImage(_selected!.avatarUrl!)
                      : null,
                  child: _selected!.avatarUrl == null
                      ? Text(_selected!.displayName.isNotEmpty
                          ? _selected!.displayName[0]
                          : '?')
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_selected!.displayName,
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                        if (_selected!.username != null)
                          Text('@${_selected!.username}',
                              style: TextStyle(color: p.muted, fontSize: 12)),
                      ]),
                ),
                IconButton(
                  onPressed: () => setState(() => _selected = null),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ]),
            )
          else ...[
            TextField(
              controller: _search,
              autofocus: true,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by name or @username',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final u in _results)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: p.surface2,
                        backgroundImage: u.avatarUrl != null
                            ? NetworkImage(u.avatarUrl!)
                            : null,
                        child: u.avatarUrl == null
                            ? Text(
                                u.displayName.isNotEmpty
                                    ? u.displayName[0]
                                    : '?',
                                style: TextStyle(color: p.muted, fontSize: 12))
                            : null,
                      ),
                      title: Text(u.displayName,
                          style: TextStyle(color: p.ink, fontSize: 14)),
                      subtitle: u.username != null
                          ? Text('@${u.username}',
                              style: TextStyle(color: p.muted, fontSize: 12))
                          : null,
                      onTap: () => setState(() => _selected = u),
                    ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: p.danger, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          SpButton(
            expand: true,
            label: _busy
                ? 'Transferring…'
                : _selected == null
                    ? 'Pick the new owner'
                    : 'Transfer to ${_selected!.displayName.split(' ').first}',
            onTap: _selected == null || _busy ? null : _confirm,
          ),
        ]);
  }
}

/// Promo codes — the web dialog: the codes this group has redeemed, and a
/// field to apply another.
///
/// Android only. A code that unlocks paid features outside the App Store is
/// exactly what Apple's 3.1.1 forbids, so the iOS menu doesn't offer it.
Future<void> showPromoCodesSheet(BuildContext context, String groupId) {
  return showSpSheet<void>(
    context,
    builder: (_) => _PromoCodesSheet(groupId: groupId),
  );
}

class _PromoCodesSheet extends ConsumerStatefulWidget {
  const _PromoCodesSheet({required this.groupId});
  final String groupId;

  @override
  ConsumerState<_PromoCodesSheet> createState() => _PromoCodesSheetState();
}

class _PromoCodesSheetState extends ConsumerState<_PromoCodesSheet> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  // When a code just gave the group a wallet, say what its payments cost —
  // the fee follows the plan, not the promo.
  GroupPromo? _unlocked;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final promo = await ref
          .read(groupAdminRepositoryProvider)
          .redeemPromo(widget.groupId, code);
      _code.clear();
      ref.invalidate(groupPromosProvider(widget.groupId));
      ref.invalidate(groupOverviewProvider(widget.groupId));
      // A code can unlock team building — refresh what the Teams tab offers.
      ref.invalidate(teamAllowanceProvider(widget.groupId));
      if (!mounted) return;
      if (promo.walletUnlocked && promo.feeNetBps != null) {
        setState(() => _unlocked = promo);
        ref.invalidate(feeTermsProvider(widget.groupId));
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(promo.active
              ? 'Code ${promo.code} applied.'
              : 'Code ${promo.code} saved — it starts on ${_day(promo.startsAt)}.')));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _day(DateTime? d) =>
      d == null ? '—' : DateFormat('d MMM yyyy').format(d.toLocal());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final promos = ref.watch(groupPromosProvider(widget.groupId));
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SpSheetHeader(
            icon: Icons.confirmation_number_outlined,
            title: 'Promo codes',
            subtitle: 'Got a code from SportPadi? Apply it to this group.',
          ),
          // The Free plan's "Try Pro features for free" (Android; renders
          // nothing when there's no offer for this group).
          _OfferAbove(groupId: widget.groupId),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _redeem(),
            style: TextStyle(
                color: p.ink, fontWeight: FontWeight.w700, letterSpacing: 1),
            decoration: const InputDecoration(
              hintText: 'Enter code',
              prefixIcon: Icon(Icons.local_offer_outlined, size: 20),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: p.danger, fontSize: 13)),
          ],
          const SizedBox(height: 12),
          SpButton(
            expand: true,
            tone: SpButtonTone.brand,
            icon: Icons.check_rounded,
            label: _busy ? 'Applying…' : 'Apply code',
            onTap: _busy ? null : _redeem,
          ),
          if (_unlocked != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: p.accentTint, borderRadius: BorderRadius.circular(16)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('You can now collect payments.',
                        style: TextStyle(
                            color: p.ink, fontWeight: FontWeight.w800, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                      'On the ${_unlocked!.feeTierName ?? 'current'} plan, SportPadi keeps ${feePhrase(_unlocked!.feeNetBps!)} of each payment '
                      '(${feeSourcePhrase(_unlocked!.feeSource ?? 'default', _unlocked!.feeTierName)}). The fee follows your plan, not the promo code — '
                      'every payment shows it, and your wallet statement adds it up each month.',
                      style: TextStyle(color: p.ink, fontSize: 12.5, height: 1.4),
                    ),
                  ]),
            ),
          ],
          const SizedBox(height: 22),
          const Eyebrow('Applied to this group'),
          const SizedBox(height: 8),
          promos.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            ),
            error: (e, _) =>
                Text('$e', style: TextStyle(color: p.muted, fontSize: 12.5)),
            data: (list) => list.isEmpty
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 16),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: p.line),
                    ),
                    child: Row(children: [
                      const SpIconTile(Icons.confirmation_number_outlined,
                          size: 36, iconSize: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('No codes applied yet.',
                            style: TextStyle(color: p.muted, fontSize: 13)),
                      ),
                    ]),
                  )
                : SpListCard(children: [
                    for (final pr in list)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 12),
                        child: Row(children: [
                          SpIconTile(Icons.confirmation_number_outlined,
                              size: 36,
                              iconSize: 18,
                              bg: pr.active ? p.accentTint : p.surface2,
                              fg: pr.active ? p.greenText : p.muted),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(pr.code,
                                      style: TextStyle(
                                          color: p.ink,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5)),
                                  if (pr.description != null)
                                    Text(pr.description!,
                                        style: TextStyle(
                                            color: p.muted, fontSize: 12)),
                                  Text(
                                      pr.active && pr.renewsOn != null
                                          ? 'Renews ${_day(pr.renewsOn)}'
                                          : pr.autoRenew
                                              ? 'From ${_day(pr.startsAt)} · auto-renews'
                                              : '${_day(pr.startsAt)} – ${_day(pr.endsAt)}',
                                      style: TextStyle(
                                          color: p.muted, fontSize: 11)),
                                ]),
                          ),
                          SpBadge(
                              pr.active
                                  ? 'Active'
                                  : pr.optedOut
                                      ? 'Opted out'
                                      : 'Ended',
                              tone: pr.active
                                  ? p.greenText
                                  : pr.optedOut
                                      ? p.orangeInk
                                      : p.muted),
                        ]),
                      ),
                  ]),
          ),
        ]);
  }
}


/// "Leave group" — any member but the owner (who hands the group over
/// first; [showTransferOwnershipSheet]). Confirms, leaves, refreshes the
/// group and the user's group list. Returns true when they left.
Future<bool> confirmLeaveGroup(
    BuildContext context, WidgetRef ref, String groupId, String groupName) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Leave $groupName?'),
      content: const Text(
          "You'll come off its teams and stop getting its updates. Your past games, stats and XP stay on your profile. To come back, you'll need an invite or the group's join link."),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Leave group'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final wards = await ref.read(groupAdminRepositoryProvider).leave(groupId);
    ref.invalidate(groupProvider(groupId));
    ref.invalidate(myGroupsProvider);
    messenger.showSnackBar(SnackBar(
        content: Text(wards > 0
            ? "You've left $groupName — $wards ${wards == 1 ? 'ward' : 'wards'} who joined with you left too."
            : "You've left $groupName.")));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
    return false;
  }
}


/// The offer card above the code field, with its own spacing (nothing when
/// there's no offer for the group).
class _OfferAbove extends ConsumerWidget {
  const _OfferAbove({required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!proOfferAllowedHere) return const SizedBox.shrink();
    final o = ref.watch(freeOfferProvider(groupId)).valueOrNull;
    if (o == null) return const SizedBox.shrink();
    final name = ref.watch(groupProvider(groupId)).valueOrNull?.name ?? 'your group';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ProOfferCard(groupId: groupId, groupName: name),
    );
  }
}

/// The offer on its own sheet (from the group's manage menu).
Future<void> showProOfferSheet(BuildContext context, String groupId, String groupName) {
  return showSpSheet<void>(
    context,
    builder: (_) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 4),
      ProOfferCard(groupId: groupId, groupName: groupName),
    ]),
  );
}
