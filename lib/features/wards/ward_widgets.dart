import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/wards/ward_models.dart';
import 'package:sportpadi_mobile/data/wards/wards_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Shared bits for the wards screens: a round avatar, choice pills, the
/// date-of-birth field and the profile entry points.

final _dobFormat = DateFormat('d MMM yyyy');

/// "YYYY-MM-DD" — the API's date-of-birth form.
String wardYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A round avatar (photo, or initials on a quiet tile).
class WardAvatar extends StatelessWidget {
  const WardAvatar({
    super.key,
    required this.name,
    this.url,
    this.image,
    this.size = 40,
  });
  final String name;
  final String? url;

  /// A just-picked photo that hasn't been uploaded yet.
  final ImageProvider? image;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (image != null) {
      return ClipOval(
        child:
            Image(image: image!, width: size, height: size, fit: BoxFit.cover),
      );
    }
    return ClipOval(child: Crest(logoUrl: url, label: name, size: size));
  }
}

/// A small violet "Ward" pill — marks a player a guardian runs for them.
class WardBadge extends StatelessWidget {
  const WardBadge({super.key, this.label = 'Ward'});
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: p.wardTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              color: p.wardInk,
              fontSize: 10.5,
              height: 1.2,
              fontWeight: FontWeight.w800)),
    );
  }
}

/// "Ward · Tobi" — marks a row (an event, a ticket, a fine) as one of my
/// wards'. [onDark] for rows on the dark hero surface (a ready ticket stub).
class WardForChip extends StatelessWidget {
  const WardForChip(this.name, {super.key, this.onDark = false});
  final String name;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final label = 'Ward · $name';
    if (!onDark) {
      return SpBadge(label,
          icon: Icons.supervisor_account_rounded,
          tone: context.palette.wardInk);
    }
    const fg = Color(0xFFC4B5FF);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x339580FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.supervisor_account_rounded, size: 12, color: fg),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: fg, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

/// A ward's private profile, as others see it: a lock and one line on who
/// decides.
class WardPrivateNote extends StatelessWidget {
  const WardPrivateNote({
    super.key,
    this.text =
        'This profile is private. Their guardians manage who can see it.',
  });
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.wardTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Icon(Icons.lock_outline_rounded, size: 18, color: p.wardInk),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  color: p.wardInk,
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

/// A row of pill choices (gender, relationship…). Wraps on narrow screens.
class WardPills<T> extends StatelessWidget {
  const WardPills({
    super.key,
    required this.options,
    required this.value,
    required this.label,
    required this.onChanged,
  });
  final List<T> options;
  final T value;
  final String Function(T) label;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final o in options)
        Material(
          color: o == value ? p.hero : p.surface,
          shape: StadiumBorder(
              side: o == value ? BorderSide.none : BorderSide(color: p.line)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onChanged == null ? null : () => onChanged!(o),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(label(o),
                  style: TextStyle(
                      color: o == value ? p.onHero : p.ink,
                      fontSize: 12.5,
                      fontWeight:
                          o == value ? FontWeight.w700 : FontWeight.w600)),
            ),
          ),
        ),
    ]);
  }
}

/// A small caption above a form control.
class WardFieldLabel extends StatelessWidget {
  const WardFieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Text(text,
            style: TextStyle(
                color: context.palette.muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600)),
      );
}

/// A tap-to-pick date of birth, drawn like the app's text fields.
class WardDobField extends StatelessWidget {
  const WardDobField({super.key, required this.value, required this.onPicked});
  final DateTime? value;
  final ValueChanged<DateTime>? onPicked;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = value ?? DateTime(now.year - 10, now.month, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(today) ? today : initial,
      firstDate: DateTime(now.year - 120),
      lastDate: today,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'Date of birth',
    );
    if (picked != null) onPicked?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final v = value;
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: p.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPicked == null ? null : () => _pick(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(children: [
            Icon(Icons.cake_outlined, size: 18, color: p.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                v == null ? 'Date of birth' : _dobFormat.format(v),
                style: TextStyle(
                    color: v == null ? p.muted : p.ink,
                    fontSize: 14.5,
                    fontWeight: v == null ? FontWeight.w400 : FontWeight.w600),
              ),
            ),
            Icon(Icons.expand_more_rounded, size: 20, color: p.muted),
          ]),
        ),
      ),
    );
  }
}

