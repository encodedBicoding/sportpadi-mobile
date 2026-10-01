import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/discussions/discussion_models.dart';
import 'package:sportpadi_mobile/data/discussions/discussions_repository.dart';
import 'package:sportpadi_mobile/features/discussions/discussion_widgets.dart';
import 'package:sportpadi_mobile/features/inbox/message_widgets.dart'
    show LinkifiedText, showReportSheet;
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// One comment in the flattened tree: its ancestors (for the thread lines)
/// and, when collapsed, how many replies are hidden under it.
class _TreeRow {
  const _TreeRow(this.comment, this.ancestors, this.hidden);
  final DiscussionComment comment;
  final List<String> ancestors;
  final int hidden;

  int get depth => math.min(ancestors.length, 4);
}

/// A discussion (docs/design/discussions.md): the post, its votes and the
/// threaded comments (4 levels; tap a thread line to fold that branch),
/// with a composer at the bottom unless it's locked for me.
class DiscussionScreen extends ConsumerStatefulWidget {
  const DiscussionScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<DiscussionScreen> createState() => _DiscussionScreenState();
}

class _DiscussionScreenState extends ConsumerState<DiscussionScreen> {
  static const _sorts = ['best', 'new', 'old'];

  final _input = TextEditingController();
  final _focus = FocusNode();
  final Set<String> _collapsed = {};
  String _sort = 'best';
  DiscussionComment? _replyTo;
  String? _wardId;
  bool _sending = false;
  bool _busy = false;
  bool _synced = false;

  /// The last thread shown, kept on screen while another sort loads.
  DiscussionThread? _last;

