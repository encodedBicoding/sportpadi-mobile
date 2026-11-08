import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/data/billing/iap_repository.dart';
import 'package:sportpadi_mobile/data/wallet/wallet_repository.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// "Not on this group's plan" — the one dialog every locked create entry
/// point shows (the Tournaments tab's New card, each mode screen's New …).
/// iOS offers the plans screen (in-app purchase); elsewhere it nudges the
/// owner by email (server-throttled) and just explains.
void showPlanLockedDialog(
  BuildContext context,
  WidgetRef ref,
  String groupId, {
  required String title,
  required String body,
  String topic = 'tournaments',
}) {
  final canBuyInApp = IapRepository.supportedPlatform;
  if (!canBuyInApp) {
    ref.read(walletRepositoryProvider).requestPlanEmail(groupId, topic: topic);
  }
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(canBuyInApp ? context.l10n.group_notNow : 'OK'),
        ),
        if (canBuyInApp)
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.push('/groups/$groupId/plan');
            },
            child: Text(context.l10n.group_seePlans),
          ),
      ],
    ),
  );
}
