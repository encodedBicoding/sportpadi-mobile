import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show NumberFormat;

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/players/scout_header.dart'
    show followStateProvider;
import 'package:sportpadi_mobile/features/profile/social_links.dart';
import 'package:sportpadi_mobile/features/share/share_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// The profile header, laid out like Instagram's (owner, 2026-11-19) — web
/// twin: components/players/ProfileHeader.tsx. No cover banner: the photo on
/// the left and Highlights · Followers · Following on the right (2026-11-20),
/// then the name and
/// @username, a line about where they play, the bio, the links and the chips,
/// then a row of full-width pills (Edit profile · Share profile on your own;
/// Follow / Following / Requested · Message · Share on someone else's).
/// Shared by your own profile (`profile_screen.dart`) and a player's
/// (`player_profile_screen.dart`) in every state — full, private-and-locked,
/// a ward their guardians keep limited (docs/design/scouting-profile.md
/// "The profile header").

/// The photo's size in the header.
const double kProfileAvatar = 86;

/// "1,234" (grouped as [locale] groups, e.g. "1 234" in French) up to
/// 9,999, then "12.3K" / "1.2M", as Instagram counts. A locale the intl
/// package has no symbols for (pcm, yo, ig, ha may be among them) groups as
/// English. 999,950 and up reads "1M", never "1000K" (review LOW).
String compactCount(int n, [String? locale]) {
  if (n < 10000) {
    try {
      return NumberFormat.decimalPattern(locale).format(n);
    } catch (_) {
      return NumberFormat.decimalPattern('en').format(n);
    }
  }
  String short(double v) => v < 100
      ? v.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')
      : v.toStringAsFixed(0);
  if (n < 999950) return '${short(n / 1000)}K';
  return '${short(n / 1000000)}M';
}

/// The slim row above the header: the page's round buttons and its title,
/// below the status bar (these pages have no app bar and no banner).
class ProfileTopBar extends StatelessWidget {
  const ProfileTopBar({super.key, required this.title, this.left, this.right});
  final String title;
  final Widget? left;
  final Widget? right;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final top = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, top + 8, 16, 0),
      child: Row(children: [
        SizedBox(width: 44, height: 44, child: left),
        Expanded(
          child: Text(title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
        ),
        SizedBox(width: 44, height: 44, child: right),
      ]),
    );
  }
}

/// Highlights · Followers · Following beside the photo (owner, 2026-11-20:
/// "a post count beside followers and following — by post I mean
/// highlights"), in Instagram's order, each a column (number over label).
/// Followers / Following open their lists only when the viewer may see the
/// profile in full ([open]): the lists are refused on a locked private
/// profile, so the numbers are plain there, as on Instagram. The highlights
/// number (`follows.state` `highlights`: what this viewer's grid lists,
/// ready posts only) selects the Highlights tab and scrolls to it
/// ([onHighlights], given only where the tabs are — it gets this widget's
/// context, which sits inside the page's `SpPinnedTabsScrollView`); null
/// from the server hides the cell.
class ProfileCounts extends ConsumerWidget {
  const ProfileCounts(
      {super.key, required this.userId, this.open = true, this.onHighlights});
  final String userId;
  final bool open;
  final void Function(BuildContext context)? onHighlights;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final state = ref.watch(followStateProvider(userId));
    final s = state.valueOrNull;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final l = context.l10n;
    // Until the first answer: nothing — a row of the same height, so the
    // highlights cell never shows "–" and then goes away (a null answer). A
    // failed read: "–" for the follower counts, no highlights cell. No number
    // from the server (or an older server): no highlights cell.
    if (s == null && !state.hasError) return const SizedBox(height: 44);
    final showPosts = s?.highlights != null;
    Widget item(int? value, String label, {VoidCallback? onTap}) {
      // Number and label each on one line, shrunk rather than wrapped or
      // cut on a narrow phone or at large text.
      final body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value == null ? '–' : compactCount(value, locale),
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                    color: p.ink,
                    fontSize: 18,
                    height: 1.2,
                    fontWeight: FontWeight.w800)),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(color: p.muted, fontSize: 12.5)),
          ),
        ]),
      );
      if (value == null || onTap == null) return body;
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: body,
      );
    }

    final posts = s?.highlights;
    final tapPosts = onHighlights;
    return Row(children: [
      if (showPosts)
        Expanded(
            child: item(posts, l.profile_countHighlights(posts ?? 0),
                onTap: tapPosts == null ? null : () => tapPosts(context))),
      Expanded(
          child: item(s?.followers,
              l.profile_countFollowers(s?.followers ?? 0),
              onTap: open
                  ? () => context.push('/players/$userId/followers?which=followers')
                  : null)),
      Expanded(
          child: item(s?.followingCount,
              l.profile_countFollowing(s?.followingCount ?? 0),
              onTap: open
                  ? () => context.push('/players/$userId/followers?which=following')
                  : null)),
    ]);
  }
}