/// The "Wards" row in the profile menu: how many I manage, and an orange dot
/// when someone has invited me to co-guardian.
class WardsMenuRow extends ConsumerWidget {
  const WardsMenuRow({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final o = ref.watch(myWardsProvider).valueOrNull;
    final n = o?.wards.length ?? 0;
    // Team invitations only exist for guardians — don't ask otherwise.
    final teamInvites = n == 0
        ? 0
        : ref.watch(wardTeamInvitesProvider('')).valueOrNull?.length ?? 0;
    final invites = (o?.invites.length ?? 0) + teamInvites;
    final sub = [
      n == 0
          ? 'Children, or anyone you care for'
          : '$n ward${n == 1 ? '' : 's'}',
      if (invites > 0) '$invites invite${invites == 1 ? '' : 's'} waiting',
    ].join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(children: [
          SpIconTile(Icons.supervisor_account_rounded,
              bg: p.accentTint, fg: p.greenText, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('Wards',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700)),
                  if (invites > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: p.orange, shape: BoxShape.circle),
                    ),
                  ],
                ]),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 12)),
              ],
            ),
          ),
          if (n > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: p.surface2, borderRadius: BorderRadius.circular(999)),
              child: Text('$n',
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 4),
          ],
          Icon(Icons.chevron_right_rounded, color: p.muted),
        ]),
      ),
    );
  }
}

