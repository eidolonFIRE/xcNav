import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/svg.dart';

import 'package:xcnav/settings_service.dart';
import 'package:xcnav/views/map/focus_mode.dart';
import 'package:xcnav/widgets/map_button.dart';

/// Column of map view buttons: compass / north-lock, focus me / group, zoom, and measurement.
class MapViewControls extends StatelessWidget {
  final MapController mapController;
  final bool mapReady;
  final FocusMode focusMode;
  final void Function(FocusMode mode) onSetFocusMode;
  final VoidCallback onToggleNorthLock;
  final VoidCallback onToggleMeasurement;

  /// Called after the user zooms with the buttons.
  final VoidCallback onZoom;

  const MapViewControls({
    super.key,
    required this.mapController,
    required this.mapReady,
    required this.focusMode,
    required this.onSetFocusMode,
    required this.onToggleNorthLock,
    required this.onToggleMeasurement,
    required this.onZoom,
  });

  void zoomBy(double delta) {
    mapController.move(mapController.camera.center, mapController.camera.zoom + delta);
    debugPrint("Map Zoom: ${mapController.camera.zoom}");
    onZoom();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constaints) {
      final buttonSize = max(30, min(60, constaints.maxHeight / 8)).toDouble();
      final connector = SizedBox(
          width: 2,
          height: buttonSize / 3,
          child: Container(
            color: Colors.black,
          ));

      return Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment:
              settingsMgr.mapControlsRightSide.value ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // --- Compass
            MapButton(
                size: buttonSize,
                onPressed: onToggleNorthLock,
                selected: false,
                child: Stack(fit: StackFit.expand, clipBehavior: Clip.none, children: [
                  StreamBuilder(
                      stream: mapController.mapEventStream,
                      builder: (context, event) => Container(
                            transformAlignment: const Alignment(0, 0),
                            transform: mapReady
                                ? Matrix4.rotationZ(mapController.camera.rotation * pi / 180)
                                : Matrix4.rotationZ(0),
                            child: settingsMgr.northlockMap.value
                                ? Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: SvgPicture.asset("assets/images/compass_north.svg"),
                                  )
                                : SvgPicture.asset("assets/images/compass.svg", fit: BoxFit.cover),
                          )),
                ])),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // --- Focus on Me
                MapButton(
                  size: buttonSize,
                  selected: focusMode == FocusMode.me,
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Padding(
                      padding: const EdgeInsets.all(2.0),
                      child: SvgPicture.asset("assets/images/icon_controls_centermap_me.svg"),
                    ),
                  ),
                  onPressed: () => onSetFocusMode(FocusMode.me),
                ),
                connector,
                // --- Focus on Group
                MapButton(
                  size: buttonSize,
                  selected: focusMode == FocusMode.group,
                  onPressed: () => onSetFocusMode(FocusMode.group),
                  child: Padding(
                    padding: const EdgeInsets.all(3.0),
                    child: SvgPicture.asset("assets/images/icon_controls_centermap_group.svg"),
                  ),
                ),
              ],
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              // --- Zoom In (+)
              MapButton(
                size: buttonSize,
                selected: false,
                onPressed: () => zoomBy(1),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: SvgPicture.asset("assets/images/icon_controls_zoom_in.svg"),
                ),
              ),
              connector,
              // --- Zoom Out (-)
              MapButton(
                size: buttonSize,
                selected: false,
                onPressed: () => zoomBy(-1),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: SvgPicture.asset("assets/images/icon_controls_zoom_out.svg"),
                ),
              ),
            ]),

            // --- Measurement
            MapButton(
              size: buttonSize,
              onPressed: onToggleMeasurement,
              selected: false,
              child: Icon(
                focusMode == FocusMode.measurement ? Icons.cancel : Icons.straighten,
                size: 30,
                color: focusMode == FocusMode.measurement ? Colors.red : Colors.black,
              ),
            )
          ]);
    });
  }
}
