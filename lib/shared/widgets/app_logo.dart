import 'package:flutter/material.dart';

/// The SportPadi wordmark. The light-mode file has dark "sport" lettering,
/// which disappears on a dark background — dark mode uses the variant with
/// light lettering (green/orange mark and "padi" unchanged).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.height = 26});
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      dark ? 'assets/images/sportpadi-logo-dark.png' : 'assets/images/sportpadi-logo.png',
      height: height,
      fit: BoxFit.contain,
    );
  }
}
