import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/profile/profile_models.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/features/players/player_profile_screen.dart'
    show playerRecordsProvider;
import 'package:sportpadi_mobile/shared/widgets/sheet_scroll.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// My sports (`/profile/sports`) — the sports you play and how you play them
/// (positions, strong foot…), which smart team balancing reads. Moved off the
/// profile page; opened from the profile menu's "Activity & stats".
class MySportsScreen extends ConsumerWidget {
  const MySportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SpHeader(title: 'My sports'),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(sportsSetupProvider.future),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
                children: [
                  Text(
                    'The sports you play and how — positions, strong foot and '
                    'more. Smart team balancing uses these.',
                    style: TextStyle(
                        color: p.muted, fontSize: 13.5, height: 1.45),
                  ),
                  const SizedBox(height: 22),
                  const _SportsSection(),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The compact "+ Add" pill beside the section title.
class _AddPill extends StatelessWidget {
  const _AddPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.surface2,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_rounded, size: 15, color: p.ink),
            const SizedBox(width: 6),
            Text('Add',
                style: TextStyle(
                    color: p.ink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The sports list — the web PlayerSportsStats: my sports with answers, add/
// edit/remove, fields driven by each category's statSchema.
// ---------------------------------------------------------------------------

class _SportsSection extends ConsumerWidget {
  const _SportsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final setup = ref.watch(sportsSetupProvider);
    final data = setup.valueOrNull;
    if (data == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SpSectionTitle('Your sports'),
        const SizedBox(height: 10),
        GlassCard(
          child: Text(
            setup.hasError ? 'Could not load your sports.' : 'Loading…',
            style: TextStyle(color: p.muted, fontSize: 13),
          ),
        ),
      ]);
    }
    final byId = {for (final c in data.categories) c.id: c};
    final mine = data.mine.where((m) => byId.containsKey(m.categoryId)).toList();
    final mineIds = mine.map((m) => m.categoryId).toSet();
    final others =
        data.categories.where((c) => !mineIds.contains(c.id)).toList();

    Future<void> addSport() async {
      // Web's "Add a sport" dialog, as a bottom sheet: pick from the sports
      // you haven't added yet.
      await showSpSheet<void>(
      context,
      framed: false,
      builder: (ctx) => Container(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          decoration: BoxDecoration(
            color: p.bg,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: SheetScrollView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SpGrabber(),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('Add a sport',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 14),
                    child: Text('Pick one you play — you can set it up next.',
                        style: TextStyle(color: p.muted, fontSize: 13)),
                  ),
                  SpListCard(children: [
                    for (final c in others)
                      InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () async {
                          Navigator.pop(ctx);
                          try {
                            await ref
                                .read(profileRepositoryProvider)
                                .upsertSport(c.id, const {});
                            if (context.mounted) {
                              ref
                                ..invalidate(sportsSetupProvider)
                                // Setup pills on My records follow.
                                ..invalidate(playerRecordsProvider);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('$e')));
                            }
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                          child: Row(children: [
                            _EmojiTile(c.emoji),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(c.name,
                                  style: TextStyle(
                                      color: p.ink,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700)),
                            ),
                            SpIconTile(Icons.add_rounded,
                                bg: p.accentTint,
                                fg: p.greenText,
                                size: 32,
                                iconSize: 18),
                          ]),
                        ),
                      ),
                  ]),
                ],
              ),
            ),
          ),
        ),
    );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSectionTitle(
          'Your sports',
          count: mine.isEmpty ? null : mine.length,
          trailing: others.isEmpty
              ? null
              : _AddPill(onTap: addSport),
        ),
        const SizedBox(height: 10),
        if (mine.isEmpty)
          GlassCard(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(children: [
              SpIconTile(Icons.sports_soccer_rounded,
                  bg: p.accentTint, fg: p.greenText, size: 52, iconSize: 24),
              const SizedBox(height: 12),
              Text("You haven't added any sports yet.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.muted, fontSize: 13)),
              const SizedBox(height: 14),
              SpButton(
                label: 'Add a sport',
                icon: Icons.add_rounded,
                onTap: addSport,
              ),
            ]),
          )
        else
          for (final m in mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SportRow(category: byId[m.categoryId]!, mine: m),
            ),
      ],
    );
  }
}

