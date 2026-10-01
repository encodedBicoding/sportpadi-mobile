import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';

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

/// The badge, tappable: opens a short sheet on what it means — SportPadi's
/// stamp that the group is genuine and authentic (web: VerifiedBadgeButton).
class VerifiedBadgeButton extends StatelessWidget {
  const VerifiedBadgeButton({super.key, this.size = 20, this.groupName});
  final double size;
  final String? groupName;

  void _explain(BuildContext context) {
    final who = (groupName ?? '').trim().isEmpty ? 'This group' : groupName!.trim();
    showSpSheet<void>(
      context,
      builder: (ctx) {
        final p = ctx.palette;
        Widget point(String t) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.check_rounded, size: 15, color: kVerifiedGold),
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(t,
                        style: TextStyle(color: p.ink, fontSize: 12.5, height: 1.35))),
              ]),
            );
        return Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: kVerifiedGold.withAlpha(38),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const VerifiedBadge(size: 44),
          ),
          const SizedBox(height: 14),
          Text('Verified by SportPadi',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'A stamp of genuineness and authenticity. SportPadi has confirmed that $who is the real group it says it is.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.45),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
                color: p.surface2, borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              point('Given only by SportPadi, after checking the group is who it claims to be.'),
              point("It can't be bought and has nothing to do with the group's plan."),
              point("It's removed if a group stops being genuine."),
            ]),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Got it'),
            ),
          ),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Verified by SportPadi — what this means',
      child: InkResponse(
        onTap: () => _explain(context),
        radius: size,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: ExcludeSemantics(child: VerifiedBadge(size: size)),
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
