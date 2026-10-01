import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/announcements/announcement_models.dart';
import 'package:sportpadi_mobile/data/announcements/announcements_repository.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

final _day = DateFormat('EEE d MMM');

const _maxImages = 4;

/// Compose an announcement (staff): who it goes to, with a live reach count,
/// the text, urgent (within the group's quota), pin / expiry dates, a link to
/// one of the group's events or teams, and up to four photos.
///
/// [teamId] / [eventId] preselect the audience when opened from a team page
/// ("Announce to team") or an event ("Message participants").
class AnnouncementComposerScreen extends ConsumerStatefulWidget {
  const AnnouncementComposerScreen({
    super.key,
    required this.groupId,
    this.teamId,
    this.eventId,
  });
  final String groupId;
  final String? teamId;
  final String? eventId;

  @override
  ConsumerState<AnnouncementComposerScreen> createState() =>
      _AnnouncementComposerScreenState();
}

class _AnnouncementComposerScreenState
    extends ConsumerState<AnnouncementComposerScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();

  bool _seeded = false;
  String _kind = 'group'; // group | teams | event | members
  final Set<String> _teamIds = {};
  String? _eventId;
  String _scope = 'all'; // going | checked_in | all
  final Map<String, PickablePerson> _members = {};

  bool _urgent = false;
  DateTime? _pinUntil;
  DateTime? _expires;
  String? _link; // 'event:<id>' | 'team:<id>'
  final List<AnnouncementAttachment> _images = [];
  bool _uploading = false;
  bool _sending = false;

  AudiencePreview? _preview;
  bool _previewLoading = false;
  Timer? _debounce;
  int _previewSeq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  AnnouncementAudience get _audience => switch (_kind) {
        'teams' => AnnouncementAudience.teams(_teamIds.toList()),
        'event' => AnnouncementAudience.event(_eventId ?? '', scope: _scope),
        'members' => AnnouncementAudience.members(_members.keys.toList()),
        _ => const AnnouncementAudience.group(),
      };

  /// First build with the composer loaded: pick the starting audience.
  void _seed(ComposerInfo c) {
    if (_seeded) return;
    _seeded = true;
    final team = widget.teamId;
    final event = widget.eventId;
    if (team != null && c.canAddressTeam(team)) {
      _kind = 'teams';
      _teamIds.add(team);
    } else if (event != null && c.canAddressEvent(event)) {
      _kind = 'event';
      _eventId = event;
    } else if (c.canGroup) {
      _kind = 'group';
    } else if (c.canTeams) {
      _kind = 'teams';
      if (c.teams.length == 1) _teamIds.add(c.teams.first.id);
    } else if (c.canEvent) {
      _kind = 'event';
      if (c.events.length == 1) _eventId = c.events.first.id;
    } else {
      _kind = 'members';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _schedulePreview());
  }

  /// Recount the audience (debounced; only the latest answer is shown).
  void _schedulePreview() {
    if (!mounted) return;
    _debounce?.cancel();
    final audience = _audience;
    final seq = ++_previewSeq;
    if (!audience.isComplete) {
      setState(() {
        _preview = null;
        _previewLoading = false;
      });
      return;
    }
    setState(() => _previewLoading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = await ref
            .read(announcementsRepositoryProvider)
            .preview(widget.groupId, audience);
        if (!mounted || seq != _previewSeq) return;
        setState(() {
          _preview = r;
          _previewLoading = false;
        });
      } catch (_) {
        if (!mounted || seq != _previewSeq) return;
        setState(() {
          _preview = null;
          _previewLoading = false;
        });
      }
    });
  }

  void _setAudience(void Function() change) {
    setState(change);
    _schedulePreview();
  }

  Future<void> _pickMembers() async {
    final picked = await showSpSheet<Map<String, PickablePerson>>(
      context,
      scrollable: false,
      padding: EdgeInsets.zero,
      builder: (_) =>
          _MemberPickerSheet(groupId: widget.groupId, initial: _members),
    );
    if (picked == null || !mounted) return;
    _setAudience(() {
      _members
        ..clear()
        ..addAll(picked);
    });
  }

  Future<DateTime?> _pickDate(DateTime? current) async {
    // Calendar days are the viewer's (their Settings zone, else the phone's).
    final now = inViewerZone(DateTime.now());
    final today = DateTime(now.year, now.month, now.day);
    final last = today.add(const Duration(days: 365));
    final cur = current == null ? null : inViewerZone(current);
    var initial = cur != null
        ? DateTime(cur.year, cur.month, cur.day)
        : today.add(const Duration(days: 7));
    if (initial.isBefore(today)) initial = today;
    if (initial.isAfter(last)) initial = last;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: last,
    );
    if (d == null) return null;
    // Until the end of that day, on the viewer's clock.
    return viewerWallClock(d.year, d.month, d.day, 23, 59);
  }

  Future<void> _addImage() async {
    if (_images.length >= _maxImages || _uploading) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final url = await ref.read(eventsRepositoryProvider).uploadImage(
            bytes,
            picked.mimeType ?? 'image/jpeg',
            assetType: 'groupImage',
            scopeId: widget.groupId,
          );
      if (!mounted) return;
      setState(() =>
          _images.add(AnnouncementAttachment(url: url, kind: 'image')));
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  bool get _canSend =>
      !_sending &&
      !_uploading &&
      _title.text.trim().isNotEmpty &&
      _body.text.trim().isNotEmpty &&
      _audience.isComplete;

  Future<void> _send(ComposerInfo c) async {
    if (!_canSend) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    ({String type, String id})? link;
    final l = _link;
    if (l != null) {
      final i = l.indexOf(':');
      if (i > 0) link = (type: l.substring(0, i), id: l.substring(i + 1));
    }
    try {
      final r = await ref.read(announcementsRepositoryProvider).send(
            groupId: widget.groupId,
            audience: _audience,
            title: _title.text.trim(),
            body: _body.text.trim(),
            urgent: _urgent && c.urgent.canSend,
            pinnedUntil: _pinUntil,
            expiresAt: _expires,
            link: link,
            attachments: List.of(_images),
          );
      if (!mounted) return;
      ref.invalidate(sentAnnouncementsProvider(widget.groupId));
      ref.invalidate(pinnedAnnouncementsProvider);
      ref.invalidate(announcementsInboxProvider);
      ref.invalidate(announcementsUnreadProvider);
      ref.invalidate(announcementComposerProvider(widget.groupId));
      final n = r.recipientCount;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Sent to $n ${n == 1 ? 'person' : 'people'}')));
      context.pushReplacement('/groups/${widget.groupId}/announcements');
    } catch (e) {
      _snack('$e');
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final composer = ref.watch(announcementComposerProvider(widget.groupId));
    final c = composer.valueOrNull;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SpHeader(
              title: 'New announcement',
              subtitle: c?.groupName,
            ),
          ),
          Expanded(
            child: AsyncView<ComposerInfo>(
              value: composer,
              onRetry: () => ref
                  .invalidate(announcementComposerProvider(widget.groupId)),
              data: (info) {
                _seed(info);
                return _form(p, info);
              },
            ),
          ),
          if (c != null)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              decoration: BoxDecoration(
                color: p.bg,
                border: Border(top: BorderSide(color: p.line)),
              ),
              child: SpButton(
                label: _sending
                    ? 'Sending…'
                    : (_urgent && c.urgent.canSend ? 'Send urgent' : 'Send'),
                icon: Icons.send_rounded,
                tone: SpButtonTone.brand,
                expand: true,
                onTap: _canSend ? () => _send(c) : null,
              ),
            ),
        ]),
      ),
    );
  }

  Widget _form(AppPalette p, ComposerInfo c) {
    final kinds = <(String, String, IconData)>[
      if (c.canGroup) ('group', 'Whole group', Icons.groups_outlined),
      if (c.canTeams) ('teams', 'Teams', Icons.shield_outlined),
      if (c.canEvent) ('event', 'Event', Icons.event_outlined),
      if (c.canMembers)
        ('members', 'Pick members', Icons.person_search_outlined),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        const Eyebrow('To'),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in kinds)
            _Pill(
              label: k.$2,
              icon: k.$3,
              selected: _kind == k.$1,
              onTap: () => _setAudience(() => _kind = k.$1),
            ),
        ]),
        const SizedBox(height: 12),
        if (_kind == 'teams') _teamsPanel(p, c),
        if (_kind == 'event') _eventPanel(p, c),
        if (_kind == 'members') _membersPanel(p),
        const SizedBox(height: 10),
        _reachLine(p),
        const SizedBox(height: 22),
        const Eyebrow('Message'),
        const SizedBox(height: 10),
        GlassCard(
          child: Column(children: [
            TextField(
              controller: _title,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _body,
              maxLength: 4000,
              minLines: 5,
              maxLines: 14,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Message',
                alignLabelWithHint: true,
                helperText: 'Plain text. Links will be tappable.',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        _imagesRow(p),
        const SizedBox(height: 22),
        const Eyebrow('Options'),
        const SizedBox(height: 10),
        GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 6, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _urgentTile(p, c.urgent),
              Divider(height: 1, color: p.surface2),
              _dateTile(
                p,
                icon: Icons.push_pin_outlined,
                title: 'Pin to the top',
                empty: 'Not pinned',
                value: _pinUntil,
                prefix: 'Until',
                onPick: () async {
                  final d = await _pickDate(_pinUntil);
                  if (d != null && mounted) setState(() => _pinUntil = d);
                },
                onClear: () => setState(() => _pinUntil = null),
              ),
              _dateTile(
                p,
                icon: Icons.timer_off_outlined,
                title: 'Hide after',
                empty: 'Never expires',
                value: _expires,
                prefix: 'After',
                onPick: () async {
                  final d = await _pickDate(_expires);
                  if (d != null && mounted) setState(() => _expires = d);
                },
                onClear: () => setState(() => _expires = null),
              ),
              if (c.events.isNotEmpty || c.teams.isNotEmpty) ...[
                const SizedBox(height: 8),
                _linkPicker(c),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _teamsPanel(AppPalette p, ComposerInfo c) {
    if (c.teams.isEmpty) {
      return Text('No teams you can address yet.',
          style: TextStyle(color: p.muted, fontSize: 13));
    }
    return SpListCard(children: [
      for (final t in c.teams)
        _SelectRow(
          selected: _teamIds.contains(t.id),
          multi: true,
          leading: Crest(logoUrl: t.logoUrl, label: t.name, size: 34),
          title: t.name,
          subtitle: '${t.players} ${t.players == 1 ? 'player' : 'players'}',
          onTap: () => _setAudience(() {
            if (!_teamIds.remove(t.id)) _teamIds.add(t.id);
          }),
        ),
    ]);
  }

  String _eventWhen(ComposerEvent e) {
    final d = e.date == null ? null : DateTime.tryParse(e.date!);
    final parts = [
      if (d != null) _day.format(d),
      if (e.time != null) formatTime12(e.time!),
    ];
    return parts.join(' · ');
  }

  Widget _eventPanel(AppPalette p, ComposerInfo c) {
    if (c.events.isEmpty) {
      return Text('No recent or upcoming events you organise.',
          style: TextStyle(color: p.muted, fontSize: 13));
    }
    const scopes = ['going', 'checked_in', 'all'];
    final scopeIndex = scopes.indexOf(_scope);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpListCard(children: [
          for (final e in c.events)
            _SelectRow(
              selected: _eventId == e.id,
              multi: false,
              leading: const SpIconTile(Icons.event_outlined,
                  size: 34, iconSize: 17),
              title: e.title,
              subtitle: [
                _eventWhen(e),
                '${e.going} going · ${e.checkedIn} checked in',
              ].where((s) => s.isNotEmpty).join(' · '),
              onTap: () => _setAudience(() => _eventId = e.id),
            ),
        ]),
        const SizedBox(height: 10),
        SpSegmented(
          options: const ['Going', 'Checked in', 'Both'],
          index: scopeIndex < 0 ? 2 : scopeIndex,
          onChanged: (i) => _setAudience(() => _scope = scopes[i]),
        ),
      ],
    );
  }

  Widget _membersPanel(AppPalette p) {
    final people = _members.values.toList()
      ..sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OutlineAction(
          label: people.isEmpty
              ? 'Choose members'
              : 'Choose members · ${people.length} picked',
          icon: Icons.person_search_outlined,
          onTap: _pickMembers,
        ),
        if (people.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final m in people)
              InputChip(
                avatar: WardAvatar(
                    name: m.displayName, url: m.avatarUrl, size: 24),
                label: Text(m.isWard ? '${m.displayName} · Ward' : m.displayName),
                onDeleted: () => _setAudience(() => _members.remove(m.userId)),
              ),
          ]),
        ],
      ],
    );
  }

  Widget _reachLine(AppPalette p) {
    final a = _audience;
    String text;
    if (!a.isComplete) {
      text = switch (_kind) {
        'teams' => 'Pick at least one team.',
        'event' => 'Pick an event.',
        'members' => 'Pick at least one member.',
        _ => '',
      };
    } else if (_previewLoading) {
      text = 'Counting who this reaches…';
    } else if (_preview != null) {
      final r = _preview!;
      text = 'Reaches ${r.people} ${r.people == 1 ? 'person' : 'people'}';
      if (r.wards > 0) {
        text += ' · ${r.wards} ${r.wards == 1 ? 'ward' : 'wards'} via '
            '${r.guardians} ${r.guardians == 1 ? 'guardian' : 'guardians'}';
      }
    } else {
      text = '';
    }
    if (text.isEmpty) return const SizedBox.shrink();
    final warn = _preview != null && _preview!.people == 0 && !_previewLoading;
    return Row(children: [
      Icon(Icons.people_alt_outlined,
          size: 16, color: warn ? p.danger : p.muted),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
            warn ? 'Nobody in that audience can receive it yet.' : text,
            style: TextStyle(
                color: warn ? p.danger : p.muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600)),
      ),
    ]);
  }

  Widget _imagesRow(AppPalette p) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final img in _images)
        Stack(clipBehavior: Clip.none, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: img.url,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                width: 72,
                height: 72,
                color: p.surface2,
                child: Icon(Icons.image_outlined, color: p.muted),
              ),
            ),
          ),
          Positioned(
            right: -6,
            top: -6,
            child: Material(
              color: p.hero,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => _images.remove(img)),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(Icons.close_rounded, size: 14, color: p.onHero),
                ),
              ),
            ),
          ),
        ]),
      if (_images.length < _maxImages)
        Material(
          color: p.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: p.line)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _uploading ? null : _addImage,
            child: SizedBox(
              width: 72,
              height: 72,
              child: _uploading
                  ? const Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              color: p.muted),
                          const SizedBox(height: 2),
                          Text('Photo',
                              style:
                                  TextStyle(color: p.muted, fontSize: 11)),
                        ]),
            ),
          ),
        ),
    ]);
  }

  Widget _urgentTile(AppPalette p, UrgentQuota q) {
    final String note;
    if (q.unlimited) {
      note = 'Sound and a heads-up alert, even for muted groups.';
    } else if (q.canSend) {
      note = '${q.remaining} of ${q.limit} urgent left today';
    } else {
      final next = q.nextFreeAt;
      note = 'This group has used its ${q.limit ?? 0} urgent announcements '
          'for today${next != null ? ' — the next one frees up ${fmtInstant(next)}' : ''}. '
          'It can still go as a normal announcement.';
    }
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Row(children: [
        const Text('Urgent'),
        if (_urgent && q.canSend) ...[
          const SizedBox(width: 8),
          Icon(Icons.priority_high_rounded, size: 16, color: p.danger),
        ],
      ]),
      subtitle: Text(note,
          style: TextStyle(
              color: q.canSend ? p.muted : p.danger, fontSize: 12)),
      value: _urgent && q.canSend,
      onChanged: q.canSend ? (v) => setState(() => _urgent = v) : null,
    );
  }

  Widget _dateTile(
    AppPalette p, {
    required IconData icon,
    required String title,
    required String empty,
    required DateTime? value,
    required String prefix,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: p.muted),
      title: Text(title),
      subtitle: Text(value == null ? empty : '$prefix ${fmtInstant(value, style: InstantStyle.day)}',
          style: TextStyle(color: p.muted, fontSize: 12)),
      trailing: value == null
          ? Icon(Icons.chevron_right_rounded, color: p.muted)
          : IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close_rounded),
              onPressed: onClear,
            ),
      onTap: onPick,
    );
  }

  Widget _linkPicker(ComposerInfo c) {
    final options = <String?>[
      null,
      for (final e in c.events) 'event:${e.id}',
      for (final t in c.teams) 'team:${t.id}',
    ];
    final value = options.contains(_link) ? _link : null;
    return InputDecorator(
      decoration: const InputDecoration(labelText: 'Link to (optional)'),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isExpanded: true,
          isDense: true,
          items: [
            const DropdownMenuItem<String?>(
                value: null, child: Text('No link')),
            for (final e in c.events)
              DropdownMenuItem<String?>(
                value: 'event:${e.id}',
                child: Text('Event · ${e.title}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            for (final t in c.teams)
              DropdownMenuItem<String?>(
                value: 'team:${t.id}',
                child: Text('Team · ${t.name}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _link = v),
        ),
      ),
    );
  }
}

/// An audience choice pill.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: selected ? p.hero : p.surface,
      shape: StadiumBorder(
          side: selected ? BorderSide.none : BorderSide(color: p.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: selected ? p.onHero : p.ink),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: selected ? p.onHero : p.ink,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

/// A selectable list row with a check (multi) or radio (single) mark.
class _SelectRow extends StatelessWidget {
  const _SelectRow({
    required this.selected,
    required this.multi,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final bool selected;
  final bool multi;
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final IconData mark = multi
        ? (selected
            ? Icons.check_box_rounded
            : Icons.check_box_outline_blank_rounded)
        : (selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Row(children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 12)),
                ]),
          ),
          Icon(mark, color: selected ? p.greenText : p.muted),
        ]),
      ),
    );
  }
}

