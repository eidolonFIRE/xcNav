import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/audio_cue_service.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/chat_messages.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:mockito/mockito.dart';

class MockMyTelemetry extends Mock implements MyTelemetry {
  @override
  MyTelemetry() {}
}

void main() {
  final cueService = AudioCueService(
    settings: Settings(),
    chatMessages: ChatMessages(),
    group: Group(),
    activePlan: ActivePlan(),
    profile: Profile(),
  );

  test('single pilot', () {
    expect(1, 1);
  });
}
