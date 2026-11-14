import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';
import 'package:datadog_flutter_plugin/datadog_internal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/datadog.dart';

/// Mimics native RUM: one active view; starting a view ends the previous one.
class FakeRum extends Fake implements DatadogRum {
  final List<String> started = [];
  String? active;

  @override
  void startView(String key, [String? name, Map<String, Object?> attributes = const {}]) {
    started.add(key);
    active = key;
  }

  @override
  void stopView(String key, [Map<String, Object?> attributes = const {}]) {
    if (active == key) active = null;
  }

  @override
  void markViewFirstBuildComplete(String viewKey) {}
}

class FakePlatform extends Fake implements DatadogSdkPlatform {
  @override
  Future<void> updateTelemetryConfiguration(String property, bool value) async {}
}

class FakeSdk extends Fake implements DatadogSdk {
  FakeSdk(this.rum);

  @override
  final FakeRum rum;

  @override
  DatadogSdkPlatform get platform => FakePlatform();
}

void main() {
  late FakeRum rum;
  late RumNavigationObserver observer;
  final navKey = GlobalKey<NavigatorState>();
  final homeKey = GlobalKey();

  Future<void> pumpApp(WidgetTester tester) async {
    rum = FakeRum();
    observer = RumNavigationObserver(datadogSdk: FakeSdk(rum));
    homeViewName = "/home/Map";
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      navigatorObservers: [observer],
      initialRoute: "/home",
      routes: {
        "/home": (context) => Scaffold(key: homeKey, body: const Text("home")),
        "/settings": (context) => const Scaffold(body: Text("settings")),
      },
    ));
    await tester.pumpAndSettle();
  }

  BuildContext homeContext() => homeKey.currentContext!;

  void showUnnamedDialog() =>
      showDialog(context: homeContext(), builder: (context) => const AlertDialog(content: Text("unnamed")));

  void showNamedDialog() => showDialog(
      context: homeContext(),
      routeSettings: const RouteSettings(name: "/dialog/test"),
      builder: (context) => const AlertDialog(content: Text("named")));

  testWidgets("home route reports the selected tab", (tester) async {
    await pumpApp(tester);
    expect(rum.active, "/home/Map");

    homeViewName = "/home/Chat";
    observer.refreshView(ModalRoute.of(homeContext())!);
    expect(rum.active, "/home/Chat");
    expect(rum.started, ["/home/Map", "/home/Chat"]);
  });

  testWidgets("named routes and dialogs are views; home tab resumes on pop", (tester) async {
    await pumpApp(tester);

    navKey.currentState!.pushNamed("/settings");
    await tester.pumpAndSettle();
    expect(rum.active, "/settings");

    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(rum.active, "/home/Map");

    showNamedDialog();
    await tester.pumpAndSettle();
    expect(rum.active, "/dialog/test");

    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(rum.active, "/home/Map");
  });

  testWidgets("unnamed popups do not split the underlying view", (tester) async {
    await pumpApp(tester);

    showUnnamedDialog();
    await tester.pumpAndSettle();
    expect(rum.active, "/home/Map");

    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(rum.active, "/home/Map");
    expect(rum.started, ["/home/Map"]);
  });

  testWidgets("refreshView ignored when route is covered", (tester) async {
    await pumpApp(tester);
    navKey.currentState!.pushNamed("/settings");
    await tester.pumpAndSettle();

    homeViewName = "/home/Side";
    observer.refreshView(ModalRoute.of(homeContext())!);
    expect(rum.active, "/settings");

    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(rum.active, "/home/Side");
  });

  testWidgets("view resumes after a named route pushed from an unnamed popup closes", (tester) async {
    await pumpApp(tester);

    showUnnamedDialog();
    await tester.pumpAndSettle();
    navKey.currentState!.pushNamed("/settings");
    await tester.pumpAndSettle();
    expect(rum.active, "/settings");

    // Back onto the unnamed popup: no view.
    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(rum.active, isNull);

    // Close the popup: home view resumes.
    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(rum.active, "/home/Map");
  });
}
