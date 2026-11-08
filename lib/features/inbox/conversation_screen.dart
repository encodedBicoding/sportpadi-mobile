import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/push/push_service.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/messages/message_models.dart';
import 'package:sportpadi_mobile/data/messages/messages_repository.dart';
import 'package:sportpadi_mobile/features/inbox/message_start.dart'
    show SpRoundPhotoButton;
import 'package:sportpadi_mobile/features/inbox/message_widgets.dart';
import 'package:sportpadi_mobile/features/settings/timezone_provider.dart';
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/player_link.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// One conversation (docs B4/B5/B8): staff on one side, a member — or a
/// ward's guardians — on the other. Polls every few seconds while open and
/// on resume; fetching the newest page marks it read. Group admins who
/// aren't taking part read it here too, read-only.
class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen>
    with WidgetsBindingObserver {
  static const _pollEvery = Duration(seconds: 8);
  static const _maxImages = 4;

  late final PushService _push;
  Timer? _poll;
  bool _foreground = true;
  bool _synced = false;

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<MessageAttachment> _images = [];
  bool _sending = false;
  bool _uploading = false;
  bool _loadingEarlier = false;
  bool _busy = false; // close / mute

  String get _id => widget.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _push = ref.read(pushServiceProvider);
    _push.activeConversationId = _id;
    _poll = Timer.periodic(_pollEvery, (_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    if (_push.activeConversationId == _id) _push.activeConversationId = null;
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _push.activeConversationId = _id;
      // ignore: discarded_futures
      _tick();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _foreground = false;
      // In the background, a push for this thread should show as usual.
      if (_push.activeConversationId == _id) _push.activeConversationId = null;
    }
  }

  Future<void> _tick() async {
    if (!mounted || !_foreground) return;
    final changed =
        await ref.read(conversationProvider(_id).notifier).refreshLatest();
    if (changed && mounted) _listsStale();
  }

  /// Reading marks it read: the badge and the list are stale.
  void _listsStale() {
    ref.invalidate(messagesUnreadProvider);
    ref.invalidate(messagesListProvider);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ── actions ──────────────────────────────────────────────────────────────

  Future<void> _addImage(ConversationInfo c) async {
    if (_images.length >= _maxImages || _uploading) return;
    setState(() => _uploading = true);
    try {
      final a = await pickMessageImage(ref, c.group.id);
      if (a != null && mounted) setState(() => _images.add(a));
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  bool get _canSend =>
      !_sending &&
      !_uploading &&
      (_input.text.trim().isNotEmpty || _images.isNotEmpty);

  Future<void> _send() async {
    if (!_canSend) return;
    final body = _input.text.trim();
    final images = List.of(_images);
    setState(() => _sending = true);
    try {
      await ref
          .read(messagesRepositoryProvider)
          .send(_id, body: body, attachments: images);
      if (!mounted) return;
      _input.clear();
      setState(() => _images.clear());
      await ref.read(conversationProvider(_id).notifier).refreshLatest();
      if (!mounted) return;
      ref.invalidate(messagesListProvider);
      if (_scroll.hasClients) {
        // ignore: discarded_futures
        _scroll.animateTo(0,
            duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _loadEarlier() async {
    if (_loadingEarlier) return;
    setState(() => _loadingEarlier = true);
    try {
      await ref.read(conversationProvider(_id).notifier).loadEarlier();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _loadingEarlier = false);
    }
  }

  Future<void> _close() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.inbox_closeThisConversation),
        content: Text(
            l10n.inbox_itBecomesReadOnlyFor2),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.inbox_cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.inbox_closeIt)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(messagesRepositoryProvider).close(_id);
      if (!mounted) return;
      await ref.read(conversationProvider(_id).notifier).refreshLatest();
      if (!mounted) return;
      ref.invalidate(messagesListProvider);
      _snack(l10n.inbox_conversationClosed2);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mute(ConversationInfo c) async {
    final choice = await showSpSheet<String>(
      context,
      builder: (ctx) {
        final p = ctx.palette;
        Widget tile(String value, IconData icon, String label) => ListTile(
              leading: Icon(icon, color: p.ink),
              title: Text(label),
              onTap: () => Navigator.of(ctx).pop(value),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SpSheetHeader(
              icon: Icons.notifications_off_outlined,
              title: l10n.inbox_muteThisConversation,
              subtitle: c.isMuted
                  ? (c.isMutedForever
                      ? l10n.inbox_mutedUntilYouTurnIt
                      : l10n.inbox_mutedUntil(fmtInstant(c.mutedUntil)))
                  : l10n.inbox_youllStillSeeNewMessages,
            ),
            SpListCard(children: [
              tile('8', Icons.schedule_rounded, l10n.inbox_for8Hours),
              tile('168', Icons.date_range_outlined, l10n.inbox_for1Week),
              tile('forever', Icons.notifications_off_outlined,
                  l10n.inbox_untilITurnItBack),
              if (c.isMuted)
                tile('off', Icons.notifications_active_outlined, l10n.inbox_unmute),
            ]),
          ],
        );
      },
    );
    if (choice == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(messagesRepositoryProvider);
      switch (choice) {
        case 'forever':
          await repo.mute(_id, forever: true);
        case 'off':
          await repo.mute(_id);
        default:
          await repo.mute(_id, hours: int.tryParse(choice) ?? 8);
      }
      if (!mounted) return;
      await ref.read(conversationProvider(_id).notifier).refreshLatest();
      if (!mounted) return;
      _listsStale();
      _snack(choice == 'off' ? l10n.inbox_unmuted : l10n.inbox_muted2);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(ChatMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.inbox_deleteThisMessage),
        content: Text(
            l10n.inbox_everyoneInTheConversationWill2),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.inbox_cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.inbox_delete)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(messagesRepositoryProvider).deleteMessage(_id, m.id);
      if (!mounted) return;
      ref.read(conversationProvider(_id).notifier).markDeleted(m.id);
      ref.invalidate(messagesListProvider);
      _snack(l10n.inbox_messageDeleted2);
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _messageActions(ChatMessage m) async {
    if (m.deleted) return;
    final canReport = !m.mine;
    if (!canReport && !m.canDelete && m.body.isEmpty) return;
    final action = await showSpSheet<String>(
      context,
      builder: (ctx) {
        final p = ctx.palette;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SpListCard(children: [
              if (m.body.isNotEmpty)
                ListTile(
                  leading: Icon(Icons.copy_rounded, color: p.ink),
                  title: Text(l10n.inbox_copyText),
                  onTap: () => Navigator.of(ctx).pop('copy'),
                ),
              if (m.body.isNotEmpty)
                ListTile(
                  leading: Icon(Icons.text_fields_rounded, color: p.ink),
                  title: Text(l10n.inbox_selectText),
                  onTap: () => Navigator.of(ctx).pop('select'),
                ),
              if (m.canDelete)
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: p.danger),
                  title: Text(l10n.inbox_delete, style: TextStyle(color: p.danger)),
                  onTap: () => Navigator.of(ctx).pop('delete'),
                ),
              if (canReport)
                ListTile(
                  leading: Icon(Icons.flag_outlined, color: p.danger),
                  title: Text(l10n.inbox_report),
                  onTap: () => Navigator.of(ctx).pop('report'),
                ),
            ]),
          ],
        );
      },
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.body));
        _snack(l10n.inbox_copied);
      case 'select':
        await showSpSheet<void>(
          context,
          builder: (ctx) {
            final p = ctx.palette;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SpSheetHeader(
                  icon: Icons.text_fields_rounded,
                  title: m.senderName,
                  subtitle:
                      m.createdAt == null ? null : fmtInstant(m.createdAt),
                ),
                LinkifiedText(
                  m.body,
                  style: TextStyle(color: p.ink, fontSize: 15, height: 1.5),
                  linkColor: p.greenText,
                ),
              ],
            );
          },
        );
      case 'delete':
        await _delete(m);
      case 'report':
        await showReportSheet(context, messageId: m.id);
    }
  }

  void _openImage(String url) {
    // ignore: discarded_futures
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: context.l10n.inbox_close,
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
              tooltip: context.l10n.inbox_close,
              onPressed: () => Navigator.of(ctx).pop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
        ]),
      ),
    );
  }

  // ── build ────────────────────────────────────────────────────────────────

  String _subtitle(ConversationInfo c) {
    if (c.isProfile) return context.l10n.inbox_directMessage;
    if (c.isOversight) {
      return [
        'with ${c.staffName}',
        if (c.teamName != null) c.teamName!,
      ].join(' · ');
    }
    if (c.mySide == 'member') {
      if (c.isContactAdmins) return context.l10n.inbox_contactTheAdmins2;
      return c.teamName != null ? context.l10n.inbox_coach3(c.teamName ?? '') : context.l10n.inbox_admin;
    }
    return c.teamName ?? c.group.name;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final thread = ref.watch(conversationProvider(_id));
    ref.watch(viewerTimezoneProvider); // repaint stamps on a zone change
    ref.listen<AsyncValue<ConversationThread>>(conversationProvider(_id),
        (prev, next) {
      // The first GET marked it read.
      if (!_synced && next.hasValue) {
        _synced = true;
        _listsStale();
      }
    });
    final c = thread.valueOrNull?.conversation;
    final party = c != null && !c.isOversight;
    final menu = c == null
        ? const <PopupMenuEntry<String>>[]
        : <PopupMenuEntry<String>>[
            if (party)
              PopupMenuItem(
                value: 'mute',
                child: Text(c.isMuted ? context.l10n.inbox_mutedChange : context.l10n.inbox_mute),
              ),
            if (c.canClose)
              PopupMenuItem(
                  value: 'close', child: Text(context.l10n.inbox_closeConversation)),
            if (c.hasGroup)
              PopupMenuItem(
                  value: 'group', child: Text(context.l10n.inbox_open2(c.group.name))),
            if (c.isProfile && c.otherUserId != null)
              PopupMenuItem(value: 'profile', child: Text(context.l10n.inbox_viewProfile)),
          ];
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
            child: SpHeader(
              title: c?.title ?? context.l10n.inbox_conversation,
              subtitle: c == null ? null : _subtitle(c),
              actions: [
                if (c != null && c.isMuted)
                  Icon(Icons.notifications_off_outlined,
                      size: 18, color: p.muted),
                if (menu.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: context.l10n.inbox_more,
                    enabled: !_busy,
                    icon: Icon(Icons.more_vert_rounded, color: p.ink),
                    onSelected: (v) {
                      final info = c;
                      if (info == null) return;
                      switch (v) {
                        case 'mute':
                          // ignore: discarded_futures
                          _mute(info);
                        case 'close':
                          // ignore: discarded_futures
                          _close();
                        case 'group':
                          context.push('/groups/${info.group.id}');
                        case 'profile':
                          context.push('/players/${info.otherUserId}');
                      }
                    },
                    itemBuilder: (_) => menu,
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView<ConversationThread>(
              value: thread,
              onRetry: () => ref.invalidate(conversationProvider(_id)),
              data: (t) => Column(children: [
                _InfoStrip(info: t.conversation),
                Expanded(child: _messages(p, t)),
                _bottom(p, t.conversation),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _messages(AppPalette p, ConversationThread t) {
    final c = t.conversation;
    final showNames = c.isContactAdmins || c.aboutWard != null || c.isOversight;
    // Oldest → newest with day separators, then reversed for a list that
    // starts at the bottom (index 0 = newest).
    final rows = <Widget>[];
    // Days are the viewer's days, not the phone's or UTC's.
    final now = DateTime.now();
    String? lastDay;
    String? lastSender;
    for (final m in t.messages) {
      final at = m.createdAt;
      if (at != null) {
        final day = dayKey(at);
        if (day != lastDay) {
          rows.add(_DaySeparator(label: fmtDayLabel(at, now: now)));
          lastDay = day;
          lastSender = null;
        }
      }
      final right = c.isOversight ? m.senderSide == 'staff' : m.mine;
      final firstInRun = m.senderId != lastSender;
      rows.add(_Bubble(
        message: m,
        right: right,
        showName: showNames && firstInRun && !m.mine,
        onLongPress: () => _messageActions(m),
        onImage: _openImage,
      ));
      lastSender = m.senderId;
    }
    if (t.hasEarlier) {
      rows.insert(
        0,
        Center(
          child: TextButton.icon(
            onPressed: _loadingEarlier ? null : _loadEarlier,
            icon: _loadingEarlier
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.history_rounded, size: 18),
            label: Text(context.l10n.inbox_loadEarlierMessages),
          ),
        ),
      );
    }
    if (t.messages.isEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(context.l10n.inbox_noMessagesYet,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 13)),
      ));
    }
    // Newest at the bottom; the thread polls, so no pull-to-refresh.
    final items = rows.reversed.toList();
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      itemCount: items.length,
      itemBuilder: (_, i) => items[i],
    );
  }

  Widget _bottom(AppPalette p, ConversationInfo c) {
    String? banner;
    IconData icon = Icons.lock_outline_rounded;
    if (c.isOversight) {
      banner = context.l10n.inbox_youreViewingThisAsA;
      icon = Icons.visibility_outlined;
    } else if (c.isClosed) {
      banner = c.mySide == 'member'
          ? context.l10n.inbox_thisConversationWasClosedYou
          : context.l10n.inbox_thisConversationWasClosedIt;
      icon = Icons.check_circle_outline;
    } else if (c.isLocked) {
      banner = c.mySide == 'member'
          ? context.l10n.inbox_thisConversationIsLockedYoure
          : context.l10n.inbox_thisConversationIsLockedThe;
    } else if (!c.canReply) {
      banner = context.l10n.inbox_youCantReplyInThis;
    }
    if (banner != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
        decoration: BoxDecoration(
          color: p.surface2,
          border: Border(top: BorderSide(color: p.line)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: p.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(banner,
                style: TextStyle(color: p.muted, fontSize: 13, height: 1.4)),
          ),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: p.bg,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_images.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: PendingImagesStrip(
                images: _images,
                onRemove: (a) => setState(() => _images.remove(a)),
              ),
            ),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          SpRoundPhotoButton(
            busy: _uploading,
            onTap: _images.length >= _maxImages || _sending
                ? null
                : () => _addImage(c),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 5,
              maxLength: 2000,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: context.l10n.inbox_message,
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
            color: _canSend ? p.accentDeep : p.surface2,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _canSend ? _send : null,
              child: SizedBox(
                width: 44,
                height: 44,
                child: _sending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.send_rounded,
                        size: 20, color: _canSend ? Colors.white : p.muted),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// Under the header: the group, the ward it's about (and, for staff, their
/// guardians), and the oversight note.
class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.info});
  final ConversationInfo info;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = info;
    final ward = c.aboutWard;
    final guardians = c.guardians.map((g) => g.name).join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              WardAvatar(name: c.title, url: c.avatarUrl, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (c.isProfile)
                      GestureDetector(
                        onTap: c.otherUserId == null
                            ? null
                            : () => context.push('/players/${c.otherUserId}'),
                        child: Text(context.l10n.inbox_directMessageViewProfile,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: p.muted,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      )
                    else
                      Row(children: [
                        Crest(
                            logoUrl: c.group.imageUrl,
                            label: c.group.name,
                            size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                              [
                                c.group.name,
                                if (c.teamName != null) c.teamName!,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    if (ward != null) ...[
                      const SizedBox(height: 5),
                      AboutWardChip(ward.firstName),
                    ],
                    if (ward != null &&
                        c.mySide != 'member' &&
                        guardians.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(context.l10n.inbox_withSGuardians(ward.firstName, guardians),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.wardInk, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              if (!c.isOversight && c.status != 'open') ...[
                const SizedBox(width: 6),
                ConversationStatusPill(c.status),
              ],
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.visibility_outlined, size: 14, color: p.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    c.isProfile
                        ? context.l10n.inbox_justTheTwoOfYou2
                        : context.l10n.inbox_visibleToSAdmins(c.group.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 11.5)),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: p.surface2,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: TextStyle(
                  color: p.muted, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.right,
    required this.showName,
    required this.onLongPress,
    required this.onImage,
  });
  final ChatMessage message;
  final bool right;
  final bool showName;
  final VoidCallback onLongPress;
  final void Function(String url) onImage;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final m = message;
    final maxW = MediaQuery.sizeOf(context).width * 0.78;
    final mineStyle = right && m.mine;
    final bg = m.deleted
        ? Colors.transparent
        : mineStyle
            ? p.accentDeep
            : right
                ? p.accentTint
                : p.surface;
    final fg = mineStyle ? Colors.white : p.ink;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(right ? 18 : 6),
      bottomRight: Radius.circular(right ? 6 : 18),
    );
    final time = fmtInstant(m.createdAt, style: InstantStyle.time);

    Widget content;
    if (m.deleted) {
      content = Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block_rounded, size: 14, color: p.muted),
        const SizedBox(width: 6),
        Text(context.l10n.inbox_messageDeleted,
            style: TextStyle(
                color: p.muted, fontSize: 13.5, fontStyle: FontStyle.italic)),
      ]);
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.attachments.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: m.body.isEmpty ? 0 : 8),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final a in m.attachments)
                  GestureDetector(
                    onTap: () => onImage(a.url),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: a.url,
                        width: m.attachments.length == 1 ? 220 : 104,
                        height: m.attachments.length == 1 ? 160 : 104,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                            width: m.attachments.length == 1 ? 220 : 104,
                            height: m.attachments.length == 1 ? 160 : 104,
                            color: p.surface2),
                        errorWidget: (_, __, ___) => Container(
                          width: 104,
                          height: 104,
                          color: p.surface2,
                          child:
                              Icon(Icons.broken_image_outlined, color: p.muted),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          if (m.body.isNotEmpty)
            LinkifiedText(
              m.body,
              style: TextStyle(color: fg, fontSize: 14.5, height: 1.4),
              linkColor: mineStyle ? Colors.white : p.greenText,
              selectable: false,
            ),
        ],
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: showName ? 10 : 3, bottom: 3),
      child: Column(
        crossAxisAlignment:
            right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showName)
            Padding(
              padding: const EdgeInsets.only(left: 6, right: 6, bottom: 3),
              // Tap the sender to open their profile.
              child: PlayerTap(
                userId: m.senderId,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  WardAvatar(
                      name: m.senderName, url: m.senderAvatarUrl, size: 18),
                  const SizedBox(width: 6),
                  Text(m.senderName,
                      style: TextStyle(
                          color: p.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          GestureDetector(
            onLongPress: m.deleted ? null : onLongPress,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: radius,
                  border: m.deleted || (!right && !mineStyle)
                      ? Border.all(color: p.line)
                      : null,
                ),
                child: content,
              ),
            ),
          ),
          if (time.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 6, right: 6, top: 2),
              child:
                  Text(time, style: TextStyle(color: p.muted, fontSize: 10.5)),
            ),
        ],
      ),
    );
  }
}
