import 'dart:async';

import 'package:collection/collection.dart';
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

/// Singleton for queueing up messages to speak to users
class TtsService {
  final instance = FlutterTts();
  TtsState state = TtsState.stopped;

  QueueList<AudioMessage> msgQueue = QueueList();

  TtsService() {
    instance.awaitSpeakCompletion(true);
    instance.setStartHandler(() {
      state = TtsState.playing;
    });

    void waitAndTryNext() {
      state = TtsState.stopped;
      Timer(const Duration(seconds: 3), _speakNextInQueue);
    }

    // Any time the messages stop, try playing the next one.
    instance.setCompletionHandler(waitAndTryNext);
    instance.setCancelHandler(waitAndTryNext);
    instance.setErrorHandler((_) => waitAndTryNext());
  }

  void _speakNextInQueue() {
    if (msgQueue.isNotEmpty) {
      final msg = msgQueue.removeFirst();

      if (msg.expires == null || msg.expires!.isAfter(DateTime.now())) {
        instance.setVolume(msg.volume ?? 1.0);
        instance.speak(msg.text);
      }
    }
  }

  /// Queue up a message to be spoken
  void speak(AudioMessage msg) {
    if (msg.priority == 0) {
      msgQueue.addFirst(msg);
      instance.stop();
    } else {
      // insertion
      for (int index = 0; index < msgQueue.length; index++) {
        if (msgQueue[index].priority > msg.priority || index == msgQueue.length - 1) {
          msgQueue.insert(index, msg);
          break;
        }
      }
    }

    if (state != TtsState.playing) _speakNextInQueue();
  }
}