/// The photo: a round crest with an optional earned-frame ring and, on your
/// own profile, the camera button to change it.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.photo,
    this.ring,
    this.onCamera,
    this.uploading = false,
  });

  /// A round picture (a ClipOval'd Crest) of [kProfileAvatar] − 10, so a
  /// frame ring fits inside the same [kProfileAvatar] box.
  final Widget photo;
  final Color? ring;
  final VoidCallback? onCamera;
  final bool uploading;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Always the same box (review LOW): the counts beside it never shift when
    // an earned frame arrives, and both profiles draw the same size.
    final framed = SizedBox.square(
      dimension: kProfileAvatar,
      child: Center(
        child: ring == null
            ? photo
            : Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ring!, width: 2.5),
                ),
                child: photo,
              ),
      ),
    );
    if (onCamera == null) return framed;
    return Stack(clipBehavior: Clip.none, children: [
      framed,
      // End-side: mirrors in a right-to-left language.
      PositionedDirectional(
        end: -2,
        bottom: -2,
        child: Material(
          color: p.ink,
          shape: CircleBorder(side: BorderSide(color: p.bg, width: 3)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: uploading ? null : onCamera,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: uploading
                  ? SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: p.bg))
                  : Icon(Icons.photo_camera_rounded, size: 12, color: p.bg),
            ),
          ),
        ),
      ),
    ]);
  }
}

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.avatar,
    required this.name,
    this.username,
    this.copiedText,
    this.isPrivate = false,
    this.badges = const [],
    this.byline,
    this.bio,
    this.links = const [],
    this.chips = const [],
    this.counts,
    this.actions,
  });

  final Widget avatar;
  final String name;

  /// Null for a ward their guardians keep limited (short name only).
  final String? username;

  /// The snack bar after copying the @username.
  final String? copiedText;

  /// Their "private profile" is on: a lock beside the @username.
  final bool isPrivate;

  /// Small badges after the @username (Follows you, Owner, Admin).
  final List<Widget> badges;

  /// "Striker · Surrey, BC".
  final String? byline;
  final String? bio;
  final List<SocialLink> links;

  /// Sport / team chips and the level badge — identity, not the record.
  final List<Widget> chips;

  /// [ProfileCounts], or null for none (a limited ward).
  final Widget? counts;

  /// The pills row.
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final handle = username;
    final line = byline;
    final about = bio;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          avatar,
          const SizedBox(width: 16),
          Expanded(child: counts ?? const SizedBox.shrink()),
        ]),
        const SizedBox(height: 12),
        // Who they are, on the left under the photo.
        Text(name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: p.ink,
                fontSize: 17,
                height: 1.2,
                fontWeight: FontWeight.w800)),
        if (handle != null || isPrivate || badges.isNotEmpty) ...[
          const SizedBox(height: 3),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (handle != null)
                _UsernameCopy(username: handle, copiedText: copiedText),
              if (isPrivate)
                Semantics(
                  label: context.l10n.profile_privateAccount,
                  child: ExcludeSemantics(
                      child: Icon(Icons.lock_outline_rounded,
                          size: 15, color: p.muted)),
                ),
              ...badges,
            ],
          ),
        ],
        if (line != null && line.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 13)),
        ],
        // Plain text, as typed (line breaks kept).
        if (about != null && about.isNotEmpty) ...[
          const SizedBox(height: 6),
          // Capped, so a pile of combining marks can't draw over the name.
          Text(about,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.ink, fontSize: 14, height: 1.35)),
        ],
        SocialLinksRow(links, alignment: WrapAlignment.start),
        ...chips,
        if (actions != null) ...[const SizedBox(height: 14), actions!],
      ]),
    );
  }
}

class _UsernameCopy extends StatelessWidget {
  const _UsernameCopy({required this.username, this.copiedText});
  final String username;
  final String? copiedText;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: username));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(copiedText ?? l10n.profile_copied(username))));
        }
      },
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: Text('@$username',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: p.muted, fontSize: 13.5, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 4),
        Icon(Icons.copy_rounded, size: 12, color: p.muted),
      ]),
    );
  }
}

