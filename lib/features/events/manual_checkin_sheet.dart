import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/manage/manage_models.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// "Check someone in" (organisers) — the web event page's dialog. Mostly for
/// ANOTHER organiser, who can't scan their own event's QR, and for players
/// without a phone. Nobody checks themselves in (the server refuses), so the
/// caller's own row says who has to do it instead.
Future<void> showManualCheckInSheet(BuildContext context,
    {required String eventId, VoidCallback? onChanged}) async {
  await showSpSheet<void>(
    context,
    builder: (_) => _ManualCheckInSheet(eventId: eventId, onChanged: onChanged),
  );
}

class _ManualCheckInSheet extends ConsumerStatefulWidget {
  const _ManualCheckInSheet({required this.eventId, this.onChanged});
  final String eventId;
  // Refreshes the event page under the sheet after each check-in.
  final VoidCallback? onChanged;

  @override
  ConsumerState<_ManualCheckInSheet> createState() =>
      _ManualCheckInSheetState();
}

class _ManualCheckInSheetState extends ConsumerState<_ManualCheckInSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<CheckInCandidate>? _people;
  String? _loadError;
  String? _error;
  String? _pending;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    try {
      final list = await ref
          .read(manageRepositoryProvider)
          .checkInCandidates(widget.eventId, q: _search.text);
      if (!mounted || seq != _seq) return;
      setState(() {
        _people = list;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => _loadError = e is ApiException ? e.message : '$e');
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _load);
    setState(() {});
  }

  Future<void> _checkIn(CheckInCandidate c) async {
    if (_pending != null) return;
    setState(() {
      _pending = c.userId;
      _error = null;
    });
    try {
      await ref.read(manageRepositoryProvider).checkIn(widget.eventId, c.userId);
      if (!mounted) return;
      widget.onChanged?.call();
      setState(() {
        _pending = null;
        _people = [
          for (final x in _people ?? const <CheckInCandidate>[])
            x.userId == c.userId ? x.copyWith(checkedIn: true) : x,
        ];
      });
    } catch (e) {
      // e.g. an unpaid ticket or a fine — say so and stay open.
      if (mounted) {
        setState(() {
          _pending = null;
          _error = e is ApiException ? e.message : '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final people = _people;
    final q = _search.text.trim();
    final organisers = [
      for (final x in people ?? const <CheckInCandidate>[])
        if (x.isOrganiser) x
    ];
    final others = [
      for (final x in people ?? const <CheckInCandidate>[])
        if (!x.isOrganiser) x
    ];

    Widget label(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
          child: Text(text.toUpperCase(),
              style: TextStyle(
                  color: p.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6)),
        );

    return PopScope(
      // No closing mid-request: the check-in would land unconfirmed.
      canPop: _pending == null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpSheetHeader(
            icon: Icons.how_to_reg_outlined,
            title: 'Check someone in',
            subtitle: 'For anyone without a phone.',
            trailing: TextButton(
              onPressed: _pending == null
                  ? () => Navigator.of(context).pop()
                  : null,
              child: const Text('Done'),
            ),
          ),
          const SpTipCard(
            "Nobody checks themselves in here. Organisers check in by scanning another admin's QR, or another admin checks them in from this list.",
            icon: Icons.verified_user_outlined,
          ),
          const SizedBox(height: 10),
          SpSearchCard(
            controller: _search,
            hint: 'Search members',
            onChanged: _onSearch,
            onClear: () {
              _search.clear();
              _onSearch('');
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: TextStyle(
                    color: p.danger,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 12),
          if (people == null && _loadError == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (people == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(children: [
                Text(_loadError!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.muted, fontSize: 13)),
                const SizedBox(height: 8),
                TextButton(onPressed: _load, child: const Text('Try again')),
              ]),
            )
          else if (people.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                  q.isEmpty
                      ? 'No one to check in yet.'
                      : 'No one matches “$q”.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.muted, fontSize: 13.5)),
            )
          else ...[
            if (organisers.isNotEmpty) ...[
              label('Organisers'),
              SpListCard(children: [for (final c in organisers) _row(c)]),
              const SizedBox(height: 12),
            ],
            if (others.isNotEmpty) ...[
              label(q.isEmpty ? 'RSVPs & members' : 'Members'),
              SpListCard(children: [for (final c in others) _row(c)]),
            ],
          ],
        ],
      ),
    );
  }

  Widget _row(CheckInCandidate c) {
    final p = context.palette;
    final sub = c.isMe
        ? "Scan another admin's QR to check in"
        : c.isCreator
            ? 'Created this event'
            : c.isOrganiser
            ? 'Organiser'
            : c.rsvp
                ? 'RSVP’d'
                : 'Member';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      child: Row(children: [
        PersonAvatar(url: c.avatarUrl, name: c.displayName, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(c.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ),
                if (c.isWard) ...[
                  const SizedBox(width: 6),
                  const WardBadge(),
                ],
                if (c.isMe) ...[
                  const SizedBox(width: 6),
                  Text('You',
                      style: TextStyle(
                          color: p.greenText,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ],
              ]),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (c.checkedIn)
          SpBadge('In', icon: Icons.check_rounded, tone: p.greenText)
        else if (!c.isMe)
          _pending == c.userId
              ? const SizedBox(
                  width: 38,
                  height: 38,
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : SpPill(
                  label: 'Check in',
                  onTap: _pending == null ? () => _checkIn(c) : null,
                ),
      ]),
    );
  }
}
