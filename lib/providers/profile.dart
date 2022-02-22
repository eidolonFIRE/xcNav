import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Profile with ChangeNotifier {
  String? name;
  String? id;
  String? secretID;
  Image avatar = Image.asset("assets/images/default_avatar.png");
  String? _avatarRaw;

  late String hash;

  String? get avatarRaw => _avatarRaw;

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

    debugPrint("Loaded ID: $id $secretID");

    _avatarRaw = prefs.getString("profile.avatar");
    if (_avatarRaw != null) {
      Uint8List imgBits = base64Decode(_avatarRaw!);
      avatar = Image.memory(imgBits);
    } else {
      avatar = Image.asset("assets/images/default_avatar.png");
    }

    hash = _hash();
  }

  updateNameAvatar(String newName, Image newAvatar) {
    name = newName;
    avatar = newAvatar;

    prefs.setString("profile.name", newName);
    // TODO: set raw
    // _avatarRaw = base64Encode(File(newAvatar).readAsBytesSync());
    notifyListeners();
  }

  updateID(String newID, String newSecretID) {
    id = newID;
    secretID = newSecretID;

    debugPrint("Profile Update: $newID $secretID");

    prefs.setString("profile.id", newID);
    prefs.setString("profile.secretID", newSecretID);

    hash = _hash();

    notifyListeners();
  }

  String _hash() {
    // build long string
    String str = "Meta" + (name ?? "") + (id ?? "") + (_avatarRaw ?? "");

    // fold string into hash
    int hash = 0;
    for (int i = 0, len = str.length; i < len; i++) {
      hash = ((hash << 5) - hash) + str.codeUnitAt(i);
      hash |= 0;
    }
    return (hash < 0 ? hash * -2 : hash).toRadixString(16);
  }
}
