import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/messages/messages_repository.dart'
    show messageStartOptionsProvider;
import 'package:sportpadi_mobile/data/payments/payment_models.dart'
    show RecipientUser;
import 'package:sportpadi_mobile/data/payments/payments_repository.dart';
import 'package:sportpadi_mobile/data/wards/ward_models.dart';
import 'package:sportpadi_mobile/data/wards/wards_repository.dart';
import 'package:sportpadi_mobile/features/inbox/message_entry_points.dart';
import 'package:sportpadi_mobile/features/wards/ward_handover.dart';
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/verified_badge.dart';

/// One ward (A5, A6, A7, A13): team invitations waiting on a guardian, who
/// they are, their check-in QR, their groups, profile and privacy, their
/// guardians (co-guardian invites), handing the account over (A11), and
/// leave / delete.
class WardDetailScreen extends ConsumerWidget {
  const WardDetailScreen({super.key, required this.wardId});
  final String wardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final data = ref.watch(wardDetailProvider(wardId));
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SpHeader(
              title: data.valueOrNull?.ward.firstName ?? 'Ward',
              subtitle: 'Ward profile',
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              // Everything on the page: the ward, their team invitations, their
              // groups and each group's "message about them" options.
              onRefresh: () {
                // The body (and what it watches) only shows once loaded.
                final bodyShown =
                    data.maybeWhen(data: (_) => true, orElse: () => false);
                final groupIds = bodyShown
                    ? [
                        for (final g in ref
                                .read(wardGroupsProvider(wardId))
                                .valueOrNull
                                ?.member ??
                            const <WardGroup>[])
                          g.groupId,
                      ]
                    : const <String>[];
                ref.invalidate(wardDetailProvider(wardId));
                ref.invalidate(wardGroupsProvider(wardId));
                ref.invalidate(wardTeamInvitesProvider(wardId));
                for (final id in groupIds) {
                  ref.invalidate(messageStartOptionsProvider(id));
                }
                return settleAll([
                  ref.read(wardDetailProvider(wardId).future),
                  if (bodyShown) ...[
                    ref.read(wardGroupsProvider(wardId).future),
                    ref.read(wardTeamInvitesProvider(wardId).future),
                    for (final id in groupIds)
                      ref.read(messageStartOptionsProvider(id).future),
                  ],
                ]);
              },
              // Loading / error aren't scrollable on their own.
              child: _pullable(data, AsyncView(
                value: data,
                onRetry: () => ref.invalidate(wardDetailProvider(wardId)),
                data: (d) => _WardBody(key: ValueKey(d.ward.userId), detail: d),
              )),
            ),
          ),
        ]),
      ),
    );
  }
}

/// [child] as is when [value] renders its (scrollable) data branch, else
/// wrapped so the loader / error can still be pulled.
Widget _pullable(AsyncValue<Object?> value, Widget child) => value.maybeWhen(
      data: (_) => child,
      orElse: () => PullableState(child: child),
    );

class _WardBody extends ConsumerStatefulWidget {
  const _WardBody({super.key, required this.detail});
  final WardDetail detail;

  @override
  ConsumerState<_WardBody> createState() => _WardBodyState();
}

class _WardBodyState extends ConsumerState<_WardBody> {
  final _name = TextEditingController();
  DateTime? _dob;
  String? _gender;
  String _relationship = 'parent';
  String _visibility = 'private';
  bool _searchable = false;

  bool _saving = false;
  bool _photoBusy = false;
  bool _privacyBusy = false;
  bool _busy = false; // leave / delete

  Ward get _ward => widget.detail.ward;
  String get _wardId => _ward.userId;

  @override
  void initState() {
    super.initState();
    _sync(_ward);
  }

