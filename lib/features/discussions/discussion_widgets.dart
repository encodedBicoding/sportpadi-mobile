import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/discussions/discussion_models.dart';
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Building blocks shared by the Discussions list, the thread, the composer
/// and the group / team sections.

IconData discussionFlairIcon(String flair) => switch (flair) {
      'question' => Icons.help_outline_rounded,
      'issue' => Icons.report_problem_outlined,
      'idea' => Icons.lightbulb_outline_rounded,
      _ => Icons.chat_bubble_outline_rounded,
    };

/// General · Question · Issue · Idea.
class DiscussionFlairPill extends StatelessWidget {
  const DiscussionFlairPill(this.flair, {super.key});
  final String flair;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final Color? tone = switch (flair) {
      'question' => p.ink,
      'issue' => p.danger,
      'idea' => p.orangeInk,
      _ => null,
    };
    return SpBadge(discussionFlairLabel(flair),
        icon: discussionFlairIcon(flair), tone: tone);
  }
}

/// Green "Resolved" pill.
class DiscussionResolvedPill extends StatelessWidget {
  const DiscussionResolvedPill({super.key});

  @override
  Widget build(BuildContext context) => SpBadge('Resolved',
      icon: Icons.check_circle_outline_rounded,
      tone: context.palette.greenText);
}

/// A small inline tag next to a name: OP, Admin, Coach.
class DiscussionTag extends StatelessWidget {
  const DiscussionTag(this.label, {super.key, required this.fg, required this.bg});
  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(
                color: fg,
                fontSize: 10.5,
                height: 1.25,
                fontWeight: FontWeight.w800)),
      );
}

/// Avatar, name, OP / Admin / Coach tags, "Tobi's guardian", and an optional
/// trailing note (time, "edited").
class DiscussionAuthorLine extends StatelessWidget {
  const DiscussionAuthorLine({
    super.key,
    required this.author,
    this.isOP = false,
    this.note,
    this.avatarSize = 20,
    this.fontSize = 12.5,
  });
  final DiscussionAuthor author;
  final bool isOP;
  final String? note;
  final double avatarSize;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final guardian = author.guardianOf;
    return Row(children: [
      WardAvatar(name: author.name, url: author.avatarUrl, size: avatarSize),
      const SizedBox(width: 6),
      Flexible(
        child: Text(author.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: p.ink,
                fontSize: fontSize,
                fontWeight: FontWeight.w700)),
      ),
      if (isOP) ...[
        const SizedBox(width: 5),
        DiscussionTag('OP', fg: Colors.white, bg: p.accentDeep),
      ],
      if (author.isAdmin) ...[
        const SizedBox(width: 5),
        DiscussionTag('Admin', fg: p.onHero, bg: p.hero),
      ] else if (author.isCoach) ...[
        const SizedBox(width: 5),
        DiscussionTag('Coach', fg: p.orangeInk, bg: p.orangeTint),
      ],
      if (guardian != null) ...[
        const SizedBox(width: 5),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: p.wardTint,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text("$guardian's guardian",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: p.wardInk,
                    fontSize: 10.5,
                    height: 1.25,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ],
      if (note != null && note!.isNotEmpty) ...[
        const SizedBox(width: 6),
        Text('· $note',
            maxLines: 1,
            style: TextStyle(color: p.muted, fontSize: fontSize - 1)),
      ],
    ]);
  }
}

/// "3h" (on the viewer's clock — see `fmtRelative`), plus "· edited".
String discussionTimeNote(DateTime? createdAt, {DateTime? editedAt}) {
  final t = fmtRelative(createdAt);
  if (editedAt == null) return t;
  return t.isEmpty ? 'edited' : '$t · edited';
}

class _VoteArrow extends StatelessWidget {
  const _VoteArrow({
    required this.up,
    required this.active,
    required this.onTap,
    required this.size,
  });
  final bool up;
  final bool active;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tone = up ? p.greenText : p.danger;
    return Material(
      color: active ? tone.withAlpha(34) : Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(
            up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: size,
            color: active ? tone : p.muted,
            semanticLabel: up ? 'Upvote' : 'Downvote',
          ),
        ),
      ),
    );
  }
}

Color _scoreColor(AppPalette p, int myVote) => myVote > 0
    ? p.greenText
    : myVote < 0
        ? p.danger
        : p.ink;

