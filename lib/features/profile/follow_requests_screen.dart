import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/players/player_record.dart'
    show listOf;
import 'package:sportpadi_mobile/features/players/profile_header.dart'
    show ProfilePill;
import 'package:sportpadi_mobile/features/players/scout_header.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart' show fmtRelative;
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// /profile/follow-requests — web twin: app/profile/follow-requests/page.tsx
/// (docs/design/scouting-profile.md "Private profiles and follow requests";
/// owner, 2026-11-19: like Instagram). Requests: the people asking to follow
/// my private profile, newest first — Confirm (they become a follower and
/// are told) or Delete (silent). A confirmed row stays with the follow pill
/// ("Follow back", as on Instagram). Sent: my own requests still waiting,
/// each with "Cancel request". The "{name} wants to follow you" notification
/// (`link_resolver.dart`) and the profile menu's row open this screen.
///
/// `GET /api/mobile/me/follow-requests[?which=outgoing][&cursor=]` →
/// `{ items: [{ userId, displayName, username, avatarUrl, requestedAt }],
/// nextCursor, total? }`; actions are `POST /api/mobile/players/:id/follow
/// { action: accept | decline | cancel-request }` — accept AND decline answer
/// 404 when no request waits any more (withdrawn, or handled elsewhere): the
/// row goes, with the server's message.
class FollowRequestsScreen extends ConsumerStatefulWidget {
  const FollowRequestsScreen({super.key});

