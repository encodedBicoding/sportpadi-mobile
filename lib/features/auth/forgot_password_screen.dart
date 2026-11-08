import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/auth/auth_repository.dart';
import 'package:sportpadi_mobile/features/auth/auth_scaffold.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// Forgot password — the app's twin of web /auth/forgot, in the 2026 auth
/// frame. Step one asks for the email; step two says the link is on its way
/// and what to do with it. The reset itself finishes on the web page the link
/// opens (/auth/reset — kept out of the Universal / App Link manifests on
/// purpose), then the player comes back here and signs in. Going back hands
/// the email to the sign-in form so they don't type it twice.
///
/// The server answers the same whether or not an account exists, so the copy
/// never says one does.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.email});

  /// Pre-filled from whatever was typed on the sign-in form.
  final String? email;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email ?? '');
  bool _busy = false;
  String? _error;
  String? _sentTo;
  int _cooldown = 0;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    _email.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _ticker?.cancel();
    setState(() => _cooldown = 30);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown = _cooldown - 1);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _send({bool resend = false}) async {
    if (!resend && !(_form.currentState?.validate() ?? false)) return;
    final email = resend ? (_sentTo ?? '') : _email.text.trim();
    if (email.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).requestPasswordReset(email);
      if (!mounted) return;
      setState(() => _sentTo = email);
      _startCooldown();
      if (resend) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.auth_aNewLinkIsOn)));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = l10n.auth_couldntSendTheLinkTry);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Back to sign-in, carrying the email along.
  void _back() {
    final email = _sentTo ?? _email.text.trim();
    if (context.canPop()) {
      context.pop(email);
    } else {
      context.go(email.isEmpty
          ? '/sign-in'
          : Uri(path: '/sign-in', queryParameters: {'email': email})
              .toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sent = _sentTo != null;
    return AuthScaffold(
      eyebrow: sent ? context.l10n.auth_checkYourInbox : context.l10n.auth_forgotPassword,
      title: sent ? context.l10n.auth_yourLinkIsOnIts : context.l10n.auth_resetYourPassword,
      subtitle: sent
          ? Text.rich(TextSpan(children: [
              TextSpan(text: context.l10n.auth_ifAnAccountExistsFor),
              TextSpan(
                  text: _sentTo,
                  style:
                      TextStyle(color: p.onHero, fontWeight: FontWeight.w700)),
              TextSpan(
                  text: context.l10n.auth_weveEmailedItALink),
            ]))
          : Text(
              context.l10n.auth_enterTheEmailYouSigned),
      onClose: _back,
      card: Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: cardShadow(context),
        ),
        child: sent ? _sentCard(p) : _formCard(p),
      ),
      footer: [
        const SizedBox(height: 14),
        Center(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _back,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.arrow_back_rounded, size: 16, color: p.greenText),
                const SizedBox(width: 6),
                Text(context.l10n.auth_backToSignIn,
                    style: TextStyle(
                        color: p.greenText,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _formCard(AppPalette p) => Form(
        key: _form,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SpIconTile(Icons.lock_reset_rounded,
                bg: p.accentTint, fg: p.greenText, size: 40, iconSize: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(context.l10n.auth_whereShouldWeSendIt,
                  style: TextStyle(
                      color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 16),
          TextFormField(
            controller: _email,
            autofocus: _email.text.isEmpty,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.send,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            onFieldSubmitted: (_) => _send(),
            decoration: authInput(context,
                label: context.l10n.auth_email, icon: Icons.mail_outline_rounded),
            validator: (v) =>
                (v == null || !v.contains('@')) ? context.l10n.auth_enterAValidEmail : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            AuthError(_error!),
          ],
          const SizedBox(height: 18),
          AuthPrimaryButton(
            label: context.l10n.auth_sendResetLink,
            busy: _busy,
            onTap: _send,
          ),
        ]),
      );

  Widget _sentCard(AppPalette p) {
    Widget step(int n, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration:
                  BoxDecoration(color: p.accentTint, shape: BoxShape.circle),
              child: Text('$n',
                  style: TextStyle(
                      color: p.greenText,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(text,
                    style: TextStyle(color: p.ink, fontSize: 14, height: 1.35)),
              ),
            ),
          ]),
        );
    final canResend = !_busy && _cooldown <= 0;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        SpIconTile(Icons.mark_email_read_outlined,
            bg: p.accentTint, fg: p.greenText, size: 40, iconSize: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(context.l10n.auth_whatToDoNext,
              style: TextStyle(
                  color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      ]),
      const SizedBox(height: 16),
      step(1, context.l10n.auth_openTheEmailFromSportPadi),
      step(2,
          context.l10n.auth_tapSetANewPassword),
      step(3, context.l10n.auth_comeBackHereAndSign),
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
            context.l10n.auth_theLinkWorksForAn,
            style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4)),
      ),
      if (_error != null) ...[
        AuthError(_error!),
        const SizedBox(height: 14),
      ],
      AuthPrimaryButton(label: context.l10n.auth_backToSignIn, onTap: _back),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: _softPill(
            p,
            icon: Icons.refresh_rounded,
            label: _busy
                ? context.l10n.auth_sending
                : _cooldown > 0
                    ? context.l10n.auth_resendInS(_cooldown)
                    : context.l10n.auth_resendLink,
            onTap: canResend ? () => _send(resend: true) : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _softPill(
            p,
            icon: Icons.alternate_email_rounded,
            label: context.l10n.auth_otherEmail,
            onTap: _busy
                ? null
                : () => setState(() {
                      _sentTo = null;
                      _error = null;
                    }),
          ),
        ),
      ]),
    ]);
  }

  Widget _softPill(AppPalette p,
      {required IconData icon,
      required String label,
      required VoidCallback? onTap}) {
    final fg = onTap == null ? p.muted : p.ink;
    return Material(
      color: p.surface2,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: fg, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}
