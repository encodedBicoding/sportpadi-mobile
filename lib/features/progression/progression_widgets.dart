import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/progression/progression_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// "Lv 3 · Starter  🔥 4" — the compact identity on player pages and cards.
class LevelBadge extends StatelessWidget {
  const LevelBadge({super.key, required this.level, required this.title, this.streak});
  final int level;
  final String title;
  final int? streak;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: p.accent.withAlpha(26),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: p.accent.withAlpha(90)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('Lv $level · $title',
            style: TextStyle(color: p.accent, fontSize: 11, fontWeight: FontWeight.w700)),
        if ((streak ?? 0) > 0) ...[
          const SizedBox(width: 6),
          Icon(Icons.local_fire_department_rounded, size: 13, color: p.amber),
          Text('${streak!}', style: TextStyle(color: p.amber, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ]),
    );
  }
}

/// Progress to the next level.
class XpBar extends StatelessWidget {
  const XpBar({super.key, required this.progress, this.xp, this.nextLevelXp});
  final double progress;
  final int? xp;
  final int? nextLevelXp;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: progress.clamp(0, 1),
          minHeight: 7,
          backgroundColor: p.line,
          valueColor: AlwaysStoppedAnimation(p.accent),
        ),
      ),
      if (xp != null) ...[
        const SizedBox(height: 4),
        Text(
          nextLevelXp != null ? '$xp XP · ${nextLevelXp! - xp!} to next level' : '$xp XP · max level',
          style: TextStyle(color: p.muted, fontSize: 11),
        ),
      ],
    ]);
  }
}

/// Streak pill: amber when alive, muted when not.
class StreakPill extends StatelessWidget {
  const StreakPill({super.key, required this.streak});
  final Streak? streak;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final n = streak?.current ?? 0;
    final on = n > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: on ? p.amber.withAlpha(36) : p.line.withAlpha(90),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.local_fire_department_rounded, size: 14, color: on ? p.amber : p.muted),
        const SizedBox(width: 4),
        Text(
          on ? '$n-week streak${(streak?.paused ?? false) ? ' · paused' : ''}' : 'No streak yet',
          style: TextStyle(color: on ? p.amber : p.muted, fontSize: 11.5, fontWeight: FontWeight.w700),
        ),
      ]),
    );
  }
}

/// Home: level, streak, this week's challenges (3 of 4 pays the bonus) and
/// the next achievement within reach. Invisible until the server has it.
class YourWeekCard extends ConsumerWidget {
  const YourWeekCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final d = ref.watch(yourWeekProvider).valueOrNull;
    if (d == null) return const SizedBox.shrink();
    final q = d.quests;
    final daysLeft = q?.endsAt == null
        ? null
        : (q!.endsAt!.difference(DateTime.now()).inHours / 24).ceil().clamp(0, 7);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('YOUR WEEK',
                    style: TextStyle(color: p.muted, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                const SizedBox(height: 2),
                Text('Level ${d.level} · ${d.title}',
                    style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
              ]),
            ),
            StreakPill(streak: d.streak),
          ]),
          const SizedBox(height: 10),
          XpBar(progress: d.progress, xp: d.xp, nextLevelXp: d.nextLevelXp),
          if (q != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              Icon(Icons.flag_outlined, size: 15, color: p.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text("This week's challenges",
                    style: TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
              Text(
                q.rewarded
                    ? 'Done · +${q.rewardXp} XP'
                    : '${q.completed}/${q.needed} for +${q.rewardXp} XP${daysLeft != null ? ' · ${daysLeft}d' : ''}',
                style: TextStyle(color: p.muted, fontSize: 11),
              ),
            ]),
            const SizedBox(height: 6),
            for (final qq in q.quests)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Icon(qq.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      size: 17, color: qq.done ? p.accent : p.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(qq.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: qq.done ? p.muted : p.ink,
                          fontSize: 13,
                          decoration: qq.done ? TextDecoration.lineThrough : null,
                        )),
                  ),
                  Text('${qq.progress}/${qq.target}', style: TextStyle(color: p.muted, fontSize: 12)),
                ]),
              ),
          ],
          if (q != null && q.missions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: [
              Icon(Icons.rocket_launch_outlined, size: 15, color: p.amber),
              const SizedBox(width: 6),
              Text('Missions', style: TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 6),
            for (final m in q.missions)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(m.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        size: 16, color: m.done ? p.accent : p.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(m.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.ink, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    Text('+${m.xp} XP', style: TextStyle(color: p.accent, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: Text(
                      '${m.description} · ${m.progress}/${m.target}'
                      '${m.endsAt != null ? ' · ends ${m.endsAt!.day}/${m.endsAt!.month}' : ''}',
                      style: TextStyle(color: p.muted, fontSize: 11.5),
                    ),
                  ),
                ]),
              ),
          ],
          if (d.next != null) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => context.push('/progress'),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p.line),
                ),
                child: Row(children: [
                  Icon(Icons.auto_awesome_rounded, size: 15, color: p.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Next up: ${d.next!.title} — ${d.next!.description}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.ink, fontSize: 12)),
                  ),
                  Text('${d.next!.current}/${d.next!.target}', style: TextStyle(color: p.muted, fontSize: 11.5)),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// The player's own progression block on Profile: level, XP bar, streak,