  DiscussionThreadKey get _key => (id: widget.id, sort: _sort);
  DiscussionController get _ctrl => ref.read(discussionProvider(_key).notifier);

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Run a thread action with the menu disabled; errors go to a snackbar.
  Future<void> _run(Future<void> Function() action, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (done != null) _snack(done);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── votes ────────────────────────────────────────────────────────────────

  Future<void> _voteDiscussion(int pressed) async {
    try {
      await _ctrl.voteDiscussion(pressed);
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _voteComment(String id, int pressed) async {
    try {
      await _ctrl.voteComment(id, pressed);
    } catch (e) {
      _snack('$e');
    }
  }

  // ── commenting ───────────────────────────────────────────────────────────

  /// My wards on this discussion's team, when I'm in its space only through
  /// them (I comment as their guardian). Watched from build.
  List<DiscussionWardRef> _wards(DiscussionDetail d) {
    if (d.teamId == null || d.group.id.isEmpty) return const [];
    final spaces = ref.watch(discussionSpacesProvider(d.group.id)).valueOrNull;
    return spaces?.team(d.teamId)?.asGuardianOf ?? const [];
  }

  DiscussionWardRef? _ward(List<DiscussionWardRef> wards) {
    if (wards.isEmpty) return null;
    for (final w in wards) {
      if (w.id == _wardId) return w;
    }
    return wards.first;
  }

  void _reply(DiscussionComment c) {
    setState(() => _replyTo = c);
    _focus.requestFocus();
  }

  Future<void> _send(List<DiscussionWardRef> wards) async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    final replyTo = _replyTo;
    final ward = _ward(wards);
    setState(() {
      _sending = true;
      _replyTo = null;
    });
    _input.clear();
    try {
      await _ctrl.addComment(
        body,
        parentId: replyTo?.id,
        viaWardId: ward?.id,
        myName: 'You',
      );
    } catch (e) {
      if (mounted) {
        // Give the text back so nothing typed is lost.
        if (_input.text.isEmpty) _input.text = body;
        setState(() => _replyTo = replyTo);
      }
      _snack('$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── the discussion's menu ────────────────────────────────────────────────

  Future<void> _edit(DiscussionDetail d) async {
    final r = await showSpSheet<({String title, String body, String flair})>(
      context,
      builder: (_) => _EditDiscussionSheet(discussion: d),
    );
    if (r == null || !mounted) return;
    await _run(() => _ctrl.edit(title: r.title, body: r.body, flair: r.flair),
        done: 'Saved.');
  }

  Future<void> _delete(DiscussionDetail d) async {
    final ok = await confirmDiscussionAction(
      context,
      title: 'Remove this discussion?',
      message: "It disappears for everyone. The group's admins can still "
          'see it for review.',
      confirm: 'Remove',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await _ctrl.delete();
      if (!mounted) return;
      _snack('Discussion removed.');
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/groups/${d.group.id}/discussions');
      }
    } catch (e) {
      _snack('$e');
      if (mounted) setState(() => _busy = false);
    }
  }

  void _report({String? commentId}) {
    final repo = ref.read(discussionsRepositoryProvider);
    // ignore: discarded_futures
    showReportSheet(
      context,
      what: commentId == null ? 'discussion' : 'comment',
      submit: (reason, details) => repo.report(widget.id,
          commentId: commentId, reason: reason, details: details),
    );
  }

  void _onMenu(String v, DiscussionThread t) {
    final d = t.discussion;
    switch (v) {
      case 'edit':
        // ignore: discarded_futures
        _edit(d);
      case 'status':
        // ignore: discarded_futures
        _run(() => _ctrl.setStatus(d.isResolved ? 'open' : 'resolved'),
            done: d.isResolved ? 'Reopened.' : 'Marked as resolved.');
      case 'pin':
        // ignore: discarded_futures
        _run(() => _ctrl.moderate(pinned: !d.pinned),
            done: d.pinned ? 'Unpinned.' : 'Pinned to the top.');
      case 'lock':
        // ignore: discarded_futures
        _run(() => _ctrl.moderate(locked: !d.locked),
            done: d.locked
                ? 'Comments reopened.'
                : 'Locked — only moderators can comment now.');
      case 'delete':
        // ignore: discarded_futures
        _delete(d);
      case 'report':
        _report();
      case 'group':
        context.push('/groups/${d.group.id}');
    }
  }

  // ── a comment's actions ──────────────────────────────────────────────────

  Future<void> _commentActions(DiscussionComment c, DiscussionThread t) async {
    if (c.deleted || c.pending) return;
    final action = await showSpSheet<String>(
      context,
      builder: (ctx) {
        final p = ctx.palette;
        Widget tile(String value, IconData icon, String label,
                {Color? color}) =>
            ListTile(
              leading: Icon(icon, color: color ?? p.ink),
              title: Text(label,
                  style: color == null ? null : TextStyle(color: color)),
              onTap: () => Navigator.of(ctx).pop(value),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SpListCard(children: [
              if (t.me.canComment) tile('reply', Icons.reply_rounded, 'Reply'),
              if (c.body.isNotEmpty)
                tile('copy', Icons.copy_rounded, 'Copy text'),
              if (c.canEdit) tile('edit', Icons.edit_outlined, 'Edit'),
              if (c.canDelete)
                tile('delete', Icons.delete_outline_rounded, 'Delete',
                    color: p.danger),
              if (!c.mine) tile('report', Icons.flag_outlined, 'Report'),
            ]),
          ],
        );
      },
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'reply':
        _reply(c);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: c.body));
        _snack('Copied.');
      case 'edit':
        final body = await showSpSheet<String>(
          context,
          builder: (_) => _EditCommentSheet(initial: c.body),
        );
        if (body == null || !mounted) return;
        await _run(() => _ctrl.editComment(c.id, body), done: 'Saved.');
      case 'delete':
        final ok = await confirmDiscussionAction(
          context,
          title: 'Remove this comment?',
          message: 'It shows as [removed]; replies to it stay.',
          confirm: 'Remove',
        );
        if (!ok || !mounted) return;
        await _run(() => _ctrl.deleteComment(c.id), done: 'Comment removed.');
      case 'report':
        _report(commentId: c.id);
    }
  }

  // ── tree ─────────────────────────────────────────────────────────────────

  List<_TreeRow> _tree(List<DiscussionComment> comments) {
    final ids = {for (final c in comments) c.id};
    final kids = <String, List<DiscussionComment>>{};
    final roots = <DiscussionComment>[];
    for (final c in comments) {
      final parent = c.parentId;
      if (parent != null && parent != c.id && ids.contains(parent)) {
        kids.putIfAbsent(parent, () => []).add(c);
      } else {
        roots.add(c);
      }
    }
    final seen = <String>{};
    int count(String id) {
      var n = 0;
      for (final k in kids[id] ?? const <DiscussionComment>[]) {
        if (seen.contains(k.id)) continue;
        n += 1 + count(k.id);
      }
      return n;
    }

    final rows = <_TreeRow>[];
    void walk(DiscussionComment c, List<String> ancestors) {
      if (!seen.add(c.id)) return;
      final folded = _collapsed.contains(c.id);
      rows.add(_TreeRow(c, ancestors, folded ? count(c.id) : 0));
      if (folded) return;
      for (final k in kids[c.id] ?? const <DiscussionComment>[]) {
        walk(k, [...ancestors, c.id]);
      }
    }

    for (final r in roots) {
      walk(r, const []);
    }
    return rows;
  }

  void _toggle(String id) => setState(() {
        if (!_collapsed.remove(id)) _collapsed.add(id);
      });

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final provider = discussionProvider(_key);
    final value = ref.watch(provider);
    ref.listen<AsyncValue<DiscussionThread>>(provider, (prev, next) {
      // Opening it refreshes its card in any list on screen.
      if (!_synced && next.hasValue) {
        _synced = true;
        ref.read(provider.notifier).broadcastCurrent();
      }
    });
    final fresh = value.valueOrNull;
    if (fresh != null) _last = fresh;
    final cached = _last;
    final t = fresh ?? (value.isLoading ? cached : null);
    final d = t?.discussion;

    final menu = t == null
        ? const <PopupMenuEntry<String>>[]
        : <PopupMenuEntry<String>>[
            if (t.me.canEdit)
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
            if (t.me.canResolve)
              PopupMenuItem(
                  value: 'status',
                  child: Text(
                      t.discussion.isResolved ? 'Reopen' : 'Mark as resolved')),
            if (t.me.canModerate) ...[
              PopupMenuItem(
                  value: 'pin',
                  child: Text(t.discussion.pinned ? 'Unpin' : 'Pin to top')),
              PopupMenuItem(
                  value: 'lock',
                  child: Text(t.discussion.locked
                      ? 'Unlock comments'
                      : 'Lock comments')),
            ],
            if (t.me.canDelete)
              const PopupMenuItem(value: 'delete', child: Text('Remove')),
            if (!t.me.isOP)
              const PopupMenuItem(value: 'report', child: Text('Report')),
            PopupMenuItem(
                value: 'group', child: Text('Open ${t.discussion.group.name}')),
          ];

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
            child: SpHeader(
              title: d?.teamName ?? d?.group.name ?? 'Discussion',
              subtitle: d == null
                  ? null
                  : d.teamName != null
                      ? d.group.name
                      : 'Group discussion',
              actions: [
                if (menu.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    enabled: !_busy,
                    icon: Icon(Icons.more_vert_rounded, color: p.ink),
                    onSelected: (v) {
                      final now = _last;
                      if (now != null) _onMenu(v, now);
                    },
                    itemBuilder: (_) => menu,
                  ),
              ],
            ),
          ),
          Expanded(
            child: t == null
                ? AsyncView<DiscussionThread>(
                    value: value,
                    onRetry: () => ref.invalidate(provider),
                    data: (_) => const SizedBox.shrink(),
                  )
                : Column(children: [
                    if (value.isLoading || _busy)
                      const LinearProgressIndicator(minHeight: 2)
                    else
                      const SizedBox(height: 2),
                    Expanded(child: _content(p, t)),
                    _bottom(p, t),
                  ]),
          ),
        ]),
      ),
    );
  }

  Widget _content(AppPalette p, DiscussionThread t) {
    final rows = _tree(t.comments);
    final header = <Widget>[
      _postCard(p, t),
      const SizedBox(height: 18),
      Row(children: [
        Text(
            t.discussion.commentCount == 1
                ? '1 comment'
                : '${t.discussion.commentCount} comments',
            style: TextStyle(
                color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
        const Spacer(),
        SizedBox(
          width: 190,
          child: SpSegmented(
            options: const ['Best', 'New', 'Old'],
            index: _sorts.indexOf(_sort),
            onChanged: (i) {
              if (_sorts[i] == _sort) return;
              setState(() => _sort = _sorts[i]);
            },
          ),
        ),
      ]),
      const SizedBox(height: 8),
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Text(
              t.me.canComment
                  ? 'No comments yet. Start the conversation.'
                  : 'No comments.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 13)),
        ),
    ];
    return RefreshIndicator(
      onRefresh: () => _ctrl.reload(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        itemCount: header.length + rows.length,
        itemBuilder: (_, i) {
          if (i < header.length) return header[i];
          final r = rows[i - header.length];
          final c = r.comment;
          final lines = r.ancestors.length > r.depth
              ? r.ancestors.sublist(r.ancestors.length - r.depth)
              : r.ancestors;
          return _CommentRow(
            row: r,
            lines: lines,
            canComment: t.me.canComment,
            collapsed: _collapsed.contains(c.id),
            onToggle: () => _toggle(c.id),
            onFoldAncestor: _toggle,
            onVote: (v) => _voteComment(c.id, v),
            onReply: () => _reply(c),
            onMore: () => _commentActions(c, t),
          );
        },
      ),
    );
  }

  Widget _postCard(AppPalette p, DiscussionThread t) {
    final d = t.discussion;
    final tags = <Widget>[
      if (d.pinned)
        SpBadge('Pinned', icon: Icons.push_pin_rounded, tone: p.greenText),
      if (d.locked)
        SpBadge('Locked', icon: Icons.lock_outline_rounded, tone: p.orangeInk),
      DiscussionFlairPill(d.flair),
      if (d.isResolved) const DiscussionResolvedPill(),
    ];
    final images = d.attachments;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Crest(logoUrl: d.group.imageUrl, label: d.group.name, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  [d.group.name, if (d.teamName != null) d.teamName!]
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 4, children: tags),
          const SizedBox(height: 10),
          SelectableText(d.title,
              style: TextStyle(
                  color: p.ink,
                  fontSize: 19,
                  height: 1.3,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          DiscussionAuthorLine(
            author: d.author,
            userId: d.author.id,
            isOP: true,
            note: discussionTimeNote(d.createdAt, editedAt: d.editedAt),
            avatarSize: 24,
            fontSize: 13,
          ),
          if (d.body.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            LinkifiedText(
              d.body.trim(),
              style: TextStyle(color: p.ink, fontSize: 15, height: 1.5),
              linkColor: p.greenText,
            ),
          ],
          if (images.isNotEmpty) ...[
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, box) {
              final single = images.length == 1;
              final w = single ? box.maxWidth : (box.maxWidth - 8) / 2;
              final h = single ? box.maxWidth * 0.62 : w;
              return Wrap(spacing: 8, runSpacing: 8, children: [
                for (final a in images)
                  GestureDetector(
                    onTap: () => openDiscussionImage(context, a.url),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: CachedNetworkImage(
                        imageUrl: a.url,
                        width: w,
                        height: h,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(width: w, height: h, color: p.surface2),
                        errorWidget: (_, __, ___) => Container(
                          width: w,
                          height: h,
                          color: p.surface2,
                          child:
                              Icon(Icons.broken_image_outlined, color: p.muted),
                        ),
                      ),
                    ),
                  ),
              ]);
            }),
          ],
          const SizedBox(height: 6),
          Divider(height: 12, color: p.surface2),
          Row(children: [
            DiscussionVotes(
              score: d.score,
              myVote: d.myVote,
              onVote: _voteDiscussion,
              horizontal: true,
            ),
            const Spacer(),
            if (t.me.canComment)
              TextButton.icon(
                onPressed: () {
                  setState(() => _replyTo = null);
                  _focus.requestFocus();
                },
                icon: const Icon(Icons.mode_comment_outlined, size: 17),
                label: const Text('Comment'),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _bottom(AppPalette p, DiscussionThread t) {
    final d = t.discussion;
    if (!t.me.canComment) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
        decoration: BoxDecoration(
          color: p.surface2,
          border: Border(top: BorderSide(color: p.line)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.lock_outline_rounded, size: 18, color: p.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                'Locked — new comments are turned off for this discussion.',
                style: TextStyle(color: p.muted, fontSize: 13, height: 1.4)),
          ),
        ]),
      );
    }
    final wards = _wards(d);
    final ward = _ward(wards);
    final replyTo = _replyTo;
    final canSend = !_sending && _input.text.trim().isNotEmpty;
    Widget note(IconData icon, String text, Color fg, {Widget? trailing}) =>
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 0, 6),
          child: Row(children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
            if (trailing != null) trailing,
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: p.bg,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (d.locked)
          note(Icons.lock_outline_rounded,
              'Locked — only moderators can comment.', p.orangeInk),
        if (ward != null)
          note(
            Icons.child_care_rounded,
            "Commenting as ${ward.firstName}'s guardian",
            p.wardInk,
            trailing: wards.length > 1
                ? PopupMenuButton<String>(
                    tooltip: 'Choose ward',
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.swap_horiz_rounded,
                        size: 18, color: p.wardInk),
                    onSelected: (id) => setState(() => _wardId = id),
                    itemBuilder: (_) => [
                      for (final w in wards)
                        PopupMenuItem(
                            value: w.id,
                            child: Text("${w.firstName}'s guardian")),
                    ],
                  )
                : null,
          ),
        if (replyTo != null)
          note(
            Icons.reply_rounded,
            'Replying to ${replyTo.author?.name ?? 'a comment'}',
            p.greenText,
            trailing: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => setState(() => _replyTo = null),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 16, color: p.muted),
              ),
            ),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              controller: _input,
              focusNode: _focus,
              minLines: 1,
              maxLines: 5,
              maxLength: 3000,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: replyTo != null ? 'Your reply' : 'Add a comment',
                counterText: '',
                isDense: true,
                filled: true,
                fillColor: p.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: p.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: p.line),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: canSend ? p.accentDeep : p.surface2,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: canSend ? () => _send(wards) : null,
              child: SizedBox(
                width: 44,
                height: 44,
                child: _sending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.send_rounded,
                        size: 20, color: canSend ? Colors.white : p.muted),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// One comment: thread lines for its depth (tap one to fold that branch),
