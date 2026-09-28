import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/features/tournaments/invitation_rows.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';

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
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('Tournament invites',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: AsyncView(
        value: invites,
        onRetry: () => ref.invalidate(groupInvitesProvider(groupId)),
        data: (list) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(groupInvitesProvider(groupId)),
          child: list.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(32),
                  children: [
                    const SizedBox(height: 60),
                    Icon(Icons.mark_email_read_outlined,
                        size: 44, color: p.muted),
                    const SizedBox(height: 12),
                    Center(
                      child: Text('No pending invites',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        "When another group invites one of this group's teams\nto a tournament, it lands here.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: p.muted, fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Text('${list.length} waiting · soonest first',
                        style: TextStyle(color: p.muted, fontSize: 12)),
                    const SizedBox(height: 10),
                    InvitationListBox(
                      invites: list,
                      // The row refreshes the personal lists itself; this one
                      // is group-scoped, so it has to be told.
                      onDone: () => ref.invalidate(groupInvitesProvider(groupId)),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
