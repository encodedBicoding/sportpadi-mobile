import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/announcements/announcements_repository.dart';
import 'package:sportpadi_mobile/data/discussions/discussions_repository.dart';
import 'package:sportpadi_mobile/data/groups/group_models.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart';
import 'package:sportpadi_mobile/data/messages/messages_repository.dart';
import 'package:sportpadi_mobile/features/announcements/announcement_entry_points.dart';
import 'package:sportpadi_mobile/features/discussions/discussion_entry_points.dart';
import 'package:sportpadi_mobile/features/inbox/message_entry_points.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// The group page's one place for talking: Announcements, Messages and
/// Discussions as a row of tiles (icon with a notification badge, name, one
/// short status line). Each tile opens a sheet with what used to sit on the
/// page itself — the same entry-point widgets, closing the sheet before they
/// navigate. The badges are the server's talk counts
/// ([groupTalkCountsProvider]); the page re-reads them on app resume and
/// when it's back on top, and this section does when one of its sheets
/// closes.
///
/// A tile hides when its feature offers the viewer nothing, and the whole
/// section when no tile is left. Messages and Discussions are for members
/// (and guardians who are here through a ward) — never for someone who only
/// follows the group.
///
/// [GroupTalkSection.team] is the team page's: the same tiles, scoped to one
/// team — its announcements (Announce to team / Sent for its staff, Open
/// Inbox), its coaches (or, for staff, its players) and its discussions —
/// with the team's counts ([teamTalkCountsProvider]).
class GroupTalkSection extends ConsumerWidget {
  const GroupTalkSection({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.isMember,
  }) : teamId = null;

  /// The team page's Talk: tiles for the people in the team's space (its
  /// players, their guardians, its coaches, the group's admins) and for
  /// whoever the team's announcements reached.
  const GroupTalkSection.team({
    super.key,
    required this.groupId,
    required String this.teamId,
    required String teamName,
  })  : groupName = teamName,
        isMember = false;

  final String groupId;

  /// The sheets' subtitle: the group's name (the team's, on a team page).
  final String groupName;

  /// Members and managers: they get Messages and Discussions and can mute
  /// the group's announcements.
  final bool isMember;

  /// Set on a team page: everything is that team's.
  final String? teamId;

