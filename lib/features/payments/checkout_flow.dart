import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Open the provider's hosted checkout in the browser, then wait for the user
/// to come back and confirm. Returns true when they tapped "I've paid".
Future<bool> runHostedCheckout(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url),
      mode: LaunchMode.externalApplication);
  if (!ok) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the payment page.')));
    }
    return false;
  }
  if (!context.mounted) return false;
  final done = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Complete payment'),
      content: const Text(
          'Finish the payment in your browser, then come back here.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("I've paid")),
      ],
    ),
  );
  return done == true;
}
