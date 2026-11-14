import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';
import 'package:flutter/widgets.dart';

DatadogLogger? ddLogger;

/// Single app-wide RUM navigation observer. Null when the user opted out of RUM.
RumNavigationObserver? rumObserver;

/// RUM view name reported for the "/home" route. Tracks the selected home tab.
String homeViewName = "/home/Map";

/// RUM view tracking for routes.
///
/// - Named routes become RUM views. "/home" reports [homeViewName] so each home tab gets its own view.
/// - Dialogs are tracked only when shown with `routeSettings: RouteSettings(name: "/dialog/...")`.
/// - Unnamed popups (menus, dropdowns, confirm dialogs) are ignored, so time keeps accruing to the
///   screen underneath instead of fragmenting its view.
/// - App background / foreground stops and resumes the current view (handled by the base class).
class RumNavigationObserver extends DatadogNavigationObserver {
  RumNavigationObserver({required super.datadogSdk}) : super(viewInfoExtractor: extractViewInfo);

  /// Set when a tracked route was popped back onto an ignored popup (no active view).
  /// The view underneath resumes once that popup closes.
  bool _resumeOnPopupClose = false;

  static RumViewInfo? extractViewInfo(Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null) return null;
    if (name == "/home") return RumViewInfo(name: homeViewName);
    return RumViewInfo(name: name);
  }

  static bool isIgnored(Route<dynamic>? route) => route is PopupRoute && route.settings.name == null;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (isIgnored(route)) return;
    _resumeOnPopupClose = false;
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (isIgnored(route)) {
      if (_resumeOnPopupClose && !isIgnored(previousRoute)) {
        _resumeOnPopupClose = false;
        super.didPop(route, previousRoute);
      }
      return;
    }
    _resumeOnPopupClose = isIgnored(previousRoute);
    super.didPop(route, previousRoute);
  }

  /// Restart the RUM view for [route] after its view name changed (e.g. home tab switch).
  /// Does nothing if [route] is covered by another route.
  void refreshView(Route<dynamic> route) {
    if (route.isCurrent) didReplace(newRoute: route, oldRoute: route);
  }
}

void error(String message,
    {String? errorMessage,
    String? errorKind,
    StackTrace? errorStackTrace,
    Map<String, Object?> attributes = const {}}) {
  DatadogSdk.instance.rum?.addErrorInfo("$message : ${errorMessage ?? '(report)'}", RumErrorSource.source,
      stackTrace: errorStackTrace, errorType: errorKind, attributes: attributes);
  ddLogger?.error(message,
      errorMessage: errorMessage, errorKind: errorKind, errorStackTrace: errorStackTrace, attributes: attributes);
  debugPrint("Error: $message : ${errorMessage ?? '(report)'}");
}

void warn(String message,
    {String? errorKind, StackTrace? errorStackTrace, Map<String, Object?> attributes = const {}}) {
  ddLogger?.warn(message, errorKind: errorKind, errorStackTrace: errorStackTrace, attributes: attributes);
  debugPrint("Warn: $message");
}

void info(String message,
    {String? errorMessage,
    String? errorKind,
    StackTrace? errorStackTrace,
    Map<String, Object?> attributes = const {}}) {
  ddLogger?.info(message,
      errorMessage: errorMessage, errorKind: errorKind, errorStackTrace: errorStackTrace, attributes: attributes);
  debugPrint("Info: $message : $errorMessage");
}

void addAttribute(String key, dynamic value) {
  DatadogSdk.instance.rum?.addAttribute(key, value);
}

void addCustomAction(String name, [Map<String, Object?> attributes = const {}]) {
  DatadogSdk.instance.rum?.addAction(RumActionType.custom, name, attributes);
}

void addTapAction(String name, [Map<String, Object?> attributes = const {}]) {
  DatadogSdk.instance.rum?.addAction(RumActionType.tap, name, attributes);
}