/// the author line (tap to fold this comment), the body, and votes / Reply /
/// more. Long-press opens the actions too.
class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.row,
    required this.lines,
    required this.canComment,
    required this.collapsed,
    required this.onToggle,
    required this.onFoldAncestor,
    required this.onVote,
    required this.onReply,
    required this.onMore,
  });
  final _TreeRow row;

  /// The ancestors whose thread lines are drawn, outermost first.
  final List<String> lines;
  final bool canComment;
  final bool collapsed;
  final VoidCallback onToggle;
  final ValueChanged<String> onFoldAncestor;
  final ValueChanged<int> onVote;
  final VoidCallback onReply;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = row.comment;
    final author = c.author;
    final live = !c.deleted && !c.pending;

    final Widget head = c.deleted || author == null
        ? Text('[removed]',
            style: TextStyle(
                color: p.muted, fontSize: 12.5, fontStyle: FontStyle.italic))
        : DiscussionAuthorLine(
            author: author,
            userId: author.id,
            isOP: c.isOP,
            note: c.pending
                ? 'Posting…'
                : discussionTimeNote(c.createdAt, editedAt: c.editedAt),
          );

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 0, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Row(children: [
              Expanded(child: head),
              if (collapsed) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: p.surface2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                      row.hidden == 0
                          ? 'Folded'
                          : '+${row.hidden} ${row.hidden == 1 ? 'reply' : 'replies'}',
                      style: TextStyle(
                          color: p.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ),
          if (!collapsed) ...[
            if (!c.deleted && c.body.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 5, left: 2),
                child: Opacity(
                  opacity: c.pending ? 0.6 : 1,
                  child: LinkifiedText(
                    c.body,
                    style: TextStyle(color: p.ink, fontSize: 14, height: 1.45),
                    linkColor: p.greenText,
                    selectable: false,
                  ),
                ),
              ),
            if (live)
              Row(children: [
                DiscussionVotes(
                  score: c.score,
                  myVote: c.myVote,
                  onVote: onVote,
                  horizontal: true,
                  compact: true,
                ),
                if (canComment)
                  TextButton.icon(
                    onPressed: onReply,
                    style: TextButton.styleFrom(
                      foregroundColor: p.muted,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.reply_rounded, size: 16),
                    label: const Text('Reply',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                IconButton(
                  tooltip: 'More',
                  visualDensity: VisualDensity.compact,
                  onPressed: onMore,
                  icon:
                      Icon(Icons.more_horiz_rounded, size: 18, color: p.muted),
                ),
              ])
            else
              const SizedBox(height: 6),
          ],
        ],
      ),
    );

    return GestureDetector(
      onLongPress: live ? onMore : null,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final a in lines)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onFoldAncestor(a),
              child: SizedBox(
                width: 16,
                child: Center(
                  child: Container(width: 2, color: p.line),
                ),
              ),
            ),
          Expanded(child: content),
        ]),
      ),
    );
  }
}

