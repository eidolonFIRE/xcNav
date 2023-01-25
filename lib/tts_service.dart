import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

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

  void _waitAndTryNext() {
    if (msgQueue.isNotEmpty) {
      Timer(const Duration(seconds: 1), speakNextInQueue);
    } else {
      _state = TtsState.stopped;
    }
  }

  Future init() async {
    instance = FlutterTts();

    if (Platform.isIOS) {
      await instance!.setSharedInstance(true);
      await instance!.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            // IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            // IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            // IosTextToSpeechAudioCategoryOptions.allowAirPlay,
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
            IosTextToSpeechAudioCategoryOptions.duckOthers,
            // IosTextToSpeechAudioCategoryOptions.interruptSpokenAudioAndMixWithOthers
          ],
          IosTextToSpeechAudioMode.spokenAudio);
    }

    // instance.getDefaultEngine.then((value) => instance.setEngine(value));
    // instance.getEngines.then((value) => debugPrint("Engines: $value"));
    await instance!.awaitSpeakCompletion(true);
    // instance.setStartHandler(() {
    //   _state = TtsState.playing;
    // });

    // Any time the messages stop, try playing the next one.
    // instance.setCompletionHandler(waitAndTryNext);
    // instance.setCancelHandler(waitAndTryNext);
    instance!.setErrorHandler((_) => _waitAndTryNext());
  }

  void speakNextInQueue() {
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
          instance!.speak(msg.text).then((_) => _waitAndTryNext());
        } else {
          // Msg was expired, try again
          speakNextInQueue();
        }
      } else {
        // debugPrint("Speak queue is empty");
        _state = TtsState.stopped;
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
    }

    debugPrint("Speak queue length: ${msgQueue.length}");

    // if nothing is playing... start it
    if (_state != TtsState.playing) {
      speakNextInQueue();
    }
  }
}
