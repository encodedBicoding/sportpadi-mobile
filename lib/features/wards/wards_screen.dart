import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/wards/ward_models.dart';
import 'package:sportpadi_mobile/data/wards/wards_repository.dart';
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Wards (docs/design/wards-and-messaging.md, A6): the players I manage,
/// co-guardian invitations waiting for my answer, and "Add a ward".
/// The server's invite notification links here (`/profile/wards`).
class WardsScreen extends ConsumerWidget {
  const WardsScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final wardId = await showSpSheet<String>(
      context,
      builder: (_) => const _AddWardSheet(),
    );
    if (!context.mounted) return;
    ref.invalidate(myWardsProvider);
    // Home's Wards filter and "Ward · X" chips come from the feed.
    if (wardId != null && wardId.isNotEmpty) ref.invalidate(myFeedProvider);
    if (wardId != null && wardId.isNotEmpty) {
      context.push('/profile/wards/$wardId');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final data = ref.watch(myWardsProvider);
    // Team invitations for any of my wards ('' = all wards).
    final teamInvites = ref.watch(wardTeamInvitesProvider('')).valueOrNull ??
        const <WardTeamInvite>[];
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SpHeader(title: 'Wards', subtitle: 'Players you manage'),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () {
                ref.invalidate(wardTeamInvitesProvider(''));
                return ref.refresh(myWardsProvider.future);
              },
              child: AsyncView(
                value: data,
                onRetry: () => ref.invalidate(myWardsProvider),
                data: (o) => ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
                  children: [
                    Text(
                      "Players you manage — children, or anyone who needs a "
                      "carer. They can't sign in; you check them in, sign them "
                      'up and manage their profile.',
                      style: TextStyle(
                          color: p.muted, fontSize: 13.5, height: 1.45),
                    ),
                    if (o.invites.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      SpSectionTitle('Invitations', count: o.invites.length),
                      const SizedBox(height: 10),
                      for (final i in o.invites) ...[
                        _InviteCard(invite: i),
                        const SizedBox(height: 10),
                      ],
                    ],
                    if (teamInvites.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      SpSectionTitle('Team invitations',
                          count: teamInvites.length),
                      const SizedBox(height: 4),
                      Text(
                        'Coaches want your wards on their teams. Tap one for '
                        'the details.',
                        style: TextStyle(color: p.muted, fontSize: 12.5),
                      ),
                      const SizedBox(height: 10),
                      SpListCard(children: [
                        for (final i in teamInvites)
                          WardTeamInviteRow(key: ValueKey(i.id), invite: i),
                      ]),
                    ],
                    const SizedBox(height: 22),
                    SpSectionTitle('Your wards',
                        count: o.wards.isEmpty ? null : o.wards.length),
                    const SizedBox(height: 10),
                    if (o.wards.isEmpty)
                      GlassCard(
                        padding: const EdgeInsets.all(22),
                        child: Column(children: [
                          SpIconTile(Icons.supervisor_account_rounded,
                              bg: p.accentTint,
                              fg: p.greenText,
                              size: 52,
                              iconSize: 24),
                          const SizedBox(height: 10),
                          Text('No wards yet',
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(
                            'Add a ward to RSVP for them, check them in with '
                            'their own QR code and follow their events on your '
                            'Home.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: p.muted, fontSize: 12.5, height: 1.4),
                          ),
                        ]),
                      )
                    else
                      SpListCard(children: [
                        for (final w in o.wards) _WardRow(ward: w),
                      ]),
                    const SizedBox(height: 16),
                    SpButton(
                      label: 'Add a ward',
                      icon: Icons.person_add_alt_1_rounded,
                      tone: SpButtonTone.brand,
                      expand: true,
                      onTap: () => _add(context, ref),
                    ),
                    // Wards 3: players who took over their account under
                    // 18 — I supervise them until they turn 18.
                    if (o.supervised.isNotEmpty) ...[
                      const SizedBox(height: 26),
                      SpSectionTitle('Supervising', count: o.supervised.length),
                      const SizedBox(height: 4),
                      Text(
                        "They run their own accounts now. You still hear "
                        'from their coaches and group admins about them, but '
                        "can't act for them.",
                        style: TextStyle(
                            color: p.muted, fontSize: 12.5, height: 1.4),
                      ),
                      const SizedBox(height: 10),
                      SpListCard(children: [
                        for (final s in o.supervised) _SupervisedRow(player: s),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _WardRow extends StatelessWidget {
  const _WardRow({required this.ward});
  final Ward ward;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sub = [
      if (ward.age != null) 'Age ${ward.age}',
      if (ward.relationship != 'other')
        "You're their ${relationshipLabel(ward.relationship).toLowerCase()}",
    ].join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.push('/profile/wards/${ward.userId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(children: [
          WardAvatar(name: ward.displayName, url: ward.avatarUrl, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ward.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
              if (sub.isNotEmpty)
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: p.muted),
        ]),
      ),
    );
  }
}

/// A player I supervise: their own account now, until their 18th birthday.
class _SupervisedRow extends StatelessWidget {
  const _SupervisedRow({required this.player});
  final SupervisedPlayer player;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final until = formatYmd(player.supervisedUntil);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.push('/players/${player.userId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(children: [
          WardAvatar(name: player.displayName, url: player.avatarUrl, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(player.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
              Text(
                  until.isEmpty
                      ? 'Runs their own account · supervised until 18'
                      : 'Runs their own account · supervised until $until',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: p.muted),
        ]),
      ),
    );
  }
}

/// "Ada invited you to be Tobi's guardian" — Accept (my consent) / Decline.
class _InviteCard extends ConsumerStatefulWidget {
  const _InviteCard({required this.invite});
  final WardInvite invite;

  @override
  ConsumerState<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends ConsumerState<_InviteCard> {
  bool _busy = false;

  Future<void> _answer(bool accept) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(wardsRepositoryProvider)
          .respond(widget.invite.wardId, accept: accept);
      messenger.showSnackBar(SnackBar(
          content: Text(accept
              ? "You're now ${widget.invite.wardName}'s guardian."
              : 'Invitation declined.')));
      if (mounted) {
        ref.invalidate(myWardsProvider);
        // A new ward's events join my Home feed ("Ward · X").
        if (accept) ref.invalidate(myFeedProvider);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final i = widget.invite;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          WardAvatar(name: i.wardName, url: i.wardAvatarUrl, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  '${i.invitedByName ?? 'Someone'} invited you to be '
                  "${i.wardName}'s guardian",
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14,
                      height: 1.3,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                  i.relationship == 'other'
                      ? 'As a co-guardian'
                      : 'As their ${relationshipLabel(i.relationship).toLowerCase()}',
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Text(
          "As a guardian you can check them in, sign them up for events and "
          'manage their profile. Accepting confirms you have the right to.',
          style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Material(
              color: p.surface2,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: _busy ? null : () => _answer(false),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Text('Decline',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SpButton(
              label: 'Accept',
              icon: Icons.check_rounded,
              tone: SpButtonTone.brand,
              expand: true,
              onTap: _busy ? null : () => _answer(true),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Add a ward
// ---------------------------------------------------------------------------

class _AddWardSheet extends ConsumerStatefulWidget {
  const _AddWardSheet();

  @override
  ConsumerState<_AddWardSheet> createState() => _AddWardSheetState();
}

class _AddWardSheetState extends ConsumerState<_AddWardSheet> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  DateTime? _dob;
  String? _gender;
  String _relationship = 'parent';
  bool _consent = false;
  List<int>? _photoBytes;
  String _photoType = 'image/jpeg';
  ImageProvider? _photoPreview;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  bool get _valid =>
      _first.text.trim().isNotEmpty &&
      _last.text.trim().isNotEmpty &&
      _dob != null &&
      _consent;

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _photoBytes = bytes;
      _photoType = picked.mimeType ?? 'image/jpeg';
      _photoPreview = MemoryImage(bytes);
    });
  }

  Future<void> _submit() async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      String? avatarUrl;
      final bytes = _photoBytes;
      if (bytes != null) {
        avatarUrl = await ref
            .read(eventsRepositoryProvider)
            .uploadImage(bytes, _photoType, assetType: 'avatar');
      }
      final id = await ref.read(wardsRepositoryProvider).create(
            firstName: _first.text.trim(),
            lastName: _last.text.trim(),
            dateOfBirth: wardYmd(_dob!),
            gender: _gender,
            relationship: _relationship,
            avatarUrl: avatarUrl,
          );
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final first = _first.text.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SpSheetHeader(
          icon: Icons.person_add_alt_1_rounded,
          title: 'Add a ward',
          subtitle:
              "They get their own player profile and QR code — you run it for them.",
        ),
        // Photo (optional).
        Row(children: [
          WardAvatar(
            name: first.isEmpty ? '?' : first,
            image: _photoPreview,
            size: 56,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Photo (optional)',
                style: TextStyle(color: p.muted, fontSize: 13)),
          ),
          TextButton.icon(
            onPressed: _busy ? null : _pickPhoto,
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: Text(_photoPreview == null ? 'Add a photo' : 'Change'),
          ),
        ]),
        const SizedBox(height: 14),
        TextField(
          controller: _first,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'First name'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _last,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Last name'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        WardDobField(
          value: _dob,
          onPicked: _busy ? null : (d) => setState(() => _dob = d),
        ),
        const SizedBox(height: 16),
        const WardFieldLabel('Gender (optional)'),
        WardPills<String?>(
          options: wardGenders,
          value: _gender,
          label: genderLabel,
          onChanged: _busy ? null : (g) => setState(() => _gender = g),
        ),
        const SizedBox(height: 16),
        const WardFieldLabel("You're their…"),
        SpSegmented(
          options: [for (final r in wardRelationships) relationshipLabel(r)],
          index: wardRelationships.indexOf(_relationship),
          onChanged: (i) {
            if (_busy) return;
            setState(() => _relationship = wardRelationships[i]);
          },
        ),
        const SizedBox(height: 16),
        // Consent — recorded on the guardianship (A13).
        Material(
          color: p.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _busy ? null : () => setState(() => _consent = !_consent),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Checkbox(
                  value: _consent,
                  activeColor: p.accentDeep,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _consent = v ?? false),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      "I'm this person's parent, guardian or carer and I "
                      'have the right to manage their SportPadi account. '
                      'I agree to the ward terms.',
                      style: TextStyle(color: p.ink, fontSize: 13, height: 1.4),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Wards are private and hidden from player search by default. You can "
          'change that on their profile.',
          style: TextStyle(color: p.muted, fontSize: 12, height: 1.4),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(color: p.danger, fontSize: 12.5)),
        ],
        const SizedBox(height: 16),
        SpButton(
          label: _busy ? 'Adding…' : 'Add ward',
          icon: Icons.check_rounded,
          tone: SpButtonTone.brand,
          expand: true,
          onTap: _valid && !_busy ? _submit : null,
        ),
      ],
    );
  }
}
