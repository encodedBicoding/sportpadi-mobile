import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Flutter ships no Material / Cupertino / Widgets strings for Nigerian
/// Pidgin, Yorùbá, Igbo or Hausa. Our own strings cover the app; the
/// framework's (date pickers, "Copy", back tooltips) fall back to English
/// through these delegates, which accept every locale and load `en`.
/// List them AFTER the Global* delegates so supported languages keep theirs.
class _FallbackMaterial extends LocalizationsDelegate<MaterialLocalizations> {
  const _FallbackMaterial();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale('en'));
  @override
  bool shouldReload(_FallbackMaterial old) => false;
}

class _FallbackWidgets extends LocalizationsDelegate<WidgetsLocalizations> {
  const _FallbackWidgets();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      GlobalWidgetsLocalizations.delegate.load(const Locale('en'));
  @override
  bool shouldReload(_FallbackWidgets old) => false;
}

class _FallbackCupertino extends LocalizationsDelegate<CupertinoLocalizations> {
  const _FallbackCupertino();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(const Locale('en'));
  @override
  bool shouldReload(_FallbackCupertino old) => false;
}

const fallbackLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  _FallbackMaterial(),
  _FallbackWidgets(),
  _FallbackCupertino(),
];
