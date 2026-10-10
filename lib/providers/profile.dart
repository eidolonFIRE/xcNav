import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

import 'package:xcnav/models/gear.dart';
import 'package:xcnav/secrets.dart';
import 'package:xcnav/util.dart';

class Profile with ChangeNotifier {
  String? name;
  String? id;
  String? secretID;
  Image avatar = Image.asset("assets/images/default_avatar.png");
  Uint8List? _avatarRaw;
  String? avatarHash;

  late String hash;

  Uint8List? get avatarRaw => _avatarRaw;

  late SharedPreferences prefs;

  /// Swappable for tests.
  http.Client httpClient = http.Client();

  bool isLoaded = false;
  final _onLoad = Completer();
  Future<void> get onLoad => _onLoad.future;

  // =========================================
  Gear? _gear;
  Gear? get gear => _gear;
  set gear(Gear? newGear) {
    _gear = newGear;
    prefs.setString("profile.gear_current", _gear == null ? "" : jsonEncode(_gear!.toJson()));
  }

  Profile() {
    load();
    hash = _hash();
  }

  void load() async {
    prefs = await SharedPreferences.getInstance();

    name = prefs.getString("profile.name");

    id = prefs.getString("profile.id");
    secretID = prefs.getString("profile.secretID");
    final gearRaw = prefs.getString("profile.gear_current");
    if (gearRaw?.isNotEmpty ?? false) {
      _gear = Gear.fromJson(jsonDecode(gearRaw!));
    }

    final loadedAvatarStr = prefs.getString("profile.avatar");
    _avatarRaw = loadedAvatarStr != null ? base64Decode(loadedAvatarStr) : null;
    if (_avatarRaw != null) {
      avatar = Image.memory(_avatarRaw!);
    } else {
      avatar = Image.asset("assets/images/default_avatar.png");
    }
    updateAvatarHash();

    debugPrint("Loaded Profile: $name, $id, $secretID, avatar size: ${_avatarRaw?.length ?? 0}");

    hash = _hash();

    isLoaded = true;
    _onLoad.complete();
  }

  bool get isValid => nameValidator(name) == null && id != null;

  void eraseIdentity() {
    prefs.remove("profile.name");
    prefs.remove("profile.id");
    prefs.remove("profile.secretID");
    prefs.remove("profile.avatar");
    prefs.remove("profile.avatar_uploaded");

    // Delete cached avatar
    path_provider.getTemporaryDirectory().then((tempDir) {
      var infile = File("${tempDir.path}/avatar.jpg");
      infile.exists().then((exists) {
        if (exists) {
          infile.delete();
        }
      });
    });
  }

  void updateAvatarHash() {
    if (_avatarRaw != null) {
      avatarHash = md5.convert(_avatarRaw!).toString();
    } else {
      avatarHash = null;
    }
  }

  void updateNameAvatar(String newName, Uint8List newRawAvatar) {
    name = newName.trim();
    _avatarRaw = newRawAvatar;
    avatar = Image.memory(newRawAvatar);
    updateAvatarHash();
    hash = _hash();

    ensureAvatarUploaded();

    prefs.setString("profile.name", newName.trim());
    prefs.setString("profile.avatar", base64Encode(newRawAvatar));

    // Save avatar to file
    path_provider.getTemporaryDirectory().then((tempDir) {
      var outfile = File("${tempDir.path}/avatar.jpg");
      outfile.writeAsBytes(newRawAvatar);
    });

    notifyListeners();
  }

  /// Identifies which avatar was last uploaded, and for which pilot.
  String? get _avatarUploadKey => id == null || avatarHash == null ? null : "${id!.toLowerCase()}:$avatarHash";

  /// We have an avatar and an id, but the profile store hasn't received this avatar yet.
  bool get avatarNeedsUpload {
    final key = _avatarUploadKey;
    return key != null && prefs.getString("profile.avatar_uploaded") != key;
  }

  /// Upload the avatar if the profile store doesn't already have it.
  /// Returns true when the store is up to date.
  Future<bool> ensureAvatarUploaded() async {
    if (!avatarNeedsUpload) return true;
    return pushAvatar();
  }

  /// Returns true on a successful upload.
  Future<bool> pushAvatar() async {
    final key = _avatarUploadKey;
    if (key == null || _avatarRaw == null) {
      debugPrint("Skipping avatar push: no pilot id or avatar yet.");
      return false;
    }
    if ("x$profileStoreUrl" == "xunset") {
      debugPrint("Error while pushing avatar: secrets.dart profileStoreUrl is unset, ignoring");
      return false;
    }

    try {
      final response = await httpClient.post(Uri.parse("https://$profileStoreUrl"),
          headers: {"Content-Type": "application/json", "authorizationToken": profileStoreToken},
          body: jsonEncode({"pilot_id": id!.toLowerCase(), "avatar": base64Encode(_avatarRaw!)}));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint("Error while pushing avatar: ${response.statusCode} ${response.body}");
        return false;
      }
      await prefs.setString("profile.avatar_uploaded", key);
      return true;
    } catch (e) {
      debugPrint("Error while pushing avatar: $e");
      return false;
    }
  }

  void updateID(String newID, String newSecretID) {
    id = newID;
    secretID = newSecretID;

    debugPrint("Profile Update: $newID, $secretID");

    prefs.setString("profile.id", newID);
    prefs.setString("profile.secretID", newSecretID);

    hash = _hash();
  }

  String _hash() {
    // build long string
    String str = "Meta${name ?? ""}${id ?? ""}${avatarHash ?? ""}";

    // fold string into hash
    int hash = 0;
    for (int i = 0, len = str.length; i < len; i++) {
      hash = ((hash << 5) - hash) + str.codeUnitAt(i);
      hash &= 0xffffff;
    }
    return (hash < 0 ? hash * -2 : hash).toRadixString(16);
  }
}
