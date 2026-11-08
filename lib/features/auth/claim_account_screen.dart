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
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

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
        eyebrow: context.l10n.auth_yourAccount,
        title: context.l10n.auth_openingYourLink,
        onClose: close,
        card: const _Card(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ),
      error: (e, _) => AuthScaffold(
        eyebrow: context.l10n.auth_yourAccount,
        title: context.l10n.auth_couldntOpenThisLink,
        subtitle: Text('$e'),
        onClose: close,
        card: _Card(
          child: AuthPrimaryButton(
            label: context.l10n.auth_tryAgain,
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
          context.l10n.auth_thisLinkHasExpired,
          context.l10n.auth_handOverLinksLast7Days,
          Icons.timer_off_outlined,
        ),
      'used' => (
          context.l10n.auth_thisAccountIsAlreadyYours,
          context.l10n.auth_theLinkHasBeenUsed,
          Icons.verified_user_outlined,
        ),
      _ => (
          context.l10n.auth_thisLinkDoesntWork,
          context.l10n.auth_itMayHaveBeenReplaced,
          Icons.link_off_rounded,
        ),
    };
    return AuthScaffold(
      eyebrow: context.l10n.auth_yourAccount,
      title: title,
      onClose: onClose,
      card: _Card(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                  style:
                      TextStyle(color: p.muted, fontSize: 13.5, height: 1.45)),
            ),
          ]),
          const SizedBox(height: 18),
          AuthPrimaryButton(
            label: state == 'used' ? context.l10n.auth_signIn : context.l10n.auth_goToSportPadi,
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
        setState(() => _error = l10n.auth_somethingWentWrongPleaseTry);
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
          SnackBar(content: Text(l10n.auth_accountReadySignIn)));
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
        eyebrow: context.l10n.auth_allSet,
        title:
            name == null ? context.l10n.auth_theAccountIsReady : context.l10n.auth_sAccountIsReady(name),
        onClose: widget.onClose,
        card: _Card(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              context.l10n.auth_youreSignedInAsSomeone(ready, name ?? 'they'),
              style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.45),
            ),
            const SizedBox(height: 18),
            AuthPrimaryButton(label: context.l10n.auth_done, onTap: () => context.go('/home')),
          ]),
        ),
      );
    }
    final until = formatYmd(i.supervisedUntil);
    final guardian = i.guardianName ?? 'your guardian';
    return AuthScaffold(
      eyebrow: context.l10n.auth_yourOwnAccount,
      title: name == null ? context.l10n.auth_chooseAPassword : context.l10n.auth_welcome(name),
      subtitle: Text(
          context.l10n.auth_chooseAPasswordToStart),
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
                      label: context.l10n.auth_email, icon: Icons.mail_outline_rounded),
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
                    label: context.l10n.auth_newPassword,
                    icon: Icons.lock_outline_rounded,
                    suffix: IconButton(
                      tooltip: _show ? context.l10n.auth_hidePassword : context.l10n.auth_showPassword,
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
                      ? context.l10n.auth_atLeastMinCharacters(_min)
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
                      label: context.l10n.auth_confirmPassword,
                      icon: Icons.lock_outline_rounded),
                  validator: (v) =>
                      v != _password.text ? context.l10n.auth_thePasswordsDontMatch : null,
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(context.l10n.auth_atLeastCharacters(_min),
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
                              context.l10n.auth_staysOnAsYourSupervising(until.isEmpty ? 'Until you turn 18' : 'Until $until', guardian),
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
                  label: context.l10n.auth_setPasswordAndSignIn,
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
          context.l10n.auth_byContinuingYouAgreeTo2,
          textAlign: TextAlign.center,
          style: TextStyle(color: p.muted, fontSize: 11.5),
        ),
      ],
    );
  }
}
