import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.height = 26});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/sportpadi-logo.png',
      height: height,
      fit: BoxFit.contain,
    );
  }
}
