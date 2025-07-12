import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/locale.dart';

int recursivelyCheck(String keyTrace, Map<String, dynamic> a, Map<String, dynamic> b, String bLangName) {
  int errors = 0;
  for (final key in a.keys) {
    if (!b.containsKey(key)) {
      errors++;
      debugPrint("Language '$bLangName' missing: $keyTrace.$key");
    }
    if (a[key] is Map) {
      errors += recursivelyCheck("$keyTrace.$key", a[key], b[key], bLangName);
    }
  }
  return errors;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test("check for missing", () async {
    // Load all language assets
    final en = jsonDecode(await rootBundle.loadString('assets/translations/en.json'));
    int errors = 0;
    for (final each in supportedLanguages.values.nonNulls) {
      final lang = jsonDecode(await rootBundle.loadString('assets/translations/${each.languageCode}.json'));
      errors += recursivelyCheck("root", en, lang, each.languageCode);
    }
    expect(errors, 0);
  });
}
