import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/links/web_handoff.dart';
import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/announcements/announcement_models.dart';
import 'package:sportpadi_mobile/data/announcements/announcements_repository.dart';
import 'package:sportpadi_mobile/data/events/event_models.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/shared/widgets/event_reminders.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// The event page's "More" button, beside Share. Everything that isn't the
/// page's main flow (what, when, where, RSVP / tickets / teams) lives here,
/// each opening its own sheet. What's in it depends on who's looking:
///
///   everyone      Add to calendar
///   signed out    Reminders → what they'd get, and Sign in
///   signed in     Reminders → the schedule and "Remind me" on / off
///   organizers    Message participants · Reminders (edit the schedule)
///                 · Event photos
///
/// Web twin: apps/web/src/components/events/EventMenu.tsx.
class EventMenuButton extends ConsumerWidget {
  const EventMenuButton({super.key, required this.event, this.onPhotos});
  final EventDetail event;

  /// Organizers: opens the photo manager (owned by the event screen).
  final VoidCallback? onPhotos;

  bool get _upcoming => event.status == 'open' && event.hasEnded != true;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Warm both up so the menu opens with its hints ready.
    final reminders = _upcoming
        ? ref.watch(eventRemindersProvider(event.id)).valueOrNull
        : null;
    if (event.canManage && event.groupId != null) {
      ref.watch(announcementComposerProvider(event.groupId!));
    }
    // Nothing to offer (e.g. a player on a cancelled event): no button.
    final anything = event.canManage ||
        (event.status != 'cancelled' && event.calendarStart != null) ||
        (reminders?.slots.isNotEmpty ?? false);
    if (!anything) return const SizedBox.shrink();
    return SpRoundButton(
      icon: Icons.more_horiz_rounded,
      tooltip: context.l10n.event_more,
      onTap: () => _open(context, ref),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final p = context.palette;
    final signedIn =
        ref.read(authControllerProvider).valueOrNull?.isAuthenticated ?? false;
    final manage = event.canManage;
    final reminders = _upcoming
        ? ref.read(eventRemindersProvider(event.id)).valueOrNull
        : null;
    final hasReminders = (reminders?.slots.isNotEmpty ?? false);
    final showReminders = _upcoming && (manage || hasReminders);
    final composer = manage && event.groupId != null
        ? ref.read(announcementComposerProvider(event.groupId!)).valueOrNull
        : null;
    final canMessage = composer?.canAddressEvent(event.id) ?? false;
    final photos = manage && event.status != 'completed' && onPhotos != null;
    final reminderHint = reminders == null || !hasReminders
        ? context.l10n.event_noneSetAddSome
        : !signedIn
            ? context.l10n.event_signInToGetThem
            : reminders.muted
                ? context.l10n.event_offForThisEvent
                : (reminders.labels.isNotEmpty
                        ? reminders.labels
                        : [
                            for (final s in reminders.slots)
                              context.l10n.event_reminderSlotBefore(kReminderSlots[s] ?? s)
                          ])
                    .join(', ');

    final picked = await showSpSheet<String>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (manage && (canMessage || showReminders || photos)) ...[
            _Label(l10n.event_organizer),
            if (canMessage)
              _Row(
                icon: Icons.campaign_outlined,
                title: l10n.event_messageParticipants,
                hint: l10n.event_anAnnouncementToWhosGoing,
                onTap: () => Navigator.of(ctx).pop('message'),
              ),
            if (showReminders)
              _Row(
                icon: Icons.alarm_rounded,
                title: l10n.event_reminders,
                hint: reminderHint,
                onTap: () => Navigator.of(ctx).pop('reminders'),
              ),
            if (photos)
              _Row(
                icon: Icons.add_photo_alternate_outlined,
                title: l10n.event_eventPhotos,
                hint:
                    l10n.event_photosSetTheCover(event.images.length),
                onTap: () => Navigator.of(ctx).pop('photos'),
              ),
            Divider(height: 18, color: p.line),
          ],
          if (!manage && showReminders)
            _Row(
              icon: reminders?.muted == true
                  ? Icons.notifications_off_outlined
                  : Icons.alarm_rounded,
              title: l10n.event_reminders,
              hint: reminderHint,
              onTap: () => Navigator.of(ctx).pop('reminders'),
            ),
          if (event.status != 'cancelled' && event.calendarStart != null)
            _Row(
              icon: Icons.event_available_outlined,
              title: l10n.event_addToCalendar,
              hint: event.isPrivate
                  ? l10n.event_googleCalendar
                  : l10n.event_googleAppleOutlook,
              onTap: () => Navigator.of(ctx).pop('calendar'),
            ),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    switch (picked) {
      case 'message':
        await showSpSheet<void>(context,
            builder: (_) => _MessageSheet(
                groupId: event.groupId!,
                eventId: event.id,
                eventTitle: event.title));
      case 'reminders':
        await showSpSheet<void>(context,
            builder: (_) =>
                _RemindersSheet(eventId: event.id, canEdit: manage));
      case 'photos':
        onPhotos?.call();
      case 'calendar':
        await showSpSheet<void>(context,
            builder: (_) => _CalendarSheet(event: event));
    }
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                color: context.palette.muted,
                fontSize: 10.5,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w800)),
      );
}

