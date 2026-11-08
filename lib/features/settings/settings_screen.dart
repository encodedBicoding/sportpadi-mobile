import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sportpadi_mobile/core/theme/theme_mode.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/i18n/locale_controller.dart';
import 'package:sportpadi_mobile/core/i18n/locales.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/profile/profile_models.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';
import 'package:sportpadi_mobile/features/settings/profile_privacy_card.dart';
import 'package:sportpadi_mobile/features/settings/push_notifications_card.dart';
import 'package:sportpadi_mobile/features/settings/sign_in_methods_card.dart';
import 'package:sportpadi_mobile/features/settings/timezone_card.dart';
import 'package:sportpadi_mobile/features/settings/activity_notifications_card.dart';
import 'package:sportpadi_mobile/features/announcements/announcement_entry_points.dart'
    show AnnouncementPreferencesCard;
import 'package:sportpadi_mobile/features/progression/progression_screens.dart';

/// Settings — mirrors the web settings page: editable profile (display name,
/// username, read-only email), payment methods (cards on file), sign out.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _displayName = TextEditingController();
  final _username = TextEditingController();
  bool _seeded = false;
  bool _saving = false;
  bool _cardBusy = false;
  bool _deleting = false;

  @override
  void dispose() {
    _displayName.dispose();
    _username.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _save() async {
    final name = _displayName.text.trim();
    final uname = _username.text.trim().replaceFirst(RegExp(r'^@'), '');
    if (name.isEmpty) return _snack(l10n.profile_displayNameIsRequired2);
    if (uname.length < 3) {
      return _snack(l10n.profile_usernameMustBeAtLeast2);
    }
    if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(uname)) {
      return _snack(l10n.profile_usernameCanOnlyUseLetters2);
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateMe({'displayName': name, 'username': uname});
      ref.invalidate(meProvider);
      _snack(l10n.profile_profileUpdated2);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Card setup happens on Stripe's hosted page (same as web) — open it, then
  /// reconcile when the user comes back.
  Future<void> _addCard() async {
    setState(() => _cardBusy = true);
    try {
      final url = await ref.read(profileRepositoryProvider).startAddCard();
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.profile_finishInYourBrowser),
          content: Text(
              l10n.profile_addTheCardOnThe),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(l10n.profile_done)),
          ],
        ),
      );
      await ref.read(profileRepositoryProvider).syncCards();
      ref.invalidate(myCardsProvider);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _cardBusy = false);
    }
  }

  Future<void> _cardAction(Future<void> Function() fn) async {
    setState(() => _cardBusy = true);
    try {
      await fn();
      ref.invalidate(myCardsProvider);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _cardBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final me = ref.watch(meProvider).valueOrNull;
    final cards = ref.watch(myCardsProvider);
    if (me != null && !_seeded) {
      _seeded = true;
      _displayName.text = me.displayName;
      _username.text = me.username;
    }
    return Scaffold(
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: Text(context.l10n.profile_settings,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Profile (same fields as web: name, username, read-only email) ──
          Eyebrow(context.l10n.profile_profile),
          const SizedBox(height: 8),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _displayName,
                  decoration: InputDecoration(labelText: context.l10n.profile_displayName),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _username,
                  decoration: InputDecoration(
                    labelText: context.l10n.profile_username,
                    prefixText: '@',
                    helperText:
                        context.l10n.profile_friendsUseThisToFind2,
                  ),
                ),
                const SizedBox(height: 10),
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: context.l10n.profile_email,
                    helperText: context.l10n.profile_receiptsAndConfirmationsGoHere2,
                    enabled: false,
                  ),
                  child: Text(
                    me?.email ?? '—',
                    style: TextStyle(color: p.muted, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 14),
                SpButton(
                  label: _saving ? context.l10n.profile_saving : context.l10n.profile_saveChanges,
                  icon: Icons.save_outlined,
                  expand: true,
                  onTap: _saving ? null : _save,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── Profile privacy: only while a guardian supervises me (claimed
          //    my account under 18) — nothing for everyone else ──
          const ProfilePrivacySection(),

          // ── Language: the player's choice, else the phone (docs/design/i18n.md) ──
          Eyebrow(context.l10n.settings_language),
          const SizedBox(height: 8),
          const _LanguageRow(),
          const SizedBox(height: 18),

          // ── Appearance: follow the phone, or force light / dark ──
          Eyebrow(context.l10n.settings_appearance),
          const SizedBox(height: 8),
          const _AppearanceCard(),
          const SizedBox(height: 18),

          // ── Sign-in methods: password + Google / Apple links ──
          Eyebrow(context.l10n.profile_signInMethods),
          const SizedBox(height: 8),
          const SignInMethodsCard(),
          const SizedBox(height: 18),

          // ── Time zone: the clock every message / notification stamp uses ──
          Eyebrow(context.l10n.profile_timeZone),
          const SizedBox(height: 8),
          const TimezoneCard(),
          const SizedBox(height: 18),

          // ── Notifications: can this device receive pushes? (tap to fix),
          //    then one card of switches for messages, discussions, events ──
          Eyebrow(context.l10n.profile_notifications),
          const SizedBox(height: 8),
          const PushNotificationsCard(),
          const SizedBox(height: 10),
          const ActivityNotificationsCard(),
          const SizedBox(height: 18),

          // ── Announcements: push / email for normal and urgent ones ──
          Eyebrow(context.l10n.profile_announcements),
          const SizedBox(height: 8),
          const AnnouncementPreferencesCard(),
          const SizedBox(height: 18),

          // ── Progress: XP / streak visibility ──
          Eyebrow(context.l10n.profile_progress),
          const SizedBox(height: 8),
          const ProgressionVisibilityTile(),
          const SizedBox(height: 18),

          // ── Payment methods (cards on file) ──
          Eyebrow(context.l10n.profile_paymentMethods),
          const SizedBox(height: 8),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.l10n.profile_saveACardForFaster,
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
                const SizedBox(height: 10),
                cards.when(
                  loading: () => Text(context.l10n.profile_loadingCards,
                      style: TextStyle(color: p.muted, fontSize: 13)),
                  error: (e, _) => Text('$e',
                      style: TextStyle(color: p.muted, fontSize: 13)),
                  data: (list) => list.isEmpty
                      ? Text(context.l10n.profile_noCardsSavedYet,
                          style: TextStyle(color: p.muted, fontSize: 13))
                      : Column(children: [
                          for (final c in list) _cardRow(c, p),
                        ]),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _cardBusy ? null : _addCard,
                  icon: const Icon(Icons.add_card_rounded, size: 18),
                  label: Text(context.l10n.profile_addCard),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // ── Account ──
          Eyebrow(context.l10n.profile_account),
          const SizedBox(height: 8),
          Material(
            color: p.surface,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _confirmSignOut(context),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: const Color.fromRGBO(222, 33, 33, 0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout_rounded, size: 18, color: p.danger),
                    const SizedBox(width: 8),
                    Text(context.l10n.profile_signOut,
                        style: TextStyle(
                            color: p.danger,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Account deletion (Google Play data-deletion requirement).
          TextButton.icon(
            onPressed: _deleting ? null : _confirmDeleteAccount,
            icon:
                Icon(Icons.delete_forever_outlined, size: 18, color: p.danger),
            label: Text(context.l10n.profile_deleteMyAccount,
                style: TextStyle(color: p.danger, fontSize: 13)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              context.l10n.profile_deletingRemovesYourNameUsername,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 11, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(l10n.profile_deleteYourAccount),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
                l10n.profile_thisDeletesYourPersonalData),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(hintText: l10n.profile_delete),
              onChanged: (_) => setDlg(() {}),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.profile_cancel)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: controller.text.trim() == 'DELETE'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: Text(l10n.profile_deleteForever),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (ok != true) return;
    setState(() => _deleting = true);
    try {
      await ref.read(profileRepositoryProvider).deleteAccount();
      _snack(l10n.profile_yourAccountHasBeenDeleted);
      await ref.read(authControllerProvider.notifier).signOut();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Widget _cardRow(PaymentCard c, AppPalette p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(Icons.credit_card_rounded,
            size: 20, color: c.isPrimary ? p.accent : p.muted),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.label,
                style: TextStyle(
                    color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w700)),
            Text(
              c.isPrimary
                  ? context.l10n.profile_primary3((c.expiry != null ? ' · expires ${c.expiry}' : ''))
                  : c.expiry != null
                      ? context.l10n.profile_expires3(c.expiry ?? '')
                      : context.l10n.profile_cardOnFile,
              style: TextStyle(color: p.muted, fontSize: 11.5),
            ),
          ]),
        ),
        if (!c.isPrimary)
          TextButton(
            onPressed: _cardBusy
                ? null
                : () => _cardAction(() =>
                    ref.read(profileRepositoryProvider).setPrimaryCard(c.id)),
            child: Text(context.l10n.profile_makePrimary, style: const TextStyle(fontSize: 12)),
          ),
        IconButton(
          icon: Icon(Icons.close_rounded, size: 18, color: p.muted),
          onPressed: _cardBusy
              ? null
              : () => _cardAction(
                  () => ref.read(profileRepositoryProvider).removeCard(c.id)),
        ),
      ]),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.profile_signOut2),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.profile_stay)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.profile_signOut)),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }
}

