import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/router/app_router.dart' show safeRedirectTarget;
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/auth/auth_scaffold.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Sign in / create account (2026): dark pitch cover with logo, close and a
/// title that follows the mode (and names what's behind a gated link), then
/// the form card on the cover's edge — pill segmented switch, filled inputs
/// with icons, show-password, soft error box, ink pill with spinner — and a
/// "New to SportPadi? Create an account" line under it.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _isSignUp = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  bool _prefilled = false;

  /// Coming back from "Forgot password" by address (not by pop) carries the
  /// email in `?email=` — put it in the form.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final email = GoRouterState.of(context).uri.queryParameters['email'];
    if (email != null && email.isNotEmpty) _email.text = email;
  }

  /// Forgot password: take what's typed along, and bring the address back.
  Future<void> _forgotPassword() async {
    final typed = _email.text.trim();
    final back = await context.push<String>(Uri(
      path: '/forgot-password',
      queryParameters: typed.isEmpty ? null : {'email': typed},
    ).toString());
    if (!mounted || back == null || back.isEmpty) return;
    setState(() {
      _email.text = back;
      _password.clear();
      _error = null;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ctrl = ref.read(authControllerProvider.notifier);
      if (_isSignUp) {
        await ctrl.signUp(_name.text.trim(), _email.text.trim(), _password.text);
      } else {
        await ctrl.signIn(_email.text.trim(), _password.text);
      }
      if (mounted) _leaveAfterSuccess();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Where to go once signed in. The router's redirect used to be trusted to
  /// do this on its own, and it does when this page was reached with `go`
  /// (cold start on a gated link). But from the guest shell this page is
  /// PUSHED on top of Home, and go_router evaluates its redirect against
  /// the underlying location — Home — which is fine for a signed-in user, so
  /// nothing moved and the form just sat there after a successful sign-in.
  /// So: leave explicitly, and leave LATE. The session change also fires the
  /// router's refresh, which re-parses the current stack — sign-in page
  /// included — and re-applies it when that parse resolves. Navigating in
  /// the same tick as the sign-in call races that re-apply, and loses: the
  /// stale stack lands after our pop and the form is back. Waiting for the
  /// next frame puts us after every pending parse, so what we set is what
  /// stays. And `go`, not `pop`: it replaces the whole stack with Home (the
  /// gate renders it as the member shell), so nothing is left to reappear;
  /// the gated destination, if any, goes on top of that.
  void _leaveAfterSuccess() {
    final target = safeRedirectTarget(
        GoRouterState.of(context).uri.queryParameters['redirect']);
    final router = GoRouter.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      router.go('/home');
      if (target != null) router.push(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Arrived here because something they tapped needs an account? Say so —
    // a sign-in page that appears out of nowhere reads as a wall; one that
    // explains itself reads as a door.
    final wanted = GoRouterState.of(context).uri.queryParameters['redirect'];
    final gated = wanted != null && wanted.isNotEmpty;
    final up = _isSignUp;

    return AuthScaffold(
      eyebrow: gated ? 'Account needed' : (up ? 'Join free' : 'Welcome back'),
      title: up ? 'Create your account' : 'Sign in to play',
      subtitle: Text(gated
          ? _gateLine(wanted, signUp: up)
          : up
              ? 'One account for every sport you play — games, groups, tickets and your record.'
              : 'Your games, groups and record, right where you left them.'),
      // Pushed from the guest shell → pop back to it; sent here by the
      // router (a gated link) → there's nothing underneath, so go Home.
      onClose: () => context.canPop() ? context.pop() : context.go('/home'),
      card: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: cardShadow(context),
        ),
        child: AutofillGroup(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SpSegmented(
                  options: const ['Sign in', 'Create account'],
                  index: up ? 1 : 0,
                  onChanged: (i) => _setMode(i == 1),
                ),
                const SizedBox(height: 18),
                if (up) ...[
                  TextFormField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    decoration: authInput(context,
                        label: 'Your name', icon: Icons.person_outline_rounded),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter your name'
                        : null,
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email],
                  decoration: authInput(context,
                      label: 'Email', icon: Icons.mail_outline_rounded),
                  validator: (v) => (v == null || !v.contains('@'))
                      ? 'Enter a valid email'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: !_showPassword,
                  textInputAction: TextInputAction.done,
                  autofillHints: [
                    up ? AutofillHints.newPassword : AutofillHints.password
                  ],
                  onFieldSubmitted: (_) => _submit(),
                  decoration: authInput(
                    context,
                    label: 'Password',
                    icon: Icons.lock_outline_rounded,
                    suffix: IconButton(
                      tooltip: _showPassword ? 'Hide password' : 'Show password',
                      icon: Icon(
                          _showPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                          color: p.muted),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 8)
                      ? 'At least 8 characters'
                      : null,
                ),
                if (up) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text('At least 8 characters.',
                        style: TextStyle(color: p.muted, fontSize: 12)),
                  ),
                ] else
                  Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _busy ? null : _forgotPassword,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 8, 4, 2),
                        child: Text('Forgot password?',
                            style: TextStyle(
                                color: p.greenText,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  AuthError(_error!),
                ],
                const SizedBox(height: 18),
                AuthPrimaryButton(
                  label: up ? 'Create account' : 'Sign in',
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
        Center(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(up ? 'Already have an account? ' : 'New to SportPadi? ',
                  style: TextStyle(color: p.muted, fontSize: 13.5)),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _setMode(!up),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Text(up ? 'Sign in' : 'Create an account',
                      style: TextStyle(
                          color: p.greenText,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'By continuing you agree to our Terms and Privacy Policy.',
          textAlign: TextAlign.center,
          style: TextStyle(color: p.muted, fontSize: 11.5),
        ),
      ],
    );
  }

  void _setMode(bool signUp) => setState(() {
        _isSignUp = signUp;
        _error = null;
      });
}

/// One line naming what's behind the door, from the path they were sent from.
String _gateLine(String raw, {bool signUp = false}) {
  final lead = signUp ? 'Create an account' : 'Sign in';
  final path = Uri.tryParse(Uri.decodeComponent(raw))?.path ?? '';
  if (path.startsWith('/events/')) return '$lead to open this event.';
  if (path.startsWith('/tournaments/')) return '$lead to open this tournament.';
  if (path.startsWith('/groups/')) return '$lead to open this group.';
  if (path.startsWith('/teams/')) return '$lead to open this team.';
  if (path.startsWith('/players/')) return '$lead to view this player.';
  return '$lead to continue.';
}
