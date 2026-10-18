import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';

/// Compulsory "balance by attribute" setup (web twin: BalanceSetupGate).
///
/// Sports that balance teams by a role axis — soccer positions, basketball
/// position — need every player's own value, or smart shuffle has nothing to
/// go on for them. The event page blocks until it's saved; the scanner asks
/// right after a QR check-in; and Home shows a card per sport still missing
/// it (`balanceGaps`). One sheet for all three.
///
/// Returns true when the viewer saved, false when nothing was needed or
/// (with [dismissible]) they tapped "Later".
Future<bool> showBalanceSetupIfNeeded(
  BuildContext context,
  WidgetRef ref, {
  String? eventId,
  String? categoryId,
  bool dismissible = false,
}) async {
  final data = await ref
      .read(eventsRepositoryProvider)
      .balanceSetup(eventId: eventId, categoryId: categoryId);
  if (!context.mounted || data == null) return false;
  if (data['required'] != true) return false;
  final field = data['field'];
  final catId = data['categoryId'];
  if (field is! Map || catId is! String || catId.isEmpty) return false;
  return showBalanceSetupSheet(
    context,
    ref,
    categoryId: catId,
    categoryName: (data['categoryName'] as String?) ?? 'this sport',
    label: (field['label'] as String?) ?? 'position',
    options: field['options'] is List
        ? (field['options'] as List).map((x) => x.toString()).toList()
        : const <String>[],
    maxPicks: field['maxPicks'] is int ? field['maxPicks'] as int : 3,
    dismissible: dismissible,
  );
}

Future<bool> showBalanceSetupSheet(
  BuildContext context,
  WidgetRef ref, {
  required String categoryId,
  required String categoryName,
  required String label,
  required List<String> options,
  required int maxPicks,
  bool dismissible = false,
}) async {
  final p = context.palette;
  final picked = <String>{};
  final freeCtrl = TextEditingController();
  var saving = false;
  var saved = false;
  await showSpSheet<void>(
    context,
    isDismissible: dismissible,
    enableDrag: dismissible,
    framed: false,
    builder: (ctx) => PopScope(
      canPop: dismissible,
      child: StatefulBuilder(
        builder: (ctx, setSheet) {
          final canSave = options.isNotEmpty
              ? picked.isNotEmpty
              : freeCtrl.text.trim().isNotEmpty;
          Future<void> doSave() async {
            if (saving || !canSave) return;
            setSheet(() => saving = true);
            try {
              final roles = options.isNotEmpty
                  ? picked.toList()
                  : [freeCtrl.text.trim()];
              await ref
                  .read(eventsRepositoryProvider)
                  .saveBalanceRoles(categoryId, roles);
              saved = true;
              ref.invalidate(balanceGapsProvider);
              if (ctx.mounted) Navigator.of(ctx).pop();
            } catch (e) {
              setSheet(() => saving = false);
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text(e.toString()),
                  behavior: SnackBarBehavior.floating,
                ));
              }
            }
          }

          return Container(
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, 28 + MediaQuery.of(ctx).viewInsets.bottom),
            decoration: BoxDecoration(
              color: Theme.of(ctx).scaffoldBackgroundColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: p.muted.withAlpha(90),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Set your ${label.toLowerCase()} for $categoryName',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    '$categoryName games pick fair teams by spreading players\' '
                    '${label.toLowerCase()} across the sides — so it needs to know yours. '
                    '${maxPicks == 1 ? 'Pick one' : 'Pick up to $maxPicks'}; '
                    'you can change this later from your profile.',
                    style:
                        TextStyle(color: p.muted, fontSize: 13, height: 1.45),
                  ),
                  const SizedBox(height: 14),
                  if (options.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final opt in options)
                          GestureDetector(
                            onTap: () => setSheet(() {
                              if (picked.contains(opt)) {
                                picked.remove(opt);
                              } else if (maxPicks == 1) {
                                picked
                                  ..clear()
                                  ..add(opt);
                              } else if (picked.length < maxPicks) {
                                picked.add(opt);
                              }
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: picked.contains(opt)
                                    ? p.accent.withAlpha(36)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                  color: picked.contains(opt)
                                      ? p.accent
                                      : p.muted.withAlpha(80),
                                ),
                              ),
                              child: Text(
                                opt,
                                style: TextStyle(
                                  color: picked.contains(opt)
                                      ? p.accent
                                      : p.muted,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    )
                  else
                    TextField(
                      controller: freeCtrl,
                      onChanged: (_) => setSheet(() {}),
                      maxLength: 60,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: 'Your ${label.toLowerCase()}',
                        counterText: '',
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48)),
                    onPressed: canSave && !saving ? doSave : null,
                    child: Text(saving ? 'Saving…' : 'Save & continue'),
                  ),
                  if (dismissible)
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text('Later', style: TextStyle(color: p.muted)),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
  freeCtrl.dispose();
  return saved;
}
