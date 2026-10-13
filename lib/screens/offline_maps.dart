import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'package:xcnav/map_service.dart';
import 'package:xcnav/models/offline_area.dart';
import 'package:xcnav/services/offline_map_service.dart';
import 'package:xcnav/util.dart';

class OfflineMaps extends StatelessWidget {
  const OfflineMaps({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("offline_maps.title".tr())),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, "/offlineAreaEditor"),
        icon: const Icon(Icons.add),
        label: Text("offline_maps.new_area".tr()),
      ),
      body: ListenableBuilder(
          listenable: offlineMapService,
          builder: (context, _) {
            if (offlineMapService.areas.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Text(
                    "offline_maps.empty".tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                  ),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.only(bottom: 80),
              children: offlineMapService.areas.reversed.map((area) => OfflineAreaCard(area)).toList(),
            );
          }),
    );
  }
}

class OfflineAreaCard extends StatelessWidget {
  final OfflineArea area;

  const OfflineAreaCard(this.area, {super.key});

  void _confirmDelete(BuildContext context) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text("dialog.confirm.sure".tr()),
              content: Text("offline_maps.confirm_delete".tr()),
              actions: [
                TextButton.icon(
                    onPressed: () {
                      offlineMapService.delete(area.id);
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: Text("btn.Delete".tr())),
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text("btn.Cancel".tr())),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    final outdated = area.isSectionalOutdated(vfrVersion);
    final active = offlineMapService.isActive(area.id);

    return Card(
      margin: const EdgeInsets.all(8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- Preview
          SizedBox(
            height: 120,
            child: IgnorePointer(
              child: FlutterMap(
                  options: MapOptions(
                    initialCameraFit:
                        CameraFit.bounds(bounds: padLatLngBounds(LatLngBounds.fromPoints(area.outline), 0.2)),
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                  ),
                  children: [
                    getMapTileLayer(area.layers.firstOrNull ?? MapTileSrc.topo),
                    PolygonLayer(polygons: [
                      Polygon(
                          points: area.outline,
                          color: Colors.blue.withAlpha(40),
                          borderColor: Colors.blue,
                          borderStrokeWidth: 2),
                    ]),
                  ]),
            ),
          ),

          ListTile(
            title: Text(DateFormat.yMMMd().add_jm().format(area.created), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text([
              area.layers.map((e) => "offline_maps.layer.${e.name}".tr()).join(", "),
              if (area.bytes > 0) asReadableSize(area.bytes.toDouble()),
            ].join("  ·  ")),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (area.status == OfflineAreaStatus.downloading || area.status == OfflineAreaStatus.queued)
                IconButton(
                    tooltip: "offline_maps.pause".tr(),
                    onPressed: () => offlineMapService.pause(area.id),
                    icon: const Icon(Icons.pause)),
              if (area.status == OfflineAreaStatus.paused || area.status == OfflineAreaStatus.failed)
                IconButton(
                    tooltip: "offline_maps.resume".tr(),
                    onPressed: () => offlineMapService.resume(area.id),
                    icon: const Icon(Icons.play_arrow, color: Colors.lightGreen)),
              if (outdated && area.status == OfflineAreaStatus.complete)
                IconButton(
                    tooltip: "offline_maps.update_sectional".tr(),
                    onPressed: () => offlineMapService.updateSectional(area.id),
                    icon: const Icon(Icons.update, color: Colors.amber)),
              IconButton(
                  tooltip: "btn.Delete".tr(),
                  onPressed: () => _confirmDelete(context),
                  icon: const Icon(Icons.delete, color: Colors.red)),
            ]),
          ),

          // --- Status / Progress
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: active
                ? ValueListenableBuilder(
                    valueListenable: offlineMapService.progress,
                    builder: (context, progress, _) => LinearProgressIndicator(value: progress?.fraction))
                : Text(
                    outdated && area.status == OfflineAreaStatus.complete
                        ? "offline_maps.sectional_outdated".tr()
                        : "offline_maps.status.${area.status.name}".tr(),
                    style: TextStyle(
                        color: switch (area.status) {
                      OfflineAreaStatus.complete => outdated ? Colors.amber : Colors.lightGreen,
                      OfflineAreaStatus.failed => Colors.red,
                      _ => Colors.grey,
                    }),
                  ),
          ),
        ],
      ),
    );
  }
}
