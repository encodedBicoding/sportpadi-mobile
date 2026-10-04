import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/features/tournaments/invitation_rows.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';

/// Every tournament invitation waiting on this user, in one place.
///
/// The Tournaments tab shows the three soonest; when a busy club is sitting on
/// a dozen, this is where they get worked through.
class TournamentInvitationsScreen extends ConsumerWidget {
  const TournamentInvitationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final invites = ref.watch(myTournamentInvitesProvider);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('Tournament invitations',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: () {
          ref.invalidate(myTournamentInvitesProvider);
          return settleAll([ref.read(myTournamentInvitesProvider.future)]);
        },
        // Loading / error aren't scrollable on their own.
        child: _pullable(invites, AsyncView(
        value: invites,
        onRetry: () => ref.invalidate(myTournamentInvitesProvider),
        data: (list) => list.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(32),
                  children: [
                    const SizedBox(height: 60),
                    Icon(Icons.mark_email_read_outlined,
                        size: 44, color: p.muted),
                    const SizedBox(height: 12),
                    Center(
                      child: Text('Nothing waiting',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        'When another group invites one of your teams\nto a tournament, it lands here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: p.muted, fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Text(
                      '${list.length} waiting on your answer · soonest first',
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    InvitationListBox(invites: list),
                  ],
                ),
        )),
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
