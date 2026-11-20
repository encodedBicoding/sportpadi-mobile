import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/join/join_models.dart';
import 'package:sportpadi_mobile/data/join/join_repository.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// `/join/<code>` — a group's membership link. [code] is the link's secret
/// code (the router sends an old link with the group's id to the group page).
class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key, required this.code});
  final String code;

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _join(GroupJoinInfo g) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final groupId = await ref.read(joinRepositoryProvider).joinGroup(widget.code);
      ref.invalidate(myGroupsProvider);
      if (mounted) goWithHome(context, '/groups/${groupId ?? g.id}');
    } on ApiException catch (e) {
      // 412: this link can't add anyone (an id, not a code) — the group's
      // page is where to ask to join.
      if (e.statusCode == 412 && g.id.isNotEmpty) {
        if (mounted) goWithHome(context, '/groups/${g.id}');
        return;
      }
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(groupJoinInfoProvider(widget.code));
    final signedIn =
        ref.watch(authControllerProvider).value?.isAuthenticated ?? false;
    final p = context.palette;
    return Scaffold(
      appBar:
          AppBar(leading: const SpLeading(), title: Text(context.l10n.join_joinGroup)),
      body: AsyncView(
        value: info,
        onRetry: () => ref.invalidate(groupJoinInfoProvider(widget.code)),
        data: (g) => g == null
            ? const JoinLinkDead()
            : Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Crest(logoUrl: g.imageUrl, label: g.name, size: 80),
              const SizedBox(height: 16),
              Text(context.l10n.join_youreInvitedToJoin,
                  style: TextStyle(color: p.muted, fontSize: 12)),
              const SizedBox(height: 4),
              Text(g.name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall),
              if (g.memberCount != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(context.l10n.join_members(g.memberCount ?? ''),
                      style: TextStyle(color: p.muted, fontSize: 12)),
                ),
              const SizedBox(height: 28),
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: p.danger, fontSize: 13)),
                const SizedBox(height: 12),
              ],
              if (g.requestToJoin && !g.alreadyMember) ...[
                // An id link, or someone an admin removed: ask to join there.
                Text(context.l10n.join_linkCantAddYou,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.muted, fontSize: 13)),
                const SizedBox(height: 12),
              ],
              if (g.alreadyMember || g.requestToJoin)
                FilledButton(
                  onPressed: () => goWithHome(context, '/groups/${g.id}'),
                  child: Text(context.l10n.join_goToGroup),
                )
              else if (signedIn)
                FilledButton(
                  onPressed: _busy ? null : () => _join(g),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(context.l10n.join_join(g.name)),
                )
              else
                FilledButton(
                  onPressed: () => context.go('/sign-in'),
                  child: Text(context.l10n.join_signInToJoin),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// An unknown or reset invite code: said as it is (the server answers both
/// alike), and no Retry — asking again can't make it work.
class JoinLinkDead extends StatelessWidget {
  const JoinLinkDead({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.link_off_rounded, size: 40, color: p.muted),
          const SizedBox(height: 12),
          Text(context.l10n.join_inviteLinkDeadTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(context.l10n.join_inviteLinkDead,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 13)),
        ]),
      ),
    );
  }
}
