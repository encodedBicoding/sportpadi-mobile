import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/join/join_repository.dart';
import 'package:sportpadi_mobile/data/teams/teams_repository.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';

class JoinTeamScreen extends ConsumerStatefulWidget {
  const JoinTeamScreen({super.key, required this.teamId});
  final String teamId;

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

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final n = int.tryParse(_jersey.text.trim());
      await ref
          .read(joinRepositoryProvider)
          .joinTeam(widget.teamId, jerseyNumber: n);
      ref.invalidate(myGroupsProvider);
      ref.invalidate(teamDetailProvider(widget.teamId));
      if (mounted) context.go('/teams/${widget.teamId}');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(teamJoinInfoProvider(widget.teamId));
    final signedIn =
        ref.watch(authControllerProvider).value?.isAuthenticated ?? false;
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('Join team')),
      body: AsyncView(
        value: info,
        onRetry: () => ref.invalidate(teamJoinInfoProvider(widget.teamId)),
        data: (t) => Center(
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
              Text("You're invited to join",
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
              if (t.alreadyOnTeam)
                FilledButton(
                  onPressed: () => context.go('/teams/${t.id}'),
                  child: const Text('Go to team'),
                )
              else if (signedIn) ...[
                TextField(
                  controller: _jersey,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Jersey number (optional)',
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _join,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text('Join ${t.name}'),
                  ),
                ),
              ] else
                FilledButton(
                  onPressed: () => context.go('/sign-in'),
                  child: const Text('Sign in to join'),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
