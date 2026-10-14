import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/map_service.dart';
import 'package:xcnav/providers/adsb.dart';
import 'package:xcnav/widgets/map_button.dart';

/// Map layer button. Opens a dialog to pick the base map / opacity and toggle overlays.
class MapSelector extends StatelessWidget {
  static const opacityLevels = [0.3, 0.6, 1.0];
  final MapTileSrc curLayer;
  final double curOpacity;
  final Function(MapTileSrc tileSrc, double opacity) onChanged;
  final bool hideWaypoints;
  final bool hideWeatherObservations;
  final Function(bool hidden)? onChangedWaypoints;
  final Function(bool hidden)? onChangedWeatherObservations;
  final bool showAdsb;
  final double size;

  const MapSelector(
      {required this.curLayer,
      required this.curOpacity,
      required this.onChanged,
      super.key,
      this.hideWaypoints = false,
      this.hideWeatherObservations = false,
      this.onChangedWaypoints,
      this.onChangedWeatherObservations,
      this.showAdsb = false,
      this.size = 40});

  @override
  Widget build(BuildContext context) {
    return MapButton(
      size: size,
      selected: false,
      onPressed: () => showDialog(context: context, builder: (context) => _MapSelectorDialog(selector: this)),
      child: Center(child: Icon(Icons.layers_outlined, size: size * 4 / 7, color: Colors.black)),
    );
  }
}

class _MapSelectorDialog extends StatefulWidget {
  final MapSelector selector;

  const _MapSelectorDialog({required this.selector});

  @override
  State<_MapSelectorDialog> createState() => _MapSelectorDialogState();
}

class _MapSelectorDialogState extends State<_MapSelectorDialog> {
  late bool hideWaypoints = widget.selector.hideWaypoints;
  late bool hideWeatherObservations = widget.selector.hideWeatherObservations;

  Widget buildTileRow(MapTileSrc tileSrc) {
    final s = widget.selector;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ToggleButtons(
          isSelected: MapSelector.opacityLevels.map((e) => false).toList(),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderWidth: 1,
          borderColor: Colors.black45,
          onPressed: (index) {
            s.onChanged(tileSrc, MapSelector.opacityLevels[index]);
            Navigator.pop(context);
          },
          children: MapSelector.opacityLevels
              .map((e) => SizedBox(
                  key: Key("mapSelector_${tileSrc.toString().split(".").last}_${(e * 100).toInt()}"),
                  width: 60,
                  height: 48,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: Colors.white),
                      Opacity(opacity: e, child: mapTileThumbnails[tileSrc]),
                      if (s.curLayer == tileSrc && s.curOpacity == e)
                        const Icon(Icons.check_circle, color: Colors.black, size: 30)
                    ],
                  )))
              .toList()),
    );
  }

  Widget buildAdsbTile() {
    final adsb = Provider.of<ADSB>(context);
    final hasData = adsb.lastHeartbeat > DateTime.now().millisecondsSinceEpoch - 1000 * 60;
    return CheckboxListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: adsb.enabled,
      onChanged: (value) => adsb.enabled = value ?? false,
      title: const Text("ADSB-in"),
      subtitle: Text.rich(TextSpan(children: [
        WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: hasData
                ? const Icon(Icons.check, color: Colors.green)
                : const Icon(Icons.link_off, color: Colors.amber)),
        TextSpan(text: "  ${hasData ? "Connected".tr() : "No Data".tr()}"),
        if (!hasData)
          WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(left: 15),
                child: GestureDetector(
                    onTap: () => Navigator.popAndPushNamed(context, "/adsbHelp"),
                    child: const Icon(Icons.help, size: 20, color: Colors.lightBlue)),
              )),
      ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.selector;
    return AlertDialog(
      title: Text("Map Layers".tr()),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // - Sectional / Satellite / Topo
          ...[MapTileSrc.sectional, MapTileSrc.satellite, MapTileSrc.topo].map(buildTileRow),

          if (s.onChangedWaypoints != null)
            CheckboxListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text("Hide Waypoints".tr()),
                value: hideWaypoints,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => hideWaypoints = value);
                    s.onChangedWaypoints?.call(value);
                  }
                }),
          if (s.onChangedWeatherObservations != null)
            CheckboxListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text("Hide Wind".tr()),
                value: hideWeatherObservations,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => hideWeatherObservations = value);
                    s.onChangedWeatherObservations?.call(value);
                  }
                }),
          if (s.showAdsb) buildAdsbTile(),
        ]),
      ),
    );
  }
}