class _OutlineAction extends StatelessWidget {
  const _OutlineAction(
      {required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.surface,
      shape: StadiumBorder(side: BorderSide(color: p.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 17, color: p.ink),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Hand-pick members: searchable, multi-select, wards tagged. Returns the
/// picked set on Done.
class _MemberPickerSheet extends ConsumerStatefulWidget {
  const _MemberPickerSheet({required this.groupId, required this.initial});
  final String groupId;
  final Map<String, PickablePerson> initial;

  @override
  ConsumerState<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends ConsumerState<_MemberPickerSheet> {
  late final Map<String, PickablePerson> _picked = {...widget.initial};
  final _search = TextEditingController();
  Timer? _debounce;
  List<PickablePerson>? _results;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    final seq = ++_seq;
    try {
      final r = await ref
          .read(announcementsRepositoryProvider)
          .pickable(widget.groupId, q: q);
      if (!mounted || seq != _seq) return;
      setState(() {
        _results = r;
        _error = null;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => _error = '$e');
    }
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _load(q));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final results = _results;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SpSheetHeader(
          icon: Icons.person_search_outlined,
          title: 'Pick members',
          subtitle: _picked.isEmpty
              ? 'Wards are reached through their guardians.'
              : '${_picked.length} picked',
          trailing: TextButton(
            onPressed: () => Navigator.of(context).pop(_picked),
            child: const Text('Done'),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: TextField(
          controller: _search,
          onChanged: _onSearch,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search by name',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
      ),
      Expanded(
        child: results == null
            ? Center(
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: p.muted)),
                      )
                    : const CircularProgressIndicator(),
              )
            : results.isEmpty
                ? Center(
                    child: Text('Nobody matches.',
                        style: TextStyle(color: p.muted)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    itemCount: results.length,
                    itemBuilder: (_, i) {
                      final u = results[i];
                      final on = _picked.containsKey(u.userId);
                      return ListTile(
                        leading: WardAvatar(
                            name: u.displayName, url: u.avatarUrl, size: 36),
                        title: Row(children: [
                          Flexible(
                            child: Text(u.displayName,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          if (u.isWard) ...[
                            const SizedBox(width: 6),
                            const WardBadge(),
                          ],
                        ]),
                        trailing: Icon(
                          on
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          color: on ? p.greenText : p.muted,
                        ),
                        onTap: () => setState(() {
                          if (on) {
                            _picked.remove(u.userId);
                          } else {
                            _picked[u.userId] = u;
                          }
                        }),
                      );
                    },
                  ),
      ),
    ]);
  }
}
