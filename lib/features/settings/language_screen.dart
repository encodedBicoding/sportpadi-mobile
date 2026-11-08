import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/i18n/locale_controller.dart';
import 'package:sportpadi_mobile/core/i18n/locales.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Settings → Language (docs/design/i18n.md). Web twin: components/settings/
/// LanguagePicker.tsx. "Follow my phone" clears the choice; picking one saves
/// it on the device and the profile and the whole app re-renders at once.
class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final l = context.l10n;
    final chosen = ref.watch(localeControllerProvider);
    final active = Localizations.localeOf(context).languageCode;
    final activeName = spLocaleFor(active)?.name ?? 'English';

    Widget row({
      required String key,
      required String title,
      String? sub,
      required bool on,
      required VoidCallback onTap,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Row(children: [
            SpIconTile(on ? Icons.check_rounded : Icons.language_rounded,
                size: 38,
                iconSize: 19,
                bg: on ? p.accentTint : p.surface2,
                fg: on ? p.greenText : p.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14.5,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w600)),
                  if (sub != null)
                    Text(sub,
                        maxLines: 2,
                        style: TextStyle(color: p.muted, fontSize: 12)),
                ],
              ),
            ),
          ]),
        ),
      );
    }

    Future<void> choose(String? code) async {
      final messenger = ScaffoldMessenger.of(context);
      await ref.read(localeControllerProvider.notifier).set(code);
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(context.l10n.settings_saved)));
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SpHeader(title: l.settings_language),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
              children: [
                Text(l.settings_languageSub,
                    style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.45)),
                const SizedBox(height: 14),
                SpListCard(children: [
                  row(
                    key: 'auto',
                    title: l.settings_followDevice,
                    sub: chosen == null
                        ? '${l.settings_followDeviceSub} · $activeName'
                        : l.settings_followDeviceSub,
                    on: chosen == null,
                    onTap: () => choose(null),
                  ),
                  for (final sl in kSpLocales)
                    row(
                      key: sl.code,
                      title: sl.name,
                      sub: sl.code == 'en' ? null : sl.english,
                      on: chosen?.languageCode == sl.code,
                      onTap: () => choose(sl.code),
                    ),
                ]),
                const SizedBox(height: 12),
                Text(l.settings_reviewNote,
                    style: TextStyle(color: p.muted, fontSize: 12, height: 1.45)),
                const SizedBox(height: 8),
                if (context.canPop())
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                        onPressed: () => context.pop(),
                        child: Text(l.common_done)),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
