import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:xcnav/map_service.dart';

class MapSelector extends StatelessWidget {
  static const opacityLevels = [0.3, 0.6, 1.0];
  final MapTileSrc curLayer;
  final double curOpacity;
  final Function(MapTileSrc tileSrc, double opacity) onChanged;
  final bool leftAlign;

  const MapSelector({
    required this.curLayer,
    required this.curOpacity,
    required this.onChanged,
    super.key,
    required this.isMapDialOpen,
    this.leftAlign = false,
  });

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
                                    key: Key("mapSelector_${tileSrc.toString().split(".").last}_${(e * 100).toInt()}"),
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
                .toList());
  }
}
