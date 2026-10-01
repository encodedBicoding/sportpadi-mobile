import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/groups/group_admin_repository.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart';
import 'package:sportpadi_mobile/data/groups/member_models.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart'
    show formatMoney;
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart'
    show groupProvider;
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';

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
  String _filter = 'active'; // active | paid | pardoned

  void _refetch() => ref.invalidate(groupFinesProvider(widget.groupId));

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _pardon(GroupFine f) async {
    setState(() => _pardoning = f.id);
    try {
      await ref
          .read(groupAdminRepositoryProvider)
          .pardonFine(widget.groupId, f.id);
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
    final issued = await showSpSheet<int>(
      context,
      scrollable: false,
      padding: EdgeInsets.zero,
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
    final groupName =
        ref.watch(groupProvider(widget.groupId)).valueOrNull?.name;

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SpHeader(title: 'Fines', subtitle: groupName),
          ),
          Expanded(
            child: AsyncView<GroupFines>(
              value: data,
              onRetry: _refetch,
              data: (d) {
                final all = d.fines;
                int count(String s) => all.where((f) => f.status == s).length;
                final open = all.where((f) => f.status == 'active').toList();
                final currencies = open.map((f) => f.currency).toSet();
                final owed = open.isEmpty
                    ? null
                    : currencies.length == 1
                        ? formatMoney(
                            open.fold<int>(0, (a, f) => a + f.amountMinor),
                            open.first.currency,
                            open.first.currencyExponent)
                        : '${open.length} unpaid';
                final shown = all.where((f) => f.status == _filter).toList();

                Widget chip(String key, String label, int n) {
                  final active = _filter == key;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Material(
                      color: active ? p.hero : p.surface,
                      shape: StadiumBorder(
                          side: active
                              ? BorderSide.none
                              : BorderSide(color: p.line)),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: () => setState(() => _filter = key),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          child: Text(n > 0 ? '$label · $n' : label,
                              style: TextStyle(
                                  color: active ? p.onHero : p.ink,
                                  fontSize: 12.5,
                                  fontWeight: active
                                      ? FontWeight.w700
                                      : FontWeight.w600)),
                        ),
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => _refetch(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                    children: [
                      if (!d.canUse)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: p.orangeTint,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SpIconTile(Icons.lock_outline_rounded,
                                    bg: p.surface, fg: p.orangeInk, size: 40),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Fines need the wallet feature',
                                            style: TextStyle(
                                                color: p.ink,
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 2),
                                        Text(
                                            'Fines are collected into the group wallet, so they come '
                                            'with the plans that include it.',
                                            style: TextStyle(
                                                color: p.orangeInk,
                                                fontSize: 12.5,
                                                height: 1.4)),
                                      ]),
                                ),
                              ]),
                        )
                      else ...[
                        // Summary + the main action.
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: p.hero,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Outstanding',
                                    style: TextStyle(
                                        color: p.heroMuted, fontSize: 12.5)),
                                const SizedBox(height: 2),
                                Text(owed ?? 'Nothing owed',
                                    style: TextStyle(
                                        color: p.onHero,
                                        fontSize: 28,
                                        letterSpacing: -0.5,
                                        fontWeight: FontWeight.w800)),
                                const SizedBox(height: 12),
                                Row(children: [
                                  _heroStat(p, '${count('active')}', 'Unpaid',
                                      warm: count('active') > 0),
                                  const SizedBox(width: 8),
                                  _heroStat(p, '${count('paid')}', 'Paid'),
                                  const SizedBox(width: 8),
                                  _heroStat(
                                      p, '${count('pardoned')}', 'Pardoned'),
                                ]),
                                const SizedBox(height: 14),
                                Material(
                                  color: Colors.white,
                                  shape: const StadiumBorder(),
                                  child: InkWell(
                                    customBorder: const StadiumBorder(),
                                    onTap: _issue,
                                    child: const SizedBox(
                                      height: 50,
                                      child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.gavel_rounded,
                                                size: 18,
                                                color: Color(0xFF0E1411)),
                                            SizedBox(width: 7),
                                            Text('Issue a fine',
                                                style: TextStyle(
                                                    color: Color(0xFF0E1411),
                                                    fontSize: 14,
                                                    fontWeight:
                                                        FontWeight.w700)),
                                          ]),
                                    ),
                                  ),
                                ),
                              ]),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 38,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              chip('active', 'Unpaid', count('active')),
                              chip('paid', 'Paid', count('paid')),
                              chip('pardoned', 'Pardoned', count('pardoned')),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (shown.isEmpty)
                          GlassCard(
                            padding: const EdgeInsets.all(22),
                            child: Column(children: [
                              const SpIconTile(Icons.inbox_outlined,
                                  size: 50, iconSize: 24),
                              const SizedBox(height: 10),
                              Text(
                                  all.isEmpty
                                      ? 'No fines issued yet.'
                                      : _filter == 'active'
                                          ? 'Nobody owes anything.'
                                          : 'None here.',
                                  textAlign: TextAlign.center,
                                  style:
                                      TextStyle(color: p.muted, fontSize: 13)),
                            ]),
                          )
                        else
                          SpListCard(children: [
                            for (final f in shown)
                              _FineRow(
                                fine: f,
                                busy: _pardoning == f.id,
                                onPardon: () => _pardon(f),
                                onTap: () =>
                                    context.push('/players/${f.userId}'),
                              ),
                          ]),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _heroStat(AppPalette p, String value, String label,
          {bool warm = false}) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: p.onHero.withAlpha(18),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(children: [
            Text(value,
                style: TextStyle(
                    color: warm ? const Color(0xFFFFB57D) : p.onHero,
                    fontSize: 19,
                    fontWeight: FontWeight.w800)),
            Text(label, style: TextStyle(color: p.heroMuted, fontSize: 11)),
          ]),
        ),
      );
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
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        child: Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: p.surface2,
            backgroundImage:
                f.userAvatarUrl != null ? NetworkImage(f.userAvatarUrl!) : null,
            child: f.userAvatarUrl == null
                ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                        color: p.muted,
                        fontSize: 14,
                        fontWeight: FontWeight.w700))
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
              Text(
                '${f.title}${f.createdAt != null ? ' · ${timeAgo(f.createdAt)}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(formatMoney(f.amountMinor, f.currency, f.currencyExponent),
                style: TextStyle(
                    color: p.ink, fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            if (f.status == 'paid')
              Text('PAID',
                  style: TextStyle(
                      color: p.greenText,
                      fontSize: 10.5,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w800))
            else if (f.status == 'pardoned')
              Text('PARDONED',
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 10.5,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w800))
            else
              GestureDetector(
                onTap: busy ? null : onPardon,
                child: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Pardon',
                        style: TextStyle(
                            color: p.greenText,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
              ),
          ]),
        ]),
      ),
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
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Row(children: [
          SpIconTile(Icons.gavel_rounded,
              bg: p.orangeTint, fg: p.orangeInk, size: 40, iconSize: 19),
          const SizedBox(width: 12),
          Text('Issue a fine',
              style: TextStyle(
                  color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
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
              decoration: const InputDecoration(
                  hintText: 'e.g. Missed match, Late arrival'),
            ),
            const SizedBox(height: 14),
            Text('Amount (wallet currency)',
                style: TextStyle(
                    color: p.ink, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: '0.00',
                prefixText:
                    widget.currency.isEmpty ? null : '${widget.currency} ',
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
                          ? CircleAvatar(
                              backgroundImage: NetworkImage(u.avatarUrl!))
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
                title: Text(u.displayName,
                    style: TextStyle(color: p.ink, fontSize: 14)),
                subtitle: u.username != null
                    ? Text('@${u.username}',
                        style: TextStyle(color: p.muted, fontSize: 12))
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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(children: [
          Expanded(
            child: Material(
              color: p.surface,
              shape: StadiumBorder(side: BorderSide(color: p.line)),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: _busy ? null : () => Navigator.pop(context),
                child: SizedBox(
                  height: 48,
                  child: Center(
                    child: Text('Cancel',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: SpButton(
              label: _busy
                  ? 'Issuing…'
                  : _picked.length > 1
                      ? 'Issue ${_picked.length} fines'
                      : 'Issue fine',
              expand: true,
              onTap: _busy ? null : _submit,
            ),
          ),
        ]),
      ),
    ]);
  }
}
