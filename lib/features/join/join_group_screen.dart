import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/join/join_repository.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';

class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(joinRepositoryProvider).joinGroup(widget.groupId);
      ref.invalidate(myGroupsProvider);
      if (mounted) goWithHome(context, '/groups/${widget.groupId}');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(groupJoinInfoProvider(widget.groupId));
    final signedIn =
        ref.watch(authControllerProvider).value?.isAuthenticated ?? false;
    final p = context.palette;
    return Scaffold(
      appBar:
          AppBar(leading: const SpLeading(), title: const Text('Join group')),
      body: AsyncView(
        value: info,
        onRetry: () => ref.invalidate(groupJoinInfoProvider(widget.groupId)),
        data: (g) => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Crest(logoUrl: g.imageUrl, label: g.name, size: 80),
              const SizedBox(height: 16),
              Text("You're invited to join",
                  style: TextStyle(color: p.muted, fontSize: 12)),
              const SizedBox(height: 4),
              Text(g.name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall),
              if (g.memberCount != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${g.memberCount} members',
                      style: TextStyle(color: p.muted, fontSize: 12)),
                ),
              const SizedBox(height: 28),
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: p.danger, fontSize: 13)),
                const SizedBox(height: 12),
              ],
              if (g.alreadyMember)
                FilledButton(
                  onPressed: () => goWithHome(context, '/groups/${g.id}'),
                  child: const Text('Go to group'),
                )
              else if (signedIn)
                FilledButton(
                  onPressed: _busy ? null : _join,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text('Join ${g.name}'),
                )
              else
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
