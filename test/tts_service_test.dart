import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/tts_service.dart';

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
}
