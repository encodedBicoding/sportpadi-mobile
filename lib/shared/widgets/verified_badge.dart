import 'package:flutter/material.dart';

/// Gold used for the group verification badge (web: VERIFIED_GOLD).
const kVerifiedGold = Color(0xFFF0A500);

/// True when a group's `verificationBadge` value means "verified" — anything
/// but "none" (booleans accepted for older payloads).
bool isVerifiedBadge(Object? v) =>
    v is bool ? v : (v is String && v.isNotEmpty && v != 'none');

/// The group verification badge — one level only, gold. The scalloped
/// "badge-check" shape with a white check, drawn so it matches the web and
/// the store images exactly. Verification is about authenticity, not plan:
/// only the platform owner sets it.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 18});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Verified by SportPadi',
      child: Semantics(
        label: 'Verified',
        child: CustomPaint(
          size: Size.square(size),
          painter: _BadgePainter(),
        ),
      ),
    );
  }
}

class _BadgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    const r = Radius.circular(4);
    final badge = Path()
      ..moveTo(3.85, 8.62)
      ..arcToPoint(const Offset(8.63, 3.85), radius: r)
      ..arcToPoint(const Offset(15.37, 3.85), radius: r)
      ..arcToPoint(const Offset(20.15, 8.63), radius: r)
      ..arcToPoint(const Offset(20.15, 15.37), radius: r)
      ..arcToPoint(const Offset(15.38, 20.15), radius: r)
      ..arcToPoint(const Offset(8.63, 20.15), radius: r)
      ..arcToPoint(const Offset(3.85, 15.38), radius: r)
      ..arcToPoint(const Offset(3.85, 8.62), radius: r)
      ..close();
    canvas.drawPath(badge, Paint()..color = kVerifiedGold);
    canvas.drawPath(
      badge,
      Paint()
        ..color = kVerifiedGold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
    final check = Path()
      ..moveTo(9, 12)
      ..lineTo(11, 14)
      ..lineTo(15, 10);
    canvas.drawPath(
      check,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
