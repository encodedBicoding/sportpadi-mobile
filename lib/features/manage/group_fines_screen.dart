import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/groups/group_admin_repository.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart';
import 'package:sportpadi_mobile/data/groups/member_models.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart' show formatMoney;
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Fines, for group admins — the web page (`/groups/:id/fines`).
///
/// A fine is a real-world penalty the group collects (missed match, late
/// arrival), paid through the web checkout like a ticket, so it belongs on
/// the app on both stores. This screen is the issuing side: the list of
/// fines with who, what, how much and its state, a Pardon for the ones still
/// open, and an "Issue a fine" sheet that asks the web form's three
/// questions — name, amount in the wallet currency, who.
class GroupFinesScreen extends ConsumerStatefulWidget {
  const GroupFinesScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<GroupFinesScreen> createState() => _GroupFinesScreenState();
}

class _GroupFinesScreenState extends ConsumerState<GroupFinesScreen> {
  String? _pardoning;

  void _refetch() => ref.invalidate(groupFinesProvider(widget.groupId));

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _pardon(GroupFine f) async {
    setState(() => _pardoning = f.id);
    try {
      await ref.read(groupAdminRepositoryProvider).pardonFine(widget.groupId, f.id);
      _refetch();
      _snack('Fine pardoned');
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _pardoning = null);
    }
  }

  Future<void> _issue() async {
    final wallet = ref.read(groupWalletProvider(widget.groupId)).valueOrNull;
    final issued = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _IssueFineSheet(
        groupId: widget.groupId,
        currency: wallet?.currency ?? '',
      ),
    );
    if (issued != null && issued > 0) {
      _refetch();
      _snack('Issued $issued fine${issued == 1 ? '' : 's'}.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final data = ref.watch(groupFinesProvider(widget.groupId));
    final canUse = data.valueOrNull?.canUse ?? false;

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('Fines'),
      ),
      floatingActionButton: canUse
          ? FloatingActionButton.extended(
              onPressed: _issue,
              icon: const Icon(Icons.gavel_rounded),
              label: const Text('Issue a fine'),
            )
          : null,
      body: AsyncView<GroupFines>(
        value: data,
        onRetry: _refetch,
        data: (d) => RefreshIndicator(
          onRefresh: () async => _refetch(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              if (!d.canUse)
                GlassCard(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.lock_outline_rounded, color: p.amber, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Fines need the wallet feature.',
                            style: TextStyle(
                                color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                            'Fines are collected into the group wallet, so they come '
                            'with the plans that include it.',
                            style: TextStyle(color: p.muted, fontSize: 12)),
                      ]),
                    ),
                  ]),
                )
              else ...[
                Text('ALL FINES',
                    style: TextStyle(
                        color: p.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2)),
                const SizedBox(height: 8),
                if (d.fines.isEmpty)
                  GlassCard(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text('No fines issued yet. Tap “Issue a fine” to add one.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.muted, fontSize: 13)),
                    ),
                  )
                else
                  for (final f in d.fines) ...[
                    _FineRow(
                      fine: f,
                      busy: _pardoning == f.id,
                      onPardon: () => _pardon(f),
                      onTap: () => context.push('/players/${f.userId}'),
                    ),
                    const SizedBox(height: 8),
                  ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FineRow extends StatelessWidget {
  const _FineRow({
    required this.fine,
    required this.busy,
    required this.onPardon,
    required this.onTap,
  });
  final GroupFine fine;
  final bool busy;
  final VoidCallback onPardon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final f = fine;
    final name = f.userName ?? 'User';
    return GlassCard(
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: p.surface2,
          backgroundImage: f.userAvatarUrl != null ? NetworkImage(f.userAvatarUrl!) : null,
          child: f.userAvatarUrl == null
              ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(color: p.muted, fontSize: 13))
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: onTap,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w600)),
              Text(
                '${f.title} · ${formatMoney(f.amountMinor, f.currency, f.currencyExponent)}'
                '${f.createdAt != null ? ' · ${timeAgo(f.createdAt)}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 11.5),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        if (f.status == 'paid')
          SpBadge('Paid', tone: p.accent)
        else if (f.status == 'pardoned')
          SpBadge('Pardoned', tone: p.muted)
        else
          OutlinedButton.icon(
            onPressed: busy ? null : onPardon,
            style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 32)),
            icon: busy
                ? const SizedBox(
                    width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.verified_user_outlined, size: 14),
            label: const Text('Pardon', style: TextStyle(fontSize: 12)),
          ),
      ]),
    );
  }
}

