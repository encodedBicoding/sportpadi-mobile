import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sportpadi_mobile/core/theme/theme_mode.dart';
import 'package:url_launcher/url_launcher.dart';
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
    if (name.isEmpty) return _snack('Display name is required');
    if (uname.length < 3) {
      return _snack('Username must be at least 3 characters');
    }
    if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(uname)) {
      return _snack('Username can only use letters, numbers, and underscores');
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateMe({'displayName': name, 'username': uname});
      ref.invalidate(meProvider);
      _snack('Profile updated ✅');
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
          title: const Text('Finish in your browser'),
          content: const Text(
              'Add the card on the secure Stripe page, then come back here.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
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
        title: const Text('Settings',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Profile (same fields as web: name, username, read-only email) ──
          const Eyebrow('Profile'),
          const SizedBox(height: 8),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _displayName,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _username,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixText: '@',
                    helperText:
                        'Friends use this to find you and buy tickets for you.',
                  ),
                ),
                const SizedBox(height: 10),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    helperText: 'Receipts and confirmations go here.',
                    enabled: false,
                  ),
                  child: Text(
                    me?.email ?? '—',
                    style: TextStyle(color: p.muted, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 14),
                SpButton(
                  label: _saving ? 'Saving…' : 'Save changes',
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

          // ── Appearance: follow the phone, or force light / dark ──
          const Eyebrow('Appearance'),
          const SizedBox(height: 8),
          const _AppearanceCard(),
          const SizedBox(height: 18),

          // ── Sign-in methods: password + Google / Apple links ──
          const Eyebrow('Sign-in methods'),
          const SizedBox(height: 8),
          const SignInMethodsCard(),
          const SizedBox(height: 18),

          // ── Time zone: the clock every message / notification stamp uses ──
          const Eyebrow('Time zone'),
          const SizedBox(height: 8),
          const TimezoneCard(),
          const SizedBox(height: 18),

          // ── Notifications: can this device receive pushes? (tap to fix),
          //    then one card of switches for messages, discussions, events ──
          const Eyebrow('Notifications'),
          const SizedBox(height: 8),
          const PushNotificationsCard(),
          const SizedBox(height: 10),
          const ActivityNotificationsCard(),
          const SizedBox(height: 18),

          // ── Announcements: push / email for normal and urgent ones ──
          const Eyebrow('Announcements'),
          const SizedBox(height: 8),
          const AnnouncementPreferencesCard(),
          const SizedBox(height: 18),

          // ── Progress: XP / streak visibility ──
          const Eyebrow('Progress'),
          const SizedBox(height: 8),
          const ProgressionVisibilityTile(),
          const SizedBox(height: 18),

          // ── Payment methods (cards on file) ──
          const Eyebrow('Payment methods'),
          const SizedBox(height: 8),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Save a card for faster ticket checkout. Cards are stored by Stripe — SportPadi never sees the number.',
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
                const SizedBox(height: 10),
                cards.when(
                  loading: () => Text('Loading cards…',
                      style: TextStyle(color: p.muted, fontSize: 13)),
                  error: (e, _) => Text('$e',
                      style: TextStyle(color: p.muted, fontSize: 13)),
                  data: (list) => list.isEmpty
                      ? Text('No cards saved yet.',
                          style: TextStyle(color: p.muted, fontSize: 13))
                      : Column(children: [
                          for (final c in list) _cardRow(c, p),
                        ]),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _cardBusy ? null : _addCard,
                  icon: const Icon(Icons.add_card_rounded, size: 18),
                  label: const Text('Add card'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // ── Account ──
          const Eyebrow('Account'),
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
                    Text('Sign out',
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
            label: Text('Delete my account',
                style: TextStyle(color: p.danger, fontSize: 13)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Deleting removes your name, username, photo, email, saved cards and memberships permanently, and signs you out everywhere. Past payments stay in group records as "Deleted user". If it was a mistake, contact support within 30 days to restore it — after that it\'s permanently erased.',
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
          title: const Text('Delete your account?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                'This deletes your personal data and signs you out everywhere. Support can restore it within 30 days; after that it\'s gone forever. Type DELETE to confirm.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'DELETE'),
              onChanged: (_) => setDlg(() {}),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: controller.text.trim() == 'DELETE'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Delete forever'),
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
      _snack('Your account has been deleted.');
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
                  ? 'Primary${c.expiry != null ? ' · expires ${c.expiry}' : ''}'
                  : c.expiry != null
                      ? 'Expires ${c.expiry}'
                      : 'Card on file',
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
            child: const Text('Make primary', style: TextStyle(fontSize: 12)),
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
        title: const Text('Sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign out')),
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
          option(ThemeMode.system, Icons.brightness_auto_rounded, 'System'),
          const SizedBox(width: 8),
          option(ThemeMode.light, Icons.light_mode_rounded, 'Light'),
          const SizedBox(width: 8),
          option(ThemeMode.dark, Icons.dark_mode_rounded, 'Dark'),
        ]),
        const SizedBox(height: 10),
        Text(
          mode == ThemeMode.system
              ? "Matches your phone's light or dark setting."
              : mode == ThemeMode.dark
                  ? 'Always dark, whatever your phone is set to.'
                  : 'Always light, whatever your phone is set to.',
          style: TextStyle(color: p.muted, fontSize: 12),
        ),
      ]),
    );
  }
}
