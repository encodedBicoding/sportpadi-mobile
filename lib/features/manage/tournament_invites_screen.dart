import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';

class TournamentInvitesScreen extends ConsumerWidget {
  const TournamentInvitesScreen({super.key, required this.groupId});
  final String groupId;

  Future<void> _respond(BuildContext context, WidgetRef ref, String id, String action) async {
    try {
      await ref.read(manageRepositoryProvider).respondInvite(id, action);
      ref.invalidate(groupInvitesProvider(groupId));
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invites = ref.watch(groupInvitesProvider(groupId));
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('Tournament invites')),
      body: AsyncView(
        value: invites,
        onRetry: () => ref.invalidate(groupInvitesProvider(groupId)),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No pending invites.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final inv = list[i];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(inv.eventTitle,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text([
                      if (inv.hostGroupName != null) inv.hostGroupName!,
                      if (inv.hostTeamName != null) 'vs ${inv.hostTeamName}',
                    ].join('  ·  '), style: TextStyle(color: p.muted, fontSize: 12)),
                    if (inv.guestTeamName != null)
                      Text('Your team: ${inv.guestTeamName}',
                          style: TextStyle(color: p.muted, fontSize: 12)),
                    if (inv.feeLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Entry fee ${inv.feeLabel}',
                            style: TextStyle(color: p.amber, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _respond(context, ref, inv.id, 'reject'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: p.danger, side: BorderSide(color: p.line)),
                          child: const Text('Decline'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _respond(context, ref, inv.id, 'approve'),
                          child: const Text('Accept'),
                        ),
                      ),
                    ]),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
