import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/links/link_resolver.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/announcements/announcement_models.dart';
import 'package:sportpadi_mobile/data/announcements/announcements_repository.dart';
import 'package:sportpadi_mobile/features/inbox/announcement_card.dart';
import 'package:sportpadi_mobile/features/inbox/message_widgets.dart'
    show showReportSheet;
import 'package:sportpadi_mobile/features/settings/timezone_provider.dart';
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/player_link.dart';

/// One announcement: the full text (selectable, links tappable), its
/// attachments and link, "Got it" for recipients, and — for its sender and
/// the group's admins — who has seen it, plus Unpin and Delete.
///
/// Opening it marks it seen server-side; the Inbox and its badge are
/// refreshed once it has loaded.
class AnnouncementDetailScreen extends ConsumerStatefulWidget {
  const AnnouncementDetailScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<AnnouncementDetailScreen> createState() =>
      _AnnouncementDetailScreenState();
}

class _AnnouncementDetailScreenState
    extends ConsumerState<AnnouncementDetailScreen> {
  bool _synced = false;
  bool _ackedHere = false;
  bool _allPeople = false;
  // Read receipts filter: 0 Not seen · 1 Seen · 2 Everyone (web twin:
  // inbox/announcements/[id] ManagePanel).
  int _receiptTab = 0;
  String? _busy; // 'ack' | 'unpin' | 'delete'

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _refreshLists() {
    ref.invalidate(announcementsUnreadProvider);
    ref.invalidate(announcementsInboxProvider);
  }

  /// Pull-to-refresh: the announcement (with its receipts); the spinner
  /// stays until it's back, and an error doesn't escape.
  Future<void> _pull() {
    ref.invalidate(announcementDetailProvider(widget.id));
    return settleAll([ref.read(announcementDetailProvider(widget.id).future)]);
  }

  Future<void> _ack(AnnouncementItem a) async {
    setState(() => _busy = 'ack');
    try {
      await ref.read(announcementsRepositoryProvider).ack(a.id);
      if (!mounted) return;
      setState(() => _ackedHere = true);
      _refreshLists();
      ref.invalidate(announcementDetailProvider(widget.id));
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _unpin(AnnouncementItem a) async {
    setState(() => _busy = 'unpin');
    try {
      await ref.read(announcementsRepositoryProvider).unpin(a.id);
      if (!mounted) return;
      ref.invalidate(announcementDetailProvider(widget.id));
      ref.invalidate(pinnedAnnouncementsProvider);
      ref.invalidate(sentAnnouncementsProvider);
      ref.invalidate(announcementsInboxProvider);
      _snack('Unpinned.');
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _delete(AnnouncementItem a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this announcement?'),
        content: const Text(
            "It disappears from everyone's inbox and from the group page. "
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = 'delete');
    try {
      await ref.read(announcementsRepositoryProvider).delete(a.id);
      if (!mounted) return;
      _refreshLists();
      ref.invalidate(pinnedAnnouncementsProvider);
      ref.invalidate(sentAnnouncementsProvider);
      final messenger = ScaffoldMessenger.of(context);
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/inbox');
      }
      messenger
          .showSnackBar(const SnackBar(content: Text('Announcement deleted.')));
    } catch (e) {
      _snack('$e');
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _openAttachment(AnnouncementAttachment a) async {
    final uri = Uri.tryParse(a.url);
    if (uri == null) return;
    try {
      // Images in the in-app browser (a quick look, then back); PDFs in
      // whatever the phone reads PDFs with.
      final ok = await launchUrl(uri,
          mode: a.isPdf
              ? LaunchMode.externalApplication
              : LaunchMode.inAppBrowserView);
      if (!ok) await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {
      _snack("Couldn't open the attachment.");
    }
  }

  void _openLink(AnnouncementLink l) {
    final route =
        resolveLinkRoute(l.url) ?? (l.type == 'team' ? '/teams/${l.id}' : null);
    if (route != null) {
      context.push(route);
    } else if (l.url != null) {
      // ignore: discarded_futures
      openAnnouncementUrl(ref, l.url!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final detail = ref.watch(announcementDetailProvider(widget.id));
    ref.watch(viewerTimezoneProvider); // repaint stamps on a zone change
    ref.listen<AsyncValue<AnnouncementDetail>>(
        announcementDetailProvider(widget.id), (prev, next) {
      // The GET marked it seen: the badge and the list are now stale.
      if (!_synced && next.hasValue) {
        _synced = true;
        _refreshLists();
      }
    });
    final d = detail.valueOrNull;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SpHeader(
              title: 'Announcement',
              subtitle: d?.item.groupName,
              actions: [
                // Recipients can report it to the group's admins (B8).
                if (d != null && d.isRecipient)
                  SpRoundButton(
                    icon: Icons.flag_outlined,
                    tooltip: 'Report',
                    onTap: () =>
                        showReportSheet(context, announcementId: widget.id),
                  ),
              ],
            ),
          ),
          Expanded(
            // Loading / error are pullable too (the body has its own
            // RefreshIndicator).
            child: detail.maybeWhen(
              data: (loaded) => _body(p, loaded),
              orElse: () => RefreshIndicator(
                onRefresh: _pull,
                child: PullableState(
                  child: AsyncView<AnnouncementDetail>(
                    value: detail,
                    onRetry: () =>
                        ref.invalidate(announcementDetailProvider(widget.id)),
                    data: (_) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
          if (d != null && d.isRecipient) _ackBar(p, d.item),
        ]),
      ),
    );
  }

  Widget _body(AppPalette p, AnnouncementDetail d) {
    final a = d.item;
    final wards = a.wardsLabel;
    final r = d.receipts;
    return RefreshIndicator(
      onRefresh: _pull,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          RailCard(
            urgent: a.isUrgent,
            padding: const EdgeInsets.fromLTRB(20, 18, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Crest(logoUrl: a.groupImageUrl, label: a.groupName, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.groupName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                          Text('From ${a.senderName} · ${a.roleLabel}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: p.muted, fontSize: 12.5)),
                        ]),
                  ),
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (a.isUrgent) const UrgentPill(),
                  if (a.audienceLabel.isNotEmpty)
                    SpBadge('To ${a.audienceLabel}',
                        icon: Icons.groups_outlined),
                  if (a.isPinned)
                    SpBadge(
                        'Pinned until ${fmtInstant(a.pinnedUntil, style: InstantStyle.day)}',
                        icon: Icons.push_pin_outlined),
                  if (wards != null) WardsForChip(wards),
                ]),
                const SizedBox(height: 14),
                Text(a.title,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 20,
                        height: 1.3,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                    a.createdAt == null
                        ? ''
                        : '${timeAgo(a.createdAt)} · ${fmtInstant(a.createdAt, style: InstantStyle.full)}',
                    style: TextStyle(color: p.muted, fontSize: 12)),
                const SizedBox(height: 14),
                _LinkifiedText(
                  a.body,
                  style: TextStyle(color: p.ink, fontSize: 15, height: 1.6),
                  linkColor: p.greenText,
                ),
                if (a.images.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _Images(images: a.images, onOpen: _openAttachment),
                ],
                if (a.pdfs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final f in a.pdfs) _pdfRow(p, f),
                ],
                if (a.expiresAt != null) ...[
                  const SizedBox(height: 14),
                  Text(
                      'Hidden from the inbox after ${fmtInstant(a.expiresAt, style: InstantStyle.day)}',
                      style: TextStyle(color: p.muted, fontSize: 12)),
                ],
              ],
            ),
          ),
          if (a.link != null) ...[
            const SizedBox(height: 12),
            _linkButton(p, a.link!),
          ],
          if (d.canManage && r != null) ...[
            const SizedBox(height: 22),
            _receipts(p, r),
          ],
          if (d.canManage) ...[
            const SizedBox(height: 18),
            Row(children: [
              if (a.isPinned) ...[
                Expanded(
                  child: _OutlinePill(
                    label: _busy == 'unpin' ? 'Unpinning…' : 'Unpin',
                    icon: Icons.push_pin_outlined,
                    onTap: _busy == null ? () => _unpin(a) : null,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: _OutlinePill(
                  label: _busy == 'delete' ? 'Deleting…' : 'Delete',
                  icon: Icons.delete_outline_rounded,
                  color: p.danger,
                  onTap: _busy == null ? () => _delete(a) : null,
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _pdfRow(AppPalette p, AnnouncementAttachment f) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: p.surface2,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openAttachment(f),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(Icons.picture_as_pdf_outlined, size: 20, color: p.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Text(f.name ?? 'Attachment (PDF)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600)),
              ),
              Icon(Icons.open_in_new_rounded, size: 16, color: p.muted),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _linkButton(AppPalette p, AnnouncementLink l) {
    final isTeam = l.type == 'team';
    final label = l.label.isNotEmpty
        ? '${isTeam ? 'Open team' : 'Open event'} · ${l.label}'
        : (isTeam ? 'Open team' : 'Open event');
    return SpButton(
      label: label,
      icon: isTeam ? Icons.shield_outlined : Icons.event_outlined,
      expand: true,
      onTap: () => _openLink(l),
    );
  }

  Widget _receipts(AppPalette p, AnnouncementReceipts r) {
    int byName(ReceiptPerson x, ReceiptPerson y) =>
        x.displayName.toLowerCase().compareTo(y.displayName.toLowerCase());
    final notSeen = [for (final x in r.people) if (!x.seen) x]..sort(byName);
    // Seen: "Got it" first, then the rest who opened it.
    final seen = [for (final x in r.people) if (x.seen) x]
      ..sort((x, y) => x.acked != y.acked ? (x.acked ? -1 : 1) : byName(x, y));
    final everyone = [...notSeen, ...seen];
    final people = switch (_receiptTab) {
      0 => notSeen,
      1 => seen,
      _ => everyone,
    };
    const cap = 30;
    final shown = _allPeople ? people : people.take(cap).toList();
    final delivery = [
      if (r.pushed > 0) '${r.pushed} by push',
      if (r.emailed > 0) '${r.emailed} by email',
    ];
    final seenPct = r.total == 0 ? 0.0 : (r.seen / r.total).clamp(0.0, 1.0);
    final ackPct = r.total == 0 ? 0.0 : (r.acked / r.total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SpSectionTitle('Read receipts'),
        const SizedBox(height: 10),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                SpIconTile(Icons.visibility_outlined,
                    bg: p.accentTint, fg: p.greenText, size: 40, iconSize: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(text: 'Seen by ${r.seen} of ${r.total}'),
                            TextSpan(
                                text: ' · ${r.acked} tapped Got it',
                                style: TextStyle(
                                    color: p.muted,
                                    fontWeight: FontWeight.w600)),
                          ]),
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800),
                        ),
                        Text(
                            [
                              '${r.deliveries} ${r.deliveries == 1 ? 'delivery' : 'deliveries'}',
                              ...delivery,
                            ].join(' · '),
                            style: TextStyle(color: p.muted, fontSize: 11.5)),
                      ]),
                ),
              ]),
              const SizedBox(height: 12),
              // Two layers, like the web: seen (light) under "Got it" (solid).
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: SizedBox(
                  height: 8,
                  child: Stack(children: [
                    Positioned.fill(child: ColoredBox(color: p.surface2)),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: seenPct,
                      heightFactor: 1,
                      child: ColoredBox(color: p.accent.withAlpha(102)),
                    ),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: ackPct,
                      heightFactor: 1,
                      child: ColoredBox(color: p.accent),
                    ),
                  ]),
                ),
              ),
              if (r.total > 0) ...[
                const SizedBox(height: 14),
                SpSegmented(
                  options: [
                    'Not seen',
                    'Seen · ${seen.length}',
                    'All · ${everyone.length}',
                  ],
                  badges: [notSeen.length, null, null],
                  index: _receiptTab,
                  onChanged: (i) => setState(() {
                    _receiptTab = i;
                    _allPeople = false;
                  }),
                ),
                const SizedBox(height: 4),
                Text(
                    switch (_receiptTab) {
                      0 => notSeen.isEmpty
                          ? 'Everyone has opened it'
                          : '${notSeen.length} ${notSeen.length == 1 ? 'hasn\u2019t' : 'haven\u2019t'} opened it yet',
                      1 => '${seen.length} opened it · ${r.acked} tapped Got it',
                      _ => 'All ${everyone.length} who received it',
                    },
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.muted, fontSize: 11.5)),
              ],
            ],
          ),
        ),
        if (r.total > 0) ...[
          const SizedBox(height: 10),
          if (people.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                        _receiptTab == 0
                            ? Icons.done_all_rounded
                            : Icons.visibility_off_outlined,
                        size: 18,
                        color: _receiptTab == 0 ? p.greenText : p.muted),
                    const SizedBox(width: 6),
                    Text(
                        switch (_receiptTab) {
                          0 => 'Everyone has seen it',
                          1 => 'No one has opened it yet',
                          _ => 'No one to show',
                        },
                        style: TextStyle(
                            color: _receiptTab == 0 ? p.greenText : p.muted,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700)),
                  ]),
            )
          else ...[
            SpListCard(children: [
              for (final person in shown) _personRow(p, person),
            ]),
            if (!_allPeople && people.length > cap)
              TextButton(
                onPressed: () => setState(() => _allPeople = true),
                child: Text('Show all ${people.length}'),
              ),
          ],
        ],
      ],
    );
  }

  Widget _personRow(AppPalette p, ReceiptPerson person) {
    final via =
        person.guardians.isEmpty ? null : 'via ${person.guardians.join(', ')}';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => openPlayerProfile(context, ref, person.userId),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Row(children: [
          WardAvatar(name: person.displayName, url: person.avatarUrl, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(person.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600)),
                ),
                if (person.isWard) ...[
                  const SizedBox(width: 6),
                  const WardBadge(),
                ],
              ]),
              if (via != null)
                Text(via,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 11.5)),
            ]),
          ),
          const SizedBox(width: 8),
          if (person.acked)
            SpBadge('Got it', icon: Icons.check_rounded, tone: p.greenText)
          else if (person.seen)
            const SpBadge('Seen', icon: Icons.done_rounded)
          else
            SpBadge('Not seen', tone: p.orangeInk),
        ]),
      ),
    );
  }

  Widget _ackBar(AppPalette p, AnnouncementItem a) {
    final acked = a.isAcked || _ackedHere;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      decoration: BoxDecoration(
        color: p.bg,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: acked
          ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.check_circle_rounded, size: 20, color: p.greenText),
              const SizedBox(width: 8),
              Text('You tapped Got it',
                  style: TextStyle(
                      color: p.greenText,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ])
          : SpButton(
              label: _busy == 'ack' ? 'Sending…' : 'Got it',
              icon: Icons.thumb_up_alt_outlined,
              tone: SpButtonTone.brand,
              expand: true,
              onTap: _busy == null ? () => _ack(a) : null,
            ),
    );
  }
}

