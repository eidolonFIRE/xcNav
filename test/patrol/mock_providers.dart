import 'package:flutter_map/plugin_api.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:flutter_test/flutter_test.dart';

// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:permission_handler/permission_handler.dart' as perm_handler;
// ignore: depend_on_referenced_packages
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart' as perm_handler_plat;

import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/plans.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/settings.dart';

Position get mockPosition => Position(
    latitude: 37,
    longitude: -121,
    timestamp: DateTime.fromMillisecondsSinceEpoch(
      500,
      isUtc: true,
    ),
    altitude: 0.0,
    accuracy: 0.0,
    heading: 0.0,
    speed: 0.0,
    speedAccuracy: 0.0);

class MockGeolocatorPlatform extends Mock
    with
        // ignore: prefer_mixin
        MockPlatformInterfaceMixin
    implements
        GeolocatorPlatform {
  @override
  Future<LocationPermission> checkPermission() => Future.value(LocationPermission.whileInUse);

  @override
  Future<LocationPermission> requestPermission() => Future.value(LocationPermission.whileInUse);

  @override
  Future<bool> isLocationServiceEnabled() => Future.value(true);

  @override
  Future<Position> getLastKnownPosition({
    bool forceLocationManager = false,
  }) =>
      Future.value(mockPosition);

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) =>
      Future.value(mockPosition);

  @override
  Stream<ServiceStatus> getServiceStatusStream() {
    return super.noSuchMethod(
      Invocation.method(
        #getServiceStatusStream,
        null,
      ),
      returnValue: Stream.value(ServiceStatus.enabled),
    );
  }

  @override
  Stream<Position> getPositionStream({
    LocationSettings? locationSettings,
  }) {
    return super.noSuchMethod(
      Invocation.method(
        #getPositionStream,
        null,
        <Symbol, Object?>{
          #desiredAccuracy: locationSettings?.accuracy ?? LocationAccuracy.best,
          #distanceFilter: locationSettings?.distanceFilter ?? 0,
          #timeLimit: locationSettings?.timeLimit ?? 0,
        },
      ),
      returnValue: Stream.value(mockPosition),
    );
  }

  @override
  Future<bool> openAppSettings() => Future.value(true);

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() => Future.value(LocationAccuracyStatus.reduced);

  @override
  Future<LocationAccuracyStatus> requestTemporaryFullAccuracy({
    required String purposeKey,
  }) =>
      Future.value(LocationAccuracyStatus.reduced);

  @override
  Future<bool> openLocationSettings() => Future.value(true);
}

class MockPermissionHandlerPlatform extends Mock
    with
        // ignore: prefer_mixin
        MockPlatformInterfaceMixin
    implements
        perm_handler_plat.PermissionHandlerPlatform {
  @override
  Future<perm_handler.PermissionStatus> checkPermissionStatus(perm_handler.Permission permission) =>
      Future.value(perm_handler.PermissionStatus.granted);

  @override
  Future<perm_handler.ServiceStatus> checkServiceStatus(perm_handler.Permission permission) =>
      Future.value(perm_handler.ServiceStatus.enabled);

  @override
  Future<bool> openAppSettings() => Future.value(true);

  @override
  Future<Map<perm_handler.Permission, perm_handler.PermissionStatus>> requestPermissions(
      List<perm_handler.Permission> permissions) {
    var permissionsMap = <perm_handler.Permission, perm_handler.PermissionStatus>{};
    return Future.value(permissionsMap);
  }

  @override
  Future<bool> shouldShowRequestPermissionRationale(perm_handler.Permission? permission) {
    return super.noSuchMethod(
      Invocation.method(
        #shouldShowPermissionRationale,
        [permission],
      ),
      returnValue: Future.value(true),
    );
  }
}

class MockClient extends Client {
  MockClient(globalContext) : super(globalContext);

  @override
  void connect() async {
    state = ClientState.connected;
    Profile profile = Provider.of<Profile>(globalContext, listen: false);
    if (Profile.nameValidator(profile.name) == null) {
      authenticate(profile);
    }

    // Watch updates to Profile
    Provider.of<Profile>(globalContext, listen: false).addListener(() {
      Profile profile = Provider.of<Profile>(globalContext, listen: false);
      if (state == ClientState.connected) {
        authenticate(profile);
      } else if (state == ClientState.authenticated && profile.name != null) {
        // Just need to update server with new profile
        pushProfile(profile);
      }
    });

    // Register Callbacks to waypoints
    Provider.of<ActivePlan>(globalContext, listen: false).onWaypointAction = waypointsUpdate;
    Provider.of<ActivePlan>(globalContext, listen: false).onSelectWaypoint = selectWaypoint;
  }
}

class MockSettings extends Settings {
  @override
  TileProvider? makeTileProvider(instanceName) => null;
}

class MockPlans extends Plans {
  @override
  Future savePlanToFile(String name) {
    return Future.value(null);
  }
}
