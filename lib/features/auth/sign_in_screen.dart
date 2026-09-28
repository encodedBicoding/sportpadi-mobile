import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/router/app_router.dart' show safeRedirectTarget;
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/shared/widgets/app_logo.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

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
  String? _error;

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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Not now',
          icon: const Icon(Icons.close_rounded),
          // Pushed from the guest shell → pop back to it; sent here by the
          // router (a gated link) → there's nothing underneath, so go Home.
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AppLogo(height: 64)),
                  if (gated) ...[
                    const SizedBox(height: 14),
                    Text(
                      _gateLine(wanted),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.muted, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 28),
                  GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SegTabs(
                            isSignUp: _isSignUp,
                            onChanged: (v) => setState(() {
                              _isSignUp = v;
                              _error = null;
                            }),
                          ),
                          const SizedBox(height: 18),
                          if (_isSignUp) ...[
                            TextFormField(
                              controller: _name,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(labelText: 'Name'),
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: 'Email'),
                            validator: (v) =>
                                (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: const InputDecoration(labelText: 'Password'),
                            validator: (v) =>
                                (v == null || v.length < 8) ? 'At least 8 characters' : null,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Text(_error!, style: TextStyle(color: p.danger, fontSize: 13)),
                          ],
                          const SizedBox(height: 18),
                          FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: _busy
                                ? const SizedBox(
                                    height: 20, width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Text(_isSignUp ? 'Create account' : 'Sign in'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'By continuing you agree to our Terms and Privacy Policy.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.muted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One line naming what's behind the door, from the path they were sent from.
String _gateLine(String raw) {
  final path = Uri.tryParse(Uri.decodeComponent(raw))?.path ?? '';
  if (path.startsWith('/events/')) return 'Sign in to open this event.';
  if (path.startsWith('/tournaments/')) return 'Sign in to open this tournament.';
  if (path.startsWith('/groups/')) return 'Sign in to open this group.';
  if (path.startsWith('/teams/')) return 'Sign in to open this team.';
  if (path.startsWith('/players/')) return 'Sign in to view this player.';
  return 'Sign in to continue.';
}

class _SegTabs extends StatelessWidget {
  const _SegTabs({required this.isSignUp, required this.onChanged});
  final bool isSignUp;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        _seg(context, 'Sign in', !isSignUp, () => onChanged(false)),
        _seg(context, 'Sign up', isSignUp, () => onChanged(true)),
      ]),
    );
  }

  Widget _seg(BuildContext context, String label, bool active, VoidCallback onTap) {
    final p = context.palette;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? p.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: active
                ? const [BoxShadow(color: Color.fromRGBO(15, 30, 22, 0.08), blurRadius: 6, offset: Offset(0, 2))]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? p.accent : p.muted,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}
