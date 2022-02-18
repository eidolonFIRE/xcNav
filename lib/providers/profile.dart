import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Profile with ChangeNotifier {
  late String name;
  late String? id;
  late String? secretID;
  late Image avatar;
  late String? _avatarRaw;

  late String hash;

  String? get avatarRaw => _avatarRaw;

  Profile() {
    load();
  }

  load() async {
    final prefs = await SharedPreferences.getInstance();
    name = prefs.getString("profile.name") ?? "anonymous";
    id = prefs.getString("profile.id");
    secretID = prefs.getString("profile.secretID");

    _avatarRaw = prefs.getString("profile.avatar");
    if (_avatarRaw != null) {
      Uint8List imgBits = base64Decode(_avatarRaw!);
      avatar = Image.memory(imgBits);
    } else {
      avatar = Image.asset("assets/images/default_avatar.png");
    }

    hash = _hash();
  }

  updateID(String newID, String newSecretID) async {
    final prefs = await SharedPreferences.getInstance();

    id = newID;
    secretID = newSecretID;

    prefs.setString("profile.id", newID);
    prefs.setString("profile.secretID", newSecretID);

    hash = _hash();

    notifyListeners();
  }

  String _hash() {
    // build long string
    String str = "Meta" + name + (id ?? "") + (_avatarRaw ?? "");

    // fold string into hash
    int hash = 0;
    for (int i = 0, len = str.length; i < len; i++) {
      hash = ((hash << 5) - hash) + str.codeUnitAt(i);
      hash |= 0;
    }
    return (hash < 0 ? hash * -2 : hash).toRadixString(16);
  }
}
