import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:xcnav/settings_service.dart';

/// An instance for each message to speak to user.
///
/// `expires` : if set and message hasn't played by this time, don't bother.
///
/// `volume` : 0 - 1
///
/// `priority:` 0 = stop the current msg short!  1-inf is sort insertion.
class AudioMessage {
  final String text;
  final int priority;
  final DateTime? expires;
  final double? volume;

  AudioMessage(this.text, {this.priority = 5, this.expires, this.volume});
}

/// Relative rank of the quality strings reported by flutter_tts `getVoices`.
/// iOS reports default/enhanced/premium; Android reports very low ... very high.
const Map<String, int> _voiceQualityRank = {
  "very low": 1,
  "low": 2,
  "default": 3,
  "normal": 3,
  "enhanced": 4,
  "high": 4,
  "premium": 5,
  "very high": 5,
};

int _voiceQuality(Map<String, String> voice) => _voiceQualityRank[voice["quality"]] ?? 0;

String _normalizeLocale(String locale) => locale.split(".").first.replaceAll("_", "-").toLowerCase();

/// Pick the highest quality voice for `locale` that works offline.
///
/// Voices matching the full locale (e.g. en-US) win over ones matching only the language (e.g. en-GB).
/// Returns null if nothing beats `defaultVoice` (or a "default" quality voice if not given), so the system default is kept.
Map<String, String>? pickBestVoice(List<Map<String, String>> voices, String locale, {Map<String, String>? defaultVoice}) {
  final target = _normalizeLocale(locale);
  final targetLang = target.split("-").first;

  int localeScore(Map<String, String> voice) {
    final voiceLocale = _normalizeLocale(voice["locale"] ?? "");
    if (voiceLocale == target) return 2;
    if (voiceLocale.split("-").first == targetLang) return 1;
    return 0;
  }

  final candidates = voices.where((v) {
    if (v["name"] == null || v["locale"] == null) return false;
    if (v["network_required"] == "1") return false;
    if ((v["features"] ?? "").split("\t").contains("notInstalled")) return false;
    return localeScore(v) > 0;
  }).toList();
  if (candidates.isEmpty) return null;

  candidates.sort((a, b) {
    final byLocale = localeScore(b).compareTo(localeScore(a));
    if (byLocale != 0) return byLocale;
    return _voiceQuality(b).compareTo(_voiceQuality(a));
  });

  final best = candidates.first;
  final baseline = defaultVoice != null ? _voiceQuality(defaultVoice) : _voiceQualityRank["default"]!;
  if (_voiceQuality(best) <= baseline) return null;
  return best;
}

/// Audio session setup for speech. Other audio is paused when `pauseMusic`, otherwise ducked.
AudioSessionConfiguration ttsAudioSessionConfig({required bool pauseMusic}) => AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: pauseMusic
          ? AVAudioSessionCategoryOptions.none
          : AVAudioSessionCategoryOptions.duckOthers |
              AVAudioSessionCategoryOptions.interruptSpokenAudioAndMixWithOthers,
      avAudioSessionMode: AVAudioSessionMode.voicePrompt,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.assistanceNavigationGuidance,
      ),
      androidAudioFocusGainType:
          pauseMusic ? AndroidAudioFocusGainType.gainTransient : AndroidAudioFocusGainType.gainTransientMayDuck,
    );

/// Global Singleton
late TtsService ttsService;

/// Singleton for queueing up messages to speak to users
class TtsService {
  FlutterTts? instance;
  Future? _initFuture;
  int currentPriority = 10;

  QueueList<AudioMessage> msgQueue = QueueList();

  /// Most messages kept in the queue. The lowest priority ones are dropped first.
  static const maxQueueLength = 20;

  /// Pause between messages.
  static const messageGap = Duration(seconds: 1);

  /// Longest a message may take before the engine is considered stuck and gets reset.
  static Duration speakTimeout(String text) => Duration(milliseconds: 10000 + 200 * text.length);

  /// Audio session used to duck or pause other audio while speaking. Null until `init()`.
  AudioSession? _session;
  bool? _sessionPausesMusic;
  bool _sessionActive = false;

  /// True while `_runQueue` is working through `msgQueue`. Only one runner may exist at a time.
  bool _running = false;

  /// Completed to end the current message (or the gap after it) early.
  /// The native speak future doesn't always complete (stop on iOS, engine errors on Android),
  /// so the runner never waits on it alone.
  Completer<void>? _wake;

