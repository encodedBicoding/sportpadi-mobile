import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/messages/message_models.dart';
import 'package:sportpadi_mobile/data/messages/messages_repository.dart';
import 'package:sportpadi_mobile/features/inbox/announcement_card.dart'
    show openAnnouncementUrl;
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Building blocks shared by the Messages tab, the thread, the new-message
/// flow and the admins' oversight screen.

/// A list timestamp, on the viewer's clock: "3:05 PM" today, then
/// "Yesterday", "Mon" this week, then a date (see `fmtRelative`).
String messageListTime(DateTime? d) {
  if (d == null) return '';
  final now = DateTime.now();
  if (dayKey(d).compareTo(dayKey(now)) >= 0) {
    return fmtInstant(d, style: InstantStyle.time);
  }
  return fmtRelative(d, now: now);
}

/// Violet "About Tobi" chip on a guardian thread.
class AboutWardChip extends StatelessWidget {
  const AboutWardChip(this.name, {super.key});
  final String name;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: p.wardTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.child_care_rounded, size: 12, color: p.wardInk),
        const SizedBox(width: 4),
        Flexible(
          child: Text('About $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: p.wardInk,
                  fontSize: 11.5,
                  height: 1.2,
                  fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

/// "Closed" / "Locked" pill for a read-only conversation.
class ConversationStatusPill extends StatelessWidget {
  const ConversationStatusPill(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (status == 'open') return const SizedBox.shrink();
    final locked = status == 'locked';
    return SpBadge(locked ? 'Locked' : 'Closed',
        icon: locked ? Icons.lock_outline_rounded : Icons.check_circle_outline,
        tone: locked ? p.orangeInk : null);
  }
}

/// One conversation in a list. [oversight] rows (an admin's view of the
/// whole group) name both sides instead of "You:".
class ConversationRow extends StatelessWidget {
  const ConversationRow({
    super.key,
    required this.item,
    this.onTap,
    this.oversight = false,
  });
  final ConversationItem item;
  final VoidCallback? onTap;
  final bool oversight;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = item;
    final unread = c.unread && !oversight;
    final preview =
        (c.lastPreview ?? '').trim().replaceAll(RegExp(r'\s*\n\s*'), ' ');
    final sub = oversight
        ? [
            'with ${c.staffName ?? 'Staff'}',
            if (c.subtitle.isNotEmpty && c.subtitle != c.groupName) c.subtitle,
          ].join(' · ')
        : [
            if (c.subtitle.isNotEmpty) c.subtitle,
            if (c.subtitle != c.groupName) c.groupName,
          ].join(' · ');
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        WardAvatar(name: c.title, url: c.avatarUrl, size: 46),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 15,
                          fontWeight:
                              unread ? FontWeight.w800 : FontWeight.w700)),
                ),
                if (c.muted && !oversight) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.notifications_off_outlined,
                      size: 15, color: p.muted),
                ],
                const SizedBox(width: 6),
                Text(messageListTime(c.lastMessageAt),
                    style: TextStyle(
                        color: unread ? p.greenText : p.muted,
                        fontSize: 11.5,
                        fontWeight:
                            unread ? FontWeight.w700 : FontWeight.w500)),
              ]),
              if (sub.isNotEmpty)
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 12)),
              if (c.aboutWard != null || !c.isOpen) ...[
                const SizedBox(height: 5),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  if (c.aboutWard != null)
                    AboutWardChip(c.aboutWard!.firstName),
                  if (!c.isOpen) ConversationStatusPill(c.status),
                ]),
              ],
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      if (c.lastFromMe && !oversight)
                        TextSpan(
                            text: 'You: ',
                            style: TextStyle(
                                color: p.muted, fontWeight: FontWeight.w600)),
                      TextSpan(
                          text: preview.isEmpty ? 'Photo' : preview,
                          style: TextStyle(
                              color: unread ? p.ink : p.muted,
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w400)),
                    ]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
                if (unread) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: p.accent, shape: BoxShape.circle),
                  ),
                ],
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}

/// Pick a photo from the gallery and upload it for a message in [groupId].
/// Null when the picker was cancelled; throws the upload's readable error.
Future<MessageAttachment?> pickMessageImage(
    WidgetRef ref, String groupId) async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 2000,
    imageQuality: 85,
  );
  if (picked == null) return null;
  final bytes = await picked.readAsBytes();
  final url = await ref.read(eventsRepositoryProvider).uploadImage(
        bytes,
        picked.mimeType ?? 'image/jpeg',
        assetType: 'groupImage',
        scopeId: groupId,
      );
  return MessageAttachment(url: url, kind: 'image');
}