  @override
  void didUpdateWidget(covariant _WardBody old) {
    super.didUpdateWidget(old);
    if (identical(old.detail, widget.detail)) return;
    // Fresh data from a refresh: follow it, but never over unsaved edits.
    if (!_dirtyAgainst(old.detail.ward)) {
      _sync(_ward);
    } else if (!_privacyBusy) {
      _visibility = wardVisibilities.contains(_ward.visibility)
          ? _ward.visibility
          : 'private';
      _searchable = _ward.searchable;
    }
  }

  void _sync(Ward w) {
    if (_name.text != w.displayName) _name.text = w.displayName;
    _dob = w.dob;
    _gender = w.gender;
    _relationship = _rel(w.relationship);
    _visibility =
        wardVisibilities.contains(w.visibility) ? w.visibility : 'private';
    _searchable = w.searchable;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// The relationship as the picker shows it (unknown values → 'other').
  static String _rel(String r) => wardRelationships.contains(r) ? r : 'other';

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _dirtyAgainst(Ward w) {
    final dob = _dob;
    final savedDob = w.dob;
    return _name.text.trim() != w.displayName.trim() ||
        (dob != null && (savedDob == null || !_sameDay(dob, savedDob))) ||
        _gender != w.gender ||
        _relationship != _rel(w.relationship);
  }

  bool get _dirty => _dirtyAgainst(_ward);

  void _refresh() {
    ref.invalidate(wardDetailProvider(_wardId));
    ref.invalidate(myWardsProvider);
  }

  // ── Groups ──────────────────────────────────────────────────────────────

  bool _groupBusy = false;

  Future<void> _addToGroup(List<WardGroupOption> options) async {
    if (_groupBusy) return;
    final first = _ward.firstName;
    final picked = await showSpSheet<WardGroupOption>(
      context,
      builder: (_) => _AddToGroupSheet(firstName: first, options: options),
    );
    if (picked == null || !mounted) return;
    setState(() => _groupBusy = true);
    try {
      final already = await ref
          .read(wardsRepositoryProvider)
          .joinGroup(_wardId, picked.groupId);
      _toast(already
          ? '$first is already in ${picked.name}.'
          : '$first is now in ${picked.name}.');
      if (mounted) ref.invalidate(wardGroupsProvider(_wardId));
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _groupBusy = false);
    }
  }

  Future<void> _removeFromGroup(WardGroup g) async {
    if (_groupBusy) return;
    final first = _ward.firstName;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $first from ${g.name}?'),
        content: Text(g.teams.isEmpty
            ? 'You can add them again later.'
            : "They'll also come off the group's teams "
                '(${g.teams.map((t) => t.name).join(', ')}). You can add '
                'them again later.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  Text('Remove', style: TextStyle(color: ctx.palette.danger))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _groupBusy = true);
    try {
      await ref.read(wardsRepositoryProvider).leaveGroup(_wardId, g.groupId);
      _toast('$first has left ${g.name}.');
      if (mounted) ref.invalidate(wardGroupsProvider(_wardId));
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _groupBusy = false);
    }
  }

