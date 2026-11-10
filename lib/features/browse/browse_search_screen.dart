import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/groups/group_class.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// One remembered search: a query typed and submitted ([kind] `q`), or a
/// result that was opened (`event` / `group` / `team` / `player`) — like
/// Instagram / TikTok, tapping it runs the search again or opens the page.
class RecentSearch {
  const RecentSearch({
    required this.kind,
    required this.title,
    this.id,
    this.sub,
    this.image,
    this.emoji,
    this.route,
    this.tournament = false,
    this.kitPrimary,
    this.kitSecondary,
  });

  final String kind;
  final String title; // the query text for kind `q`
  final String? id;
  final String? sub;
  final String? image;
  final String? emoji;
  final String? route;
  final bool tournament;
  final String? kitPrimary;
  final String? kitSecondary;

  bool get isQuery => kind == 'q';

  /// Same entry = same query (any case) or same page.
  String get key => isQuery ? 'q:${title.toLowerCase()}' : '$kind:$id';

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'title': title,
        if (id != null) 'id': id,
        if (sub != null) 'sub': sub,
        if (image != null) 'image': image,
        if (emoji != null) 'emoji': emoji,
        if (route != null) 'route': route,
        if (tournament) 'tournament': true,
        if (kitPrimary != null) 'kitPrimary': kitPrimary,
        if (kitSecondary != null) 'kitSecondary': kitSecondary,
      };

  static RecentSearch? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = parseStr(j['kind']);
    final title = parseStr(j['title']);
    if (kind == null || title == null) return null;
    if (kind != 'q' && parseStr(j['route']) == null) return null;
    return RecentSearch(
      kind: kind,
      title: title,
      id: parseStr(j['id']),
      sub: parseStr(j['sub']),
      image: parseStr(j['image']),
      emoji: parseStr(j['emoji']),
      route: parseStr(j['route']),
      tournament: j['tournament'] == true,
      kitPrimary: parseStr(j['kitPrimary']),
      kitSecondary: parseStr(j['kitSecondary']),
    );
  }
}

/// Recent searches on this device, kept per account (a shared phone doesn't
/// show one person's searches to the next). Newest first, at most [max].
class RecentSearchStore {
  RecentSearchStore(this.owner);
  final String owner;
  static const max = 20;
  static const _storage = FlutterSecureStorage();
  String get _key => 'browse.recent.$owner';

  Future<List<RecentSearch>> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [
        for (final e in list)
          if (RecentSearch.fromJson(e) case final r?) r
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<RecentSearch> items) async {
    try {
      await _storage.write(
          key: _key,
          value: jsonEncode([for (final r in items.take(max)) r.toJson()]));
    } catch (_) {/* best effort */}
  }
}

/// Browse search — its own page (opened by tapping Browse's search bar):
/// back button + search field on top; with nothing typed, the recent
/// searches (tap to run / open, ✕ to remove, Clear all); with 2+ characters,
/// the network results (events, groups, teams, players). Web twin:
/// /discover/search.
class BrowseSearchScreen extends ConsumerStatefulWidget {
  const BrowseSearchScreen({super.key, this.initialQuery});
  final String? initialQuery;
  @override
  ConsumerState<BrowseSearchScreen> createState() => _BrowseSearchScreenState();
}

