import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/highlights/highlight_models.dart';
import 'package:sportpadi_mobile/data/highlights/highlights_repository.dart';
import 'package:sportpadi_mobile/data/wards/wards_repository.dart'
    show myWardsProvider;
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';

/// "⚽ Goal · 23'" — what the subject did, and when in the match.
String highlightStatLabel(HighlightStat s) {
  final sb = StringBuffer();
  if (s.icon != null) sb.write('${s.icon} ');
  sb.write(s.label);
  if (s.minute != null) sb.write(" · ${s.minute}'");
  return sb.toString();
}

/// The stat picker: my recent stats — and, for a guardian, each ward's —
/// that can take a highlight. Returns the chosen entry, or null when the
/// sheet was closed.
///
/// An entry that already has a highlight is shown as taken and can't be
/// picked — except the one [currentHighlightId] itself is linked to, which
/// is marked as the current link.
Future<LinkableStat?> showHighlightStatPicker(BuildContext context,
    {String? currentHighlightId}) {
  return showSpSheet<LinkableStat>(
    context,
    scrollable: false,
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
    builder: (_) => _StatPicker(currentHighlightId: currentHighlightId),
  );
}

class _StatPicker extends ConsumerStatefulWidget {
  const _StatPicker({this.currentHighlightId});
  final String? currentHighlightId;

  @override
  ConsumerState<_StatPicker> createState() => _StatPickerState();
}

class _StatPickerState extends ConsumerState<_StatPicker> {
  /// Whose stats are listed: null = mine, else a ward's user id.
  String? _wardId;

  final List<LinkableStat> _items = [];
  String? _cursor;
  bool _end = false;
  bool _loading = false;
  String? _error;
  // Bumped when the person changes, so a page still in flight is dropped.
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    if (!reset && _end) return;
    final gen = reset ? ++_gen : _gen;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _cursor = null;
        _end = false;
      }
    });
    final me = ref.read(authControllerProvider).valueOrNull?.user?.id;
    final forUserId = _wardId ?? me;
    var cursor = reset ? null : _cursor;
    final fresh = <LinkableStat>[];
    var end = false;
    String? error;
    try {
      // A short or empty page isn't the end while there is a cursor.
      for (var hops = 0; hops < 5; hops++) {
        final page = await ref
            .read(highlightsRepositoryProvider)
            .linkable(forUserId: forUserId, cursor: cursor);
        if (!mounted || gen != _gen) return;
        fresh.addAll(page.items);
        cursor = page.nextCursor;
        if (cursor == null) {
          end = true;
          break;
        }
        if (fresh.isNotEmpty) break;
      }
    } catch (e) {
      if (!mounted || gen != _gen) return;
      // A cursor the server can no longer open ([isRefusedCursor]): start the
      // list again from the top rather than offer a Retry that sends it back.
      // A reset sends no cursor, so this cannot come round again by itself.
      if (!reset && isRefusedCursor(e, cursor)) {
        setState(() => _loading = false);
        _load(reset: true);
        return;
      }
      error = '$e';
    }
    final failed = error;
    final nextCursor = cursor;
    final reachedEnd = end;
    setState(() {
      _items.addAll(fresh);
      if (failed == null) {
        _cursor = nextCursor;
        _end = reachedEnd;
      }
      _error = failed;
      _loading = false;
    });
  }

  void _pickPerson(String? wardId) {
    if (wardId == _wardId) return;
    setState(() => _wardId = wardId);
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    // Guardians: the wards they may post about (nothing for everyone else).
    final wards = ref.watch(myWardsProvider).valueOrNull?.wards ?? const [];
    final height = MediaQuery.sizeOf(context).height * 0.62;

    Widget person(String label, String? wardId) {
      final active = _wardId == wardId;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: active ? p.hero : p.surface,
          shape: StadiumBorder(
              side: active ? BorderSide.none : BorderSide(color: p.line)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => _pickPerson(wardId),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(label,
                  style: TextStyle(
                      color: active ? p.onHero : p.ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      );
    }

    Widget list() {
      if (_items.isEmpty) {
        if (_loading) return const Center(child: CircularProgressIndicator());
        final error = _error;
        if (error != null) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(error,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.muted, fontSize: 13)),
              const SizedBox(height: 8),
              TextButton(
                  onPressed: () => _load(reset: true),
                  child: Text(l.common_retry)),
            ]),
          );
        }
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                  _end
                      ? l.highlights_noStatsYet
                      : l.highlights_noStatsFoundSoFar,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: p.muted, fontSize: 13, height: 1.45)),
              if (!_end) ...[
                const SizedBox(height: 8),
                TextButton(
                    onPressed: _load, child: Text(l.highlights_keepLooking)),
              ],
            ]),
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: _items.length + (_end ? 0 : 1),
        itemBuilder: (context, i) {
          if (i == _items.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Center(
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : TextButton(
                        onPressed: _load,
                        child: Text(_error ?? l.profile_showMore)),
              ),
            );
          }
          final e = _items[i];
          final current = e.highlightId != null &&
              e.highlightId == widget.currentHighlightId;
          final taken = e.taken && !current;
          final where = [
            if (e.stat.eventTitle != null) e.stat.eventTitle!,
            if (e.stat.eventDate != null) formatYmd(e.stat.eventDate),
          ].join(' · ');
          return Opacity(
            opacity: taken ? 0.55 : 1,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(highlightStatLabel(e.stat),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
              subtitle: where.isEmpty
                  ? null
                  : Text(where,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontSize: 12.5)),
              trailing: current
                  ? Icon(Icons.check_circle_rounded, color: p.greenText)
                  : taken
                      ? Text(
                          e.highlightIsMine
                              ? l.highlights_statTakenByYou
                              : l.highlights_statTaken,
                          style: TextStyle(
                              color: p.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600))
                      : Icon(Icons.chevron_right_rounded, color: p.muted),
              // Taken: the server would refuse it — don't offer it.
              onTap: taken || current
                  ? null
                  : () => Navigator.of(context).pop(e),
            ),
          );
        },
      );
    }

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpSheetHeader(
            icon: Icons.add_link_rounded,
            title: l.highlights_pickStatTitle,
            subtitle: l.highlights_pickStatSubtitle,
          ),
          if (wards.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  person(l.highlights_myStats, null),
                  for (final w in wards) person(w.displayName, w.userId),
                ],
              ),
            ),
          Expanded(child: list()),
        ],
      ),
    );
  }
}