/// System / Light / Dark as three pills. System (default) follows the
/// phone, so dark-mode phones get the dark theme without asking.
class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final mode = ref.watch(themeModeProvider);
    Widget option(ThemeMode m, IconData icon, String label) {
      final on = mode == m;
      return Expanded(
        child: Material(
          color: on ? p.hero : p.surface2,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => ref.read(themeModeProvider.notifier).set(m),
            child: SizedBox(
              height: 64,
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 20, color: on ? p.onHero : p.muted),
                    const SizedBox(height: 4),
                    Text(label,
                        style: TextStyle(
                            color: on ? p.onHero : p.ink,
                            fontSize: 12.5,
                            fontWeight:
                                on ? FontWeight.w700 : FontWeight.w600)),
                  ]),
            ),
          ),
        ),
      );
    }

    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          option(ThemeMode.system, Icons.brightness_auto_rounded, context.l10n.profile_system),
          const SizedBox(width: 8),
          option(ThemeMode.light, Icons.light_mode_rounded, context.l10n.profile_light),
          const SizedBox(width: 8),
          option(ThemeMode.dark, Icons.dark_mode_rounded, context.l10n.profile_dark),
        ]),
        const SizedBox(height: 10),
        Text(
          mode == ThemeMode.system
              ? context.l10n.profile_matchesYourPhonesLightOr
              : mode == ThemeMode.dark
                  ? context.l10n.profile_alwaysDarkWhateverYourPhone
                  : context.l10n.profile_alwaysLightWhateverYourPhone,
          style: TextStyle(color: p.muted, fontSize: 12),
        ),
      ]),
    );
  }
}


/// Settings → Language row: the language in use, opening the picker.
class _LanguageRow extends ConsumerWidget {
  const _LanguageRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final l = context.l10n;
    final chosen = ref.watch(localeControllerProvider);
    final active = Localizations.localeOf(context).languageCode;
    final name = spLocaleFor(active)?.name ?? 'English';
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/settings/language'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Row(children: [
            SpIconTile(Icons.language_rounded,
                size: 38, iconSize: 19, bg: p.accentTint, fg: p.greenText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                          color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
                  Text(chosen == null ? l.settings_followDevice : l.settings_language,
                      style: TextStyle(color: p.muted, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.muted),
          ]),
        ),
      ),
    );
  }
}
