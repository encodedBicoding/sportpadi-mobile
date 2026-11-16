import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/referral/referral.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/highlights/highlight_media.dart'
    show HighlightLimits;
import 'package:sportpadi_mobile/data/highlights/highlight_models.dart';
import 'package:sportpadi_mobile/data/highlights/highlights_repository.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// What a viewer can do to a highlight besides watching it: share, report,
/// and — where the server allows it (`permissions`) — delete it or change
/// the stat it is pinned to.

/// The web address of a post; opening it on a phone with the app lands on
/// the same post (`core/links/link_resolver.dart`).
String highlightShareUrl(WidgetRef ref, String id) {
  final base = ref.read(appConfigProvider).apiBaseUrl;
  // Carries who shared it, like every other share link in the app.
  final me = ref.read(authControllerProvider).valueOrNull?.user?.id;
  return withRef('$base/highlights/$id', me, 'app');
}

/// Share = copy the link, as everywhere else in the app.
void shareHighlight(BuildContext context, WidgetRef ref, HighlightItem item) {
  // ignore: discarded_futures
  Clipboard.setData(ClipboardData(text: highlightShareUrl(ref, item.id)));
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(context.l10n.event_linkCopied)));
}

enum HighlightMoreAction { copyLink, link, unlink, report, delete }

/// The "more" sheet. Only what this viewer may do is listed
/// (`permissions` on the item).
Future<HighlightMoreAction?> showHighlightMore(
    BuildContext context, HighlightItem item) {
  return showSpSheet<HighlightMoreAction>(
    context,
    builder: (ctx) {
      final p = ctx.palette;
      final l = ctx.l10n;
      // Each row on a Material of its own: the card under it is a painted
      // box, which would hide a tap's ripple drawn on the sheet.
      Widget row(IconData icon, String label, HighlightMoreAction action,
              {Color? color}) =>
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              leading: Icon(icon, color: color ?? p.ink),
              title: Text(label,
                  style: TextStyle(
                      color: color ?? p.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600)),
              onTap: () => Navigator.of(ctx).pop(action),
            ),
          );
      final perms = item.permissions;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpListCard(children: [
            // Only a post that is out has a link worth copying: one that is
            // down (or still being converted) answers 404 to everyone but
            // its author, so the link would be a dead end for whoever it
            // was sent to. The web greys out share on the same card.
            if (item.isReady)
              row(Icons.link_rounded, l.event_copyLink,
                  HighlightMoreAction.copyLink),
            if (perms.canEditLink && item.stat == null)
              row(Icons.add_link_rounded, l.highlights_linkToStat,
                  HighlightMoreAction.link),
            // A post about a ward whose stat was removed from the match
            // shows no stat any more, but it is still the ward's: its link
            // can be taken off, which gives it back to its author (the
            // viewer asks first — as on the web).
            if (perms.canEditLink && item.stat == null && item.aboutSomeoneElse)
              row(Icons.link_off_rounded, l.highlights_removeStat,
                  HighlightMoreAction.unlink),
            if (perms.canEditLink && item.stat != null) ...[
              row(Icons.swap_horiz_rounded, l.highlights_changeStat,
                  HighlightMoreAction.link),
              row(Icons.link_off_rounded, l.highlights_removeStat,
                  HighlightMoreAction.unlink),
            ],
            if (perms.canReport)
              row(Icons.flag_outlined, l.inbox_report,
                  HighlightMoreAction.report),
            if (perms.canDelete)
              row(Icons.delete_outline_rounded, l.inbox_delete,
                  HighlightMoreAction.delete,
                  color: p.danger),
          ]),
        ],
      );
    },
  );
}

/// "Delete this highlight?" — true when confirmed.
///
/// What it says depends on what deleting costs. A post that went out still
/// counts towards its AUTHOR's posts for the week after it is deleted, and
/// the author is told so ([byAuthor]); a guardian removing a post about
/// their ward isn't — it is not their week. A post that failed never
/// counted, so nothing is said about the week there.
Future<bool> confirmDeleteHighlight(BuildContext context, HighlightItem item,
    {required bool byAuthor}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final l = ctx.l10n;
      final String body;
      if (item.status == 'failed') {
        body = l.highlights_appDeleteBodyFailed;
      } else if (byAuthor) {
        body = '${l.highlights_deleteBody} ${l.highlights_appDeleteKeepsPlace}';
      } else {
        body = l.highlights_deleteBody;
      }
      return AlertDialog(
        title: Text(l.highlights_deleteTitle),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.common_cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.inbox_delete)),
        ],
      );
    },
  );
  return ok == true;
}

/// A link decides who a post is ABOUT (a guardian's post linked to a ward's
/// stat is about the ward), and a post is seen by whoever may see that
/// person's profile. So before a link change moves a post from one person
/// to another, say so. True when confirmed.
Future<bool> confirmSubjectChange(BuildContext context,
    {required String from, required String to}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.l10n.highlights_subjectChangeTitle),
      content: Text(ctx.l10n.highlights_subjectChangeBody(from, to)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.common_cancel)),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.highlights_subjectChangeConfirm)),
      ],
    ),
  );
  return ok == true;
}

/// Report a post — or, with [commentId], one comment on it. True when the
/// report was sent; the caller says thanks where the person can see it.
Future<bool> showHighlightReport(BuildContext context,
    {required String highlightId, String? commentId}) async {
  final sent = await showSpSheet<bool>(
    context,
    builder: (_) =>
        _ReportSheet(highlightId: highlightId, commentId: commentId),
  );
  return sent == true;
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.highlightId, this.commentId});
  final String highlightId;
  final String? commentId;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  String? _reason;
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(highlightsRepositoryProvider).report(
            widget.highlightId,
            reason: reason,
            note: _note.text,
            commentId: widget.commentId,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    // The server's reasons (`HIGHLIGHT_REPORT_REASONS`), in the order a
    // worried person looks for them.
    final reasons = <(String, String)>[
      ('inappropriate', l.highlights_reasonInappropriate),
      ('harassment', l.highlights_reasonHarassment),
      ('child_safety', l.highlights_reasonChildSafety),
      ('not_me', l.highlights_reasonNotMe),
      ('spam', l.inbox_reasonSpam),
      ('other', l.common_other),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSheetHeader(
          icon: Icons.flag_outlined,
          iconBg: p.liveTint,
          iconFg: p.danger,
          title: widget.commentId != null
              ? l.highlights_reportCommentTitle
              : l.highlights_reportTitle,
          subtitle: l.highlights_reportSubtitle,
        ),
        SpListCard(children: [
          for (final r in reasons)
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                dense: true,
                leading: Icon(
                  _reason == r.$1
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: _reason == r.$1 ? p.greenText : p.muted,
                ),
                title: Text(r.$2),
                onTap: _busy ? null : () => setState(() => _reason = r.$1),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          minLines: 2,
          maxLines: 4,
          maxLength: HighlightLimits.reportNoteMax,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: l.highlights_reportNoteHint),
        ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(_error!, style: TextStyle(color: p.danger, fontSize: 12.5)),
        ],
        const SizedBox(height: 10),
        SpButton(
          label: _busy ? l.inbox_sending : l.inbox_sendReport,
          icon: Icons.flag_outlined,
          expand: true,
          onTap: _reason == null || _busy ? null : _send,
        ),
      ],
    );
  }
}
