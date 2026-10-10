import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/models/flight_detector.dart';

void main() {
  group("isLaunchCandidate", () {
    test("defaults match original behavior", () {
      const config = LaunchDetectorConfig();
      // Too slow / too fast
      expect(config.isLaunchCandidate(speed: 3, agl: 100, vario: 3), false);
      expect(config.isLaunchCandidate(speed: 30, agl: 100, vario: 3), false);
      // High enough
      expect(config.isLaunchCandidate(speed: 10, agl: 50, vario: 0), true);
      // Low but climbing
      expect(config.isLaunchCandidate(speed: 10, agl: 5, vario: 2), true);
      // Low and not climbing
      expect(config.isLaunchCandidate(speed: 10, agl: 5, vario: 0), false);
      // No ground data
      expect(config.isLaunchCandidate(speed: 10, agl: null, vario: 0), true);
    });

    test("custom thresholds", () {
      const config = LaunchDetectorConfig(minSpeed: 2, maxSpeed: 15, minAgl: 10, minVario: 0.5);
      expect(config.isLaunchCandidate(speed: 3, agl: 15, vario: 0), true);
      expect(config.isLaunchCandidate(speed: 16, agl: 15, vario: 0), false);
      expect(config.isLaunchCandidate(speed: 5, agl: 5, vario: 0.6), true);
      expect(config.isLaunchCandidate(speed: 5, agl: 5, vario: 0.4), false);
    });

    test("agl disabled", () {
      const config = LaunchDetectorConfig(useAgl: false);
      expect(config.isLaunchCandidate(speed: 10, agl: 100, vario: 0), false);
      expect(config.isLaunchCandidate(speed: 10, agl: null, vario: 0), false);
      expect(config.isLaunchCandidate(speed: 10, agl: 0, vario: 2), true);
    });

    test("vario disabled", () {
      const config = LaunchDetectorConfig(useVario: false);
      expect(config.isLaunchCandidate(speed: 10, agl: 5, vario: 5), false);
      expect(config.isLaunchCandidate(speed: 10, agl: 50, vario: 0), true);
    });

    test("both disabled is speed only", () {
      const config = LaunchDetectorConfig(useAgl: false, useVario: false);
      expect(config.isLaunchCandidate(speed: 10, agl: 0, vario: 0), true);
      expect(config.isLaunchCandidate(speed: 2, agl: 0, vario: 0), false);
    });
  });

  group("shouldLaunch", () {
    test("hold time", () {
      const config = LaunchDetectorConfig(holdTime: Duration(seconds: 5));
      expect(config.shouldLaunch(triggerHystMs: 4000, sp140Armed: null), false);
      expect(config.shouldLaunch(triggerHystMs: 6000, sp140Armed: null), true);
    });

    test("sp140 armed toggle", () {
      expect(const LaunchDetectorConfig().shouldLaunch(triggerHystMs: 0, sp140Armed: true), true);
      expect(const LaunchDetectorConfig(useSp140Armed: false).shouldLaunch(triggerHystMs: 0, sp140Armed: true), false);
      expect(const LaunchDetectorConfig().shouldLaunch(triggerHystMs: 0, sp140Armed: false), false);
    });
  });

  group("isLandingCandidate", () {
    test("defaults match original behavior", () {
      const config = LandingDetectorConfig();
      expect(config.isLandingCandidate(speed: 1, agl: 10, vario: 0), true);
      // Moving
      expect(config.isLandingCandidate(speed: 2, agl: 10, vario: 0), false);
      // Climbing / sinking
      expect(config.isLandingCandidate(speed: 1, agl: 10, vario: 0.5), false);
      expect(config.isLandingCandidate(speed: 1, agl: 10, vario: -0.5), false);
      // High up (hovering into wind)
      expect(config.isLandingCandidate(speed: 1, agl: 150, vario: 0), false);
      // No ground data
      expect(config.isLandingCandidate(speed: 1, agl: null, vario: 0), true);
    });

    test("toggles", () {
      expect(const LandingDetectorConfig(useVario: false).isLandingCandidate(speed: 1, agl: 10, vario: 2), true);
      expect(const LandingDetectorConfig(useAgl: false).isLandingCandidate(speed: 1, agl: 500, vario: 0), true);
    });

    test("custom thresholds", () {
      const config = LandingDetectorConfig(maxSpeed: 3, maxVario: 1, maxAgl: 20);
      expect(config.isLandingCandidate(speed: 2.5, agl: 10, vario: 0.8), true);
      expect(config.isLandingCandidate(speed: 2.5, agl: 25, vario: 0), false);
    });
  });

  group("shouldLand", () {
    test("hold time", () {
      const config = LandingDetectorConfig(holdTime: Duration(seconds: 5));
      expect(config.shouldLand(triggerHystMs: 4000, sp140Armed: null), false);
      expect(config.shouldLand(triggerHystMs: 6000, sp140Armed: null), true);
    });

    test("sp140 armed toggle", () {
      expect(const LandingDetectorConfig().shouldLand(triggerHystMs: 30000, sp140Armed: true), false);
      expect(const LandingDetectorConfig(useSp140Armed: false).shouldLand(triggerHystMs: 30000, sp140Armed: true), true);
    });
  });
}
