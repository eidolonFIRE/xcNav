import 'dart:async';

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

/// Singleton for queueing up messages to speak to users
class TtsService {
  final instance = FlutterTts();
  TtsState _state = TtsState.stopped;

  QueueList<AudioMessage> msgQueue = QueueList();

  TtsService() {
    instance.awaitSpeakCompletion(true);
    instance.setStartHandler(() {
      _state = TtsState.playing;
    });

    void waitAndTryNext() {
      _state = TtsState.stopped;
      Timer(const Duration(seconds: 2), _speakNextInQueue);
    }

    // Any time the messages stop, try playing the next one.
    instance.setCompletionHandler(waitAndTryNext);
    instance.setCancelHandler(waitAndTryNext);
    instance.setErrorHandler((_) => waitAndTryNext());
  }

  void _speakNextInQueue() {
    // debugPrint("Speak next in queue");
    if (msgQueue.isNotEmpty) {
      final msg = msgQueue.removeFirst();

      if (msg.expires == null || msg.expires!.isAfter(DateTime.now())) {
        instance.setVolume(msg.volume ?? 1.0);
        debugPrint("Speak: \"${msg.text}\"");
        instance.speak(msg.text);
      }
    } else {
      // debugPrint("Speak queue is empty");
    }
  }

  /// Queue up a message to be spoken
  void speak(AudioMessage msg) {
    if (msg.priority == 0) {
      msgQueue.addFirst(msg);
      instance.stop();
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

    // if nothing is playing... start it
    if (_state != TtsState.playing) _speakNextInQueue();
  }
}