class _Row extends StatelessWidget {
  const _Row(
      {required this.icon,
      required this.title,
      this.hint,
      required this.onTap});
  final IconData icon;
  final String title;
  final String? hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
        child: Row(children: [
          SpIconTile(icon, size: 40, iconSize: 20, fg: p.ink),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
              if (hint != null)
                Text(hint!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: p.muted, fontSize: 12, height: 1.3)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: p.muted),
        ]),
      ),
    );
  }
}

// ── Message participants ───────────────────────────────────────────────────

class _MessageSheet extends ConsumerStatefulWidget {
  const _MessageSheet(
      {required this.groupId, required this.eventId, required this.eventTitle});
  final String groupId;
  final String eventId;
  final String eventTitle;

  @override
  ConsumerState<_MessageSheet> createState() => _MessageSheetState();
}

class _MessageSheetState extends ConsumerState<_MessageSheet> {
  static const _scopes = ['going', 'checked_in', 'all'];
  int _scope = 2;
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _urgent = false;
  bool _busy = false;
  AudiencePreview? _reach;
  int _reachFor = -1;

  /// The count failed — still let them send (the server checks anyway).
  bool _reachFailed = false;

  AnnouncementAudience get _audience =>
      AnnouncementAudience.event(widget.eventId, scope: _scopes[_scope]);

  @override
  void initState() {
    super.initState();
    _count();
    _title.addListener(_redraw);
    _body.addListener(_redraw);
  }

  void _redraw() => setState(() {});

  Future<void> _count() async {
    final at = _scope;
    if (_reachFailed) setState(() => _reachFailed = false);
    try {
      final r = await ref
          .read(announcementsRepositoryProvider)
          .preview(widget.groupId, _audience);
      if (mounted && at == _scope) {
        setState(() {
          _reach = r;
          _reachFor = at;
        });
      }
    } catch (_) {
      if (mounted && at == _scope) setState(() => _reachFailed = true);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send(bool urgentAllowed) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final r = await ref.read(announcementsRepositoryProvider).send(
        groupId: widget.groupId,
        audience: _audience,
        title: _title.text.trim(),
        body: _body.text.trim(),
        urgent: _urgent && urgentAllowed,
        link: (type: 'event', id: widget.eventId),
      );
      nav.pop();
      messenger.showSnackBar(SnackBar(
          content: Text(
              l10n.event_sentToPeople(r.recipientCount))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final quota = ref
        .watch(announcementComposerProvider(widget.groupId))
        .valueOrNull
        ?.urgent;
    final urgentAllowed = quota?.canSend ?? false;
    final reach = _reachFor == _scope ? _reach : null;
    final canSend = !_busy &&
        _title.text.trim().isNotEmpty &&
        _body.text.trim().isNotEmpty &&
        (_reachFailed || (reach != null && reach.people > 0));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSheetHeader(
          icon: Icons.campaign_outlined,
          iconBg: p.accentTint,
          iconFg: p.greenText,
          title: context.l10n.event_messageParticipants,
          subtitle: widget.eventTitle,
        ),
        SpSegmented(
          options: [context.l10n.event_going, context.l10n.event_checkedIn, context.l10n.event_both],
          index: _scope,
          onChanged: (i) {
            setState(() => _scope = i);
            _count();
          },
        ),
        const SizedBox(height: 6),
        Text(
          _reachFailed
              ? context.l10n.event_couldntCountWhoItReaches
              : reach == null
                  ? context.l10n.event_counting
                  : reach.people == 0
                      ? context.l10n.event_nobodyHereCanReceiveIt
                      : context.l10n.event_countPluralOneReachesPerson2(reach.people, (reach.wards > 0 ? context.l10n.event_throughTheirGuardians(reach.wards) : '')),
          style: TextStyle(color: p.muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          enabled: !_busy,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
              labelText: context.l10n.event_title, hintText: context.l10n.event_eGPitchMovedTo),
        ),
        TextField(
          controller: _body,
          enabled: !_busy,
          minLines: 3,
          maxLines: 6,
          maxLength: 4000,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
              labelText: context.l10n.event_message, hintText: context.l10n.event_whatDoTheyNeedTo),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _urgent && urgentAllowed,
          onChanged: _busy || !urgentAllowed
              ? null
              : (v) => setState(() => _urgent = v),
          title: Text(context.l10n.event_urgent,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
              quota == null
                  ? context.l10n.event_pushesPastQuietSettings
                  : !urgentAllowed
                      ? context.l10n.event_noneLeftToday
                      : quota.unlimited || quota.limit == null
                          ? context.l10n.event_pushesPastQuietSettings
                          : context.l10n.event_urgentLeftToday(quota.remaining ?? 0, quota.limit!),
              style: TextStyle(color: p.muted, fontSize: 12)),
        ),
        const SizedBox(height: 8),
        Row(children: [
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    Navigator.of(context).pop();
                    context.push(
                        '/groups/${widget.groupId}/announcements/new?event=${widget.eventId}');
                  },
            child: Text(context.l10n.event_moreOptions),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: canSend ? () => _send(urgentAllowed) : null,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded, size: 18),
            label: Text(context.l10n.event_send),
          ),
        ]),
      ],
    );
  }
}

