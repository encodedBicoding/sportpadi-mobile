import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/wards/ward_models.dart';
import 'package:sportpadi_mobile/data/wards/wards_repository.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/auth/auth_scaffold.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';

/// Wards 3 (A11): a ward opens the hand-over link a guardian emailed them
/// (`https://<site>/claim/<token>`) and chooses a password — the account
/// they've been playing on becomes theirs (same user, so every game, stat,
/// team and ticket stays). Public: the token is the credential, so this works
/// signed out. On success it signs them straight in.
class ClaimAccountScreen extends ConsumerWidget {
  const ClaimAccountScreen({super.key, required this.token});
  final String token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(claimInfoProvider(token));
    void close() => context.canPop() ? context.pop() : context.go('/home');
    return info.when(
      loading: () => AuthScaffold(
        eyebrow: 'Your account',
        title: 'Opening your link…',
        onClose: close,
        card: const _Card(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ),
      error: (e, _) => AuthScaffold(
        eyebrow: 'Your account',
        title: "Couldn't open this link",
        subtitle: Text('$e'),
        onClose: close,
        card: _Card(
          child: AuthPrimaryButton(
            label: 'Try again',
            onTap: () => ref.invalidate(claimInfoProvider(token)),
          ),
        ),
      ),
      data: (i) => i.isReady
          ? _ClaimForm(token: token, info: i, onClose: close)
          : _DeadLink(state: i.state, onClose: close),
    );
  }
}

/// The white card the auth screens put their content on.
class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: cardShadow(context),
      ),
      child: child,
    );
  }
}

/// Expired, already used, or not a link we know.
class _DeadLink extends StatelessWidget {
  const _DeadLink({required this.state, required this.onClose});
  final String state;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (title, body, icon) = switch (state) {
      'expired' => (
          'This link has expired',
          'Hand-over links last 7 days. Ask your guardian to send you a new '
              'one from your page in their SportPadi app.',
          Icons.timer_off_outlined,
        ),
      'used' => (
          'This account is already yours',
          'The link has been used, so the account is already set up. Sign in '
              'with your email and the password you chose.',
          Icons.verified_user_outlined,
        ),
      _ => (
          "This link doesn't work",
          "It may have been replaced by a newer one, or cancelled. Check your "
              'email for the latest link, or ask your guardian to send it '
              'again.',
          Icons.link_off_rounded,
        ),
    };
    return AuthScaffold(
      eyebrow: 'Your account',
      title: title,
      onClose: onClose,
      card: _Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: p.surface2,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 20, color: p.muted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(body,
                  style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.45)),
            ),
          ]),
          const SizedBox(height: 18),
          AuthPrimaryButton(
            label: state == 'used' ? 'Sign in' : 'Go to SportPadi',
            onTap: () => context.go(state == 'used' ? '/sign-in' : '/home'),
          ),
        ]),
      ),
    );
  }
}

class _ClaimForm extends ConsumerStatefulWidget {
  const _ClaimForm(
      {required this.token, required this.info, required this.onClose});
  final String token;
  final ClaimInfo info;
  final VoidCallback onClose;

  @override
  ConsumerState<_ClaimForm> createState() => _ClaimFormState();
}

class _ClaimFormState extends ConsumerState<_ClaimForm> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _show = false;
  bool _busy = false;
  String? _error;

  /// Set when the account was set up on a phone signed in as someone else:
  /// we don't swap their session, we say where to sign in instead.
  String? _readyEmail;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  int get _min => widget.info.minPasswordLength;

  /// POST the password. Null (with [_error] set) when it didn't go through.
  Future<({String email, bool supervised})?> _complete() async {
    try {
      return await ref
          .read(wardsRepositoryProvider)
          .completeClaim(widget.token, _password.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await _complete();
    if (!mounted) return;
    if (res == null) {
      setState(() => _busy = false);
      return;
    }
    final email = res.email.isNotEmpty ? res.email : (widget.info.email ?? '');
    // Someone is already signed in on this phone (often the guardian who
    // sent the link): leave their session alone.
    final signedIn =
        ref.read(authControllerProvider).valueOrNull?.isAuthenticated ?? false;
    if (signedIn) {
      setState(() {
        _busy = false;
        _readyEmail = email;
      });
      return;
    }
    try {
      await ref
          .read(authControllerProvider.notifier)
          .signIn(email, _password.text);
      if (!mounted) return;
      // Leave on the next frame, after the router's auth refresh (same
      // reasoning as the sign-in screen).
      final router = GoRouter.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) => router.go('/home'));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account ready — sign in')));
      context.go(Uri(
        path: '/sign-in',
        queryParameters: email.isEmpty ? null : {'email': email},
      ).toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final i = widget.info;
    final name = i.firstName;
    final ready = _readyEmail;
    if (ready != null) {
      return AuthScaffold(
        eyebrow: 'All set',
        title: name == null ? 'The account is ready' : "$name's account is ready",
        onClose: widget.onClose,
        card: _Card(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              "You're signed in as someone else on this phone, so we haven't "
              'switched accounts. Sign in with $ready and the new password on '
              'the phone ${name ?? 'they'} will use.',
              style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.45),
            ),
            const SizedBox(height: 18),
            AuthPrimaryButton(
                label: 'Done', onTap: () => context.go('/home')),
          ]),
        ),
      );
    }
    final until = formatYmd(i.supervisedUntil);
    final guardian = i.guardianName ?? 'your guardian';
    return AuthScaffold(
      eyebrow: 'Your own account',
      title: name == null ? 'Choose a password' : 'Welcome, $name',
      subtitle: const Text(
          'Choose a password to start using your account. Everything stays — '
          'your games, stats, badges, teams and tickets.'),
      onClose: widget.onClose,
      card: _Card(
        child: AutofillGroup(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InputDecorator(
                  decoration: authInput(context,
                      label: 'Email', icon: Icons.mail_outline_rounded),
                  child: Text(i.email ?? '',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: !_show,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: authInput(
                    context,
                    label: 'New password',
                    icon: Icons.lock_outline_rounded,
                    suffix: IconButton(
                      tooltip: _show ? 'Hide password' : 'Show password',
                      icon: Icon(
                          _show
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                          color: p.muted),
                      onPressed: () => setState(() => _show = !_show),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < _min)
                      ? 'At least $_min characters'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirm,
                  obscureText: !_show,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  onFieldSubmitted: (_) => _submit(),
                  decoration: authInput(context,
                      label: 'Confirm password',
                      icon: Icons.lock_outline_rounded),
                  validator: (v) =>
                      v != _password.text ? "The passwords don't match" : null,
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text('At least $_min characters.',
                      style: TextStyle(color: p.muted, fontSize: 12)),
                ),
                if (i.supervised) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: p.wardTint,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.supervisor_account_rounded,
                              size: 18, color: p.wardInk),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${until.isEmpty ? 'Until you turn 18' : 'Until $until'}, '
                              '$guardian stays on as your supervising '
                              "guardian — they'll still hear from your "
                              'coaches and group admins about you, but '
                              "can't use your account.",
                              style: TextStyle(
                                  color: p.wardInk,
                                  fontSize: 12.5,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ]),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  AuthError(_error!),
                ],
                const SizedBox(height: 18),
                AuthPrimaryButton(
                  label: 'Set password and sign in',
                  busy: _busy,
                  onTap: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
      footer: [
        const SizedBox(height: 18),
        Text(
          'By continuing you agree to our Terms and Privacy Policy.',
          textAlign: TextAlign.center,
          style: TextStyle(color: p.muted, fontSize: 11.5),
        ),
      ],
    );
  }
}
