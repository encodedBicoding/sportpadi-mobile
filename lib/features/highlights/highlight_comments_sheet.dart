import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/highlights/highlight_media.dart'
    show HighlightLimits, newHighlightClientId;
import 'package:sportpadi_mobile/data/highlights/highlight_models.dart';
import 'package:sportpadi_mobile/data/highlights/highlights_repository.dart';
import 'package:sportpadi_mobile/features/highlights/highlight_actions.dart';
import 'package:sportpadi_mobile/features/highlights/highlight_text_limit.dart';
import 'package:sportpadi_mobile/features/highlights/highlight_visitor.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/player_link.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// The comments on a highlight: a flat list, oldest first (the newest is
/// last), paged; add one (≤ 500 characters), delete where the server says so
/// (your own, or any on your post), report someone else's.
///
/// [onCount] is called whenever the post's comment count is known to have
/// changed, so the number on the post follows. [onNotFound] is called when
/// the server answers "not found" here — the post itself may be gone (a
/// remembered feed can be minutes old); the opener looks into it.
///
/// [onVisitor] set = a signed-out visitor: the list is read-only (the server
/// masks a child commenter for them), a "Sign up to comment" bar stands where
/// the box would be, and a comment's Report asks too — the sheet closes and
/// [onVisitor] opens the sign-up sheet on the page.
Future<void> showHighlightComments(
  BuildContext context, {
  required HighlightItem item,
  required ValueChanged<int> onCount,
  required VoidCallback onNotFound,
  void Function(HighlightVisitorAction action)? onVisitor,
}) {
  return showSpSheet<void>(
    context,
    scrollable: false,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    builder: (sheetContext) => _CommentsSheet(
      item: item,
      onCount: onCount,
      onNotFound: onNotFound,
      onVisitor: onVisitor,
      // A profile opened from here must not land under the sheet.
      launch: closeSheetThen(sheetContext, context),
    ),
  );
}

class _CommentsSheet extends ConsumerStatefulWidget {
  const _CommentsSheet({
    required this.item,
    required this.onCount,
    required this.onNotFound,
    required this.launch,
    this.onVisitor,
  });
  final HighlightItem item;
  final ValueChanged<int> onCount;
  final VoidCallback onNotFound;
  final SheetLaunch launch;
  final void Function(HighlightVisitorAction action)? onVisitor;

  /// Close the sheet, then ask the visitor to sign up (on the page).
  void ask(HighlightVisitorAction action) {
    final f = onVisitor;
    if (f != null) launch((_) => f(action));
  }

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  final _input = TextEditingController();

  /// The box stops where the server does (it counts code points).
  final _limit = HighlightTextLimit(HighlightLimits.commentMax);
  final _scroll = ScrollController();

  final List<HighlightComment> _items = [];
  String? _cursor;
  bool _end = false;
  bool _loading = false;
  String? _error;

  /// The thread carries on from its first comment because the server
  /// refused a cursor ([isRefusedCursor]) — at most once per sheet, so a
  /// server that refused its own fresh cursor is not asked in a loop.
  bool _restarted = false;

  /// After that restart: the comments the sheet already had. They stay where
  /// they are — a comment just sent included (review highlights-cursors-seo.md
  /// LOW-5) — and the pages that repeat them add only what is new.
  Set<String>? _repeat;
  late int _count = widget.item.commentCount;

  bool _sending = false;

  /// What the last action has to say (a refusal, "report sent").
  String? _notice;
  bool _noticeIsError = false;

  /// One id per comment being sent, kept across retries of the same text so
  /// a retry after a lost answer can't post it twice.
  String? _clientId;
  String? _clientIdText;

  String get _id => widget.item.id;