// ── Reminders ──────────────────────────────────────────────────────────────

class _RemindersSheet extends ConsumerStatefulWidget {
  const _RemindersSheet({required this.eventId, required this.canEdit});
  final String eventId;
  final bool canEdit;

  @override
  ConsumerState<_RemindersSheet> createState() => _RemindersSheetState();
}

class _RemindersSheetState extends ConsumerState<_RemindersSheet> {
  Set<String>? _edit;
  bool _busy = false;

  Future<void> _mute(bool muted) async {
    final messenger = ScaffoldMessenger.of(context);
    // The sheet may be swiped away mid-request; the container outlives it.
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    try {
      await container
          .read(eventsRepositoryProvider)
          .setRemindersMuted(widget.eventId, muted);
      container.invalidate(eventRemindersProvider(widget.eventId));
      messenger.showSnackBar(SnackBar(
          content: Text(muted
              ? l10n.event_remindersOffForThisEvent
              : l10n.event_remindersBackOnForThis)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final edit = _edit;
    if (edit == null) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    try {
      await container
          .read(eventsRepositoryProvider)
          .updateEvent(widget.eventId, {'reminders': orderReminderSlots(edit)});
      container.invalidate(eventRemindersProvider(widget.eventId));
      if (mounted) nav.pop();
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.event_reminderScheduleSaved)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final signedIn =
        ref.watch(authControllerProvider).valueOrNull?.isAuthenticated ?? false;
    final async = ref.watch(eventRemindersProvider(widget.eventId));
    final r = async.valueOrNull;
    final header = SpSheetHeader(
      icon: Icons.alarm_rounded,
      iconBg: p.accentTint,
      iconFg: p.greenText,
      title: context.l10n.event_reminders,
      subtitle: widget.canEdit
          ? context.l10n.event_whenSportPadiRemindsPeopleAbout2
          : context.l10n.event_whatSportPadiSendsYouBefore2,
    );
    if (r == null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        header,
        Padding(
          padding: const EdgeInsets.all(24),
          child: async.hasError
              ? Text(context.l10n.event_couldntLoadTheReminders,
                  style: TextStyle(color: p.muted))
              : const CircularProgressIndicator(),
        ),
      ]);
    }
    final selected = _edit ?? r.slots.toSet();
    final changed = _edit != null && !sameReminderSlots(_edit!, r.slots);
    final labels = r.labels.isNotEmpty
        ? r.labels
        : [for (final s in r.slots) '${kReminderSlots[s] ?? s} before'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (widget.canEdit)
          EventRemindersPicker(
            selected: selected,
            enabled: !_busy,
            onChanged: (s) => setState(() => _edit = s),
          )
        else if (r.slots.isEmpty)
          Text(context.l10n.event_thisEventHasNoReminders, style: TextStyle(color: p.muted))
        else
          for (final l in labels)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                  color: p.surface2, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                Icon(Icons.check_rounded, size: 18, color: p.greenText),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(l,
                        style: TextStyle(color: p.ink, fontSize: 13.5))),
              ]),
            ),
        if (signedIn && r.slots.isNotEmpty) ...[
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: !r.muted,
            onChanged: _busy ? null : (on) => _mute(!on),
            title: Text(context.l10n.event_remindMe,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
                r.muted
                    ? context.l10n.event_offForThisEventOnly
                    : context.l10n.event_onTurnOffJustFor,
                style: TextStyle(color: p.muted, fontSize: 12)),
          ),
        ],
        if (!signedIn) ...[
          const SizedBox(height: 14),
          SpButton(
            label: context.l10n.event_signInToGetReminders,
            icon: Icons.notifications_active_outlined,
            expand: true,
            onTap: () {
              Navigator.of(context).pop();
              context.push('/sign-in');
            },
          ),
        ],
        if (widget.canEdit) ...[
          const SizedBox(height: 14),
          SpButton(
            label: context.l10n.event_saveSchedule,
            expand: true,
            onTap: changed && !_busy ? _save : null,
          ),
        ],
      ],
    );
  }
}

