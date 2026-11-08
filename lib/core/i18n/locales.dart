import 'package:flutter/material.dart';

/// The languages SportPadi speaks — mirrors packages/lib/src/locales.ts
/// (docs/design/i18n.md). Codes are BCP-47; Nigerian Pidgin is `pcm`.
class SpLocale {
  const SpLocale(this.code, this.name, this.english,
      {this.rtl = false, this.materialFallback = false});

  /// BCP-47 language code.
  final String code;

  /// The language's own name — what the picker shows.
  final String name;
  final String english;
  final bool rtl;

  /// Flutter has no Material/Cupertino strings for this language: date
  /// pickers, tooltips and the like fall back to English.
  final bool materialFallback;

  Locale get locale => Locale(code);
}

const kSpLocales = <SpLocale>[
  SpLocale('en', 'English', 'English'),
  SpLocale('pcm', 'Naijá (Pidgin)', 'Nigerian Pidgin', materialFallback: true),
  SpLocale('yo', 'Yorùbá', 'Yoruba', materialFallback: true),
  SpLocale('ig', 'Igbo', 'Igbo', materialFallback: true),
  SpLocale('ha', 'Hausa', 'Hausa', materialFallback: true),
  SpLocale('fr', 'Français', 'French'),
  SpLocale('es', 'Español', 'Spanish'),
  SpLocale('pt', 'Português', 'Portuguese'),
  SpLocale('ar', 'العربية', 'Arabic', rtl: true),
  SpLocale('de', 'Deutsch', 'German'),
  SpLocale('hi', 'हिन्दी', 'Hindi'),
];

const kDefaultLocaleCode = 'en';

final List<Locale> kSupportedLocales = [for (final l in kSpLocales) l.locale];

SpLocale? spLocaleFor(String? code) {
  if (code == null) return null;
  for (final l in kSpLocales) {
    if (l.code == code) return l;
  }
  return null;
}

/// The best supported locale for the phone's language list: exact code,
/// else the language part ("yo-NG" → yo, "pt-BR" → pt), else English.
Locale negotiateLocale(List<Locale>? device) {
  for (final d in device ?? const <Locale>[]) {
    final tag = d.toLanguageTag().toLowerCase();
    if (spLocaleFor(tag) != null) return Locale(tag);
    if (spLocaleFor(d.languageCode) != null) return Locale(d.languageCode);
  }
  return const Locale(kDefaultLocaleCode);
}