  /// The server said "not found": tell the opener, once.
  bool _toldNotFound = false;
  void _checkNotFound(Object e) {
    if (_toldNotFound || e is! ApiException || e.statusCode != 404) return;
    _toldNotFound = true;
    widget.onNotFound();
  }

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels > pos.maxScrollExtent - 240) _load();
  }

  Future<void> _load() async {
    if (_loading || _end) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    var cursor = _cursor;
    final fresh = <HighlightComment>[];
    var end = false;
    int? count;
    String? error;
    try {
      // A short or empty page isn't the end while there is a cursor — and
      // after a restart, nor is a page of comments the sheet already has.
      final repeat = _repeat;
      for (var hops = 0; hops < (repeat == null ? 5 : 20); hops++) {
        final page = await ref
            .read(highlightsRepositoryProvider)
            .comments(_id, cursor: cursor);
        if (!mounted) return;
        for (final c in page.items) {
          if (repeat == null || !repeat.contains(c.id)) fresh.add(c);
        }
        count = page.commentCount ?? count;
        cursor = page.nextCursor;
        if (cursor == null) {
          end = true;
          break;
        }
        if (fresh.isNotEmpty) break;
      }
    } catch (e) {
      if (!mounted) return;
      if (!_restarted && isRefusedCursor(e, cursor)) {
        // Carry on from the first comment, keeping everything on screen.
        _restarted = true;
        _repeat = {for (final c in _items) c.id};
        setState(() {
          _cursor = null;
          _end = false;
          _loading = false;
        });
        _load();
        return;
      }
      error = '$e';
      _checkNotFound(e);
    }
    final failed = error;
    final nextCursor = cursor;
    final reachedEnd = end;
    final newCount = count;
    setState(() {
      // A comment I just added sits at the end already; when its page
      // arrives it takes its real place instead of showing twice.
      final ids = {for (final c in fresh) c.id};
      _items.removeWhere((c) => ids.contains(c.id));
      _items.addAll(fresh);
      if (failed == null) {
        _cursor = nextCursor;
        _end = reachedEnd;
      }
      _error = failed;
      _loading = false;
      if (newCount != null) _count = newCount;
    });
    if (newCount != null) widget.onCount(_count);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    if (_clientId == null || _clientIdText != text) {
      _clientId = newHighlightClientId();
      _clientIdText = text;
    }
    setState(() {
      _sending = true;
      _notice = null;
    });
    try {
      final r = await ref
          .read(highlightsRepositoryProvider)
          .addComment(_id, text, clientId: _clientId);
      if (!mounted) return;
      _clientId = null;
      _clientIdText = null;
      _input.clear();
      setState(() {
        _items.removeWhere((c) => c.id == r.comment.id);
        _items.add(r.comment);
        _count = r.commentCount ?? _count + 1;
        _sending = false;
      });
      widget.onCount(_count);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        // ignore: discarded_futures
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _notice = '$e';
        _noticeIsError = true;
      });
      _checkNotFound(e);
    }
  }

  Future<void> _delete(HighlightComment c) async {
    try {
      final count = await ref
          .read(highlightsRepositoryProvider)
          .deleteComment(_id, c.id);
      if (!mounted) return;
      setState(() {
        _items.removeWhere((x) => x.id == c.id);
        _count = count ?? (_count > 0 ? _count - 1 : 0);
        _notice = null;
      });
      widget.onCount(_count);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _notice = '$e';
        _noticeIsError = true;
      });
    }
  }

  Future<void> _report(HighlightComment c) async {
    final sent = await showHighlightReport(context,
        highlightId: _id, commentId: c.id);
    if (!mounted || !sent) return;
    setState(() {
      _notice = l10n.highlights_reportSent;
      _noticeIsError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final height = MediaQuery.sizeOf(context).height * 0.62;
    final notice = _notice;
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _count > 0 ? l.highlights_commentsCount(_count) : l.inbox_comments,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: p.ink, fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(child: _list(p)),
          if (notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(notice,
                  style: TextStyle(
                      color: _noticeIsError ? p.danger : p.greenText,
                      fontSize: 12.5)),
            ),
          const SizedBox(height: 8),
          if (!widget.item.isReady)
            // A video that failed will never be "ready": say what happened
            // instead of promising comments. Its author is told why it
            // failed; a viewer who may report it (H2) is told what the card
            // says, not the author's reason.
            Text(
                widget.item.takenDownForReport
                    ? l.highlights_takenDownText
                    : widget.item.status == 'failed'
                        ? (widget.item.failureMessage ?? l.highlights_failed)
                        : l.highlights_commentsWhenReady,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 12.5))
          else if (widget.onVisitor != null)
            SpButton(
              label: l.highlights_commentsSignUp,
              icon: Icons.person_add_alt_1_rounded,
              expand: true,
              onTap: () => widget.ask(HighlightVisitorAction.comment),
            )
          else
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  // The limit is enforced as you type; no counter needed.
                  inputFormatters: [_limit],
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(hintText: l.inbox_addAComment2),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: p.hero,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _sending ? null : _send,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: _sending
                          ? Padding(
                              padding: const EdgeInsets.all(13),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: p.onHero),
                            )
                          : Icon(Icons.arrow_upward_rounded,
                              color: p.onHero, size: 21),
                    ),
                  ),
                ),
              ),
            ]),
        ],
      ),
    );
  }

  Widget _list(AppPalette p) {
    final l = context.l10n;
    if (_items.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      final error = _error;
      if (error != null) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(error,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 13)),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: Text(l.common_retry)),
          ]),
        );
      }
      if (!_end) {
        return Center(
          child: TextButton(
              onPressed: _load, child: Text(l.highlights_keepLooking)),
        );
      }
      return Center(
        child: Text(l.highlights_noCommentsYet,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 13)),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 4),
      itemCount: _items.length + (_end ? 0 : 1),
      itemBuilder: (context, i) {
        if (i == _items.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(
                      onPressed: _load,
                      child: Text(_error ?? l.highlights_moreComments)),
            ),
          );
        }
        return _row(p, _items[i]);
      },
    );
  }

  Widget _row(AppPalette p, HighlightComment c) {
    final l = context.l10n;
    final name = c.user.displayName.isEmpty ? l.common_player : c.user.displayName;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          // No id = someone the server hides from a visitor ("SportPadi
          // player"): nothing to open, and the sheet stays.
          onTap: c.user.userId.isEmpty
              ? null
              : () => widget.launch(
                  (page) => openPlayerProfile(page, ref, c.user.userId)),
          child: ClipOval(
            child: Crest(logoUrl: c.user.avatarUrl, label: name, size: 34),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 6),
                Text(fmtRelative(c.createdAt),
                    style: TextStyle(color: p.muted, fontSize: 11.5)),
              ]),
              const SizedBox(height: 2),
              Text(c.body,
                  style: TextStyle(color: p.ink, fontSize: 13.5, height: 1.4)),
            ],
          ),
        ),
        if (c.canDelete || !c.mine)
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            iconSize: 18,
            icon: Icon(Icons.more_horiz_rounded, color: p.muted),
            onSelected: (v) {
              if (v == 'delete') {
                // ignore: discarded_futures
                _delete(c);
              } else if (v == 'report') {
                if (widget.onVisitor != null) {
                  widget.ask(HighlightVisitorAction.report);
                  return;
                }
                // ignore: discarded_futures
                _report(c);
              }
            },
            itemBuilder: (_) => [
              if (c.canDelete)
                PopupMenuItem(value: 'delete', child: Text(l.inbox_delete)),
              if (!c.mine)
                PopupMenuItem(value: 'report', child: Text(l.inbox_report)),
            ],
          ),
      ]),
    );
  }
}