/// The Wards card right under the profile cover (the web's design): an
/// orange icon tile, "Wards" with a count pill and an orange dot while an
/// invitation waits, one line on what's there, and a chevron. Shown to
/// guardians, anyone invited to be one, and adults supervising players;
/// takes no space for everyone else.
class WardsProfileCard extends ConsumerWidget {
  const WardsProfileCard({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final o = ref.watch(myWardsProvider).valueOrNull;
    if (o == null ||
        (o.wards.isEmpty && o.invites.isEmpty && o.supervised.isEmpty)) {
      return const SizedBox.shrink();
    }
    final wards = o.wards.length;
    final invites = o.invites.length;
    // Players I supervise (claimed, under 18) — named when that's all there
    // is.
    final supervisedNames = [
      for (final s in o.supervised) s.displayName.split(' ').first
    ];
    final sub = invites > 0
        ? '$invites guardian invitation${invites == 1 ? '' : 's'} waiting'
        : wards > 0
            ? 'Players you manage — check them in and sign them up'
            : 'Supervising ${supervisedNames.join(', ')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassCard(
        onTap: onOpen,
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          SpIconTile(Icons.volunteer_activism_outlined,
              bg: p.orangeTint, fg: p.orangeInk, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('Wards',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  if (wards > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: p.surface2,
                          borderRadius: BorderRadius.circular(999)),
                      child: Text('$wards',
                          style: TextStyle(
                              color: p.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                  if (invites > 0) ...[
                    const SizedBox(width: 6),
                    Semantics(
                      label: 'Invitation waiting',
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: p.orange, shape: BoxShape.circle),
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 1),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: p.muted),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Team invitations — a coach wants one of my wards on a team (A7). Any one
// guardian accepting is the consent.
// ---------------------------------------------------------------------------

/// Accept or decline a ward's team invitation, with the snackbar that
/// explains what happened. Returns true when it went through.
Future<bool> answerWardTeamInvite(
  BuildContext context,
  WidgetRef ref,
  WardTeamInvite invite, {
  required bool accept,
}) async {
  // Grab everything that needs the context before the await: the card may
  // be gone (its list refreshed) by the time the answer lands.
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final repo = ref.read(wardsRepositoryProvider);
  try {
    final r = await repo.respondTeamInvite(invite.id, accept: accept);
    final first = invite.wardFirstName;
    final notes = [
      accept
          ? '$first is on ${invite.teamName}.'
          : "Declined — $first won't join ${invite.teamName}.",
      if (accept && r.jerseyDropped)
        'Their shirt number was taken meanwhile, so the coach will pick another.',
      if (accept && r.madeSub)
        'The starting line-up was full, so they joined as a sub.',
    ];
    messenger.showSnackBar(SnackBar(content: Text(notes.join(' '))));
    // Every list of invitations, and the ward's groups (their team chips).
    container.invalidate(wardTeamInvitesProvider);
    if (accept) container.invalidate(wardGroupsProvider);
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
    // It may have been answered by another guardian meanwhile.
    container.invalidate(wardTeamInvitesProvider);
    return false;
  }
}

/// A full team-invitation card (a ward's page): team, group and sport, what
/// the coach picked, who asked, and Accept / Decline.
class WardTeamInviteCard extends ConsumerStatefulWidget {
  const WardTeamInviteCard({super.key, required this.invite});
  final WardTeamInvite invite;

  @override
  ConsumerState<WardTeamInviteCard> createState() => _WardTeamInviteCardState();
}

class _WardTeamInviteCardState extends ConsumerState<WardTeamInviteCard> {
  bool _busy = false;

  Future<void> _answer(bool accept) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok =
        await answerWardTeamInvite(context, ref, widget.invite, accept: accept);
    if (!ok && mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final i = widget.invite;
    final sport = [
      if (i.categoryEmoji != null) i.categoryEmoji!,
      if (i.categoryName != null) i.categoryName!,
    ].join(' ');
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Crest(logoUrl: i.teamLogoUrl, label: i.teamName, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${i.teamName} wants ${i.wardFirstName}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14.5,
                      height: 1.3,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text([if (sport.isNotEmpty) sport, i.groupName].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final pos in i.positions) SpBadge(pos),
          if (i.jerseyNumber != null) SpBadge('#${i.jerseyNumber}'),
          SpBadge(i.isStarter ? 'Starter' : 'Sub'),
        ]),
        if (i.invitedByName != null) ...[
          const SizedBox(height: 8),
          Text('Invited by ${i.invitedByName}',
              style: TextStyle(color: p.muted, fontSize: 12)),
        ],
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

/// A compact team-invitation row (the Wards list, across all wards): tap
/// through to the ward, or answer right here.
class WardTeamInviteRow extends ConsumerStatefulWidget {
  const WardTeamInviteRow({super.key, required this.invite});
  final WardTeamInvite invite;

  @override
  ConsumerState<WardTeamInviteRow> createState() => _WardTeamInviteRowState();
}

class _WardTeamInviteRowState extends ConsumerState<WardTeamInviteRow> {
  bool _busy = false;

  Future<void> _answer(bool accept) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok =
        await answerWardTeamInvite(context, ref, widget.invite, accept: accept);
    if (!ok && mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final i = widget.invite;
    final sub = [
      [
        if (i.categoryEmoji != null) i.categoryEmoji!,
        i.groupName,
      ].join(' '),
      if (i.invitedByName != null) 'Invited by ${i.invitedByName}',
    ].join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.push('/profile/wards/${i.wardId}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 4, 10),
        child: Row(children: [
          WardAvatar(name: i.wardName, url: i.wardAvatarUrl, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${i.wardFirstName} → ${i.teamName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Decline',
            visualDensity: VisualDensity.compact,
            onPressed: _busy ? null : () => _answer(false),
            icon: Icon(Icons.close_rounded, size: 20, color: p.muted),
          ),
          Material(
            color: _busy ? p.surface2 : p.accentDeep,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _busy ? null : () => _answer(true),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.check_rounded,
                    size: 18, color: _busy ? p.muted : Colors.white),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
