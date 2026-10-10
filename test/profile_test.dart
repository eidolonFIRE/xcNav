import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/secrets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final avatarBytes = Uint8List.fromList([1, 2, 3, 4]);
  final noStore = "x$profileStoreUrl" == "xunset" ? "secrets.dart profileStoreUrl is unset" : null;

  Future<Profile> makeProfile({String? id = "ABC123", String? uploaded}) async {
    SharedPreferences.setMockInitialValues({
      "profile.name": "tester",
      if (id != null) "profile.id": id,
      "profile.avatar": base64Encode(avatarBytes),
      if (uploaded != null) "profile.avatar_uploaded": uploaded,
    });
    final profile = Profile();
    await profile.onLoad;
    return profile;
  }

  test("avatar uploads once and is remembered", () async {
    final profile = await makeProfile();
    final posts = <http.Request>[];
    profile.httpClient = MockClient((request) async {
      posts.add(request);
      return http.Response("", 200);
    });

    expect(profile.avatarNeedsUpload, true);
    expect(await profile.ensureAvatarUploaded(), true);
    expect(posts.length, 1);
    expect(posts.first.headers["authorizationToken"], profileStoreToken);
    final body = jsonDecode(posts.first.body);
    expect(body["pilot_id"], "abc123");
    expect(base64Decode(body["avatar"]), avatarBytes);

    expect(profile.avatarNeedsUpload, false);
    expect(await profile.ensureAvatarUploaded(), true);
    expect(posts.length, 1);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString("profile.avatar_uploaded"), "abc123:${profile.avatarHash}");
  }, skip: noStore);

  test("failed upload is retried later", () async {
    final profile = await makeProfile();
    profile.httpClient = MockClient((request) async => http.Response("nope", 500));

    expect(await profile.ensureAvatarUploaded(), false);
    expect(profile.avatarNeedsUpload, true);
  }, skip: noStore);

  test("already uploaded avatar is not pushed again", () async {
    final profile = await makeProfile(uploaded: "abc123:${md5.convert(avatarBytes)}");
    profile.httpClient = MockClient((request) async => fail("should not post"));

    expect(profile.avatarNeedsUpload, false);
    expect(await profile.ensureAvatarUploaded(), true);
  });

  test("no avatar push without a pilot id", () async {
    final profile = await makeProfile(id: null);
    profile.httpClient = MockClient((request) async => fail("should not post"));

    expect(profile.avatarNeedsUpload, false);
    expect(await profile.pushAvatar(), false);
  });

  test("new id means the avatar needs uploading again", () async {
    final profile = await makeProfile(id: null);
    expect(profile.avatarNeedsUpload, false);
    final oldHash = profile.hash;

    profile.updateID("def456", "secret");
    expect(profile.avatarNeedsUpload, true);
    expect(profile.hash, isNot(oldHash));
  });
}
