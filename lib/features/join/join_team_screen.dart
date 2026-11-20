import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/join/join_models.dart';
import 'package:sportpadi_mobile/data/join/join_repository.dart';
import 'package:sportpadi_mobile/data/teams/teams_repository.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/features/join/join_group_screen.dart' show JoinLinkDead;
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// `/join-team/<code>` — a team's join link. [code] is the link's secret
/// code (the router sends an old link with the team's id to the team page).
class JoinTeamScreen extends ConsumerStatefulWidget {
  const JoinTeamScreen({super.key, required this.code});
  final String code;

  @override
  ConsumerState<JoinTeamScreen> createState() => _JoinTeamScreenState();
}

class _JoinTeamScreenState extends ConsumerState<JoinTeamScreen> {
  final _jersey = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _jersey.dispose();
    super.dispose();
  }

  Future<void> _join(TeamJoinInfo t) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final n = int.tryParse(_jersey.text.trim());
      final teamId = await ref
              .read(joinRepositoryProvider)
              .joinTeam(widget.code, jerseyNumber: n) ??
          t.id;
      ref.invalidate(myGroupsProvider);
      ref.invalidate(teamDetailProvider(teamId));
      if (mounted) goWithHome(context, '/teams/$teamId');
    } on ApiException catch (e) {
      // 412: this link can't add anyone (an id, not a code) — open the team.
      if (e.statusCode == 412 && t.id.isNotEmpty) {
        if (mounted) goWithHome(context, '/teams/${t.id}');
        return;
      }
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(teamJoinInfoProvider(widget.code));
    final signedIn =
        ref.watch(authControllerProvider).value?.isAuthenticated ?? false;
    final p = context.palette;
    return Scaffold(
      appBar:
          AppBar(leading: const SpLeading(), title: Text(context.l10n.join_joinTeam)),
      body: AsyncView(
        value: info,
        onRetry: () => ref.invalidate(teamJoinInfoProvider(widget.code)),
        data: (t) => t == null
            ? const JoinLinkDead()
            : Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Crest(
                  logoUrl: t.logoUrl,
                  kitPrimary: t.kitPrimary,
                  kitSecondary: t.kitSecondary,
                  label: t.name,
                  size: 80),
              const SizedBox(height: 16),
              Text(context.l10n.join_youreInvitedToJoin,
                  style: TextStyle(color: p.muted, fontSize: 12)),
              const SizedBox(height: 4),
              Text(t.name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    [
                      if (t.username != null) '@${t.username}',
                      if (t.groupName != null) t.groupName!,
                    ].join('  ·  '),
                    style: TextStyle(color: p.muted, fontSize: 12)),
              ),
              const SizedBox(height: 24),
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: p.danger, fontSize: 13)),
                const SizedBox(height: 12),
              ],
              if (t.requestToJoin && !t.alreadyOnTeam) ...[
                // An id link, or someone an admin removed: not by this link.
                Text(context.l10n.join_linkCantAddYouTeam,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.muted, fontSize: 13)),
                const SizedBox(height: 12),
              ],
              if (t.alreadyOnTeam || t.requestToJoin)
                FilledButton(
                  onPressed: () => goWithHome(context, '/teams/${t.id}'),
                  child: Text(context.l10n.join_goToTeam),
                )
              else if (signedIn) ...[
                TextField(
                  controller: _jersey,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.l10n.join_jerseyNumberOptional,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : () => _join(t),
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(context.l10n.join_join(t.name)),
                  ),
                ),
              ] else
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