  @override
  ConsumerState<FollowRequestsScreen> createState() =>
      _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends ConsumerState<FollowRequestsScreen> {
  String _which = 'incoming';
  final _items = <Map<String, dynamic>>[];
  String? _cursor;
  bool _loading = true;
  bool _more = false;

  /// A page is on its way — a second "Show more" waits for it (no duplicate
  /// pages; review LOW).
  bool _paging = false;

  /// The first page failed: the whole list is the error. A LATER page that
  /// failed keeps the list on screen, with [_pageError] and a retry under it.
  String? _error;
  String? _pageError;

  /// Requests waiting for me (the first page's `total`) — the tab's badge.
  int? _total;

  /// What I did to a row, kept here rather than re-read: a confirmed one
  /// stays with its Follow back pill, a deleted / withdrawn one goes. A tab
  /// switch reloads the list, which no longer has the handled rows.
  final _done = <String, String>{};
  String? _busy;

  // Bumped by each reset so an older page still in flight is dropped.
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_paging || !_more)) return;
    final gen = reset ? ++_gen : _gen;
    setState(() {
      _paging = true;
      _pageError = null;
      if (reset) {
        _loading = true;
        _error = null;
        _items.clear();
        _cursor = null;
        _done.clear();
      }
    });
    try {
      final res = await ref.read(dioProvider).get(
          '/api/mobile/me/follow-requests',
          queryParameters: {
            if (_which == 'outgoing') 'which': 'outgoing',
            if (_cursor != null) 'cursor': _cursor,
          });
      final m = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      if (!mounted || gen != _gen) return;
      // One row per person even if two pages overlap (the list moved).
      final have = {for (final u in _items) parseStr(u['userId'])};
      setState(() {
        _items.addAll([
          for (final u in listOf(m['items']))
            if (!have.contains(parseStr(u['userId']))) u
        ]);
        _cursor = parseStr(m['nextCursor']);
        _more = _cursor != null;
        if (_which == 'incoming' && m['total'] != null) {
          _total = parseInt(m['total']);
        }
        _loading = false;
        _paging = false;
      });
      _fillIfEmpty();
    } catch (e) {
      if (!mounted || gen != _gen) return;
      final msg = apiError(e, fallback: l10n.profile_couldNotLoad).message;
      setState(() {
        if (_items.isEmpty && _loading) {
          _error = msg;
        } else {
          _pageError = msg;
        }
        _loading = false;
        _paging = false;
      });
    }
  }

  /// Every row on screen handled while the server has more: fetch on rather
  /// than say "no requests" over the rest (review LOW).
  void _fillIfEmpty() {
    if (_visible.isEmpty && _more && !_paging && _pageError == null) {
      _load();
    }
  }

  List<Map<String, dynamic>> get _visible => [
        for (final u in _items)
          if (_done[parseStr(u['userId']) ?? ''] != 'gone') u
      ];

  /// accept | decline | cancel-request, then mark the row.
  Future<void> _act(String userId, String action) async {
    setState(() => _busy = userId);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(dioProvider)
          .post('/api/mobile/players/$userId/follow', data: {'action': action});
      if (!mounted) return;
      setState(() {
        _done[userId] = action == 'accept' ? 'accepted' : 'gone';
        if (_which == 'incoming' && _total != null && _total! > 0) {
          _total = _total! - 1;
        }
      });
    } catch (e) {
      final err = apiError(e, fallback: l10n.profile_couldNotUpdate2);
      messenger.showSnackBar(SnackBar(content: Text(err.message)));
      // "That follow request isn't there any more." — withdrawn meanwhile,
      // or handled elsewhere: the row goes.
      if (mounted && err.statusCode == 404) {
        setState(() {
          _done[userId] = 'gone';
          if (_which == 'incoming' && _total != null && _total! > 0) {
            _total = _total! - 1;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = null);
      // My counts and request count (the profile's row, the menu), and any
      // open list.
      ref.invalidate(followStateProvider);
      followsChanged.value++;
      _fillIfEmpty();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final rows = _visible;
    final bottom = MediaQuery.of(context).padding.bottom;
    Widget centred(Widget child) => ListView(children: [
          const SizedBox(height: 80),
          Center(
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: child)),
        ]);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: Text(l.profile_followRequests),
        backgroundColor: p.bg,
        foregroundColor: p.ink,
        elevation: 0,
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SpSegmented(
            index: _which == 'incoming' ? 0 : 1,
            options: [l.profile_requestsTabIncoming, l.profile_requestsTabSent],
            badges: [_total == null || _total == 0 ? null : _total, null],
            onChanged: (i) {
              setState(() => _which = i == 0 ? 'incoming' : 'outgoing');
              _load(reset: true);
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(reset: true),
            child: _loading || (rows.isEmpty && _more && _pageError == null)
                ? centred(const CircularProgressIndicator())
                : _error != null
                    ? centred(Column(children: [
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: p.muted)),
                        const SizedBox(height: 8),
                        TextButton(
                            onPressed: () => _load(reset: true),
                            child: Text(l.profile_tryAgain)),
                      ]))
                    : rows.isEmpty && _pageError == null
                        ? centred(Text(
                            _which == 'incoming'
                                ? l.profile_noFollowRequests
                                : l.profile_noSentRequests,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: p.muted)))
                        : ListView.builder(
                            // Clear of the home indicator (review LOW).
                            padding:
                                EdgeInsets.fromLTRB(16, 4, 16, 24 + bottom),
                            itemCount: rows.length + 1,
                            itemBuilder: (_, i) {
                              if (i < rows.length) return _row(rows[i]);
                              if (_pageError != null) {
                                // A later page failed: keep the list, retry here.
                                return Center(
                                  child: Column(children: [
                                    Text(_pageError!,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: p.muted, fontSize: 12.5)),
                                    TextButton(
                                        onPressed: _load,
                                        child: Text(l.profile_tryAgain)),
                                  ]),
                                );
                              }
                              if (!_more) return const SizedBox.shrink();
                              return Center(
                                child: _paging
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2)),
                                      )
                                    : TextButton(
                                        onPressed: _load,
                                        child: Text(l.profile_showMore)),
                              );
                            },
                          ),
          ),
        ),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> u) {
    final p = context.palette;
    final l = context.l10n;
    final id = parseStr(u['userId']) ?? '';
    final name = parseStr(u['displayName']) ?? 'Player';
    final handle = parseStr(u['username']);
    final when = fmtRelative(parseDate(u['requestedAt']));
    final busy = _busy == id;
    Widget trailing;
    if (_which == 'outgoing') {
      // Says what it does: no confirm needed (the profile's "Requested"
      // pill asks first).
      trailing = ProfilePill(
        label: l.profile_cancelRequest,
        compact: true,
        busy: busy,
        onTap: () => _act(id, 'cancel-request'),
      );
    } else if (_done[id] == 'accepted') {
      // Confirmed: Instagram offers "Follow back" in the same place.
      trailing = FollowButton(userId: id, name: name, compact: true);
    } else {
      trailing = Row(mainAxisSize: MainAxisSize.min, children: [
        ProfilePill(
          label: l.profile_confirmRequest,
          filled: true,
          compact: true,
          busy: busy,
          onTap: () => _act(id, 'accept'),
        ),
        const SizedBox(width: 6),
        ProfilePill(
          label: l.profile_deleteRequest,
          compact: true,
          onTap: busy ? null : () => _act(id, 'decline'),
        ),
      ]);
    }
    final who = Row(children: [
      ClipOval(
          child: Crest(
              logoUrl: parseStr(u['avatarUrl']), label: name, size: 44)),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
            Text([if (handle != null) '@$handle', if (when.isNotEmpty) when]
                    .join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 12)),
          ],
        ),
      ),
    ]);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: id.isEmpty ? null : () => context.push('/players/$id'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        // At a narrow width or with large text the pills go on a line under
        // the name (Instagram does on small screens) instead of squeezing it
        // to nothing or overflowing (review profile-header-app MED-3): side by
        // side only while the name keeps ~100 logical px at the user's text
        // size next to ~170 of pills (fr / de "Confirmer · Supprimer"), i.e.
        // a 343-pt row at 1.0×; a 320-pt phone, or larger text, stacks.
        // Stacked, the pills scale down rather than overflow.
        child: LayoutBuilder(builder: (context, c) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final wide = c.maxWidth >= 56 + (100 + 170) * scale;
          if (wide) {
            return Row(children: [
              Expanded(child: who),
              const SizedBox(width: 8),
              trailing,
            ]);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              who,
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 56),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: trailing,
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
