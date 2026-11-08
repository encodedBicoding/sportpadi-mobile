import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Dates in the reader's language (docs/design/i18n.md, phase 4).
///
/// `bootstrap` loads intl's date data once; the app builder calls
/// [applyDateLocale] with the language on screen. English keeps the US
/// patterns the app always used; a language intl has no date data for
/// (Naijá, Igbo, Hausa) falls back to them too.
Future<void> initDateLocales() => initializeDateFormatting();

void applyDateLocale(String languageCode) {
  Intl.defaultLocale = languageCode != 'en' && DateFormat.localeExists(languageCode) ? languageCode : 'en_US';
}

/// The locale to pass where code used to hard-code `'en_US'`.
String get spDateLocale => Intl.defaultLocale ?? 'en_US';
