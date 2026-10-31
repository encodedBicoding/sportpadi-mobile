// XP history: every point gained or lost, newest first, with the reason and
// the game or event it came from — grouped by day. The Home header's XP line
// lands here; "Open progress" goes on to levels and achievements.
// Web twin: app/profile/xp/page.tsx.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/progression/progression_repository.dart';
import 'package:sportpadi_mobile/features/progression/progression_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart' show SpEmpty;
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

class XpHistoryScreen extends ConsumerStatefulWidget {
  const XpHistoryScreen({super.key});
  @override
  ConsumerState<XpHistoryScreen> createState() => _XpHistoryScreenState();
}

class _XpHistoryScreenState extends ConsumerState<XpHistoryScreen> {
  final _items = <XpLedgerItem>[];
  String? _cursor;
  bool _loading = true;
  bool _more = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(progressionRepositoryProvider)
          .ledger(cursor: reset ? null : _cursor);
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _more = page.nextCursor != null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    if (_dayKey(d) == _dayKey(now)) return 'Today';
    if (_dayKey(d) == _dayKey(now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return DateFormat(d.year == now.year ? 'EEE d MMM' : 'EEE d MMM yyyy').format(d);
  }

  static String _fmt(int n) => NumberFormat.decimalPattern().format(n);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final week = ref.watch(yourWeekProvider).valueOrNull;
    // Group by local day, in arrival order (newest first).
    final days = <({String key, String label, List<XpLedgerItem> items})>[];
    for (final it in _items) {
      final d = it.occurredAt.toLocal();
      final k = _dayKey(d);
      if (days.isEmpty || days.last.key != k) {
        days.add((key: k, label: _dayLabel(d), items: <XpLedgerItem>[]));
      }
      days.last.items.add(it);
    }
    Color tone(int n) => n > 0 ? p.accentDeep : n < 0 ? p.amber : p.muted;

    return Scaffold(
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('XP history', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(yourWeekProvider);
          await _load(reset: true);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (week != null)
              GlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  PointsStrip(week: week),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SpButton(
                      label: 'Open progress',
                      icon: Icons.trending_up_rounded,
                      onTap: () => context.push('/progress'),
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 12),
            Text(
              'Every point you earned or lost, and why. Showing up, playing and '
              'stats earn XP; mistakes like an own goal or a missed penalty take '
              'a little back — never more than the game paid.',
              style: TextStyle(color: p.muted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              GlassCard(
                onTap: () => _load(reset: _items.isEmpty),
                child: Text('$_error — tap to retry', style: TextStyle(color: p.danger, fontSize: 13)),
              )
            else if (_loading && _items.isEmpty)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (_items.isEmpty)
              const SpEmpty(
                  icon: Icons.auto_awesome_outlined,
                  title: 'No XP yet',
                  text: 'Check in to a game and it starts here.')
            else ...[
              for (final day in days) ...[
                GlassCard(
                  padding: EdgeInsets.zero,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: p.surface2,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Text(day.label.toUpperCase(),
                              style: TextStyle(
                                  color: p.muted, fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w800)),
                        ),
                        Builder(builder: (_) {
                          final net = day.items.fold(0, (s, i) => s + i.xp);
                          return Text('${net > 0 ? '+' : ''}${_fmt(net)} XP',
                              style: TextStyle(color: tone(net), fontSize: 12.5, fontWeight: FontWeight.w800));
                        }),
                      ]),
                    ),
                    for (var i = 0; i < day.items.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: p.line),
                      _Row(item: day.items[i], tone: tone(day.items[i].xp)),
                    ],
                  ]),
                ),
                const SizedBox(height: 12),
              ],
              if (_more)
                Center(
                  child: TextButton(
                    onPressed: _loading ? null : () => _load(),
                    child: Text(_loading ? 'Loading…' : 'Show earlier'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.tone});
  final XpLedgerItem item;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final it = item;
    final where = [it.eventTitle, it.groupName].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    final time = DateFormat.jm().format(it.occurredAt.toLocal());
    final route = it.gameId != null
        ? '/games/${it.gameId}'
        : it.eventSlug != null
            ? '/events/${it.eventSlug}'
            : null;
    return InkWell(
      onTap: route == null ? null : () => context.push(route),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w600)),
              Text(where.isEmpty ? time : '$time · $where',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 10),
          Text('${it.xp > 0 ? '+' : ''}${NumberFormat.decimalPattern().format(it.xp)}',
              style: TextStyle(
                  color: tone,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }
}
