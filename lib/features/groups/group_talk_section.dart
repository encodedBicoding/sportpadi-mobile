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
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SpSectionTitle('Talk'),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: tiles[i]),
                ],
              ],
            ),
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
    final announcementsStatus = urgent
        ? '${counts.urgent} urgent'
        : unseen > 0
            ? '$unseen new'
            : muted
                ? 'Muted'
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
    } else if (selfBlocked && staff == null) {
      messagesStatus = 'Your guardian contacts staff for you';
    } else if (staff != null) {
      messagesStatus = staff.isAdmin ? 'Conversations' : 'Message a member';
    } else if (canContactAdmins && hasCoaches) {
      messagesStatus = 'Talk to the admins or coaches';
    } else if (hasCoaches) {
      messagesStatus = 'Message your coach';
    } else {
      messagesStatus = 'Contact the admins';
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
    final topTitle =
        hot == null || hot.isEmpty ? '' : hot.first.title.trim();
    final discussionsStatus = counts.discussions > 0
        ? '${counts.discussions} new'
        : topTitle.isEmpty
            ? 'Start a discussion'
            : topTitle;

    return <Widget>[
      if (showAnnouncements)
        _TalkTile(
          icon: Icons.campaign_outlined,
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
              withInbox: true,
              canMute: isMember,
            ),
          ),
        ),
      if (showMessages)
        _TalkTile(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Messages',
          status: messagesStatus,
          badge: counts.messages,
          onTap: () => _afterSheet(context, _openMessages(context)),
        ),
      if (showDiscussions)
        _TalkTile(
          icon: Icons.forum_outlined,
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
    final announcementsStatus = urgent
        ? '${counts.urgent} urgent'
        : unseen > 0
            ? '$unseen new'
            : canAnnounce
                ? 'Announce to the team'
                : 'News for the team';

    // ── Messages: this team's coaches; its players for staff.
    final o = ref.watch(messageStartOptionsProvider(groupId)).valueOrNull;
    final coaches = teamCoachOptions(o, teamId);
    final toPlayers = canMessageTeamPlayers(o, teamId);
    // A supervised player on this team: the sheet explains why there's no
    // "Message coach".
    final selfBlocked = inTeam && o?.selfBlockedReason != null;
    final showMessages = coaches.isNotEmpty || toPlayers || selfBlocked;
    final String messagesStatus;
    if (counts.messages > 0) {
      messagesStatus = '${counts.messages} unread';
    } else if (selfBlocked && !toPlayers) {
      messagesStatus = 'Your guardian contacts staff for you';
    } else if (coaches.length == 1) {
      messagesStatus = 'Message ${coaches.first.name}';
    } else if (coaches.isNotEmpty) {
      messagesStatus = 'Message your coach';
    } else {
      messagesStatus = 'Message a player';
    }

    // ── Discussions: the team's, for the people in its space.
    final hot = inTeam
        ? ref
            .watch(discussionListProvider(_hotKey(groupId, teamId)))
            .valueOrNull
            ?.items
        : null;
    final topTitle =
        hot == null || hot.isEmpty ? '' : hot.first.title.trim();
    final discussionsStatus = counts.discussions > 0
        ? '${counts.discussions} new'
        : topTitle.isEmpty
            ? 'Start a discussion'
            : topTitle;

    return <Widget>[
      if (showAnnouncements)
        _TalkTile(
          icon: Icons.campaign_outlined,
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
              withInbox: true,
              canMute: false,
              teamId: teamId,
            ),
          ),
        ),
      if (showMessages)
        _TalkTile(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Messages',
          status: messagesStatus,
          badge: counts.messages,
          onTap: () =>
              _afterSheet(context, _openTeamMessages(context, teamId)),
        ),
      if (inTeam)
        _TalkTile(
          icon: Icons.forum_outlined,
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
  Future<void> _openMessages(BuildContext context) {
    return showSpSheet<void>(
      context,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpSheetHeader(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Messages',
            subtitle: groupName,
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
  Future<void> _openTeamMessages(BuildContext context, String teamId) {
    return showSpSheet<void>(
      context,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpSheetHeader(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Messages',
            subtitle: groupName,
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
              subtitle: groupName,
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

/// One Talk tile: icon (with a notification badge, top-right), name and a
/// status line. Red — tile and badge — when something urgent is waiting.
class _TalkTile extends StatelessWidget {
  const _TalkTile({
    required this.icon,
    required this.label,
    required this.status,
    required this.onTap,
    this.badge = 0,
    this.urgent = false,
  });
  final IconData icon;
  final String label;
  final String status;
  final VoidCallback onTap;
  final int badge;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tone = urgent ? p.danger : p.greenText;
    final fill = urgent ? p.liveTint : p.surface;
    return Semantics(
      button: true,
      label: badge > 0 ? '$label, $badge new. $status' : '$label. $status',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: dark ? Border.all(color: p.line) : null,
              boxShadow: urgent ? null : cardShadow(context),
            ),
            child: Column(children: [
              Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: urgent ? p.surface : tone.withAlpha(30),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, size: 20, color: tone),
                ),
                if (badge > 0)
                  Positioned(
                    top: -5,
                    right: -8,
                    child: _Badge(
                      count: badge,
                      color: urgent ? p.danger : p.accentDeep,
                      border: fill,
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    maxLines: 1,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 2),
              Text(status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: urgent ? p.danger : p.muted,
                      fontSize: 11.5,
                      height: 1.3)),
            ]),
          ),
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
      height: 20,
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 5),
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
