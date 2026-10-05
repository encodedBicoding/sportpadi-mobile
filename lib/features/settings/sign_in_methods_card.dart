import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/env/sso_config.dart';
import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/auth/auth_models.dart';
import 'package:sportpadi_mobile/data/auth/auth_repository.dart';
import 'package:sportpadi_mobile/data/auth/social_sign_in.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Settings → Sign-in methods: email + password (set one on an SSO-only
/// account) and Google / Apple links. The last remaining way in can't be
/// removed — the server refuses too.
class SignInMethodsCard extends ConsumerStatefulWidget {
  const SignInMethodsCard({super.key});
  @override
  ConsumerState<SignInMethodsCard> createState() => _SignInMethodsCardState();
}

class _SignInMethodsCardState extends ConsumerState<SignInMethodsCard> {
  SignInMethods? _m;
  String? _busy;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await ref.read(authRepositoryProvider).signInMethods();
      if (mounted) setState(() => _m = m);
    } catch (_) {
      /* leave the card quiet */
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _link(String provider) async {
    setState(() => _busy = provider);
    try {
      final social = ref.read(socialSignInProvider);
      final cred =
          provider == 'apple' ? await social.apple() : await social.google();
      await ref.read(authRepositoryProvider).linkWithIdToken(
            provider: cred.provider,
            idToken: cred.idToken,
            nonce: cred.nonce,
            accessToken: cred.accessToken,
          );
      if (!mounted) return;
      _toast('${_label(provider)} linked.');
      await _load();
    } on SocialSignInCancelled {
      // dismissed
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    } catch (_) {
      if (mounted) _toast('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _unlink(String provider) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${_label(provider)}?'),
        content: Text(
            "You won't be able to sign in with ${_label(provider)} until you link it again."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = provider);
    try {
      await ref.read(authRepositoryProvider).unlinkProvider(provider);
      if (!mounted) return;
      _toast('${_label(provider)} unlinked.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _setPassword() async {
    final ctrl = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set a password'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autofocus: true,
          autofillHints: const [AutofillHints.newPassword],
          decoration:
              const InputDecoration(hintText: 'New password (8+ characters)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (pw == null || !mounted) return;
    if (pw.length < 8) {
      _toast('At least 8 characters.');
      return;
    }
    setState(() => _busy = 'password');
    try {
      await ref.read(authRepositoryProvider).setPassword(pw);
      if (!mounted) return;
      _toast('Password set — you can now sign in with your email too.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  static String _label(String p) => p == 'apple' ? 'Apple' : 'Google';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final m = _m;
    if (_loading || m == null) {
      return GlassCard(
        child: Row(children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: p.muted)),
          const SizedBox(width: 10),
          Text(_loading ? 'Loading…' : "Couldn't load sign-in methods.",
              style: TextStyle(color: p.muted, fontSize: 13)),
        ]),
      );
    }

    // Providers to list: what's linked, plus what this build + server can
    // link (Apple only on iOS; Google only with a client id in the build).
    final canLinkHere = <String>{
      if (SsoConfig.googleEnabled && m.available.contains('google')) 'google',
      if (SsoConfig.appleEnabled && m.available.contains('apple')) 'apple',
    };
    final providers = <String>{...m.linked, ...canLinkHere}.toList()..sort();
    final linkedNames = m.linked.map(_label).join(' / ');

    Widget row({
      required Widget lead,
      required String title,
      required String sub,
      required Widget trail,
    }) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            lead,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    Text(sub,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 12)),
                  ]),
            ),
            const SizedBox(width: 8),
            trail,
          ]),
        );

    Widget small(String label, VoidCallback? onTap, {bool busy = false}) =>
        Material(
          color: p.surface2,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: busy ? null : onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: busy
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: p.muted))
                  : Text(label,
                      style: TextStyle(
                          color: onTap == null ? p.muted : p.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
            ),
          ),
        );

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        row(
          lead: SpIconTile(
              m.hasPassword ? Icons.mail_outline_rounded : Icons.key_rounded,
              size: 36,
              iconSize: 18),
          title: 'Email & password',
          sub: m.hasPassword
              ? m.email
              : 'No password yet — you sign in with ${linkedNames.isEmpty ? 'a linked account' : linkedNames}.',
          trail: m.hasPassword
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: p.accentTint,
                      borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.lock_rounded, size: 12, color: p.greenText),
                    const SizedBox(width: 4),
                    Text('On',
                        style: TextStyle(
                            color: p.greenText,
                            fontSize: 11,
                            fontWeight: FontWeight.w800)),
                  ]),
                )
              : small('Set a password', _busy == null ? _setPassword : null,
                  busy: _busy == 'password'),
        ),
        for (final prov in providers) ...[
          Divider(color: p.surface2, height: 1),
          row(
            lead: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: p.surface2, borderRadius: BorderRadius.circular(12)),
              child: Center(
                child: prov == 'apple'
                    ? Icon(Icons.apple, size: 20, color: p.ink)
                    : Text('G',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
              ),
            ),
            title: _label(prov),
            sub: m.linked.contains(prov)
                ? 'Linked — sign in with one tap.'
                : 'Link to sign in with your ${_label(prov)} account.',
            trail: m.linked.contains(prov)
                ? small(
                    'Unlink',
                    m.lastOne || _busy != null ? null : () => _unlink(prov),
                    busy: _busy == prov,
                  )
                : canLinkHere.contains(prov)
                    ? small('Link', _busy == null ? () => _link(prov) : null,
                        busy: _busy == prov)
                    : const SizedBox.shrink(),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          m.lastOne
              ? "This is your only way to sign in — set a password or link another method before removing it."
              : 'Linking uses the email on that account; it has to match this one. You always keep at least one way to sign in.',
          style: TextStyle(color: p.muted, fontSize: 11.5),
        ),
      ]),
    );
  }
}