/// ▲ score, stacked (list cards) or in a row ([horizontal]: the thread and
/// comments). Upvotes only. My vote is highlighted; [onVote] gets 1 (the
/// controller turns a repeat into a clear). Null [onVote] disables it.
class DiscussionVotes extends StatelessWidget {
  const DiscussionVotes({
    super.key,
    required this.score,
    required this.myVote,
    required this.onVote,
    this.horizontal = false,
    this.compact = false,
  });
  final int score;
  final int myVote;
  final ValueChanged<int>? onVote;
  final bool horizontal;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final size = compact ? 16.0 : 19.0;
    final vote = onVote;
    final children = [
      _VoteArrow(
          up: true,
          active: myVote > 0,
          size: size,
          onTap: vote == null ? null : () => vote(1)),
      Padding(
        padding: horizontal
            ? const EdgeInsets.symmetric(horizontal: 2)
            : const EdgeInsets.symmetric(vertical: 1),
        child: Text('$score',
            style: TextStyle(
                color: _scoreColor(p, myVote),
                fontSize: compact ? 12.5 : 13.5,
                fontWeight: FontWeight.w800)),
      ),
      // Upvotes only — no downvote arrow.
    ];
    return horizontal
        ? Row(mainAxisSize: MainAxisSize.min, children: children)
        : SizedBox(
            width: 42,
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          );
  }
}

/// A selectable pill (filters, the composer's choices).
class DiscussionPill extends StatelessWidget {
  const DiscussionPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.leading,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  /// Instead of [icon] (a team crest).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = selected ? p.onHero : p.ink;
    return Material(
      color: selected ? p.hero : p.surface,
      shape: StadiumBorder(
          side: selected ? BorderSide.none : BorderSide(color: p.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 6),
            ] else if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

/// One discussion in a list: votes, tags, title, preview, thumbnail, who
/// and when, and the comment count. [compact] drops the preview (the group
/// and team sections).
class DiscussionCard extends StatelessWidget {
  const DiscussionCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onVote,
    this.compact = false,
    this.showTeam = true,
  });
  final DiscussionItem item;
  final VoidCallback onTap;
  final ValueChanged<int>? onVote;
  final bool compact;
  final bool showTeam;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final d = item;
    final team = showTeam ? d.teamName : null;
    final preview = d.preview.trim();
    final tags = <Widget>[
      if (d.pinned)
        SpBadge('Pinned', icon: Icons.push_pin_rounded, tone: p.greenText),
      if (d.locked)
        SpBadge('Locked', icon: Icons.lock_outline_rounded, tone: p.orangeInk),
      DiscussionFlairPill(d.flair),
      if (d.isResolved) const DiscussionResolvedPill(),
      if (team != null) SpBadge(team, icon: Icons.shield_outlined),
    ];
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(6, 10, 14, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DiscussionVotes(score: d.score, myVote: d.myVote, onVote: onVote),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 6, runSpacing: 4, children: tags),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (d.unseen) ...[
                  // New activity since I last looked.
                  Semantics(
                    label: 'New activity',
                    child: Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 7),
                      decoration: BoxDecoration(
                          color: p.accent, shape: BoxShape.circle),
                    ),
                  ),
                  const SizedBox(width: 7),
                ],
                Expanded(
                  child: Text(d.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 15.5,
                          height: 1.3,
                          fontWeight: FontWeight.w800)),
                ),
                if (d.imageUrl != null) ...[
                  const SizedBox(width: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: d.imageUrl!,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(width: 60, height: 60, color: p.surface2),
                      errorWidget: (_, __, ___) => Container(
                        width: 60,
                        height: 60,
                        color: p.surface2,
                        child: Icon(Icons.image_outlined,
                            size: 20, color: p.muted),
                      ),
                    ),
                  ),
                ],
              ]),
              if (!compact && preview.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(preview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: p.muted, fontSize: 13, height: 1.4)),
              ],
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: DiscussionAuthorLine(
                    author: d.author,
                    note: fmtRelative(d.createdAt),
                    avatarSize: 18,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.mode_comment_outlined, size: 15, color: p.muted),
                const SizedBox(width: 4),
                Text('${d.commentCount}',
                    style: TextStyle(
                        color: p.muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}

/// A photo full screen, pinch to zoom.
void openDiscussionImage(BuildContext context, String url) {
  // ignore: discarded_futures
  showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black,
    pageBuilder: (ctx, __, ___) => SafeArea(
      child: Stack(children: [
        Positioned.fill(
          child: InteractiveViewer(
            maxScale: 5,
            child: Center(
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                errorWidget: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 40),
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(ctx).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ),
      ]),
    ),
  );
}

/// A confirm dialog; true when confirmed.
Future<bool> confirmDiscussionAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true), child: Text(confirm)),
      ],
    ),
  );
  return ok == true;
}