/// A small soft badge after the @username ("Follows you", "Owner").
class ProfileBadge extends StatelessWidget {
  const ProfileBadge(this.label, {super.key, this.bg, this.fg});
  final String label;
  final Color? bg;
  final Color? fg;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: bg ?? p.surface2, borderRadius: BorderRadius.circular(999)),
      child: Text(label,
          style: TextStyle(
              color: fg ?? p.muted, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

/// One of the header's full-width pills: soft (grey) by default, [filled]
/// for the one action that matters most (Follow).
class ProfilePill extends StatelessWidget {
  const ProfilePill({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.trailingIcon,
    this.filled = false,
    this.busy = false,
    this.compact = false,
    this.expand = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool filled;
  final bool busy;

  /// Smaller, for a row in a list (followers, requests).
  final bool compact;

  /// Fill the width it is given — only inside an `Expanded` (the header's
  /// row); false (the default) hugs the label, safe in any `Row`.
  final bool expand;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bg = filled ? p.hero : p.surface2;
    final fg = filled ? p.onHero : p.ink;
    final pill = Material(
      color: bg,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 14, vertical: compact ? 7 : 10),
          child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  SizedBox(
                      width: 14,
                      height: 14,
                      child:
                          CircularProgressIndicator(strokeWidth: 2, color: fg))
                else if (icon != null)
                  Icon(icon, size: 16, color: fg),
                if (busy || icon != null) const SizedBox(width: 6),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: fg,
                          fontSize: compact ? 13 : 14,
                          fontWeight: FontWeight.w700)),
                ),
                if (trailingIcon != null) ...[
                  const SizedBox(width: 2),
                  Icon(trailingIcon, size: 18, color: fg),
                ],
              ]),
        ),
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}

/// "Share profile" — the share sheet on the player's page. [iconOnly]: the
/// square third pill next to Follow / Message.
class ShareProfilePill extends ConsumerWidget {
  const ShareProfilePill({
    super.key,
    required this.userId,
    required this.name,
    this.username,
    this.avatarUrl,
    this.iconOnly = false,
    this.expand = false,
  });
  final String userId;
  final String name;
  final String? username;
  final String? avatarUrl;
  final bool iconOnly;

  /// The labelled pill fills its slot (inside an `Expanded`).
  final bool expand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final label = context.l10n.share_shareProfile;
    void open() => showShareSheet(context, ref,
        url: shareSiteUrl(
            ref.read(appConfigProvider).apiBaseUrl, '/players/$userId'),
        title: name,
        subtitle: username != null ? '@$username' : null,
        imageUrl: avatarUrl);
    if (!iconOnly) {
      return ProfilePill(
          label: label,
          icon: Icons.ios_share_rounded,
          expand: expand,
          onTap: open);
    }
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: p.surface2,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: open,
            child: SizedBox(
              width: 46,
              height: 40,
              child: ExcludeSemantics(
                  child: Icon(Icons.ios_share_rounded, size: 18, color: p.ink)),
            ),
          ),
        ),
      ),
    );
  }
}

/// "This account is private" — what a locked private profile shows instead
/// of its tabs.
class ProfileLockCard extends StatelessWidget {
  const ProfileLockCard(
      {super.key, required this.title, required this.text, this.action});
  final String title;
  final String text;

  /// A retry, when the follow state couldn't be read.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GlassCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: p.ink, width: 2),
          ),
          child: Icon(Icons.lock_outline_rounded, size: 21, color: p.ink),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    color: p.ink, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(text,
                style: TextStyle(color: p.muted, fontSize: 13, height: 1.4)),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ]),
        ),
      ]),
    );
  }
}

/// Your own profile: "Follow requests · N waiting" while anyone is waiting
/// (Instagram keeps it in the activity feed; the notification opens the same
/// screen).
class FollowRequestsRow extends StatelessWidget {
  const FollowRequestsRow({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final p = context.palette;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      onTap: () => context.push('/profile/follow-requests'),
      child: Row(children: [
        SpIconTile(Icons.person_add_alt_1_rounded,
            bg: p.accentTint, fg: p.greenText, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.l10n.profile_followRequests,
                style: TextStyle(
                    color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
            Text(context.l10n.profile_followRequestsWaiting(count),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 12)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
              color: p.orange, borderRadius: BorderRadius.circular(999)),
          child: Text('$count',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right_rounded, color: p.muted),
      ]),
    );
  }
}
