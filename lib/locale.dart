import 'package:flutter/material.dart';

enum LanguageOverride {
  none,
  english,
  russian,
  hungarian,
  thai,
}

const Map<LanguageOverride, String> languageNames = {
  LanguageOverride.none: "System Default",
  LanguageOverride.english: "English",
  LanguageOverride.russian: "Русский",
  LanguageOverride.hungarian: "Magyar",
  LanguageOverride.thai: "ไทย",
};

const Map<LanguageOverride, Locale?> supportedLanguages = {
  LanguageOverride.none: null,
  LanguageOverride.english: Locale("en"),
  LanguageOverride.russian: Locale("ru"),
  LanguageOverride.hungarian: Locale("hu"),
  LanguageOverride.thai: Locale("th"),
};
