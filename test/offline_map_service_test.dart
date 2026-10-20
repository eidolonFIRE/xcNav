import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:xcnav/map_service.dart';
import 'package:xcnav/models/offline_area.dart';
import 'package:xcnav/services/offline_map_service.dart';

void main() {
  OfflineArea makeArea({List<LatLng>? outline, bool isPolygon = false}) => OfflineArea(
        id: "123",
        created: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        outline: outline ?? [LatLng(37.5, -122.5), LatLng(37.5, -122.0), LatLng(37.0, -122.0), LatLng(37.0, -122.5)],
        isPolygon: isPolygon,
        layers: [MapTileSrc.topo, MapTileSrc.sectional],
      );

  group("offlineAreaGeometry", () {
    test("rectangles are their bounding box, closed, lng first", () {
      final ring = (offlineAreaGeometry(makeArea())["coordinates"] as List).single as List;
      expect(ring.length, 5);
      expect(ring.first, ring.last);
      expect(ring.first, [-122.5, 37.5]);
      expect(ring[2], [-122.0, 37.0]);
    });

    test("polygons keep their shape", () {
      final triangle = [LatLng(37.5, -122.5), LatLng(37.5, -122.0), LatLng(37.0, -122.5)];
      final geometry = offlineAreaGeometry(makeArea(outline: triangle, isPolygon: true));
      expect(geometry["type"], "Polygon");
      final ring = (geometry["coordinates"] as List).single as List;
      expect(ring.length, 4);
      expect(ring[1], [-122.0, 37.5]);
      expect(ring.last, ring.first);
    });
  });

  test("region options: map layers bring their style, terrain is just its tileset", () {
    final area = makeArea();
    final jobs = area.planJobs();

    final topo = offlineRegionOptions(area, jobs.firstWhere((e) => e.src == MapTileSrc.topo));
    final topoDescriptor = topo.descriptorsOptions!.single!;
    expect(topoDescriptor.styleURI, mapStyleUri(MapTileSrc.topo));
    expect(topoDescriptor.minZoom, offlineMinZoom);
    expect(topoDescriptor.maxZoom, offlineMaxZoom(MapTileSrc.topo));
    expect(topoDescriptor.stylePackOptions, isNotNull);
    expect(topoDescriptor.tilesets, isNull);
    expect(topo.metadata, {"areaId": "123", "layer": "topo"});
    expect(topo.geometry, offlineAreaGeometry(area));

    final terrain = offlineRegionOptions(area, jobs.firstWhere((e) => e.isTerrain)).descriptorsOptions!.single!;
    expect(terrain.styleURI, "");
    expect(terrain.tilesets, [terrainTilesetUrl]);
    expect(terrain.stylePackOptions, isNull);
    expect(terrain.maxZoom, offlineTerrainMaxZoom);
  });

  test("region ids are per area and layer", () {
    expect(offlineRegionId("123", "topo"), isNot(offlineRegionId("123", "satellite")));
    expect(offlineRegionId("123", "topo"), isNot(offlineRegionId("124", "topo")));
  });
}
