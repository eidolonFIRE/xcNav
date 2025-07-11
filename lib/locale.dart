import 'package:flutter/material.dart';

enum LanguageOverride {
  none,
  english,
  russian,
  hungarian,
}

const Map<LanguageOverride, String> languageNames = {
  LanguageOverride.none: "System Default",
  LanguageOverride.english: "English",
  LanguageOverride.russian: "Русский",
  LanguageOverride.hungarian: "Magyar",
};

const Map<LanguageOverride, Locale?> supportedLanguages = {
  LanguageOverride.none: null,
  LanguageOverride.english: Locale("en"),
  LanguageOverride.russian: Locale("ru"),
  LanguageOverride.hungarian: Locale("hu"),
};