/// Image attachments: one large, or a two-column grid. Tap to open.
class _Images extends StatelessWidget {
  const _Images({required this.images, required this.onOpen});
  final List<AnnouncementAttachment> images;
  final void Function(AnnouncementAttachment) onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget tile(AnnouncementAttachment a) => ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Material(
            color: p.surface2,
            child: InkWell(
              onTap: () => onOpen(a),
              child: CachedNetworkImage(
                imageUrl: a.url,
                fit: BoxFit.cover,
                placeholder: (_, __) => const SizedBox.shrink(),
                errorWidget: (_, __, ___) => Center(
                    child: Icon(Icons.broken_image_outlined, color: p.muted)),
              ),
            ),
          ),
        );
    if (images.length == 1) {
      return AspectRatio(aspectRatio: 16 / 10, child: tile(images.first));
    }
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [for (final a in images) tile(a)],
    );
  }
}

/// A quiet outlined pill button (Unpin, Delete).
class _OutlinePill extends StatelessWidget {
  const _OutlinePill(
      {required this.label, required this.icon, this.onTap, this.color});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = onTap == null ? p.muted : (color ?? p.ink);
    return Material(
      color: p.surface,
      shape: StadiumBorder(side: BorderSide(color: p.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 17, color: c),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Plain text with its web links made tappable; selectable as a whole.
class _LinkifiedText extends ConsumerStatefulWidget {
  const _LinkifiedText(this.text,
      {required this.style, required this.linkColor});
  final String text;
  final TextStyle style;
  final Color linkColor;

  @override
  ConsumerState<_LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends ConsumerState<_LinkifiedText> {
  static final _url =
      RegExp(r'''(https?://|www\.)[^\s<>"']+''', caseSensitive: false);
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
      // "see https://x.com/y." — the full stop is the sentence's, not the URL's.
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
    return SelectionArea(
      child: Text.rich(TextSpan(style: widget.style, children: spans)),
    );
  }
}