class _BrowseSearchScreenState extends ConsumerState<BrowseSearchScreen> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  Map<String, dynamic>? _results;
  bool _searching = false;
  int _seq = 0; // drops an older search answering after a newer one

  RecentSearchStore? _store;
  List<RecentSearch> _recent = const [];

  @override
  void initState() {
    super.initState();
    final q0 = widget.initialQuery?.trim() ?? '';
    if (q0.isNotEmpty) {
      _search.text = q0;
      _run(q0);
    } else {
      // Open with the keyboard up, like tapping a search bar elsewhere.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
    _loadRecent();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    // The session is already known by the time Browse is on screen (the
    // router waits for it), unlike the profile.
    final me = ref.read(authControllerProvider).valueOrNull?.user?.id;
    final store = RecentSearchStore(me ?? 'guest');
    final items = await store.load();
    if (!mounted) return;
    setState(() {
      _store = store;
      _recent = items;
    });
  }

  void _remember(RecentSearch r) {
    final next = [r, ..._recent.where((e) => e.key != r.key)]
        .take(RecentSearchStore.max)
        .toList();
    setState(() => _recent = next);
    _store?.save(next);
  }

  void _forget(RecentSearch r) {
    final next = _recent.where((e) => e.key != r.key).toList();
    setState(() => _recent = next);
    _store?.save(next);
  }

  void _clearRecent() {
    setState(() => _recent = const []);
    _store?.save(const []);
  }

  void _onChanged(String v) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(v));
  }

  Future<void> _run(String q) async {
    final query = q.trim();
    final seq = ++_seq;
    if (query.length < 2) {
      if (mounted) {
        setState(() {
          _results = null;
          _searching = false;
        });
      }
      return;
    }
    setState(() => _searching = true);
    try {
      final r = await ref.read(eventsRepositoryProvider).searchAll(query);
      if (mounted && seq == _seq) setState(() => _results = r);
    } catch (_) {
      if (mounted && seq == _seq) setState(() => _results = const {});
    } finally {
      if (mounted && seq == _seq) setState(() => _searching = false);
    }
  }

  /// Keyboard "search": remember the text and put the keyboard away.
  void _submit(String v) {
    final q = v.trim();
    if (q.length < 2) return;
    _remember(RecentSearch(kind: 'q', title: q));
    _debounce?.cancel();
    _run(q);
    _focus.unfocus();
  }

  void _openRecent(RecentSearch r) {
    _remember(r);
    if (r.isQuery) {
      _search.value = TextEditingValue(
        text: r.title,
        selection: TextSelection.collapsed(offset: r.title.length),
      );
      _debounce?.cancel();
      _focus.unfocus();
      _run(r.title);
    } else if (r.route != null) {
      context.push(r.route!);
    }
  }

  void _openResult(RecentSearch r) {
    _remember(r);
    if (r.route != null) context.push(r.route!);
  }

  void _clearText() {
    _debounce?.cancel();
    _search.clear();
    _seq++;
    setState(() {
      _results = null;
      _searching = false;
    });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final showResults = _search.text.trim().length >= 2;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(children: [
              SpRoundButton(
                icon: Icons.arrow_back_ios_new_rounded,
                tooltip: context.l10n.common_back,
                iconSize: 18,
                onTap: () {
                  _focus.unfocus();
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/home');
                  }
                },
              ),
              const SizedBox(width: 10),
              Expanded(child: _field(p)),
            ]),
          ),
          Expanded(child: showResults ? _resultsList(p) : _recentList(p)),
        ]),
      ),
    );
  }

  Widget _field(AppPalette p) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: dark ? Border.all(color: p.line) : null,
        boxShadow: cardShadow(context),
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: _search,
        focusNode: _focus,
        onChanged: _onChanged,
        onSubmitted: _submit,
        textInputAction: TextInputAction.search,
        style: TextStyle(color: p.ink, fontSize: 14.5),
        decoration: InputDecoration(
          isDense: true,
          hintText: context.l10n.browse_searchGroupsPlayersEvents,
          hintStyle: TextStyle(color: p.muted, fontSize: 14.5),
          prefixIcon: Icon(Icons.search_rounded, size: 21, color: p.muted),
          suffixIcon: _searching
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : _search.text.isNotEmpty
                  ? IconButton(
                      tooltip: context.l10n.browse_clearSearch,
                      onPressed: _clearText,
                      icon: Icon(Icons.close_rounded, size: 18, color: p.muted),
                    )
                  : null,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
        ),
      ),
    );
  }

  // ── Recent ────────────────────────────────────────────────────────────────

  Widget _recentList(AppPalette p) {
    final t = context.l10n;
    if (_recent.isEmpty) {
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
        children: [
          Icon(Icons.history_rounded, size: 30, color: p.muted),
          const SizedBox(height: 10),
          Text(t.browse_recentEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 13, height: 1.45)),
        ],
      );
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 0, 6),
          child: Row(children: [
            Expanded(
              child: Text(t.browse_recentSearches,
                  style: TextStyle(
                      color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            TextButton(
              onPressed: _clearRecent,
              child: Text(t.browse_clearAllRecent,
                  style: TextStyle(
                      color: p.greenText,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        for (final r in _recent) _recentRow(p, r),
      ],
    );
  }

  Widget _recentRow(AppPalette p, RecentSearch r) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openRecent(r),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 7, 0, 7),
          child: Row(children: [
            r.isQuery
                ? Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                        color: p.surface2, shape: BoxShape.circle),
                    child: Icon(Icons.search_rounded, size: 20, color: p.ink),
                  )
                : _lead(p, r),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(r.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 14.5,
                            fontWeight:
                                r.isQuery ? FontWeight.w600 : FontWeight.w700)),
                    if (!r.isQuery && (r.sub ?? '').isNotEmpty)
                      Text(r.sub!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.muted, fontSize: 12)),
                  ]),
            ),
            IconButton(
              tooltip: context.l10n.browse_removeRecent,
              onPressed: () => _forget(r),
              icon: Icon(Icons.close_rounded, size: 18, color: p.muted),
            ),
          ]),
        ),
      );

  /// The picture for a result / remembered result.
  Widget _lead(AppPalette p, RecentSearch r) {
    switch (r.kind) {
      case 'event':
        return Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: r.tournament ? p.orangeTint : p.accentTint,
            borderRadius: BorderRadius.circular(14),
          ),
          child: r.tournament
              ? Icon(Icons.emoji_events_outlined, size: 20, color: p.orangeInk)
              : Text(r.emoji ?? '🏅', style: const TextStyle(fontSize: 19)),
        );
      case 'player':
        return ClipOval(
            child: Crest(logoUrl: r.image, label: r.title, size: 42));
      case 'team':
        return Crest(
            logoUrl: r.image,
            kitPrimary: r.kitPrimary,
            kitSecondary: r.kitSecondary,
            label: r.title,
            size: 42);
      default:
        return Crest(logoUrl: r.image, label: r.title, size: 42);
    }
  }

  // ── Results ───────────────────────────────────────────────────────────────

  /// "🏫 School" for a group row, or null when the type isn't set.
  String? _classLine(String? code) => code == null
      ? null
      : '${groupClassEmoji[code] ?? ''} ${groupClassName(context.l10n, code)}'
          .trim();

  Widget _resultsList(AppPalette p) {
    final r = _results;
    if (r == null) {
      return Center(
        child: Text(context.l10n.browse_searching,
            style: TextStyle(color: p.muted, fontSize: 13)),
      );
    }
    List<Map<String, dynamic>> section(String key) => r[key] is List
        ? [
            for (final e in r[key] as List)
              if (e is Map) Map<String, dynamic>.from(e)
          ]
        : const [];
    final events = section('events');
    final groups = section('groups');
    final teams = section('teams');
    final players = section('players');
    if (events.isEmpty && groups.isEmpty && teams.isEmpty && players.isEmpty) {
      return _emptyState(p, Icons.search_off_rounded,
          context.l10n.browse_nothingOnTheNetworkMatches,
          context.l10n.browse_tryAShorterNameOr);
    }

    Widget header(String label, int n) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
          child: Row(children: [
            Text(label,
                style: TextStyle(
                    color: p.ink, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: p.surface2, borderRadius: BorderRadius.circular(999)),
              child: Text('$n',
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        );

    Widget group(List<RecentSearch> rows) => GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Divider(
                    height: 1,
                    thickness: 1,
                    indent: 12,
                    endIndent: 12,
                    color: p.surface2),
              _resultRow(p, rows[i]),
            ],
          ]),
        );

    final t = context.l10n;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        if (events.isNotEmpty) ...[
          header(t.browse_events, events.length),
          group([
            for (final e in events)
              () {
                final id = parseStr(e['id']);
                final tournament = e['isTournament'] == true;
                return RecentSearch(
                  kind: 'event',
                  id: id,
                  title: parseStr(e['title']) ?? t.browse_event,
                  sub: [
                    formatDay(e['eventDate']),
                    if (tournament) t.browse_tournament,
                  ].join(' · '),
                  emoji: e['category'] is Map
                      ? parseStr((e['category'] as Map)['emoji'])
                      : null,
                  tournament: tournament,
                  route: tournament && id != null
                      ? '/tournaments/$id'
                      : '/events/${parseStr(e['slug']) ?? id}',
                );
              }(),
          ]),
        ],
        if (groups.isNotEmpty) ...[
          header(t.browse_groups, groups.length),
          group([
            for (final g in groups)
              RecentSearch(
                kind: 'group',
                id: parseStr(g['id']),
                title: parseStr(g['name']) ?? t.browse_group,
                sub: _classLine(parseGroupClass(g['classification'])),
                image: parseStr(g['imageUrl']),
                route: '/groups/${parseStr(g['id'])}',
              ),
          ]),
        ],
        if (teams.isNotEmpty) ...[
          header(t.browse_teams, teams.length),
          group([
            for (final tm in teams)
              RecentSearch(
                kind: 'team',
                id: parseStr(tm['id']),
                title: parseStr(tm['name']) ?? t.browse_team,
                sub: [
                  if (parseStr(tm['username']) != null)
                    '@${parseStr(tm['username'])}',
                  if (parseStr(tm['groupName']) != null)
                    parseStr(tm['groupName'])!,
                ].join(' · '),
                image: parseStr(tm['logoUrl']),
                kitPrimary: parseStr(tm['kitPrimary']),
                kitSecondary: parseStr(tm['kitSecondary']),
                route: '/teams/${parseStr(tm['id'])}',
              ),
          ]),
        ],
        if (players.isNotEmpty) ...[
          header(t.browse_players, players.length),
          group([
            for (final u in players)
              RecentSearch(
                kind: 'player',
                id: parseStr(u['userId']),
                title: parseStr(u['displayName']) ?? t.browse_player,
                sub: parseStr(u['username']) != null
                    ? '@${parseStr(u['username'])}'
                    : null,
                image: parseStr(u['avatarUrl']),
                route: '/players/${parseStr(u['userId'])}',
              ),
          ]),
        ],
      ],
    );
  }

  Widget _resultRow(AppPalette p, RecentSearch r) => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openResult(r),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(children: [
            _lead(p, r),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(r.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700)),
                    if ((r.sub ?? '').isNotEmpty)
                      Text(r.sub!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.muted, fontSize: 12)),
                  ]),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: p.muted),
          ]),
        ),
      );

  Widget _emptyState(AppPalette p, IconData icon, String title, String body) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                  color: p.surface2, borderRadius: BorderRadius.circular(20)),
              child: Icon(icon, color: p.muted, size: 26),
            ),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: p.ink, fontSize: 15, fontWeight: FontWeight.w700)),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(body,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: p.muted, fontSize: 12.5, height: 1.45)),
            ],
          ]),
        ),
      );
}