/// per-sport levels, "Your game" for the selected sport, and the top three
/// achievements with a way into the full grid.
class ProfileProgressionSection extends ConsumerWidget {
  const ProfileProgressionSection({super.key, this.userId, this.categoryId, this.categoryNames = const {}});
  final String? userId;
  final String? categoryId;
  final Map<String, String> categoryNames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final d = ref.watch(myProgressionProvider).valueOrNull;
    if (d == null) return const SizedBox.shrink();
    final strengths = (userId != null && categoryId != null)
        ? ref.watch(strengthsProvider((userId: userId!, categoryId: categoryId!))).valueOrNull ?? const <Strength>[]
        : const <Strength>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Eyebrow('Progress'),
          const Spacer(),
          InkWell(
            onTap: () => context.push('/leaderboards'),
            child: Text('Leaderboards',
                style: TextStyle(color: p.accent, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 8),
        GlassCard(
          onTap: () => context.push('/progress'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: d.title, style: TextStyle(color: p.ink, fontSize: 20, fontWeight: FontWeight.w800)),
                  TextSpan(text: '  · Level ${d.level}', style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w600)),
                ])),
              ),
              StreakPill(streak: d.weekly),
            ]),
            const SizedBox(height: 10),
            XpBar(progress: d.progress, xp: d.xp, nextLevelXp: d.nextLevelXp),
            if (d.categories.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final c in d.categories)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99), border: Border.all(color: p.line)),
                    child: Text('${categoryNames[c.categoryId] ?? 'Sport'}: ${c.title}',
                        style: TextStyle(color: p.ink, fontSize: 11)),
                  ),
              ]),
            ],
          ]),
        ),
        if (strengths.isNotEmpty) ...[
          const SizedBox(height: 10),
          GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Your game', style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final s in strengths)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(
                        child: Text('${s.icon != null ? '${s.icon} ' : ''}${s.label}',
                            style: TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ),
                      Text('${s.value} · top ${(100 - s.percentile).clamp(1, 100)}%',
                          style: TextStyle(color: p.muted, fontSize: 11.5)),
                    ]),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: (s.percentile.clamp(4, 100)) / 100,
                        minHeight: 5,
                        backgroundColor: p.line,
                        valueColor: AlwaysStoppedAnimation(p.accent),
                      ),
                    ),
                  ]),
                ),
              const SizedBox(height: 4),
              Text('Compared with everyone who plays this sport on SportPadi.',
                  style: TextStyle(color: p.muted, fontSize: 10.5)),
            ]),
          ),
        ],
        const SizedBox(height: 10),
        GlassCard(
          onTap: () => context.push('/progress'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text('Achievements · ${d.unlocked.length}/${d.catalogue.length}',
                    style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              Icon(Icons.chevron_right_rounded, color: p.muted),
            ]),
            const SizedBox(height: 6),
            if (d.unlocked.isEmpty)
              Text('Check in to your first game to unlock First Whistle.',
                  style: TextStyle(color: p.muted, fontSize: 12.5))
            else
              for (final a in d.unlocked.take(3))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Icon(Icons.emoji_events_rounded, size: 16, color: p.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(a.title,
                          style: TextStyle(color: p.ink, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
          ]),
        ),
      ]),
    );
  }
}

/// Ring colour for an earned avatar frame (null = no frame).
Color? frameColor(String frame) => switch (frame) {
      'bronze' => const Color(0xFFB0712F),
      'silver' => const Color(0xFFC9CED6),
      'gold' => const Color(0xFFF5B82E),
      'legend' => const Color(0xFFD946EF),
      _ => null,
    };

/// Wraps an avatar in the player's earned frame (nothing below Regular).
class FramedAvatar extends ConsumerWidget {
  const FramedAvatar({super.key, required this.userId, required this.child});
  final String? userId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = userId == null ? null : ref.watch(identityProvider(userId!)).valueOrNull;
    final c = id == null ? null : frameColor(id.frame);
    if (c == null) return child;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c, width: id!.frame == 'gold' || id.frame == 'legend' ? 3 : 2),
        boxShadow: id.frame == 'legend' ? [BoxShadow(color: c.withAlpha(110), blurRadius: 14)] : null,
      ),
      child: child,
    );
  }
}

/// A group's own level, streak, numbers and achievements (group page).
class GroupReputationCard extends ConsumerWidget {
  const GroupReputationCard({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final d = ref.watch(groupProgressionProvider(groupId)).valueOrNull;
    if (d == null || d.xp == 0) return const SizedBox.shrink();
    Widget stat(IconData icon, String n, String label) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
            child: Column(children: [
              Icon(icon, size: 15, color: p.accent),
              const SizedBox(height: 2),
              Text('$n $label', style: TextStyle(color: p.ink, fontSize: 11.5)),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('GROUP LEVEL',
                    style: TextStyle(color: p.muted, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                Text('Level ${d.level}', style: TextStyle(color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
              ]),
            ),
            if (d.weeklyStreak > 0)
              StreakPill(streak: Streak(current: d.weeklyStreak, best: d.weeklyStreak, paused: false)),
          ]),
          const SizedBox(height: 8),
          XpBar(progress: d.progress),
          const SizedBox(height: 10),
          Row(children: [
            stat(Icons.emoji_events_outlined, '${d.games}', 'games'),
            const SizedBox(width: 6),
            stat(Icons.groups_outlined, '${d.players}', 'players'),
            const SizedBox(width: 6),
            stat(Icons.place_outlined, '${d.venues}', 'venues'),
          ]),
          if (d.achievements.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final a in d.achievements)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: p.accent.withAlpha(20),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: p.accent.withAlpha(80)),
                  ),
                  child: Text('✓ $a', style: TextStyle(color: p.ink, fontSize: 11)),
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}