/// OP: edit the title, details and flair.
class _EditDiscussionSheet extends StatefulWidget {
  const _EditDiscussionSheet({required this.discussion});
  final DiscussionDetail discussion;

  @override
  State<_EditDiscussionSheet> createState() => _EditDiscussionSheetState();
}

class _EditDiscussionSheetState extends State<_EditDiscussionSheet> {
  late final _title = TextEditingController(text: widget.discussion.title);
  late final _body = TextEditingController(text: widget.discussion.body);
  late String _flair = widget.discussion.flair;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _title.text.trim().length >= 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SpSheetHeader(
          icon: Icons.edit_outlined,
          title: 'Edit discussion',
          subtitle: 'Everyone will see it was edited.',
        ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in discussionFlairs)
            DiscussionPill(
              label: f.label,
              icon: discussionFlairIcon(f.value),
              selected: _flair == f.value,
              onTap: () => setState(() => _flair = f.value),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          maxLength: 140,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Title'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _body,
          maxLength: 5000,
          minLines: 4,
          maxLines: 10,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Details',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 10),
        SpButton(
          label: 'Save',
          icon: Icons.check_rounded,
          expand: true,
          onTap: ok
              ? () => Navigator.of(context).pop((
                    title: _title.text.trim(),
                    body: _body.text.trim(),
                    flair: _flair,
                  ))
              : null,
        ),
      ],
    );
  }
}

/// Edit my comment.
class _EditCommentSheet extends StatefulWidget {
  const _EditCommentSheet({required this.initial});
  final String initial;

  @override
  State<_EditCommentSheet> createState() => _EditCommentSheetState();
}

class _EditCommentSheetState extends State<_EditCommentSheet> {
  late final _body = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _body.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SpSheetHeader(icon: Icons.edit_outlined, title: 'Edit comment'),
        TextField(
          controller: _body,
          autofocus: true,
          maxLength: 3000,
          minLines: 3,
          maxLines: 10,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        SpButton(
          label: 'Save',
          icon: Icons.check_rounded,
          expand: true,
          onTap: text.isEmpty || text == widget.initial.trim()
              ? null
              : () => Navigator.of(context).pop(text),
        ),
      ],
    );
  }
}
