import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/auth/auth_scaffold.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

const _otpLength = 4;

/// Every account confirms its email before it can use the app — the twin of
/// the web /verify-email page. The router parks a signed-in-but-unverified
/// user here, and the server refuses create/join/buy calls until it's done, so
/// this can't be skipped by closing the screen.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _controllers =
      List.generate(_otpLength, (_) => TextEditingController());
  final _nodes = List.generate(_otpLength, (_) => FocusNode());
  bool _sending = false;
  bool _verifying = false;
  String? _error;
  int _cooldown = 0;
  Timer? _ticker;
  String? _sentFor;

  @override
  void initState() {
    super.initState();
    // Auto-send once, as soon as we know the address.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sendCode());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _email =>
      ref.read(authControllerProvider).value?.user?.email ?? '';

  void _startCooldown() {
    _ticker?.cancel();
    setState(() => _cooldown = 30);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown = _cooldown - 1);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _sendCode({bool manual = false}) async {
    final email = _email;
    if (email.isEmpty || _sending || _cooldown > 0) return;
    if (!manual && _sentFor == email) return;
    _sentFor = email;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).sendVerificationCode();
      if (mounted) {
        _startCooldown();
        if (manual) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('A new code is on the way.')));
        }
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Couldn't send the code. Try again.");
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verify() async {
    final code = _controllers.map((c) => c.text).join();
    if (code.length != _otpLength || _verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).verifyEmail(code);
      // The router redirect picks up the verified session and releases the
      // user into the app — nothing to navigate to here.
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
        for (final c in _controllers) {
          c.clear();
        }
        _nodes.first.requestFocus();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = "That code didn't work. Try again.");
        for (final c in _controllers) {
          c.clear();
        }
        _nodes.first.requestFocus();
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  void _onDigit(int i, String v) {
    if (v.length > 1) {
      // Pasted / autofilled code — spread it across the boxes.
      final digits = v.replaceAll(RegExp(r'\D'), '');
      for (var k = 0; k < _otpLength; k++) {
        _controllers[k].text = k < digits.length ? digits[k] : '';
      }
      _nodes[(digits.length - 1).clamp(0, _otpLength - 1)].requestFocus();
      setState(() {});
      if (digits.length >= _otpLength) _verify();
      return;
    }
    setState(() {});
    if (v.isNotEmpty && i < _otpLength - 1) {
      _nodes[i + 1].requestFocus();
    } else if (v.isEmpty && i > 0) {
      _nodes[i - 1].requestFocus();
    }
    if (_controllers.every((c) => c.text.isNotEmpty)) _verify();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final email = ref.watch(authControllerProvider).value?.user?.email ?? '';
    final canResend = !_sending && _cooldown <= 0;
    return AuthScaffold(
      eyebrow: 'One last step',
      title: 'Confirm your email',
      subtitle: Text.rich(
        TextSpan(children: [
          const TextSpan(text: 'We sent a 4-digit code to '),
          TextSpan(
              text: email.isEmpty ? 'your email' : email,
              style: TextStyle(color: p.onHero, fontWeight: FontWeight.w700)),
          const TextSpan(
              text: '. Enter it below to finish setting up your account.'),
        ]),
      ),
      card: Container(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: cardShadow(context),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SpIconTile(Icons.mark_email_unread_outlined,
                bg: p.accentTint, fg: p.greenText, size: 40, iconSize: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Enter your code',
                  style: TextStyle(
                      color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _otpLength; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: SizedBox(
                    width: 60,
                    child: TextField(
                      controller: _controllers[i],
                      focusNode: _nodes[i],
                      autofocus: i == 0,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      textInputAction: i == _otpLength - 1
                          ? TextInputAction.done
                          : TextInputAction.next,
                      autofillHints:
                          i == 0 ? const [AutofillHints.oneTimeCode] : null,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      maxLength: i == 0 ? _otpLength : 1,
                      enabled: !_verifying,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 26,
                          fontWeight: FontWeight.w800),
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: _controllers[i].text.isEmpty
                            ? p.surface2
                            : p.accentTint,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: p.accent, width: 2),
                        ),
                      ),
                      onChanged: (v) => _onDigit(i, v),
                    ),
                  ),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            AuthError(_error!),
          ],
          const SizedBox(height: 18),
          AuthPrimaryButton(
            label: 'Verify email',
            busy: _verifying,
            onTap: _controllers.any((c) => c.text.isEmpty) ? null : _verify,
          ),
          const SizedBox(height: 12),
          Center(
            child: Material(
              color: p.surface2,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: canResend ? () => _sendCode(manual: true) : null,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.refresh_rounded,
                        size: 16, color: canResend ? p.ink : p.muted),
                    const SizedBox(width: 6),
                    Text(
                      _sending
                          ? 'Sending…'
                          : _cooldown > 0
                              ? 'Resend code in ${_cooldown}s'
                              : 'Resend code',
                      style: TextStyle(
                          color: canResend ? p.ink : p.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
      footer: [
        const SizedBox(height: 16),
        Center(
          child: Text("Can't find it? Check spam, or resend in a moment.",
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 12.5)),
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
            child: Text('Use a different account',
                style: TextStyle(
                    color: p.greenText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}
