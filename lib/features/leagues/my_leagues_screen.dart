import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/leagues/leagues_repository.dart';
import 'package:sportpadi_mobile/features/leagues/league_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// "My leagues" (web `/leagues/mine`): where I'm registered, my next league
/// matches, and — when the organiser set a roster cutoff — my league pass.
/// Call-ups from a coach sit on top: accepting registers me on that roster.
class MyLeaguesScreen extends ConsumerWidget {
  const MyLeaguesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final q = ref.watch(myLeaguesProvider);
    return SpSubPage(
      title: 'My leagues',
      subtitle: 'Your registrations and league pass',
      body: AsyncView(
        value: q,
        onRetry: () => ref.invalidate(myLeaguesProvider),
        data: (list) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myLeaguesProvider);
            ref.invalidate(myLeagueCallsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              const _CallUps(),
              if (list.isEmpty)
                const SpEmpty(
                    icon: Icons.emoji_events_rounded,
                    text: "You're not on a league roster yet. When a coach calls you up and you accept, it shows up here."),
              for (final r in list) ...[
                GlassCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Crest(logoUrl: r.o('team')?.s('logoUrl'), label: r.o('team')?.s('name'), size: 40),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.o('league')?.str('title') ?? '',
                              style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
                          Text(
                              [
                                r.o('team')?.s('name'),
                                if (r.iOrNull('shirtNumber') != null) '#${r.i('shirtNumber')}',
                                r.s('position'),
                              ].whereType<String>().join(' · '),
                              style: TextStyle(color: p.muted, fontSize: 12)),
                          if (r.o('presentedBy') != null)
                            Text('Presented by ${r.o('presentedBy')!.str('name')}',
                                style: TextStyle(color: p.muted, fontSize: 11)),
                        ]),
                      ),
                      SpPill(
                          label: 'Table',
                          tone: SpPillTone.soft,
                          height: 32,
                          onTap: () => context.push('/leagues/${r.o('league')?.str('slug')}')),
                    ]),
                    if (r.o('pass')?.b('available') == true) ...[
                      const SizedBox(height: 12),
                      if (r.o('pass')!.b('live'))
                        SpButton(
                          label: 'Show league pass',
                          icon: Icons.qr_code_2_rounded,
                          expand: true,
                          onTap: () => showSpSheet<void>(context, builder: (_) => _PassSheet(entryId: r.str('entryId'))),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(14)),
                          child: Text(
                              'Your league pass goes live ${r.o('pass')!.date('liveAt') == null ? 'after the roster cutoff' : 'on ${MaterialLocalizations.of(context).formatFullDate(r.o('pass')!.date('liveAt')!)}'}.',
                              style: TextStyle(color: p.muted, fontSize: 12.5)),
                        ),
                    ],
                  ]),
                ),
                if (r.list('upcoming').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SpListCard(children: [for (final f in r.list('upcoming')) FixtureTile(f: f)]),
                ],
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Open league call-ups: "I'm in" registers me, "Can't play" tells the coach.
class _CallUps extends ConsumerWidget {
  const _CallUps();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final calls = ref.watch(myLeagueCallsProvider).valueOrNull ?? const <J>[];
    if (calls.isEmpty) return const SizedBox.shrink();
    Future<void> answer(J c, bool accept) => leagueAction(context, ref, 'respondCall', {'callId': c.str('callId'), 'accept': accept},
        success: accept ? "You're on the league roster." : 'Your coach has been told.',
        refresh: [myLeagueCallsProvider, myLeaguesProvider]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SpSectionTitle('Call-ups', count: calls.length),
      const SizedBox(height: 8),
      for (final c in calls) ...[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: p.hero, borderRadius: BorderRadius.circular(24)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Crest(logoUrl: c.o('team')?.s('logoUrl'), label: c.o('team')?.s('name'), size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${c.o('team')?.str('name', 'Your team') ?? 'Your team'} calls you up'.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.orange, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                  Text(c.o('league')?.str('title') ?? 'League',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.onHero, fontSize: 15, fontWeight: FontWeight.w800)),
                  Text(
                      [
                        c.s('calledByName') != null ? 'From ${c.str('calledByName')}' : 'From your coach',
                        if (c.o('league')?.date('rosterLockAt') != null)
                          'answer by ${MaterialLocalizations.of(context).formatMediumDate(c.o('league')!.date('rosterLockAt')!)}',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.heroMuted, fontSize: 12)),
                ]),
              ),
            ]),
            if (c.s('callNote') != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: p.onHero.withAlpha(20), borderRadius: BorderRadius.circular(16)),
                child: Text(c.str('callNote'), style: TextStyle(color: p.onHero, fontSize: 13, height: 1.35)),
              ),
            ],
            const SizedBox(height: 12),
            if (c.b('open'))
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: p.accentDeep, foregroundColor: Colors.white, minimumSize: const Size(0, 44)),
                    onPressed: () => answer(c, true),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text("I'm in", style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: p.onHero.withAlpha(26), foregroundColor: p.onHero, minimumSize: const Size(0, 44)),
                    onPressed: () => answer(c, false),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text("Can't play", style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ])
            else
              Text('The roster cutoff has passed — ask your coach or the organiser.',
                  style: TextStyle(color: p.heroMuted, fontSize: 12.5)),
          ]),
        ),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 6),
    ]);
  }
}

/// The rotating QR — refetched every 30 s while open, so a screenshot stops
/// scanning within a couple of minutes.
class _PassSheet extends ConsumerStatefulWidget {
  const _PassSheet({required this.entryId});
  final String entryId;
  @override
  ConsumerState<_PassSheet> createState() => _PassSheetState();
}

class _PassSheetState extends ConsumerState<_PassSheet> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => ref.invalidate(leaguePassProvider(widget.entryId)));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final q = ref.watch(leaguePassProvider(widget.entryId));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const SpSheetHeader(title: 'League pass', subtitle: 'Show this to the organiser when they ask.', icon: Icons.verified_rounded),
      AsyncView(
        value: q,
        data: (d) {
          final v = d.s('value');
          if (v == null) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Your pass isn\'t live yet.', style: TextStyle(color: p.muted)),
            );
          }
          return Column(children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: QrImageView(data: v, size: 230, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.verified_rounded, color: p.greenText, size: 18),
              const SizedBox(width: 6),
              Text('Registered player', style: TextStyle(color: p.greenText, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            Text('Refreshes every 30 seconds — a screenshot won\'t scan.', style: TextStyle(color: p.muted, fontSize: 12)),
            const SizedBox(height: 8),
          ]);
        },
      ),
    ]);
  }
}
