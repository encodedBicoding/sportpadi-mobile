import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/env/sso_config.dart';
import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/auth/social_sign_in.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';

/// "Continue with Google / Apple" — a row of outline pills above the email
/// form. Google everywhere the build has a client id; Apple on iOS only.
/// Nothing drawn when neither applies, so the form sits where it always did.
class SocialSignInRow extends ConsumerStatefulWidget {
  const SocialSignInRow({
    super.key,
    required this.onSuccess,
    required this.onError,
    this.enabled = true,
  });

  /// Called after the session is live (the caller leaves the page).
  final VoidCallback onSuccess;

  /// A message for the form's error box (never for a cancelled sheet).
  final ValueChanged<String> onError;
  final bool enabled;

  static bool get hasAny => SsoConfig.googleEnabled || SsoConfig.appleEnabled;

  @override
  ConsumerState<SocialSignInRow> createState() => _SocialSignInRowState();
}

class _SocialSignInRowState extends ConsumerState<SocialSignInRow> {
  String? _busy;

  Future<void> _go(String provider) async {
    if (_busy != null) return;
    setState(() => _busy = provider);
    try {
      final ctrl = ref.read(authControllerProvider.notifier);
      if (provider == 'apple') {
        await ctrl.signInWithApple();
      } else {
        await ctrl.signInWithGoogle();
      }
      if (mounted) widget.onSuccess();
    } on SocialSignInCancelled {
      // They closed the sheet — nothing to say.
    } on ApiException catch (e) {
      widget.onError(e.message);
    } catch (_) {
      widget.onError('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final google = SsoConfig.googleEnabled;
    final apple = SsoConfig.appleEnabled;
    if (!google && !apple) return const SizedBox.shrink();
    final buttons = <Widget>[
      if (apple)
        _SocialPill(
          label: 'Apple',
          icon: const Icon(Icons.apple, size: 20),
          busy: _busy == 'apple',
          onTap: widget.enabled && _busy == null ? () => _go('apple') : null,
        ),
      if (google)
        _SocialPill(
          label: 'Google',
          icon: const _GoogleGlyph(),
          busy: _busy == 'google',
          onTap: widget.enabled && _busy == null ? () => _go('google') : null,
        ),
    ];
    return Row(children: [
      for (var i = 0; i < buttons.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(child: buttons[i]),
      ],
    ]);
  }
}

class _SocialPill extends StatelessWidget {
  const _SocialPill({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onTap,
  });
  final String label;
  final Widget icon;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.surface,
      shape: StadiumBorder(side: BorderSide(color: p.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: SizedBox(
          height: 46,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (busy)
              SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: p.muted))
            else
              IconTheme(
                  data: IconThemeData(color: p.ink, size: 18), child: icon),
            const SizedBox(width: 9),
            Text(label,
                style: TextStyle(
                    color: onTap == null && !busy ? p.muted : p.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

/// A bold "G" in the current text colour — a letter, not Google's mark.
class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();
  @override
  Widget build(BuildContext context) => Text('G',
      style: TextStyle(
          color: IconTheme.of(context).color,
          fontSize: 17,
          height: 1,
          fontWeight: FontWeight.w800));
}

/// "— or with email —" between the SSO row and the form.
class OrWithEmail extends StatelessWidget {
  const OrWithEmail({super.key, this.label = 'OR WITH EMAIL'});
  final String label;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(children: [
      Expanded(child: Divider(color: p.line, height: 1)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(label,
            style: TextStyle(
                color: p.muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1)),
      ),
      Expanded(child: Divider(color: p.line, height: 1)),
    ]);
  }
}
