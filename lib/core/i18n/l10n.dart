import 'package:flutter/widgets.dart';

import 'package:sportpadi_mobile/l10n/generated/app_localizations.dart';

export 'package:sportpadi_mobile/l10n/generated/app_localizations.dart';

/// `context.l10n.nav_home` — the generated strings (docs/design/i18n.md).
/// Prefer this in widgets: it rebuilds them when the language changes.
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// The strings for the language on screen right now, for code with no
/// BuildContext at hand (label helpers, async callbacks after an await).
/// Kept current by the app builder (see app.dart); English until then.
AppLocalizations get l10n => _current ?? lookupAppLocalizations(const Locale('en'));
AppLocalizations? _current;

/// Called from MaterialApp.builder on every rebuild — including a language change.
void setCurrentL10n(AppLocalizations value) => _current = value;
