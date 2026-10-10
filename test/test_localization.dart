import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

late Map<String, dynamic> _enTranslations;

/// Serves translations preloaded by [initTestLocalization].
/// (Loading through rootBundle on every test hangs after the first test.)
class _MapAssetLoader extends AssetLoader {
  const _MapAssetLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async => _enTranslations;
}

/// Call from `setUpAll`.
Future initTestLocalization() async {
  SharedPreferences.setMockInitialValues({});
  await EasyLocalization.ensureInitialized();
  _enTranslations = jsonDecode(File("assets/translations/en.json").readAsStringSync());
}

/// Wrap [child] in an english-only [EasyLocalization].
Widget testLocalization({required Widget child}) => EasyLocalization(
    supportedLocales: const [Locale("en")],
    path: "assets/translations",
    startLocale: const Locale("en"),
    useOnlyLangCode: true,
    assetLoader: const _MapAssetLoader(),
    child: child);
