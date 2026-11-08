import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/env/sso_config.dart';
import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/auth/auth_models.dart';
import 'package:sportpadi_mobile/data/auth/auth_repository.dart';
import 'package:sportpadi_mobile/data/auth/social_sign_in.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

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
      _toast(l10n.profile_linked(_label(provider)));
      await _load();
    } on SocialSignInCancelled {
      // dismissed
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    } catch (_) {
      if (mounted) _toast(l10n.profile_somethingWentWrongPleaseTry);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _unlink(String provider) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.profile_remove2(_label(provider))),
        content: Text(
            l10n.profile_youWontBeAbleTo(_label(provider))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.profile_keepIt)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.profile_remove)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = provider);
    try {
      await ref.read(authRepositoryProvider).unlinkProvider(provider);
      if (!mounted) return;
      _toast(l10n.profile_unlinked2(_label(provider)));
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
        title: Text(l10n.profile_setAPassword),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autofocus: true,
          autofillHints: const [AutofillHints.newPassword],
          decoration:
              InputDecoration(hintText: l10n.profile_newPassword8Characters),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.profile_cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(l10n.profile_save)),
        ],
      ),
    );
    if (pw == null || !mounted) return;
    if (pw.length < 8) {
      _toast(l10n.profile_atLeast8Characters);
      return;
    }
    setState(() => _busy = 'password');
    try {
      await ref.read(authRepositoryProvider).setPassword(pw);
      if (!mounted) return;
      _toast(l10n.profile_passwordSetYouCanNow);
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
          Text(_loading ? context.l10n.profile_loading : context.l10n.profile_couldntLoadSignInMethods,
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
          title: context.l10n.profile_emailPassword,
          sub: m.hasPassword
              ? m.email
              : context.l10n.profile_noPasswordYetYouSign(linkedNames.isEmpty ? 'a linked account' : linkedNames),
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
                    Text(context.l10n.profile_onLabel,
                        style: TextStyle(
                            color: p.greenText,
                            fontSize: 11,
                            fontWeight: FontWeight.w800)),
                  ]),
                )
              : small(context.l10n.profile_setAPassword, _busy == null ? _setPassword : null,
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
                ? context.l10n.profile_linkedSignInWithOne
                : context.l10n.profile_linkToSignInWith(_label(prov)),
            trail: m.linked.contains(prov)
                ? small(
                    context.l10n.profile_unlink,
                    m.lastOne || _busy != null ? null : () => _unlink(prov),
                    busy: _busy == prov,
                  )
                : canLinkHere.contains(prov)
                    ? small(context.l10n.profile_link, _busy == null ? () => _link(prov) : null,
                        busy: _busy == prov)
                    : const SizedBox.shrink(),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          m.lastOne
              ? context.l10n.profile_thisIsYourOnlyWay
              : context.l10n.profile_linkingUsesTheEmailOn2,
          style: TextStyle(color: p.muted, fontSize: 11.5),
        ),
      ]),
    );
  }
}
