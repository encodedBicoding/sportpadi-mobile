import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart'
    show groupInvitationCountProvider;
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// "My groups" in the user menu (side menu and profile menu) — Groups left
/// the dock: the groups you're a member of are listed right here, with a
/// "See all" to /groups when there are more than fit, and a Group invites row
/// for the groups you've been invited to. Browse is where new groups are
/// found. Web twin: components/groups/MyGroupsMenu.tsx.
class MyGroupsMenu extends ConsumerWidget {
  const MyGroupsMenu({super.key, required this.onGo});

  /// Navigate (the menu closes itself first).
  final void Function(String dest) onGo;

  /// How many groups the menu shows before "See all".
  static const shown = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final l = context.l10n;
    final groups = ref.watch(myGroupsProvider);
    final invites = ref.watch(groupInvitationCountProvider).valueOrNull ?? 0;
    final all = groups.valueOrNull ?? const [];
    final head = all.take(shown).toList();
    final more = all.length - head.length;

    Widget row({
      required Widget leading,
      required String title,
      String? sub,
      int? badge,
      required String dest,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => onGo(dest),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600)),
                  if (sub != null)
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 12)),
                ],
              ),
            ),
            if (badge != null && badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: p.orange, borderRadius: BorderRadius.circular(999)),
                child: Text(badge > 99 ? '99+' : '$badge',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              )
            else
              Icon(Icons.chevron_right_rounded, size: 18, color: p.muted),
          ]),
        ),
      );
    }

    return SpListCard(children: [
      if (groups.isLoading && all.isEmpty)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(l.groups_loading,
              style: TextStyle(color: p.muted, fontSize: 13)),
        )
      else if (all.isEmpty)
        row(
          leading: SpIconTile(Icons.groups_outlined,
              size: 38, iconSize: 19, bg: p.accentTint, fg: p.greenText),
          title: l.groups_notInAGroup,
          sub: l.groups_findOneOnBrowse,
          dest: 'tab:1',
        ),
      for (final g in head)
        row(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Crest(logoUrl: g.logoUrl, label: g.name, size: 38),
          ),
          title: g.name,
          sub: [
            if (g.role == 'admin') l.groups_admin,
            if (g.memberCount != null) l.groups_members(g.memberCount!),
          ].join(' · '),
          dest: '/groups/${g.id}',
        ),
      if (more > 0)
        row(
          leading: SpIconTile(Icons.groups_outlined,
              size: 38, iconSize: 19, bg: p.surface2, fg: p.muted),
          title: l.groups_seeAll(all.length),
          dest: '/groups',
        ),
      // New group: the menu closes and /groups opens with the create sheet up.
      row(
        leading: SpIconTile(Icons.add_rounded,
            size: 38, iconSize: 20, bg: p.hero, fg: p.onHero),
        title: l.groups_newGroup,
        sub: l.groups_newGroupSub,
        dest: '/groups?create=1',
      ),
      row(
        leading: SpIconTile(Icons.mail_outline_rounded,
            size: 38,
            iconSize: 19,
            bg: invites > 0 ? p.orangeTint : p.surface2,
            fg: invites > 0 ? p.orangeInk : p.muted),
        title: l.groups_invites,
        sub: invites > 0 ? l.groups_invitedYou(invites) : l.groups_invitesSub,
        badge: invites,
        dest: '/groups?tab=invites',
      ),
    ]);
  }
}