  List<Widget> _groupsSection(AppPalette p, AsyncValue<WardGroups> groups) {
    final first = _ward.firstName;
    final g = groups.valueOrNull;
    return [
      const SizedBox(height: 22),
      SpSectionTitle('Groups',
          count: g == null || g.member.isEmpty ? null : g.member.length),
      const SizedBox(height: 10),
      if (g == null && groups.hasError)
        GlassCard(
          child: Row(children: [
            Expanded(
              child: Text("Couldn't load $first's groups.",
                  style: TextStyle(color: p.muted, fontSize: 13)),
            ),
            TextButton(
              onPressed: () => ref.invalidate(wardGroupsProvider(_wardId)),
              child: const Text('Retry'),
            ),
          ]),
        )
      else if (g == null)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        )
      else ...[
        if (g.member.isEmpty)
          GlassCard(
            child: Text(
              "$first isn't in any groups yet. Add them to one of yours so "
              'they can join its events and teams.',
              style: TextStyle(color: p.muted, fontSize: 13, height: 1.4),
            ),
          )
        else
          SpListCard(children: [
            for (final wg in g.member) _groupRow(p, wg),
          ]),
        const SizedBox(height: 12),
        SpButton(
          label: _groupBusy ? 'Working…' : 'Add to a group',
          icon: Icons.group_add_rounded,
          expand: true,
          onTap: _groupBusy ? null : () => _addToGroup(g.canAdd),
        ),
      ],
    ];
  }

  Widget _groupRow(AppPalette p, WardGroup g) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.push('/groups/${g.groupId}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 0, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Crest(logoUrl: g.imageUrl, label: g.name, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(g.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ),
                if (g.verified) ...[
                  const SizedBox(width: 4),
                  const VerifiedBadge(size: 14),
                ],
              ]),
              if (g.addedByName != null)
                Text('Added by ${g.addedByName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 12)),
              if (g.teams.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final t in g.teams)
                    SpBadge(t.name,
                        icon: Icons.shield_outlined, tone: p.wardInk),
                ]),
              ],
              // Message their coach / the admins "About <ward>"
              // (hidden when there's no one to message there).
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: WardGroupMessageButton(
                  groupId: g.groupId,
                  wardId: _wardId,
                  wardName: _ward.firstName,
                ),
              ),
            ]),
          ),
          IconButton(
            tooltip: 'Remove from group',
            onPressed: _groupBusy ? null : () => _removeFromGroup(g),
            icon: Icon(Icons.remove_circle_outline_rounded,
                size: 20, color: p.muted),
          ),
        ]),
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Profile ─────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final w = _ward;
    final name = _name.text.trim();
    if (name.isEmpty) {
      _toast('Add their name first.');
      return;
    }
    final dob = _dob;
    final savedDob = w.dob;
    final patch = <String, dynamic>{
      if (name != w.displayName.trim()) 'displayName': name,
      if (dob != null && (savedDob == null || !_sameDay(dob, savedDob)))
        'dateOfBirth': wardYmd(dob),
      if (_gender != w.gender) 'gender': _gender,
      if (_relationship != _rel(w.relationship)) 'relationship': _relationship,
    };
    if (patch.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(wardsRepositoryProvider).update(_wardId, patch);
      _toast('Saved.');
      if (mounted) _refresh();
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePhoto() async {
    if (_photoBusy) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() => _photoBusy = true);
    try {
      final bytes = await picked.readAsBytes();
      final url = await ref.read(eventsRepositoryProvider).uploadImage(
            bytes,
            picked.mimeType ?? 'image/jpeg',
            assetType: 'avatar',
          );
      await ref
          .read(wardsRepositoryProvider)
          .update(_wardId, {'avatarUrl': url});
      if (mounted) _refresh();
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  // ── Privacy ─────────────────────────────────────────────────────────────

  Future<void> _setPrivacy({String? visibility, bool? searchable}) async {
    if (_privacyBusy) return;
    final prevVisibility = _visibility;
    final prevSearchable = _searchable;
    setState(() {
      _privacyBusy = true;
      if (visibility != null) _visibility = visibility;
      if (searchable != null) _searchable = searchable;
    });
    try {
      await ref.read(wardsRepositoryProvider).update(_wardId, {
        if (visibility != null) 'visibility': visibility,
        if (searchable != null) 'searchable': searchable,
      });
      if (mounted) _refresh();
    } catch (e) {
      if (mounted) {
        setState(() {
          _visibility = prevVisibility;
          _searchable = prevSearchable;
        });
      }
      _toast('$e');
    } finally {
      if (mounted) setState(() => _privacyBusy = false);
    }
  }

  // ── Guardians ───────────────────────────────────────────────────────────

  Future<void> _invite() async {
    final d = widget.detail;
    final sent = await showSpSheet<String>(
      context,
      builder: (_) => _InviteGuardianSheet(
        wardId: _wardId,
        wardFirstName: _ward.firstName,
        excludeIds: {d.me, _wardId, for (final g in d.guardians) g.userId},
      ),
    );
    if (!mounted || sent == null) return;
    _toast(sent == 'already'
        ? "They've already been invited — waiting for them to accept."
        : "Invitation sent. They'll get a notification to accept.");
    _refresh();
  }

  Future<void> _cancelInvite(WardGuardian g) async {
    try {
      await ref.read(wardsRepositoryProvider).cancelInvite(_wardId, g.userId);
      _toast('Invitation cancelled.');
      if (mounted) _refresh();
    } catch (e) {
      _toast('$e');
    }
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/profile/wards');
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    final first = _ward.firstName;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Stop being $first's guardian?"),
        content: Text(
            "You won't be able to check $first in, sign them up or see their "
            'profile any more. Their other guardians keep managing them.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Stop being guardian',
                  style: TextStyle(color: ctx.palette.danger))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(wardsRepositoryProvider).leave(_wardId);
      if (!mounted) return;
      ref.invalidate(myWardsProvider);
      ref.invalidate(myFeedProvider);
      _toast("You're no longer $first's guardian.");
      _close();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      // Usually "you're their only guardian" — worth a dialog, not a toast.
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Can't leave yet"),
          content: Text('$e'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    final w = _ward;
    final typed = await showDialog<String>(
      context: context,
      builder: (_) => _DeleteWardDialog(name: w.displayName),
    );
    if (typed == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(wardsRepositoryProvider).delete(_wardId, typed);
      if (!mounted) return;
      ref.invalidate(myWardsProvider);
      ref.invalidate(myFeedProvider);
      _toast('${w.displayName} has been deleted.');
      _close();
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _toast('$e');
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  static String _visibilityHint(String v) => switch (v) {
        'groups' =>
          'Group members — people in the groups they play in can see their profile.',
        'public' => 'Everyone — anyone on SportPadi can see their profile.',
        _ =>
          'Only guardians & organisers — organisers of events they join see their name and check-in.',
      };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final d = widget.detail;
    final w = _ward;
    final first = w.firstName;
    final teamInvites =
        ref.watch(wardTeamInvitesProvider(_wardId)).valueOrNull ??
            const <WardTeamInvite>[];
    final groups = ref.watch(wardGroupsProvider(_wardId));
    final meta = [
      if (w.age != null) 'Age ${w.age}',
      if (w.username != null) '@${w.username}',
    ].join(' · ');

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        // Team invitations waiting on a guardian's yes.
        if (teamInvites.isNotEmpty) ...[
          SpSectionTitle('Team invitations', count: teamInvites.length),
          const SizedBox(height: 10),
          for (final i in teamInvites) ...[
            WardTeamInviteCard(key: ValueKey(i.id), invite: i),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 12),
        ],

        // Identity.
        GlassCard(
          child: Row(children: [
            GestureDetector(
              onTap: _photoBusy ? null : _changePhoto,
              child: Stack(clipBehavior: Clip.none, children: [
                WardAvatar(name: w.displayName, url: w.avatarUrl, size: 68),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: p.hero,
                      shape: BoxShape.circle,
                      border: Border.all(color: p.surface, width: 2),
                    ),
                    child: _photoBusy
                        ? Padding(
                            padding: const EdgeInsets.all(5),
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: p.onHero),
                          )
                        : Icon(Icons.photo_camera_rounded,
                            size: 13, color: p.onHero),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(w.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 19,
                            height: 1.2,
                            fontWeight: FontWeight.w800)),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.muted, fontSize: 12.5)),
                    ],
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      SpBadge('Ward',
                          icon: Icons.shield_outlined, tone: p.greenText),
                      SpBadge(
                        switch (_visibility) {
                          'groups' => 'Groups',
                          'public' => 'Public',
                          _ => 'Private',
                        },
                        icon: _visibility == 'public'
                            ? Icons.public_rounded
                            : Icons.lock_outline_rounded,
                      ),
                    ]),
                  ]),
            ),
          ]),
        ),
        const SizedBox(height: 14),

        // Check-in QR.
        GlassCard(
          child: Column(children: [
            Row(children: [
              SpIconTile(Icons.qr_code_2_rounded,
                  bg: p.accentTint, fg: p.greenText, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Check-in QR',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      Text(
                          'Organisers scan this to check $first in. Show it '
                          'from your phone or print it for their kit bag.',
                          style: TextStyle(
                              color: p.muted, fontSize: 12, height: 1.35)),
                    ]),
              ),
            ]),
            const SizedBox(height: 14),
            if (w.qrCode != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: QrImageView(
                    data: w.qrCode!, size: 190, backgroundColor: Colors.white),
              )
            else
              Text('No QR code yet.',
                  style: TextStyle(color: p.muted, fontSize: 12.5)),
          ]),
        ),

        // Groups (and their teams there).
        ..._groupsSection(p, groups),

        // Profile.
        const SizedBox(height: 22),
        const SpSectionTitle('Profile'),
        const SizedBox(height: 10),
        GlassCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            WardDobField(
              value: _dob,
              onPicked: _saving ? null : (v) => setState(() => _dob = v),
            ),
            const SizedBox(height: 16),
            const WardFieldLabel('Gender'),
            WardPills<String?>(
              options: wardGenders,
              value: _gender,
              label: genderLabel,
              onChanged: _saving ? null : (g) => setState(() => _gender = g),
            ),
            const SizedBox(height: 16),
            const WardFieldLabel("You're their…"),
            SpSegmented(
              options: [
                for (final r in wardRelationships) relationshipLabel(r)
              ],
              index: wardRelationships.indexOf(_relationship),
              onChanged: (i) {
                if (_saving) return;
                setState(() => _relationship = wardRelationships[i]);
              },
            ),
            const SizedBox(height: 16),
            SpButton(
              label: _saving ? 'Saving…' : 'Save changes',
              icon: Icons.check_rounded,
              expand: true,
              onTap: _dirty && !_saving ? _save : null,
            ),
          ]),
        ),

        // Privacy.
        const SizedBox(height: 22),
        const SpSectionTitle('Privacy'),
        const SizedBox(height: 10),
        GlassCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text("Who can see $first's profile",
                style: TextStyle(
                    color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            SpSegmented(
              options: const ['Private', 'Groups', 'Everyone'],
              index: wardVisibilities.indexOf(_visibility),
              onChanged: (i) {
                final v = wardVisibilities[i];
                if (v != _visibility) _setPrivacy(visibility: v);
              },
            ),
            const SizedBox(height: 8),
            Text(_visibilityHint(_visibility),
                style: TextStyle(color: p.muted, fontSize: 12, height: 1.4)),
            Divider(height: 26, thickness: 1, color: p.surface2),
            Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Show in player search',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      Text('Let people find $first by name.',
                          style: TextStyle(color: p.muted, fontSize: 12)),
                    ]),
              ),
              Switch(
                value: _searchable,
                onChanged:
                    _privacyBusy ? null : (v) => _setPrivacy(searchable: v),
              ),
            ]),
          ]),
        ),

        // Guardians.
        const SizedBox(height: 22),
        SpSectionTitle('Guardians', count: d.active.length),
        const SizedBox(height: 10),
        SpListCard(children: [
          for (final g in d.guardians)
            _guardianRow(p, g, isMe: g.userId == d.me),
        ]),
        const SizedBox(height: 12),
        SpButton(
          label: 'Invite a co-guardian',
          icon: Icons.person_add_alt_rounded,
          expand: true,
          onTap: _invite,
        ),
        const SizedBox(height: 8),
        Text(
          'Co-guardians can do everything you can once they accept.',
          textAlign: TextAlign.center,
          style: TextStyle(color: p.muted, fontSize: 12),
        ),

        // Hand the account over to them (Wards 3).
        const SizedBox(height: 22),
        const SpSectionTitle('Their own account'),
        const SizedBox(height: 10),
        WardHandoverCard(detail: d),

        // Leave / delete.
        const SizedBox(height: 26),
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Eyebrow('Manage'),
        ),
        SpListCard(children: [
          _actionRow(
            p,
            icon: Icons.logout_rounded,
            title: 'Stop being a guardian',
            sub: "You'll no longer manage $first.",
            color: p.ink,
            onTap: _busy ? null : _leave,
          ),
          _actionRow(
            p,
            icon: Icons.delete_outline_rounded,
            title: 'Delete $first',
            sub: 'Removes their account and personal data for good.',
            color: p.danger,
            onTap: _busy ? null : _delete,
          ),
        ]),
      ],
    );
  }

  Widget _guardianRow(AppPalette p, WardGuardian g, {required bool isMe}) {
    final sub = [
      relationshipLabel(g.relationship),
      if (g.isPending) 'Invited — waiting for them to accept',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(children: [
        WardAvatar(name: g.displayName, url: g.avatarUrl, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${g.displayName}${isMe ? ' (you)' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: g.isPending ? p.muted : p.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: g.isPending ? p.orangeInk : p.muted, fontSize: 12)),
          ]),
        ),
        if (g.isPending)
          TextButton(
            onPressed: () => _cancelInvite(g),
            child: const Text('Cancel'),
          ),
      ]),
    );
  }

  Widget _actionRow(
    AppPalette p, {
    required IconData icon,
    required String title,
    required String sub,
    required Color color,
    required VoidCallback? onTap,
  }) =>
      InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(children: [
            SpIconTile(icon,
                bg: color == p.danger ? p.liveTint : p.surface2,
                fg: color,
                size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: color,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700)),
                    Text(sub,
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

// ---------------------------------------------------------------------------
// Delete — type the ward's name to confirm.
// ---------------------------------------------------------------------------

class _DeleteWardDialog extends StatefulWidget {
  const _DeleteWardDialog({required this.name});
  final String name;

  @override
  State<_DeleteWardDialog> createState() => _DeleteWardDialogState();
}

class _DeleteWardDialogState extends State<_DeleteWardDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _matches =>
      _typed.text.trim().toLowerCase() == widget.name.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AlertDialog(
      title: Text('Delete ${widget.name}?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "This deletes ${widget.name}'s account and personal data for "
              'good. Attendance and payment records stay, shown as '
              '"Deleted user". This can\'t be undone.',
              style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.45),
            ),
            const SizedBox(height: 14),
            Text('Type their name to confirm',
                style: TextStyle(
                    color: p.ink, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _typed,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(hintText: widget.name),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Keep'),
        ),
        TextButton(
          onPressed: _matches
              ? () => Navigator.pop(context, _typed.text.trim())
              : null,
          child: Text('Delete',
              style: TextStyle(color: _matches ? p.danger : p.muted)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Invite a co-guardian — search → pick → relationship → send.
// ---------------------------------------------------------------------------

class _InviteGuardianSheet extends ConsumerStatefulWidget {
  const _InviteGuardianSheet({
    required this.wardId,
    required this.wardFirstName,
    required this.excludeIds,
  });
  final String wardId;
  final String wardFirstName;
  final Set<String> excludeIds;

  @override
  ConsumerState<_InviteGuardianSheet> createState() =>
      _InviteGuardianSheetState();
}

class _InviteGuardianSheetState extends ConsumerState<_InviteGuardianSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<RecipientUser> _results = const [];
  bool _searching = false;
  RecipientUser? _picked;
  String _relationship = 'parent';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _runSearch(String q) {
    _debounce?.cancel();
    final query = q.trim();
    if (query.length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      try {
        final res =
            await ref.read(paymentsRepositoryProvider).searchRecipients(query);
        if (!mounted) return;
        setState(() => _results = [
              for (final r in res)
                if (r.userId.isNotEmpty &&
                    !widget.excludeIds.contains(r.userId))
                  r
            ]);
      } catch (_) {
        if (mounted) setState(() => _results = const []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _send() async {
    final who = _picked;
    if (who == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final already = await ref
          .read(wardsRepositoryProvider)
          .invite(widget.wardId, who.userId, _relationship);
      if (mounted) Navigator.of(context).pop(already ? 'already' : 'sent');
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
    final first = widget.wardFirstName;
    final picked = _picked;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSheetHeader(
          icon: Icons.person_add_alt_rounded,
          title: 'Invite a co-guardian',
          subtitle:
              "Someone else who looks after $first, like their other parent. "
              "They'll get a notification to accept.",
        ),
        if (picked == null) ...[
          TextField(
            controller: _search,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Search by name or @username',
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : const Icon(Icons.search_rounded),
            ),
            onChanged: _runSearch,
          ),
          const SizedBox(height: 8),
          for (final r in _results)
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() {
                _picked = r;
                _results = const [];
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(children: [
                  WardAvatar(name: r.displayName, url: r.avatarUrl, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                          if (r.username.isNotEmpty)
                            Text('@${r.username}',
                                style: TextStyle(color: p.muted, fontSize: 12)),
                        ]),
                  ),
                  Icon(Icons.add_circle_outline_rounded, color: p.greenText),
                ]),
              ),
            ),
          if (_search.text.trim().length >= 2 &&
              !_searching &&
              _results.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                "No one found — try their @username. They need a SportPadi "
                'account of their own.',
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
            ),
        ] else ...[
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: p.line),
            ),
            child: Row(children: [
              WardAvatar(
                  name: picked.displayName, url: picked.avatarUrl, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(picked.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700)),
                      if (picked.username.isNotEmpty)
                        Text('@${picked.username}',
                            style: TextStyle(color: p.muted, fontSize: 12)),
                    ]),
              ),
              IconButton(
                tooltip: 'Pick someone else',
                icon: Icon(Icons.close_rounded, size: 18, color: p.muted),
                onPressed: _busy ? null : () => setState(() => _picked = null),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          WardFieldLabel("They're $first's…"),
          SpSegmented(
            options: [for (final r in wardRelationships) relationshipLabel(r)],
            index: wardRelationships.indexOf(_relationship),
            onChanged: (i) {
              if (_busy) return;
              setState(() => _relationship = wardRelationships[i]);
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: p.danger, fontSize: 12.5)),
          ],
          const SizedBox(height: 16),
          SpButton(
            label: _busy ? 'Sending…' : 'Send invitation',
            icon: Icons.send_rounded,
            tone: SpButtonTone.brand,
            expand: true,
            onTap: _busy ? null : _send,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Add to a group — one of MY groups the ward isn't in yet.
// ---------------------------------------------------------------------------

class _AddToGroupSheet extends StatelessWidget {
  const _AddToGroupSheet({required this.firstName, required this.options});
  final String firstName;
  final List<WardGroupOption> options;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSheetHeader(
          icon: Icons.group_add_rounded,
          title: 'Add $firstName to a group',
          subtitle: "Groups you're in. $firstName can then join its events "
              'and be picked for its teams.',
        ),
        if (options.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(children: [
              SpIconTile(Icons.groups_outlined,
                  bg: p.accentTint, fg: p.greenText, size: 52, iconSize: 24),
              const SizedBox(height: 10),
              Text(
                'Join a group yourself first — then you can add $firstName '
                'to it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 13, height: 1.4),
              ),
            ]),
          )
        else
          SpListCard(children: [
            for (final o in options)
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => Navigator.of(context).pop(o),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Row(children: [
                    Crest(logoUrl: o.imageUrl, label: o.name, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(children: [
                        Flexible(
                          child: Text(o.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                        ),
                        if (o.verified) ...[
                          const SizedBox(width: 4),
                          const VerifiedBadge(size: 14),
                        ],
                      ]),
                    ),
                    Icon(Icons.add_circle_outline_rounded, color: p.greenText),
                  ]),
                ),
              ),
          ]),
      ],
    );
  }
}
