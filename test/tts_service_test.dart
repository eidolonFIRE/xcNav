import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mockito/mockito.dart';
import 'package:xcnav/tts_service.dart';

/// Records what's spoken. Each speak future completes only when the test says so (or never).
class FakeTts extends Mock implements FlutterTts {
  final List<String> spoken = [];
  final List<Completer<dynamic>> pending = [];
  int stops = 0;
  bool throwOnSpeak = false;

  @override
  Future<dynamic> speak(String text, {bool? focus}) {
    spoken.add(text);
    if (throwOnSpeak) {
      throwOnSpeak = false;
      return Future.error(Exception("engine died"));
    }
    final completer = Completer<dynamic>();
    pending.add(completer);
    return completer.future;
  }

  /// Finish the most recent utterance normally.
  void finish() => pending.last.complete(1);

  @override
  Future<dynamic> setVolume(double value) async => 1;

  @override
  Future<dynamic> stop() async {
    // Like iOS: stopping doesn't complete the pending speak future.
    stops++;
    return 1;
  }
}

void main() {
  group("pickBestVoice", () {
    test("android: picks highest quality offline installed voice", () {
      final voices = [
        {"name": "en-us-x-tpd-network", "locale": "en-US", "quality": "very high", "network_required": "1"},
        {"name": "en-us-x-sfg-local", "locale": "en-US", "quality": "high", "network_required": "0", "features": ""},
        {
          "name": "en-us-x-iob-local",
          "locale": "en-US",
          "quality": "very high",
          "network_required": "0",
          "features": "networkTimeoutMs\tnotInstalled"
        },
        {"name": "en-us-x-legacy", "locale": "en-US", "quality": "normal", "network_required": "0", "features": ""},
      ];
      final best = pickBestVoice(voices, "en_US",
          defaultVoice: {"name": "en-us-x-legacy", "locale": "en-US", "quality": "normal"});
      expect(best?["name"], "en-us-x-sfg-local");
    });

    test("android: keeps default when nothing is better", () {
      final voices = [
        {"name": "a", "locale": "en-US", "quality": "very high", "network_required": "0", "features": ""},
        {"name": "b", "locale": "en-US", "quality": "high", "network_required": "0", "features": ""},
      ];
      expect(pickBestVoice(voices, "en_US", defaultVoice: {"name": "a", "locale": "en-US", "quality": "very high"}),
          isNull);
    });

    test("ios: prefers premium over enhanced, ignores default quality", () {
      final voices = [
        {"name": "Samantha", "locale": "en-US", "quality": "default", "identifier": "com.apple.voice.compact.en-US"},
        {"name": "Ava", "locale": "en-US", "quality": "enhanced", "identifier": "com.apple.voice.enhanced.en-US.Ava"},
        {"name": "Zoe", "locale": "en-US", "quality": "premium", "identifier": "com.apple.voice.premium.en-US.Zoe"},
      ];
      expect(pickBestVoice(voices, "en_US")?["name"], "Zoe");
    });

    test("ios: no enhanced voice installed keeps system default", () {
      final voices = [
        {"name": "Samantha", "locale": "en-US", "quality": "default"},
        {"name": "Albert", "locale": "en-US", "quality": "default"},
      ];
      expect(pickBestVoice(voices, "en_US"), isNull);
    });

    test("exact locale beats language-only match", () {
      final voices = [
        {"name": "Daniel", "locale": "en-GB", "quality": "premium"},
        {"name": "Ava", "locale": "en-US", "quality": "enhanced"},
        {"name": "Yuri", "locale": "ru-RU", "quality": "premium"},
      ];
      expect(pickBestVoice(voices, "en_US")?["name"], "Ava");
    });

    test("falls back to same language when exact locale missing", () {
      final voices = [
        {"name": "Daniel", "locale": "en-GB", "quality": "premium"},
        {"name": "Yuri", "locale": "ru-RU", "quality": "premium"},
      ];
      expect(pickBestVoice(voices, "en_AU")?["name"], "Daniel");
    });

    test("no voices for language returns null", () {
      final voices = [
        {"name": "Yuri", "locale": "ru-RU", "quality": "premium"},
      ];
      expect(pickBestVoice(voices, "hu_HU"), isNull);
    });
  });

  group("ttsAudioSessionConfig", () {
    test("ducks other audio by default", () {
      final config = ttsAudioSessionConfig(pauseMusic: false);
      expect(config.androidAudioFocusGainType, AndroidAudioFocusGainType.gainTransientMayDuck);
      expect(config.avAudioSessionCategoryOptions!.contains(AVAudioSessionCategoryOptions.duckOthers), isTrue);
    });

    test("pauses other audio when enabled", () {
      final config = ttsAudioSessionConfig(pauseMusic: true);
      expect(config.androidAudioFocusGainType, AndroidAudioFocusGainType.gainTransient);
      expect(config.avAudioSessionCategoryOptions, AVAudioSessionCategoryOptions.none);
    });

    test("notifies other apps on release so music resumes", () {
      for (final pause in [true, false]) {
        expect(ttsAudioSessionConfig(pauseMusic: pause).avAudioSessionSetActiveOptions,
            AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation);
      }
    });
  });

  group("queue", () {
    late TtsService tts;
    late FakeTts engine;

    setUp(() {
      tts = TtsService();
      engine = FakeTts();
      tts.instance = engine;
    });

    testWidgets("plays queue in order with a gap", (tester) async {
      tts.speak(AudioMessage("a"));
      tts.speak(AudioMessage("b"));
      await tester.pump();
      expect(engine.spoken, ["a"]);

      engine.finish();
      await tester.pump();
      expect(engine.spoken, ["a"]);
      await tester.pump(TtsService.messageGap);
      expect(engine.spoken, ["a", "b"]);

      engine.finish();
      await tester.pump(const Duration(seconds: 5));
      expect(engine.spoken, ["a", "b"]);
    });

    testWidgets("recovers when speak never completes", (tester) async {
      tts.speak(AudioMessage("stuck"));
      tts.speak(AudioMessage("next"));
      await tester.pump();
      expect(engine.spoken, ["stuck"]);

      await tester.pump(TtsService.speakTimeout("stuck"));
      expect(engine.stops, 1);
      await tester.pump(TtsService.messageGap);
      expect(engine.spoken, ["stuck", "next"]);

      engine.finish();
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets("recovers when speak throws", (tester) async {
      engine.throwOnSpeak = true;
      tts.speak(AudioMessage("bad"));
      tts.speak(AudioMessage("good"));
      await tester.pump();
      await tester.pump(TtsService.messageGap);
      expect(engine.spoken, ["bad", "good"]);

      engine.finish();
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets("priority 0 interrupts without starting a second runner", (tester) async {
      tts.speak(AudioMessage("a"));
      tts.speak(AudioMessage("b"));
      await tester.pump();
      expect(engine.spoken, ["a"]);

      // "a" never completes after stop, like iOS
      tts.speak(AudioMessage("urgent", priority: 0));
      await tester.pump();
      expect(engine.stops, 1);
      expect(engine.spoken, ["a", "urgent"]);

      engine.finish();
      await tester.pump(TtsService.messageGap);
      expect(engine.spoken, ["a", "urgent", "b"]);

      engine.finish();
      await tester.pump(const Duration(minutes: 1));
      expect(engine.spoken, ["a", "urgent", "b"]);
    });

    testWidgets("priority 0 while idle speaks once", (tester) async {
      tts.speak(AudioMessage("urgent", priority: 0));
      await tester.pump();
      expect(engine.spoken, ["urgent"]);
      expect(engine.stops, 0);

      tts.speak(AudioMessage("b"));
      await tester.pump();
      engine.finish();
      await tester.pump(TtsService.messageGap);
      expect(engine.spoken, ["urgent", "b"]);

      engine.finish();
      await tester.pump(const Duration(minutes: 1));
      expect(engine.spoken, ["urgent", "b"]);
    });

    testWidgets("priority 0 skips the gap", (tester) async {
      tts.speak(AudioMessage("a"));
      tts.speak(AudioMessage("b"));
      await tester.pump();
      engine.finish();
      await tester.pump();

      tts.speak(AudioMessage("urgent", priority: 0));
      await tester.pump();
      expect(engine.spoken, ["a", "urgent"]);

      engine.finish();
      await tester.pump(TtsService.messageGap);
      expect(engine.spoken, ["a", "urgent", "b"]);

      engine.finish();
      await tester.pump(const Duration(minutes: 1));
      expect(engine.spoken, ["a", "urgent", "b"]);
    });

    testWidgets("drops expired messages", (tester) async {
      tts.speak(AudioMessage("a"));
      tts.speak(AudioMessage("old", expires: DateTime.now().subtract(const Duration(seconds: 1))));
      tts.speak(AudioMessage("b", priority: 6));
      await tester.pump();
      engine.finish();
      await tester.pump(TtsService.messageGap);
      expect(engine.spoken, ["a", "b"]);

      engine.finish();
      await tester.pump(const Duration(seconds: 5));
    });

    test("caps queue length", () {
      // First message is taken off the queue to speak
      for (int i = 0; i < TtsService.maxQueueLength + 5; i++) {
        tts.speak(AudioMessage("$i"));
      }
      expect(tts.msgQueue.length, TtsService.maxQueueLength);
    });
  });
}