/// A sport's emoji on a quiet rounded tile.
class _EmojiTile extends StatelessWidget {
  const _EmojiTile(this.emoji, {this.size = 40});
  final String? emoji;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.palette.surface2,
          borderRadius: BorderRadius.circular(size * 0.34),
        ),
        child: Text(emoji ?? '🏅', style: TextStyle(fontSize: size * 0.48)),
      );
}

class _SportRow extends ConsumerWidget {
  const _SportRow({required this.category, required this.mine});
  final SportCategory category;
  final MySport mine;

  String _summary(StatField f) {
    final v = mine.answers[f.key];
    if (f.type == 'multi') {
      final arr = v is List ? v : const [];
      return arr.isEmpty ? '—' : arr.join(', ');
    }
    return v is String && v.isNotEmpty ? v : '—';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return GlassCard(
      onTap: () => _edit(context, ref),
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _EmojiTile(category.emoji, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(category.name,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 6),
              if (category.fields.isEmpty)
                Text('Nothing to set up for this sport.',
                    style: TextStyle(color: p.muted, fontSize: 12))
              else
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final f in category.fields)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: p.surface2,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(
                              text: '${f.label} · ',
                              style: TextStyle(color: p.muted)),
                          TextSpan(
                              text: _summary(f),
                              style: TextStyle(
                                  color: p.ink, fontWeight: FontWeight.w700)),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                ]),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SpIconTile(Icons.edit_outlined,
            bg: p.surface2, fg: p.muted, size: 32, iconSize: 15),
      ]),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final saved = await showSpSheet<bool>(
      context,
      framed: false,
      builder: (_) => _SportEditSheet(category: category, mine: mine),
    );
    if (saved == true && context.mounted) {
      ref
        ..invalidate(sportsSetupProvider)
        ..invalidate(playerRecordsProvider);
    }
  }
}

class _SportEditSheet extends ConsumerStatefulWidget {
  const _SportEditSheet({required this.category, required this.mine});
  final SportCategory category;
  final MySport mine;

  @override
  ConsumerState<_SportEditSheet> createState() => _SportEditSheetState();
}

class _SportEditSheetState extends ConsumerState<_SportEditSheet> {
  late final Map<String, dynamic> _draft =
      Map<String, dynamic>.from(widget.mine.answers);
  bool _busy = false;

  void _toggle(StatField f, String option) {
    setState(() {
      if (f.type == 'multi') {
        final list = _draft[f.key] is List
            ? List<String>.from(
                (_draft[f.key] as List).map((x) => '$x'))
            : <String>[];
        if (list.contains(option)) {
          list.remove(option);
        } else {
          if (f.max != null && list.length >= f.max!) return;
          list.add(option);
        }
        _draft[f.key] = list;
      } else {
        _draft[f.key] = _draft[f.key] == option ? '' : option;
      }
    });
  }

  bool _selected(StatField f, String option) {
    final v = _draft[f.key];
    return f.type == 'multi'
        ? v is List && v.contains(option)
        : v == option;
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .upsertSport(widget.category.id, _draft);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .removeSport(widget.category.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = widget.category;
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          const SpGrabber(),
          const SizedBox(height: 16),
          Row(children: [
            _EmojiTile(c.emoji, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Text(c.name,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w800)),
            ),
            InkWell(
              onTap: _busy ? null : _remove,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Text('Remove',
                    style: TextStyle(
                        color: p.danger,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          if (c.fields.isEmpty)
            Text('Nothing to set up for this sport.',
                style: TextStyle(color: p.muted, fontSize: 13))
          else
            for (final f in c.fields) ...[
              Text(
                f.type == 'multi' && f.max != null
                    ? '${f.label} (up to ${f.max})'
                    : f.label,
                style: TextStyle(
                    color: p.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final o in f.options)
                  Material(
                    color: _selected(f, o) ? p.ink : p.surface,
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _toggle(f, o),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: _selected(f, o)
                                  ? p.ink
                                  : p.line),
                        ),
                        child: Text(o,
                            style: TextStyle(
                              color: _selected(f, o)
                                  ? p.bg
                                  : p.ink,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 14),
            ],
          SpButton(
            label: _busy ? 'Saving…' : 'Save',
            expand: true,
            onTap: _busy ? null : _save,
          ),
        ],
      ),
    );
  }
}
