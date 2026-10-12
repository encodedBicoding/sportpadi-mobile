import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart' show categoriesProvider;
import 'package:sportpadi_mobile/data/teams/team_models.dart';
import 'package:sportpadi_mobile/data/teams/teams_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/features/teams/sport_art.dart';
import 'package:sportpadi_mobile/features/teams/sport_cards.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';
import 'package:sportpadi_mobile/shared/widgets/team_tile.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// One sport's teams in a group (web `/groups/[id]/teams/sport/[sport]`):
/// the sport's hero with counts, search, adults / kids, and (admins) a new
/// team in this sport.
class SportTeamsScreen extends ConsumerStatefulWidget {
  const SportTeamsScreen({super.key, required this.groupId, required this.sport});
  final String groupId;
  final String sport;

  @override
  ConsumerState<SportTeamsScreen> createState() => _SportTeamsScreenState();
}

class _SportTeamsScreenState extends ConsumerState<SportTeamsScreen> {
  final _search = TextEditingController();
  String _grade = 'all';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final group = ref.watch(groupProvider(widget.groupId)).valueOrNull;
    final canManage = group?.canManage ?? false;
    final tq = ref.watch(groupTeamsProvider(widget.groupId));
    final all = tq.valueOrNull ?? const <TeamSummary>[];
    final allow = canManage ? ref.watch(teamAllowanceProvider(widget.groupId)).valueOrNull : null;
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const [];

    final bucket = bucketTeams(all).where((b) => b.key == widget.sport).firstOrNull;
    final def = bucket?.def ?? sportByKey(widget.sport);
    final name = bucket?.name ?? def?.name ?? 'Teams';
    final color = def?.color ?? const Color(0xFF5E6B66);
    final teams = bucket?.teams ?? const <TeamSummary>[];
    // The category a new team in this sport goes into.
    final categoryId = widget.sport.startsWith('c-')
        ? widget.sport.substring(2)
        : cats.where((c) => sportFor(c.name)?.key == widget.sport).firstOrNull?.id;
    final canAdd = canManage &&
        (allow?.canBuild ?? false) &&
        categoryId != null &&
        ((allow?.canBuildMultiple ?? false) || !(allow?.takenCategoryIds.contains(categoryId) ?? false));

    final needle = _search.text.trim().toLowerCase();
    final shown = teams.where((t) {
      if (_grade == 'kids' && t.grade != 'kids') return false;
      if (_grade == 'adults' && t.grade == 'kids') return false;
      return needle.isEmpty || t.name.toLowerCase().contains(needle) || (t.username ?? '').toLowerCase().contains(needle);
    }).toList();
    final players = teams.fold<int>(0, (n, t) => n + (t.memberCount ?? 0));
    final kids = teams.where((t) => t.grade == 'kids').length;
    final loading = tq.isLoading && tq.valueOrNull == null;

    return SpSubPage(
      title: '$name teams',
      subtitle: group?.name,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(groupTeamsProvider(widget.groupId)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              decoration: BoxDecoration(color: sportTint(p, color), borderRadius: BorderRadius.circular(28)),
              child: Stack(children: [
                Positioned(right: -4, top: 0, child: SportArt(def, emoji: bucket?.emoji, width: 128)),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('SPORT',
                      style: TextStyle(color: sportInk(p, color), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                  const SizedBox(height: 4),
                  Text(name, style: TextStyle(color: p.ink, fontSize: 24, fontWeight: FontWeight.w800, height: 1.1)),
                  const SizedBox(height: 40),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    for (final (n, label) in [(teams.length, 'Teams'), (players, 'Players'), (kids, 'Kids teams')])
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(loading ? '–' : '$n', style: TextStyle(color: p.ink, fontSize: 22, fontWeight: FontWeight.w800, height: 1)),
                          const SizedBox(height: 4),
                          Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: sportInk(p, color), fontSize: 11, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                  ]),
                  if (canAdd) ...[
                    const SizedBox(height: 14),
                    SpPill(
                      label: 'New ${name.toLowerCase()} team',
                      icon: Icons.add_rounded,
                      height: 36,
                      expand: true,
                      onTap: () => context.push('/groups/${widget.groupId}/new-team?category=$categoryId'),
                    ),
                  ],
                ]),
              ]),
            ),
            const SizedBox(height: 14),
            if (teams.isNotEmpty) ...[
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search teams by name or @handle',
                  prefixIcon: Icon(Icons.search_rounded, color: p.muted),
                  filled: true,
                  fillColor: p.surface,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide(color: p.line)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide(color: p.line)),
                ),
              ),
              if (kids > 0 && kids < teams.length) ...[
                const SizedBox(height: 10),
                Row(children: [
                  for (final (v, label) in const [('all', 'All'), ('adults', 'Adults'), ('kids', 'Kids')])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(label: Text(label), selected: _grade == v, onSelected: (_) => setState(() => _grade = v)),
                    ),
                ]),
              ],
              const SizedBox(height: 12),
            ],
            if (loading)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                child: Column(children: [
                  const Center(child: SpIconTile(Icons.shield_outlined, size: 56, iconSize: 26)),
                  const SizedBox(height: 12),
                  Text(
                      teams.isNotEmpty
                          ? 'No team matches — try another search.'
                          : canAdd
                              ? 'No ${name.toLowerCase()} teams yet — build the first one.'
                              : canManage && categoryId == null
                                  ? "$name isn't set up as a sport on SportPadi yet."
                                  : 'This group has no ${name.toLowerCase()} teams yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.muted, fontSize: 13.5)),
                ]),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 172,
                ),
                itemCount: shown.length,
                itemBuilder: (_, i) => TeamTile(team: shown[i]),
              ),
          ],
        ),
      ),
    );
  }
}
