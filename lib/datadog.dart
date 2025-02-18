import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';
import 'package:flutter/foundation.dart';

DatadogLogger? ddLogger;

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

void startView(String key) {
  DatadogSdk.instance.rum?.startView(key);
}

void stopView(String key) {
  DatadogSdk.instance.rum?.stopView(key);
}

void addCustomAction(String name, [Map<String, Object?> attributes = const {}]) {
  DatadogSdk.instance.rum?.addAction(RumActionType.custom, name, attributes);
}

void addTapAction(String name, [Map<String, Object?> attributes = const {}]) {
  DatadogSdk.instance.rum?.addAction(RumActionType.tap, name, attributes);
}