/// Photos waiting to be sent, each with a remove button.
class PendingImagesStrip extends StatelessWidget {
  const PendingImagesStrip(
      {super.key, required this.images, required this.onRemove});
  final List<MessageAttachment> images;
  final void Function(MessageAttachment) onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (images.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final a = images[i];
          return Stack(clipBehavior: Clip.none, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: a.url,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                    width: 64,
                    height: 64,
                    color: p.surface2,
                    child: Icon(Icons.broken_image_outlined, color: p.muted)),
              ),
            ),
            Positioned(
              top: -6,
              right: -6,
              child: Material(
                color: p.hero,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onRemove(a),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(Icons.close_rounded,
                        size: 14, color: p.onHero),
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// Plain text with its web links made tappable; selectable as a whole
/// unless [selectable] is false (a chat bubble keeps long-press for its
/// actions, and offers "Select text" there instead).
class LinkifiedText extends ConsumerStatefulWidget {
  const LinkifiedText(this.text,
      {super.key,
      required this.style,
      required this.linkColor,
      this.selectable = true});
  final String text;
  final TextStyle style;
  final Color linkColor;
  final bool selectable;

  @override
  ConsumerState<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends ConsumerState<LinkifiedText> {
  static final _url = RegExp(r'''(https?://|www\.)[^\s<>"']+''',
      caseSensitive: false);
  static const _trailing = '.,;:!?)]}';
  final List<TapGestureRecognizer> _recognizers = [];

  void _clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final text = widget.text;
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _url.allMatches(text)) {
      var url = m.group(0)!;
      var end = m.end;
      while (url.isNotEmpty && _trailing.contains(url[url.length - 1])) {
        url = url.substring(0, url.length - 1);
        end--;
      }
      if (url.isEmpty) continue;
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final link = url;
      final r = TapGestureRecognizer()
        ..onTap = () => openAnnouncementUrl(ref, link);
      _recognizers.add(r);
      spans.add(TextSpan(
        text: link,
        style: TextStyle(
          color: widget.linkColor,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationColor: widget.linkColor,
        ),
        recognizer: r,
      ));
      last = end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    final rich = Text.rich(TextSpan(style: widget.style, children: spans));
    return widget.selectable ? SelectionArea(child: rich) : rich;
  }
}

/// Sends a report with a reason and optional details; true when it had
/// already been reported.
typedef ReportSubmit = Future<bool> Function(String reason, String details);

/// Report a message or an announcement: a reason and optional details.
/// Shows the outcome in a snackbar. Anything else reportable (a discussion,
/// a comment) passes its own [submit] and names itself with [what].
Future<void> showReportSheet(BuildContext context,
    {String? messageId,
    String? announcementId,
    String? what,
    ReportSubmit? submit}) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await showSpSheet<String>(
    context,
    builder: (_) => _ReportSheet(
        messageId: messageId,
        announcementId: announcementId,
        what: what,
        submit: submit),
  );
  if (result == null) return;
  messenger.showSnackBar(SnackBar(content: Text(result)));
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet(
      {this.messageId, this.announcementId, this.what, this.submit});
  final String? messageId;
  final String? announcementId;
  final String? what;
  final ReportSubmit? submit;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  String? _reason;
  final _details = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
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
      final submit = widget.submit;
      final already = submit != null
          ? await submit(reason, _details.text)
          : await ref.read(messagesRepositoryProvider).report(
                messageId: widget.messageId,
                announcementId: widget.announcementId,
                reason: reason,
                details: _details.text,
              );
      if (!mounted) return;
      Navigator.of(context).pop(already
          ? "You've already reported this — the admins will look at it."
          : "Thanks — your report was sent to the group's admins.");
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
    final what = widget.what ??
        (widget.announcementId != null ? 'announcement' : 'message');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSheetHeader(
          icon: Icons.flag_outlined,
          iconBg: p.liveTint,
          iconFg: p.danger,
          title: 'Report this $what',
          subtitle: "Reports go to the group's admins and the SportPadi team.",
        ),
        SpListCard(children: [
          for (final r in messageReportReasons)
            ListTile(
              dense: true,
              leading: Icon(
                _reason == r.value
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: _reason == r.value ? p.greenText : p.muted,
              ),
              title: Text(r.label),
              onTap: _busy ? null : () => setState(() => _reason = r.value),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _details,
          minLines: 2,
          maxLines: 5,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Anything the admins should know (optional)',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(_error!, style: TextStyle(color: p.danger, fontSize: 12.5)),
        ],
        const SizedBox(height: 10),
        SpButton(
          label: _busy ? 'Sending…' : 'Send report',
          icon: Icons.flag_outlined,
          expand: true,
          onTap: _reason == null || _busy ? null : _send,
        ),
      ],
    );
  }
}
