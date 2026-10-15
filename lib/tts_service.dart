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

enum TtsState {
  stopped,
  playing,
}

/// Global Singleton
late TtsService ttsService;

/// Singleton for queueing up messages to speak to users
class TtsService {
  FlutterTts? instance;
  TtsState _state = TtsState.stopped;
  int currentPriority = 10;

  QueueList<AudioMessage> msgQueue = QueueList();

  /// Audio session used to duck or pause other audio while speaking. Null until `init()`.
  AudioSession? _session;
  bool? _sessionPausesMusic;
  bool _sessionActive = false;

  /// Id of the most recent utterance, and whether it is still speaking.
  /// Interrupted utterances may never complete (iOS), so only the latest one counts.
  int _utteranceId = 0;
  bool _speaking = false;

  void _waitAndTryNext() {
    if (msgQueue.isNotEmpty) {
      Timer(const Duration(seconds: 1), speakNextInQueue);
    } else {
      _state = TtsState.stopped;
      _releaseSessionIfIdle();
    }
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
    if (session == null || !_sessionActive || _speaking || msgQueue.isNotEmpty) return;
    _sessionActive = false;
    session.setActive(false).catchError((e) {
      debugPrint("Failed to deactivate audio session: $e");
      return false;
    });
  }

  Future init() async {
    instance = FlutterTts();

    if (Platform.isIOS) {
      // The audio session is managed in `_activateSession` so it stays active across queued messages.
      await instance!.autoStopSharedSession(false);
    } else if (Platform.isAndroid) {
      // Route speech as navigation guidance so it plays like turn-by-turn prompts.
      await instance!.setAudioAttributesForNavigation();
    }

    try {
      _session = await AudioSession.instance;
    } catch (e) {
      debugPrint("Failed to get audio session: $e");
    }

    await _selectBestVoice();

    // instance.getDefaultEngine.then((value) => instance.setEngine(value));
    // instance.getEngines.then((value) => debugPrint("Engines: $value"));
    await instance!.awaitSpeakCompletion(true);
    // instance.setStartHandler(() {
    //   _state = TtsState.playing;
    // });

    // Any time the messages stop, try playing the next one.
    // instance.setCompletionHandler(waitAndTryNext);
    // instance.setCancelHandler(waitAndTryNext);
    instance!.setErrorHandler((_) {
      _speaking = false;
      _waitAndTryNext();
    });
  }

  /// Switch to the best offline voice for the device locale, if it beats the system default.
  Future _selectBestVoice() async {
    try {
      final voices = ((await instance!.getVoices) as List? ?? [])
          .map((v) => Map<String, String>.from((v as Map).map((k, v) => MapEntry(k.toString(), v.toString()))))
          .toList();

      Map<String, String>? defaultVoice;
      if (Platform.isAndroid) {
        final value = await instance!.getDefaultVoice;
        if (value is Map && value.isNotEmpty) {
          defaultVoice = value.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      }

      final best = pickBestVoice(voices, Platform.localeName, defaultVoice: defaultVoice);
      if (best != null) {
        debugPrint("TTS voice: ${best["name"]} (${best["locale"]}, ${best["quality"]})");
        await instance!.setVoice(best);
      }
    } catch (e) {
      debugPrint("Failed to select TTS voice: $e");
    }
  }

  Future<void> speakNextInQueue() async {
    // _state = TtsState.playing;
    // debugPrint("Speak next in queue");

    if (instance != null) {
      if (msgQueue.isNotEmpty) {
        final msg = msgQueue.removeFirst();

        if (msg.expires == null || msg.expires!.isAfter(DateTime.now())) {
          instance!.setVolume(msg.volume ?? 1.0);
          debugPrint("Speak: \"${msg.text}\"");
          _state = TtsState.playing;
          currentPriority = msg.priority;
          final id = ++_utteranceId;
          _speaking = true;
          if (_session != null) await _activateSession();
          instance!.speak(msg.text).whenComplete(() {
            if (id == _utteranceId) _speaking = false;
          }).then((_) => _waitAndTryNext());
        } else {
          // Msg was expired, try again
          speakNextInQueue();
        }
      } else {
        // debugPrint("Speak queue is empty");
        _state = TtsState.stopped;
        _releaseSessionIfIdle();
      }
    }
  }

  /// Queue up a message to be spoken
  void speak(AudioMessage msg) async {
    if (instance == null) {
      debugPrint("Initializing TTS engine...");
      await init();
    }

    if (msg.priority == 0) {
      msgQueue.addFirst(msg);
      if (currentPriority != 0) {
        instance!.stop().then((value) => speakNextInQueue());
      }
    } else {
      // insertion
      for (int index = 0; index <= msgQueue.length; index++) {
        if (index == msgQueue.length || msgQueue[index].priority > msg.priority) {
          // debugPrint("Speak queue insert $index / ${msgQueue.length}");
          msgQueue.insert(index, msg);
          break;
        }
      }

      if (msgQueue.length > 20) {
        // Too many messages, drop the last one
        msgQueue.removeLast();
      }
    }

    // debugPrint("Speak queue length: ${msgQueue.length}");

    // if nothing is playing... start it
    if (_state != TtsState.playing) {
      speakNextInQueue();
    }
  }
}