  void _wakeUp() {
    final wake = _wake;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  /// Take audio focus before speaking. Other audio is ducked or paused depending on settings.
  Future _activateSession() async {
    final session = _session;
    if (session == null || _sessionActive) return;
    try {
      final pauseMusic = settingsMgr.pauseMusicForSpeech.value;
      if (_sessionPausesMusic != pauseMusic) {
        await session.configure(ttsAudioSessionConfig(pauseMusic: pauseMusic));
        _sessionPausesMusic = pauseMusic;
      }
      _sessionActive = await session.setActive(true);
    } catch (e) {
      debugPrint("Failed to activate audio session: $e");
    }
  }

  /// Give audio focus back once nothing is speaking or queued, so other audio resumes.
  void _releaseSessionIfIdle() {
    final session = _session;
    if (session == null || !_sessionActive || _running || msgQueue.isNotEmpty) return;
    _sessionActive = false;
    session.setActive(false).catchError((e) {
      debugPrint("Failed to deactivate audio session: $e");
      return false;
    });
  }

  Future init() async {
    final tts = FlutterTts();

    if (Platform.isIOS) {
      // The audio session is managed in `_activateSession` so it stays active across queued messages.
      await tts.autoStopSharedSession(false);
    } else if (Platform.isAndroid) {
      // Route speech as navigation guidance so it plays like turn-by-turn prompts.
      await tts.setAudioAttributesForNavigation();
    }

    try {
      _session = await AudioSession.instance;
    } catch (e) {
      debugPrint("Failed to get audio session: $e");
    }

    await _selectBestVoice(tts);

    // instance.getDefaultEngine.then((value) => instance.setEngine(value));
    // instance.getEngines.then((value) => debugPrint("Engines: $value"));
    await tts.awaitSpeakCompletion(true);
    // instance.setStartHandler(() {
    //   _state = TtsState.playing;
    // });

    // Any time the messages stop, try playing the next one.
    // instance.setCompletionHandler(waitAndTryNext);
    // instance.setCancelHandler(waitAndTryNext);
    // Android doesn't complete the speak future on errors, so move on from here.
    tts.setErrorHandler((msg) {
      debugPrint("TTS error: $msg");
      _wakeUp();
    });

    // Only publish once fully set up, so nothing speaks on a half initialized engine.
    instance = tts;
  }

  /// Initialize once, even if many messages arrive while it's in progress. Returns false if it failed.
  Future<bool> _ensureInit() async {
    if (instance != null) return true;
    debugPrint("Initializing TTS engine...");
    try {
      await (_initFuture ??= init());
    } catch (e) {
      debugPrint("Failed to initialize TTS engine: $e");
      // Allow a retry on the next message.
      _initFuture = null;
    }
    return instance != null;
  }

  Future<void> _stopEngine() async {
    try {
      await instance?.stop().timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint("Failed to stop TTS: $e");
    }
  }

  /// Switch to the best offline voice for the device locale, if it beats the system default.
  Future _selectBestVoice(FlutterTts tts) async {
    try {
      final voices = ((await tts.getVoices) as List? ?? [])
          .map((v) => Map<String, String>.from((v as Map).map((k, v) => MapEntry(k.toString(), v.toString()))))
          .toList();

      Map<String, String>? defaultVoice;
      if (Platform.isAndroid) {
        final value = await tts.getDefaultVoice;
        if (value is Map && value.isNotEmpty) {
          defaultVoice = value.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      }

      final best = pickBestVoice(voices, Platform.localeName, defaultVoice: defaultVoice);
      if (best != null) {
        debugPrint("TTS voice: ${best["name"]} (${best["locale"]}, ${best["quality"]})");
        await tts.setVoice(best);
      }
    } catch (e) {
      debugPrint("Failed to select TTS voice: $e");
    }
  }

  /// Next message that hasn't expired, or null if there are none left.
  AudioMessage? _nextMessage() {
    final now = DateTime.now();
    while (msgQueue.isNotEmpty) {
      final msg = msgQueue.removeFirst();
      if (msg.expires == null || msg.expires!.isAfter(now)) return msg;
    }
    return null;
  }

  /// Speak queued messages one at a time until the queue is empty.
  Future<void> _runQueue() async {
    if (_running || instance == null) return;
    _running = true;
    try {
      AudioMessage? msg;
      while ((msg = _nextMessage()) != null) {
        final interrupted = await _speakOne(msg!);
        if (!interrupted && msgQueue.isNotEmpty) await _pause(messageGap);
      }
    } catch (e) {
      debugPrint("TTS queue failed: $e");
    } finally {
      _running = false;
      currentPriority = 10;
      _releaseSessionIfIdle();
    }
  }

  /// Speak one message. Returns true if it was cut short by `_wakeUp`.
  Future<bool> _speakOne(AudioMessage msg) async {
    final tts = instance!;
    final wake = _wake = Completer<void>();
    currentPriority = msg.priority;
    debugPrint("Speak: \"${msg.text}\"");

    Future<void> speakIt() async {
      await tts.setVolume(msg.volume ?? 1.0);
      await _activateSession();
      // Interrupted while getting ready
      if (wake.isCompleted) return;
      await tts.speak(msg.text);
    }

    try {
      await Future.any([speakIt(), wake.future]).timeout(speakTimeout(msg.text));
    } on TimeoutException {
      debugPrint("TTS timed out: \"${msg.text}\"");
      // Android ignores new messages while it still thinks it's speaking, so reset it.
      await _stopEngine();
    } catch (e) {
      debugPrint("TTS failed: $e");
    }
    return wake.isCompleted;
  }

  /// Wait `duration`, or less if `_wakeUp` is called.
  Future<void> _pause(Duration duration) {
    final wake = _wake = Completer<void>();
    final timer = Timer(duration, _wakeUp);
    return wake.future.whenComplete(timer.cancel);
  }

  /// Queue up a message to be spoken
  void speak(AudioMessage msg) async {
    if (msg.priority == 0) {
      msgQueue.addFirst(msg);
    } else {
      // insertion
      for (int index = 0; index <= msgQueue.length; index++) {
        if (index == msgQueue.length || msgQueue[index].priority > msg.priority) {
          // debugPrint("Speak queue insert $index / ${msgQueue.length}");
          msgQueue.insert(index, msg);
          break;
        }
      }
    }

    if (msgQueue.length > maxQueueLength) {
      // Too many messages, drop the last one
      msgQueue.removeLast();
    }

    // debugPrint("Speak queue length: ${msgQueue.length}");

    if (!await _ensureInit()) return;

    if (_running) {
      // Cut the current message short
      if (msg.priority == 0 && currentPriority != 0) {
        _wakeUp();
        _stopEngine();
      }
    } else {
      // if nothing is playing... start it
      _runQueue();
    }
  }
}