  /// The group's (or one team's) hot discussions — the same list (and
  /// cache) the Discussions sheet shows.
  static DiscussionListKey _hotKey(String groupId, [String space = '']) => (
        groupId: groupId,
        space: space,
        sort: 'hot',
        flair: null,
        status: null,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = teamId;
    final tiles = team == null
        ? _groupTiles(context, ref)
        : _teamTiles(context, ref, team);
    if (tiles.isEmpty) return const SizedBox.shrink();
    // Web's phone layout: an eyebrow, then one card of rows divided by
    // hairlines — icon tile (with the unread badge), name, status, chevron.
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(padding: EdgeInsets.only(left: 4, bottom: 8), child: Eyebrow('Talk')),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(20),
              border: dark ? Border.all(color: p.line) : null,
              boxShadow: cardShadow(context),
            ),
            child: Column(children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: p.surface2),
                tiles[i],
              ],
            ]),
          ),
        ],
      ),
    );
  }

  /// The group page's tiles.
  List<Widget> _groupTiles(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(groupTalkCountsProvider(groupId)).valueOrNull ??
        GroupTalkCounts.none;

    // ── Announcements: Open Inbox, mute, staff tools (composer). Pinned
    // ones have their own section on the page.
    final composer =
        ref.watch(announcementComposerProvider(groupId)).valueOrNull;
    final unseen = counts.announcements;
    final urgent = counts.urgent > 0;
    final muted = isMember &&
        (ref
                .watch(mutedAnnouncementGroupsProvider)
                .valueOrNull
                ?.contains(groupId) ??
            false);
    // Members always; staff for the composer; anyone else only while
    // something here was sent to them.
    final showAnnouncements = isMember || composer != null || unseen > 0;
    final announcementsStatus = unseen > 0
        ? (urgent ? '$unseen new · ${counts.urgent} urgent' : '$unseen new')
        : muted
            ? 'Muted · urgent ones still come through'
            : 'News from the group';

    // ── Messages: what I can start here (start-options).
    final o = ref.watch(messageStartOptionsProvider(groupId)).valueOrNull;
    final staff = o?.asStaff;
    final canContactAdmins = o?.adminContacts.isNotEmpty ?? false;
    final hasCoaches = o?.coaches.isNotEmpty ?? false;
    // A guardian who isn't a member still writes about their ward.
    final messagesViaWard = o != null &&
        (o.adminContacts.any((c) => !c.isMe) ||
            o.coaches.any((c) => c.forWho.any((f) => !f.isMe)));
    // A supervised player (claimed their account under 18) can't message
    // staff; the sheet says so rather than the tile vanishing.
    final selfBlocked = o?.selfBlockedReason != null;
    final showMessages = (isMember || messagesViaWard) &&
        (canContactAdmins || hasCoaches || staff != null || selfBlocked);
    final String messagesStatus;
    if (counts.messages > 0) {
      messagesStatus = '${counts.messages} unread';
    } else if (staff != null) {
      messagesStatus = staff.isAdmin ? 'Conversations' : 'Message your players';
    } else if (selfBlocked && !canContactAdmins && !hasCoaches) {
      messagesStatus = 'Through your guardian';
    } else if (canContactAdmins && hasCoaches) {
      messagesStatus = 'Talk to the admins or coaches';
    } else if (canContactAdmins) {
      messagesStatus = 'Talk to the admins';
    } else {
      messagesStatus = 'Message a coach';
    }
    // The Messages sheet's one-line explainer (web's msgExplainer).
    final String messagesExplainer;
    if (staff != null && staff.isAdmin) {
      messagesExplainer = 'Every conversation in the group, and reports.';
    } else if (staff != null) {
      messagesExplainer = 'Message the players on your teams.';
    } else if (selfBlocked && !canContactAdmins && !hasCoaches) {
      messagesExplainer = 'Messages with admins and coaches go through your guardian.';
    } else {
      messagesExplainer = "Message the group's admins — every admin sees it and can answer.";
    }

    // ── Discussions: only for people in a space here (members, or a
    // guardian through a ward).
    final spaces = ref.watch(discussionSpacesProvider(groupId)).valueOrNull;
    final discussionsViaWard =
        spaces?.teams.any((t) => t.asGuardianOf.isNotEmpty) ?? false;
    final showDiscussions =
        (spaces?.any ?? false) && (isMember || discussionsViaWard);
    final hot = showDiscussions
        ? ref.watch(discussionListProvider(_hotKey(groupId))).valueOrNull?.items
        : null;
    final topTitle = hot == null || hot.isEmpty ? '' : hot.first.title.trim();
    final discussionsStatus = counts.discussions > 0
        ? '${counts.discussions} with new activity'
        : topTitle.isEmpty
            ? (hot == null ? 'Questions, issues and ideas' : 'Start a discussion')
            : topTitle;

    return <Widget>[
      if (showAnnouncements)
        _TalkTile(
          icon: Icons.campaign_outlined,
          tint: _Tint.orange,
          label: 'Announcements',
          status: announcementsStatus,
          badge: unseen,
          urgent: urgent,
          onTap: () => _afterSheet(
            context,
            showGroupAnnouncementsSheet(
              context,
              groupId: groupId,
              groupName: groupName,
              subtitle: "News and updates from the group's admins and coaches.",
              urgent: urgent,
              withInbox: true,
              canMute: isMember,
            ),
          ),
        ),
      if (showMessages)
        _TalkTile(
          icon: Icons.chat_bubble_outline_rounded,
          tint: _Tint.green,
          label: 'Messages',
          status: messagesStatus,
          badge: counts.messages,
          onTap: () => _afterSheet(context, _openMessages(context, messagesExplainer)),
        ),
      if (showDiscussions)
        _TalkTile(
          icon: Icons.forum_outlined,
          tint: _Tint.green,
          label: 'Discussions',
          status: discussionsStatus,
          badge: counts.discussions,
          onTap: () => _afterSheet(context, _openDiscussions(context)),
        ),
    ];
  }

  /// The team page's tiles. Who gets what follows the blocks the team page
  /// used to show: Announce to team for its staff, Message coach for its
  /// players and their guardians (Message a player for its coaches and the
  /// group's admins), and Discussions for the people in its space.
  List<Widget> _teamTiles(BuildContext context, WidgetRef ref, String teamId) {
    final counts = ref
            .watch(teamTalkCountsProvider((groupId: groupId, teamId: teamId)))
            .valueOrNull ??
        GroupTalkCounts.none;
    // In the team's space: its players, their guardians, its coaches and the
    // group's admins.
    final spaces = ref.watch(discussionSpacesProvider(groupId)).valueOrNull;
    final inTeam = spaces?.team(teamId) != null;

    // ── Announcements: Open Inbox; Announce to team / Sent for its staff.
    // Pinned ones have their own section on the page.
    final composer =
        ref.watch(announcementComposerProvider(groupId)).valueOrNull;
    final canAnnounce = composer?.canAddressTeam(teamId) ?? false;
    final unseen = counts.announcements;
    final urgent = counts.urgent > 0;
    final showAnnouncements = inTeam || canAnnounce || unseen > 0;
    final announcementsStatus = unseen > 0
        ? (urgent ? '$unseen new · ${counts.urgent} urgent' : '$unseen new')
        : 'News from the team';

    // ── Messages: this team's coaches; its players for staff.
    final o = ref.watch(messageStartOptionsProvider(groupId)).valueOrNull;
    final coaches = teamCoachOptions(o, teamId);
    final toPlayers = canMessageTeamPlayers(o, teamId);
    // A supervised player on this team: the sheet explains why there's no
    // "Message coach".
    final selfBlocked = inTeam && o?.selfBlockedReason != null;
    final showMessages = coaches.isNotEmpty || toPlayers || selfBlocked;
    final coachNames = {for (final c in coaches) c.name}.toList();
    final String messagesStatus;
    if (counts.messages > 0) {
      messagesStatus = '${counts.messages} unread';
    } else if (toPlayers) {
      messagesStatus = 'Message a player on this team';
    } else if (coachNames.isNotEmpty) {
      messagesStatus = 'Message ${coachNames.join(', ')}';
    } else {
      messagesStatus = 'Through your guardian';
    }
    final String messagesExplainer;
    if (toPlayers) {
      messagesExplainer = 'Message a player on this team — for a ward, their guardians.';
    } else if (selfBlocked && coaches.isEmpty) {
      messagesExplainer = 'Messages with admins and coaches go through your guardian.';
    } else {
      messagesExplainer = "Message this team's coaches. The group's admins can see every conversation.";
    }

    // ── Discussions: the team's, for the people in its space.
    final hot = inTeam
        ? ref
            .watch(discussionListProvider(_hotKey(groupId, teamId)))
            .valueOrNull
            ?.items
        : null;
    final topTitle = hot == null || hot.isEmpty ? '' : hot.first.title.trim();
    final discussionsStatus = counts.discussions > 0
        ? '${counts.discussions} with new activity'
        : topTitle.isEmpty
            ? (hot == null ? 'Questions, issues and ideas' : 'Start a discussion')
            : topTitle;

    return <Widget>[
      if (showAnnouncements)
        _TalkTile(
          icon: Icons.campaign_outlined,
          tint: _Tint.orange,
          label: 'Announcements',
          status: announcementsStatus,
          badge: unseen,
          urgent: urgent,
          onTap: () => _afterSheet(
            context,
            showGroupAnnouncementsSheet(
              context,
              groupId: groupId,
              groupName: groupName,
              subtitle: "News and updates from the team's coaches and the group's admins.",
              urgent: urgent,
              withInbox: true,
              canMute: false,
              teamId: teamId,
            ),
          ),
        ),
      if (showMessages)
        _TalkTile(
          icon: Icons.chat_bubble_outline_rounded,
          tint: _Tint.green,
          label: 'Messages',
          status: messagesStatus,
          badge: counts.messages,
          onTap: () => _afterSheet(context, _openTeamMessages(context, teamId, messagesExplainer)),
        ),
      if (inTeam)
        _TalkTile(
          icon: Icons.forum_outlined,
          tint: _Tint.green,
          label: 'Discussions',
          status: discussionsStatus,
          badge: counts.discussions,
          onTap: () => _afterSheet(context, _openDiscussions(context)),
        ),
    ];
  }

  /// Re-reads the badges once a Talk sheet closes — whatever was read or
  /// muted in it changes them. (A page opened from the sheet is covered by
  /// the group or team page, which refreshes them when it's back on top.)
  void _afterSheet(BuildContext context, Future<void> sheet) {
    final container = ProviderScope.containerOf(context, listen: false);
    final team = teamId;
    unawaited(sheet.whenComplete(() {
      if (team == null) {
        container.invalidate(groupTalkCountsProvider(groupId));
      } else {
        container.invalidate(
            teamTalkCountsProvider((groupId: groupId, teamId: team)));
      }
    }));
  }

  /// Contact the admins (for me / each ward), Message coach, staff's
  /// Message a member and admins' Conversations.
  Future<void> _openMessages(BuildContext context, String explainer) {
    return showSpSheet<void>(
      context,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpSheetHeader(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Messages',
            subtitle: explainer,
          ),
          GroupMessagesSection(
            groupId: groupId,
            padding: EdgeInsets.zero,
            launch: closeSheetThen(sheetContext, context),
          ),
        ],
      ),
    );
  }

  /// Team page: Message coach (this team's) and, for its staff, Message a
  /// player.
  Future<void> _openTeamMessages(BuildContext context, String teamId, String explainer) {
    return showSpSheet<void>(
      context,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpSheetHeader(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Messages',
            subtitle: explainer,
          ),
          TeamMessagesSection(
            groupId: groupId,
            teamId: teamId,
            launch: closeSheetThen(sheetContext, context),
          ),
        ],
      ),
    );
  }

  /// The top hot discussions, See all and Start a discussion — the team's
  /// on a team page (See all opens its space, Start preselects it).
  Future<void> _openDiscussions(BuildContext context) {
    final team = teamId;
    return showSpSheet<void>(
      context,
      builder: (sheetContext) {
        final launch = closeSheetThen(sheetContext, context);
        final q = team == null ? '' : '?team=$team';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SpSheetHeader(
              icon: Icons.forum_outlined,
              title: 'Discussions',
              subtitle: team == null
                  ? 'Questions, issues and ideas for the group and your teams — out in the open.'
                  : 'Questions, issues and ideas for the team — out in the open.',
              trailing: TextButton(
                onPressed: () =>
                    launch((c) => c.push('/groups/$groupId/discussions$q')),
                child: const Text('See all'),
              ),
            ),
            if (team == null)
              GroupDiscussionsSection(
                groupId: groupId,
                limit: 5,
                showTitle: false,
                padding: EdgeInsets.zero,
                launch: launch,
              )
            else
              TeamDiscussionsSection(
                groupId: groupId,
                teamId: team,
                limit: 5,
                showTitle: false,
                padding: EdgeInsets.zero,
                launch: launch,
              ),
          ],
        );
      },
    );
  }
}

