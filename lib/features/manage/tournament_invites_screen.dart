import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/features/tournaments/invitation_rows.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart'
    show groupProvider;

/// One group's pending tournament invites, reached from the group menu.
///
/// Shares [InvitationListBox] with the Tournaments tab and
/// /tournaments/invitations, so all three behave identically — including the
/// bits this screen used to get wrong on its own: a paid tournament handing off
/// to checkout, confirming before an irreversible decline, and refreshing the
/// other lists the same invite appears on.
class TournamentInvitesScreen extends ConsumerWidget {
  const TournamentInvitesScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final invites = ref.watch(groupInvitesProvider(groupId));
    final groupName = ref.watch(groupProvider(groupId)).valueOrNull?.name;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SpHeader(title: 'Tournament invites', subtitle: groupName),
          ),
          Expanded(
            child: AsyncView(
              value: invites,
              onRetry: () => ref.invalidate(groupInvitesProvider(groupId)),
              data: (list) => RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(groupInvitesProvider(groupId)),
                child: list.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(32, 70, 32, 32),
                        children: [
                          Center(
                            child: SpIconTile(Icons.mark_email_read_outlined,
                                bg: p.orangeTint,
                                fg: p.orangeInk,
                                size: 60,
                                iconSize: 28),
                          ),
                          const SizedBox(height: 14),
                          Text('No pending invites',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(
                            "When another group invites one of this group's teams to a tournament, it lands here.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: p.muted, fontSize: 13, height: 1.45),
                          ),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
                        children: [
                          // How many, and what answering does.
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: p.orangeTint,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Row(children: [
                              SpIconTile(Icons.emoji_events_outlined,
                                  bg: p.surface,
                                  fg: p.orangeInk,
                                  size: 46,
                                  iconSize: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          '${list.length} invitation${list.length == 1 ? '' : 's'} waiting',
                                          style: TextStyle(
                                              color: p.ink,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700)),
                                      Text(
                                          'Soonest first. Accepting takes you to the squad to call your players.',
                                          style: TextStyle(
                                              color: p.orangeInk,
                                              fontSize: 12,
                                              height: 1.4)),
                                    ]),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 14),
                          InvitationListBox(
                            invites: list,
                            // The row refreshes the personal lists itself;
                            // this one is group-scoped, so it has to be told.
                            onDone: () =>
                                ref.invalidate(groupInvitesProvider(groupId)),
                          ),
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
