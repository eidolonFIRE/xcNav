import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/audio_cue_service.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/chat_messages.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:mockito/mockito.dart';
import 'package:xcnav/tts_service.dart';

class MockTtsService extends TtsService {
  final List<AudioMessage> spoken = [];
  MockTtsService();

  @override
  void speak(AudioMessage msg) {
    spoken.add(msg);
    print(msg.text);
  }
}

void main() {
  late AudioCueService cueService;
  late Geo myGeo;
  late MockTtsService ttsService;

  // Common Setup
  setUpAll(() {
    ttsService = MockTtsService();

    myGeo = Geo.fromValues(-37, 122, 100, 0, 0, 0, 0);

    cueService = AudioCueService(
      ttsService: ttsService,
      settings: Settings(),
      chatMessages: ChatMessages(),
      group: Group(),
      activePlan: ActivePlan(),
      profile: Profile(),
    );
  });

  test('single pilot', () {
    // TODO: finish making unit tests for this
    // cueService.cueFuel(myGeo, 10, Duration(minutes: 10));
    // expect("", ttsService.spoken.last.text);
  });
}
