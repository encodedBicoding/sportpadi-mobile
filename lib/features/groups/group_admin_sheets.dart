import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/groups/group_admin_repository.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart';
import 'package:sportpadi_mobile/data/groups/member_models.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Transfer group ownership — the web dialog.
///
/// The owner searches the platform for a person, picks them, then confirms,
/// handing over the creator flag. The current owner stays on as an admin.
Future<void> showTransferOwnershipSheet(BuildContext context, String groupId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TransferOwnershipSheet(groupId: groupId),
  );
}

class _TransferOwnershipSheet extends ConsumerStatefulWidget {
  const _TransferOwnershipSheet({required this.groupId});
  final String groupId;

  @override
  ConsumerState<_TransferOwnershipSheet> createState() => _TransferOwnershipSheetState();
}

class _TransferOwnershipSheetState extends ConsumerState<_TransferOwnershipSheet> {
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
        final rows = await ref.read(groupsRepositoryProvider).searchUsers(query);
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
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true), child: const Text('Transfer')),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${who.displayName} now owns this group.')));
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
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.swap_horiz_rounded, size: 18, color: p.accent),
          const SizedBox(width: 8),
          Text('Transfer ownership',
              style: TextStyle(color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 4),
        Text('Hand this group to someone else. You stay on as an admin.',
            style: TextStyle(color: p.muted, fontSize: 12.5)),
        const SizedBox(height: 14),
        if (_selected != null)
          GlassCard(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: p.surface2,
                backgroundImage:
                    _selected!.avatarUrl != null ? NetworkImage(_selected!.avatarUrl!) : null,
                child: _selected!.avatarUrl == null
                    ? Text(_selected!.displayName.isNotEmpty ? _selected!.displayName[0] : '?')
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_selected!.displayName,
                      style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
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
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
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
                      backgroundImage: u.avatarUrl != null ? NetworkImage(u.avatarUrl!) : null,
                      child: u.avatarUrl == null
                          ? Text(u.displayName.isNotEmpty ? u.displayName[0] : '?',
                              style: TextStyle(color: p.muted, fontSize: 12))
                          : null,
                    ),
                    title: Text(u.displayName, style: TextStyle(color: p.ink, fontSize: 14)),
                    subtitle: u.username != null
                        ? Text('@${u.username}', style: TextStyle(color: p.muted, fontSize: 12))
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
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _selected == null || _busy ? null : _confirm,
          child: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_selected == null
                  ? 'Pick the new owner'
                  : 'Transfer to ${_selected!.displayName.split(' ').first}'),
        ),
      ]),
    );
  }
}

/// Promo codes — the web dialog: the codes this group has redeemed, and a
/// field to apply another.
///
/// Android only. A code that unlocks paid features outside the App Store is
/// exactly what Apple's 3.1.1 forbids, so the iOS menu doesn't offer it.
Future<void> showPromoCodesSheet(BuildContext context, String groupId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
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
      final promo =
          await ref.read(groupAdminRepositoryProvider).redeemPromo(widget.groupId, code);
      _code.clear();
      ref.invalidate(groupPromosProvider(widget.groupId));
      ref.invalidate(groupOverviewProvider(widget.groupId));
      if (!mounted) return;
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

  String _day(DateTime? d) => d == null ? '—' : DateFormat('d MMM yyyy').format(d.toLocal());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final promos = ref.watch(groupPromosProvider(widget.groupId));
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.confirmation_number_outlined, size: 18, color: p.accent),
          const SizedBox(width: 8),
          Text('Promo codes',
              style: TextStyle(color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 4),
        Text('Got a code from SportPadi? Apply it to this group.',
            style: TextStyle(color: p.muted, fontSize: 12.5)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              onSubmitted: (_) => _redeem(),
              decoration: const InputDecoration(hintText: 'Enter code'),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: _busy ? null : _redeem,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Apply'),
          ),
        ]),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: p.danger, fontSize: 13)),
        ],
        const SizedBox(height: 16),
        Text('APPLIED TO THIS GROUP',
            style: TextStyle(
                color: p.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        promos.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
                child: SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
          error: (e, _) => Text('$e', style: TextStyle(color: p.muted, fontSize: 12.5)),
          data: (list) => list.isEmpty
              ? Text('No codes applied yet.', style: TextStyle(color: p.muted, fontSize: 13))
              : Column(children: [
                  for (final pr in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: GlassCard(
                        padding: const EdgeInsets.all(10),
                        child: Row(children: [
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
                                        style: TextStyle(color: p.muted, fontSize: 12)),
                                  Text(
                                    '${_day(pr.startsAt)} – ${_day(pr.endsAt)}',
                                    style: TextStyle(color: p.muted, fontSize: 11),
                                  ),
                                ]),
                          ),
                          SpBadge(pr.active ? 'Active' : 'Ended',
                              tone: pr.active ? p.accent : p.muted),
                        ]),
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }
}
