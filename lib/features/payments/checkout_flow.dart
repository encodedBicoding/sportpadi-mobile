import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// Open the provider's hosted checkout in the browser, then wait for the user
/// to come back and confirm. Returns true when they tapped "I've paid".
Future<bool> runHostedCheckout(BuildContext context, String url) async {
  final ok =
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.wallet_couldNotOpenThePayment)));
    }
    return false;
  }
  if (!context.mounted) return false;
  final done = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.wallet_completePayment),
      content: Text(
          l10n.wallet_finishThePaymentInYour),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.wallet_cancel)),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.wallet_ivePaid)),
      ],
    ),
  );
  return done == true;
}