/// The web's issue-a-fine dialog: name, amount (wallet currency), who —
/// search the platform and pick one or many.
class _IssueFineSheet extends ConsumerStatefulWidget {
  const _IssueFineSheet({required this.groupId, required this.currency});
  final String groupId;
  final String currency;

  @override
  ConsumerState<_IssueFineSheet> createState() => _IssueFineSheetState();
}

class _IssueFineSheetState extends ConsumerState<_IssueFineSheet> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _search = TextEditingController();
  final Map<String, GroupMemberItem> _picked = {};
  List<GroupMemberItem> _results = const [];
  Timer? _debounce;
  bool _searching = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _title.dispose();
    _amount.dispose();
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

  Future<void> _submit() async {
    final title = _title.text.trim();
    final amount = double.tryParse(_amount.text.trim());
    if (title.isEmpty) {
      setState(() => _error = 'Give the fine a name.');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    if (_picked.isEmpty) {
      setState(() => _error = 'Pick at least one person to fine.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final n = await ref.read(groupAdminRepositoryProvider).issueFine(
            widget.groupId,
            userIds: _picked.keys.toList(),
            title: title,
            amount: amount,
          );
      if (mounted) Navigator.pop(context, n);
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
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85 - bottom,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(children: [
              Icon(Icons.gavel_rounded, size: 18, color: p.accent),
              const SizedBox(width: 8),
              Text('Issue a fine',
                  style:
                      TextStyle(color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              children: [
                Text('Fine name',
                    style: TextStyle(
                        color: p.ink, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration:
                      const InputDecoration(hintText: 'e.g. Missed match, Late arrival'),
                ),
                const SizedBox(height: 14),
                Text('Amount (wallet currency)',
                    style: TextStyle(
                        color: p.ink, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    prefixText: widget.currency.isEmpty ? null : '${widget.currency} ',
                  ),
                ),
                const SizedBox(height: 14),
                Text('Who to fine${_picked.isEmpty ? '' : ' (${_picked.length})'}',
                    style: TextStyle(
                        color: p.ink, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                if (_picked.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final u in _picked.values)
                        InputChip(
                          label: Text(u.displayName),
                          avatar: u.avatarUrl != null
                              ? CircleAvatar(backgroundImage: NetworkImage(u.avatarUrl!))
                              : null,
                          onDeleted: () => setState(() => _picked.remove(u.userId)),
                        ),
                    ]),
                  ),
                TextField(
                  controller: _search,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search users by name or @username',
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
                for (final u in _results)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: p.surface2,
                      backgroundImage:
                          u.avatarUrl != null ? NetworkImage(u.avatarUrl!) : null,
                      child: u.avatarUrl == null
                          ? Text(u.displayName.isNotEmpty ? u.displayName[0] : '?',
                              style: TextStyle(color: p.muted, fontSize: 12))
                          : null,
                    ),
                    title: Text(u.displayName, style: TextStyle(color: p.ink, fontSize: 14)),
                    subtitle: u.username != null
                        ? Text('@${u.username}', style: TextStyle(color: p.muted, fontSize: 12))
                        : null,
                    trailing: Icon(
                      _picked.containsKey(u.userId)
                          ? Icons.check_circle_rounded
                          : Icons.add_circle_outline_rounded,
                      color: _picked.containsKey(u.userId) ? p.accent : p.muted,
                    ),
                    onTap: () => setState(() {
                      if (_picked.containsKey(u.userId)) {
                        _picked.remove(u.userId);
                      } else {
                        _picked[u.userId] = u;
                      }
                    }),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: p.danger, fontSize: 13)),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(
                20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_picked.length > 1
                          ? 'Issue ${_picked.length} fines'
                          : 'Issue fine'),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
