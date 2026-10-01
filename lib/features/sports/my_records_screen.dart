import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/players/player_profile_screen.dart';
import 'package:sportpadi_mobile/features/players/player_record.dart';
import 'package:sportpadi_mobile/features/sports/sport_record_card.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// My records (`/profile/records`, design §6): one sport card per sport I've
/// played (or set up), then every other sport as a quiet list — each opens
/// that sport's record page.
class MyRecordsScreen extends ConsumerWidget {
  const MyRecordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final me = ref.watch(authControllerProvider).valueOrNull?.user?.id;
    final data = me == null ? null : ref.watch(playerRecordsProvider(me));

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            if (me == null) return;
            ref.invalidate(playerRecordsProvider(me));
            // Errors show on the page itself; the spinner just stops.
            await ref
                .read(playerRecordsProvider(me).future)
                .then((_) {}, onError: (_) {});
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              SpHeader(
                title: 'My records',
                subtitle: 'Your numbers, sport by sport',
                actions: [
                  SpRoundButton(
                    icon: Icons.tune_rounded,
                    tooltip: 'My sports',
                    onTap: () => context.push('/profile/sports'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (data == null)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(48),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                AsyncView(
                  value: data,
                  onRetry: () => ref.invalidate(playerRecordsProvider(me!)),
                  data: (m) => _Content(categories: listOf(m['categories'])),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.categories});
  final List<Map<String, dynamic>> categories;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final withIds = [
      for (final c in categories)
        if (parseStr(c['categoryId']) != null) c
    ];
    // Most played first (the server's order); then sports only set up.
    final played = [
      for (final c in withIds)
        if (hasPlayed(c)) c
    ];
    final setUp = [
      for (final c in withIds)
        if (!hasPlayed(c) && listOf(c['setup']).isNotEmpty) c
    ];
    final others = [
      for (final c in withIds)
        if (!hasPlayed(c) && listOf(c['setup']).isEmpty) c
    ];
    void open(Map<String, dynamic> c) =>
        context.push('/profile/records/${parseStr(c['categoryId'])}');

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (played.isEmpty && setUp.isEmpty)
        GlassCard(
          padding: const EdgeInsets.all(22),
          child: Column(children: [
            SpIconTile(Icons.emoji_events_outlined,
                bg: p.accentTint, fg: p.greenText, size: 52, iconSize: 25),
            const SizedBox(height: 12),
            Text('No games on record yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: p.ink, fontSize: 15.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
                'Tell us the sports you play, then finish a game — your numbers land here, sport by sport.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.45)),
            const SizedBox(height: 16),
            SpButton(
              label: 'Set up my sports',
              icon: Icons.tune_rounded,
              onTap: () => context.push('/profile/sports'),
            ),
          ]),
        )
      else
        for (final (i, c) in [...played, ...setUp].indexed) ...[
          if (i > 0) const SizedBox(height: 12),
          SportRecordCard(category: c, onTap: () => open(c)),
        ],
      if (others.isNotEmpty) ...[
        const SizedBox(height: 26),
        SpSectionTitle('Other sports', count: others.length),
        const SizedBox(height: 10),
        SpListCard(children: [
          for (final c in others)
            OtherSportRow(category: c, onTap: () => open(c)),
        ]),
      ],
    ]);
  }
}
