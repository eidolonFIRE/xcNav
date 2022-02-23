import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Profile with ChangeNotifier {
  String? name;
  String? id;
  String? secretID;
  Image avatar = Image.asset("assets/images/default_avatar.png");
  Uint8List? _avatarRaw;

  late String hash;

  Uint8List? get avatarRaw => _avatarRaw;

  late SharedPreferences prefs;

  Profile() {
    load();
    hash = _hash();
  }

  load() async {
    prefs = await SharedPreferences.getInstance();

    name = prefs.getString("profile.name");
    id = prefs.getString("profile.id");
    secretID = prefs.getString("profile.secretID");

    _avatarRaw = base64Decode(prefs.getString("profile.avatar") ?? "");
    if (_avatarRaw != null) {
      avatar = Image.memory(_avatarRaw!);
    } else {
      avatar = Image.asset("assets/images/default_avatar.png");
    }

    debugPrint("Loaded Profile: $name, $id, $secretID");

    hash = _hash();
  }

  updateNameAvatar(String newName, Uint8List newRawAvatar) {
    name = newName.trim();
    _avatarRaw = newRawAvatar;
    avatar = Image.memory(newRawAvatar);

    prefs.setString("profile.name", newName.trim());
    prefs.setString("profile.avatar", base64Encode(newRawAvatar));
    notifyListeners();
  }

  updateID(String newID, String newSecretID) {
    id = newID;
    secretID = newSecretID;

    debugPrint("Profile Update: $newID, $secretID");

    prefs.setString("profile.id", newID);
    prefs.setString("profile.secretID", newSecretID);

    hash = _hash();

    notifyListeners();
  }

  String _hash() {
    // build long string
    String str = "Meta" +
        (name ?? "") +
        (id ?? "") +
        (_avatarRaw != null ? base64Encode(_avatarRaw!) : "");

    // fold string into hash
    int hash = 0;
    for (int i = 0, len = str.length; i < len; i++) {
      hash = ((hash << 5) - hash) + str.codeUnitAt(i);
      hash |= 0;
    }
    return (hash < 0 ? hash * -2 : hash).toRadixString(16);
  }
}
