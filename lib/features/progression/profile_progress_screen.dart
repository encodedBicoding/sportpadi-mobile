import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/data/progression/progression_repository.dart';
import 'package:sportpadi_mobile/features/players/player_profile_screen.dart'
    show playerStatsProvider, playerRecordsProvider;
import 'package:sportpadi_mobile/features/players/player_record.dart';
import 'package:sportpadi_mobile/features/progression/progression_widgets.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// Progress & achievements (web /profile/progress twin): level and XP, weekly
/// streak, per-sport levels, "Your game" strengths and the achievements grid —
/// moved off the profile page (which now leads with honours and recent
/// matches) onto its own page under the profile menu.
class ProfileProgressScreen extends ConsumerWidget {
  const ProfileProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final userId = ref.watch(meProvider).valueOrNull?.userId;
    final stats =
        userId == null ? null : ref.watch(playerStatsProvider(userId)).valueOrNull;
    final categories = listOf(stats?['categories']);
    // "Your game" follows the most-played sport (the payload lists it first).
    final topCategoryId =
        categories.isEmpty ? null : parseStr(categories.first['categoryId']);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SpHeader(title: context.l10n.profile_progressAchievements),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () {
                ref.invalidate(myProgressionProvider);
                ref.invalidate(strengthsProvider);
                if (userId != null) ref.invalidate(playerRecordsProvider(userId));
                return settleAll([
                  ref.read(myProgressionProvider.future),
                  if (userId != null) ref.read(playerStatsProvider(userId).future),
                ]);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
                children: [
                  ProfileProgressionSection(
                    userId: userId,
                    categoryId: topCategoryId,
                    categoryNames: {
                      for (final c in categories)
                        if (parseStr(c['categoryId']) != null)
                          parseStr(c['categoryId'])!: parseStr(c['name']) ?? 'Sport',
                    },
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
