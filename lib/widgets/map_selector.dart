import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/map_service.dart';
import 'package:xcnav/providers/adsb.dart';

class MapSelector extends StatelessWidget {
  static const opacityLevels = [0.3, 0.6, 1.0];
  final MapTileSrc curLayer;
  final double curOpacity;
  final Function(MapTileSrc tileSrc, double opacity) onChanged;
  final bool hideWaypoints;
  final bool hideWeatherObservations;
  final Function(bool hidden)? onChangedWaypoints;
  final Function(bool hidden)? onChangedWeatherObservations;
  final bool leftAlign;
  final bool showAdsb;

  const MapSelector(
      {required this.curLayer,
      required this.curOpacity,
      required this.onChanged,
      super.key,
      required this.isMapDialOpen,
      this.leftAlign = false,
      this.hideWaypoints = false,
      this.hideWeatherObservations = false,
      this.onChangedWaypoints,
      this.onChangedWeatherObservations,
      this.showAdsb = false});

  final ValueNotifier<bool> isMapDialOpen;

  @override
  Widget build(BuildContext context) {
    return SpeedDial(
        icon: Icons.layers_outlined,
        iconTheme: const IconThemeData(size: 50, color: Colors.black87),
        buttonSize: const Size(40, 40),
        direction: SpeedDialDirection.down,
        renderOverlay: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        openCloseDial: isMapDialOpen,
        switchLabelPosition: leftAlign,
        children:
            // - Sectional / Satellite
            [MapTileSrc.sectional, MapTileSrc.satellite, MapTileSrc.topo]
                    .mapIndexed((layerIndex, tileSrc) => SpeedDialChild(
                            labelWidget: SizedBox(
                          height: 40,
                          child: ToggleButtons(
                              isSelected: opacityLevels.map((e) => false).toList(),
                              borderRadius: const BorderRadius.all(Radius.circular(12)),
                              borderWidth: 1,
                              borderColor: Colors.black45,
                              onPressed: ((index) {
                                onChanged(tileSrc, opacityLevels[index]);
                                isMapDialOpen.value = false;
                              }),
                              children: opacityLevels
                                  .map(
                                    (e) => SizedBox(
                                        key: Key(
                                            "mapSelector_${tileSrc.toString().split(".").last}_${(e * 100).toInt()}"),
                                        width: 50,
                                        height: 40,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            Container(
                                              color: Colors.white,
                                            ),
                                            Opacity(opacity: e, child: mapTileThumbnails[tileSrc]),
                                            if (curLayer == tileSrc && curOpacity == e)
                                              const Icon(
                                                Icons.check_circle,
                                                color: Colors.black,
                                                size: 30,
                                              )
                                          ],
                                        )),
                                  )
                                  .toList()),
                        )))
                    .toList() +
                [
                  if (onChangedWaypoints != null)
                    SpeedDialChild(
                        label: "Hide Waypoints".tr(),
                        child: Checkbox.adaptive(
                            value: hideWaypoints,
                            onChanged: (value) {
                              if (value != null) {
                                onChangedWaypoints?.call(value);
                                isMapDialOpen.value = false;
                              }
                            })),
                  if (onChangedWeatherObservations != null)
                    SpeedDialChild(
                        label: "Hide Wind".tr(),
                        child: Checkbox.adaptive(
                            value: hideWeatherObservations,
                            onChanged: (value) {
                              if (value != null) {
                                onChangedWeatherObservations?.call(value);
                                isMapDialOpen.value = false;
                              }
                            })),
                  if (showAdsb)
                    SpeedDialChild(
                      labelWidget: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text("ADSB-in"),
                              (Provider.of<ADSB>(context).lastHeartbeat >
                                      DateTime.now().millisecondsSinceEpoch - 1000 * 60)
                                  ? Text.rich(TextSpan(children: [
                                      WidgetSpan(
                                          alignment: PlaceholderAlignment.middle,
                                          child: Icon(
                                            Icons.check,
                                            color: Colors.green,
                                          )),
                                      TextSpan(text: "  ${"Connected".tr()}")
                                    ]))
                                  : Text.rich(TextSpan(children: [
                                      const WidgetSpan(
                                          alignment: PlaceholderAlignment.middle,
                                          child: Icon(
                                            Icons.link_off,
                                            color: Colors.amber,
                                          )),
                                      TextSpan(text: "  ${"No Data".tr()}"),
                                      WidgetSpan(
                                          alignment: PlaceholderAlignment.middle,
                                          child: Padding(
                                            padding: const EdgeInsets.only(left: 15),
                                            child: GestureDetector(
                                                onTap: () => {Navigator.popAndPushNamed(context, "/adsbHelp")},
                                                child: const Icon(Icons.help, size: 20, color: Colors.lightBlue)),
                                          )),
                                    ])),
                            ],
                          ),
                        ),
                      ),
                      child: Checkbox.adaptive(
                        value: Provider.of<ADSB>(context).enabled,
                        onChanged: (value) {
                          Provider.of<ADSB>(context, listen: false).enabled = value ?? false;
                          isMapDialOpen.value = false;
                        },
                      ),
                    ),
                ]);
  }
}
