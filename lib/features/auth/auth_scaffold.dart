import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';

const _mint = Color(0xFF6EDC9E);

/// The 2026 auth frame (sign in / create account / verify email): a dark
/// pitch cover with the logo, an optional close button, an eyebrow, a big
/// title and a line under it; the form card overlaps the cover's bottom
/// edge; footer lines sit under the card.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.card,
    this.subtitle,
    this.onClose,
    this.footer = const [],
  });

  final String eyebrow;
  final String title;
  final Widget? subtitle;
  final VoidCallback? onClose;
  final Widget card;
  final List<Widget> footer;

  static const _overlap = 48.0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: p.bg,
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(32)),
            child: CustomPaint(
              painter: _AuthCover(p.hero, p.accentDeep, p.orange),
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, top + 10, 20, _overlap + 34),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 44,
                          child: Row(children: [
                            Image.asset(
                              'assets/images/sportpadi-logo-dark.png',
                              height: 30,
                              fit: BoxFit.contain,
                            ),
                            const Spacer(),
                            if (onClose != null)
                              SpRoundButton(
                                icon: Icons.close_rounded,
                                tooltip: 'Not now',
                                onTap: onClose!,
                              ),
                          ]),
                        ),
                        const SizedBox(height: 34),
                        Text(eyebrow.toUpperCase(),
                            style: const TextStyle(
                                color: _mint,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5)),
                        const SizedBox(height: 8),
                        Text(title,
                            style: TextStyle(
                                color: p.onHero,
                                fontSize: 30,
                                height: 1.1,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.6)),
                        if (subtitle != null) ...[
                          const SizedBox(height: 10),
                          DefaultTextStyle.merge(
                            style: TextStyle(
                                color: p.heroMuted, fontSize: 14, height: 1.45),
                            child: subtitle!,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Card + footer, pulled up over the cover's bottom edge.
          Transform.translate(
            offset: const Offset(0, -_overlap),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [card, ...footer],
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Filled, borderless input used on the auth cards.
InputDecoration authInput(BuildContext context,
    {required String label, IconData? icon, Widget? suffix}) {
  final p = context.palette;
  OutlineInputBorder b(Color c, [double w = 0]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: w == 0 ? BorderSide.none : BorderSide(color: c, width: w),
      );
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: p.surface2,
    prefixIcon: icon == null ? null : Icon(icon, size: 20, color: p.muted),
    suffixIcon: suffix,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: b(p.line),
    enabledBorder: b(p.line),
    focusedBorder: b(p.accent, 1.5),
    errorBorder: b(p.danger, 1.2),
    focusedErrorBorder: b(p.danger, 1.5),
  );
}

/// Soft red box with an icon — form errors on the auth cards.
class AuthError extends StatelessWidget {
  const AuthError(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: p.liveTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline_rounded, size: 18, color: p.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message,
              style: TextStyle(
                  color: p.danger,
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

/// The ink primary pill, with a spinner while [busy].
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onTap != null && !busy;
    return Material(
      color: enabled || busy ? p.ink : p.ink.withAlpha(90),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          height: 54,
          child: Center(
            child: busy
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: p.bg))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.bg,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 18, color: p.bg),
                  ]),
          ),
        ),
      ),
    );
  }
}

class _AuthCover extends CustomPainter {
  _AuthCover(this.base, this.green, this.warm);
  final Color base;
  final Color green;
  final Color warm;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, Color.lerp(base, green, 0.75)!],
        ).createShader(rect),
    );
    canvas.drawCircle(
      Offset(size.width * 1.02, size.height * 0.2),
      size.width * 0.42,
      Paint()..color = warm.withAlpha(40),
    );
    // Pitch markings: halfway line and centre circle, off to the right.
    final line = Paint()
      ..color = const Color(0x1AFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final cx = size.width * 0.78;
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), line);
    canvas.drawCircle(Offset(cx, size.height * 0.55), 58, line);
    canvas.drawCircle(
        Offset(cx, size.height * 0.55), 4, Paint()..color = const Color(0x1AFFFFFF));
  }

  @override
  bool shouldRepaint(covariant _AuthCover old) =>
      old.base != base || old.green != green || old.warm != warm;
}