// ── Add to calendar ────────────────────────────────────────────────────────

class _CalendarSheet extends ConsumerWidget {
  const _CalendarSheet({required this.event});
  final EventDetail event;

  static String _stamp(DateTime d, bool allDay) {
    final u = d.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${u.year}${two(u.month)}${two(u.day)}';
    return allDay
        ? date
        : '${date}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  }

  Future<void> _go(BuildContext context, String url) async {
    Navigator.of(context).pop();
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  /// The .ics, opened in the browser ALREADY SIGNED IN (one-tap hand-off) —
  /// so private events work too, and the file carries the event's reminders
  /// as alarms, so the phone's calendar alerts as well.
  Future<void> _goIcs(BuildContext context, WidgetRef ref) async {
    final url = await signedInWebUriFor(
        ref, '/api/events/${Uri.encodeComponent(event.slug)}/calendar');
    if (!context.mounted) return;
    Navigator.of(context).pop();
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final base = ref.read(appConfigProvider).apiBaseUrl;
    final start = event.calendarStart!;
    final end = event.calendarEnd ?? start.add(const Duration(hours: 2));
    final allDay = event.calendarAllDay;
    final page = '$base/e/${event.slug}';
    final google = Uri.https('calendar.google.com', '/calendar/render', {
      'action': 'TEMPLATE',
      'text': event.title,
      'dates': '${_stamp(start, allDay)}/${_stamp(end, allDay)}',
      'details': [
        if (event.groupName != null) l10n.event_hostedByName(event.groupName!),
        page,
      ].join('\n'),
      if (event.locationName != null) 'location': event.locationName!,
    }).toString();
    Widget row(IconData icon, Color bg, Color fg, String title, String? sub,
            VoidCallback onTap) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassCard(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            onTap: onTap,
            child: Row(children: [
              SpIconTile(icon, bg: bg, fg: fg, size: 38, iconSize: 19),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700)),
                      if (sub != null)
                        Text(sub,
                            style: TextStyle(color: p.muted, fontSize: 12)),
                    ]),
              ),
              Icon(Icons.open_in_new_rounded, size: 18, color: p.muted),
            ]),
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSheetHeader(
          icon: Icons.event_available_outlined,
          iconBg: p.accentTint,
          iconFg: p.greenText,
          title: context.l10n.event_addToCalendar,
          subtitle: event.title,
        ),
        row(Icons.event_rounded, p.accentTint, p.greenText, context.l10n.event_googleCalendar,
            null, () => _go(context, google)),
        row(Icons.calendar_month_outlined, p.surface2, p.ink,
            context.l10n.event_appleOutlookOthers, context.l10n.event_includesTheEventsReminders,
            () => _goIcs(context, ref)),
      ],
    );
  }
}