enum _Tint { orange, green }

/// One Talk row (web's TalkTile on phones): icon tile with the unread badge,
/// name, one status line, chevron. Announcements are orange (red, with a
/// rail down the left, when something urgent is waiting); Messages and
/// Discussions green. The status reads bold when something is new.
class _TalkTile extends StatelessWidget {
  const _TalkTile({
    required this.icon,
    required this.tint,
    required this.label,
    required this.status,
    required this.onTap,
    this.badge = 0,
    this.urgent = false,
  });
  final IconData icon;
  final _Tint tint;
  final String label;
  final String status;
  final VoidCallback onTap;
  final int badge;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final Color fg = urgent ? p.danger : tint == _Tint.orange ? p.orangeInk : p.greenText;
    final Color bg = urgent ? p.liveTint : tint == _Tint.orange ? p.orangeTint : p.accentTint;
    return Semantics(
      button: true,
      label: badge > 0 ? '$label, $badge new. $status' : '$label. $status',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Stack(children: [
            if (urgent)
              Positioned(left: 0, top: 0, bottom: 0, child: Container(width: 3, color: p.danger)),
            Padding(
              padding: EdgeInsets.fromLTRB(urgent ? 16 : 14, 12, 12, 12),
              child: Row(children: [
                Stack(clipBehavior: Clip.none, children: [
                  SpIconTile(icon, bg: bg, fg: fg, size: 40, iconSize: 20),
                  if (badge > 0)
                    Positioned(
                      top: -6,
                      right: -6,
                      child: _Badge(
                        count: badge,
                        color: urgent ? p.danger : p.orange,
                        border: p.surface,
                      ),
                    ),
                ]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.2)),
                    const SizedBox(height: 2),
                    Text(status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: urgent ? p.danger : badge > 0 ? p.ink : p.muted,
                            fontSize: 11.5,
                            fontWeight: urgent || badge > 0 ? FontWeight.w600 : FontWeight.w400)),
                  ]),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, size: 18, color: p.muted),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A notification badge for a tile's icon: a rounded pill, "9+" above 9.
class _Badge extends StatelessWidget {
  const _Badge(
      {required this.count, required this.color, required this.border});
  final int count;
  final Color color;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 18,
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 2),
      ),
      child: Text(count > 9 ? '9+' : '$count',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              height: 1,
              fontWeight: FontWeight.w800)),
    );
  }
}
