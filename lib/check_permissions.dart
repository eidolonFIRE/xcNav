import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:xcnav/dialogs/request_location_always.dart';

bool currentlyCheckingPermissions = false;

Future<bool?> checkPermissions(BuildContext context) async {
  if (!currentlyCheckingPermissions) {
    currentlyCheckingPermissions = true;

    await Permission.notification.request();

    if (!await GeolocatorPlatform.instance.isLocationServiceEnabled()) {
      await Permission.location.request();
    }

    if (Platform.isIOS) {
      await Permission.camera.request();
      await Permission.photos.request();
      await Permission.locationWhenInUse.request();
      final locAlwaysStatus = await Permission.locationAlways.request();

      if (await Permission.locationAlways.isPermanentlyDenied || !locAlwaysStatus.isGranted) {
        debugPrint("Location was permanently denied, opening app settings.");
        await showDialog(context: context, builder: (context) => const RequestLocationDialog());
      }
    } else {
      debugPrint("Checking location permissions...");
      final whenInUse = await Permission.locationWhenInUse.status;
      if (whenInUse.isPermanentlyDenied) {
        debugPrint("Location was fully denied!");
        if (context.mounted) {
          await showDialog(context: context, builder: (context) => const RequestLocationDialog());
        }
        currentlyCheckingPermissions = false;
        return true;
      } else if (whenInUse.isDenied) {
        debugPrint("Location whenInUse was not granted!");
        final status = await Permission.locationWhenInUse.request();
        if (!status.isGranted) {
          currentlyCheckingPermissions = false;
          return true;
        }
      }
    }

    debugPrint("Location permissions all look good!");
    currentlyCheckingPermissions = false;
    return false;
  }
  return null;
}
