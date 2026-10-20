import 'package:flutter_test/flutter_test.dart';

import 'package:xcnav/map_service.dart';

void main() {
  test("style overrides only change topo", () {
    expect(styleOverridesFor(MapTileSrc.topo), useMapTilerStyles ? topoStyleOverrides : outdoorsStyleOverrides);
    expect(styleOverridesFor(MapTileSrc.satellite), isEmpty);
    expect(styleOverridesFor(MapTileSrc.sectional), isEmpty);
  });

  test("Outdoors gets relief shading from the 3D terrain's elevation tiles, in place of its own", () {
    expect(styleAdditionsFor(MapTileSrc.satellite), isEmpty);
    if (useMapTilerStyles) {
      expect(styleAdditionsFor(MapTileSrc.topo), isEmpty);
      return;
    }
    final hillshade = styleAdditionsFor(MapTileSrc.topo).single;
    expect(hillshade.layer["type"], "hillshade");
    expect(hillshade.layer["source"], terrainSourceFor(MapTileSrc.topo).id);
    expect(hillshade.below, "hillshade");
    expect(outdoorsStyleOverrides["hillshade"], {"visibility": "none"});
  });

  test("hillshade exaggeration stays within Mapbox's 0 to 1", () {
    for (final expression in [
      topoStyleOverrides["Hillshade"]!["hillshade-exaggeration"],
      (outdoorsHillshade()["paint"] as Map)["hillshade-exaggeration"],
    ]) {
      // ["interpolate", ["linear"], ["zoom"], zoom, value, zoom, value, ...]
      final stops = (expression as List).sublist(3);
      for (int i = 1; i < stops.length; i += 2) {
        expect(stops[i] as num, inInclusiveRange(0, 1));
      }
    }
  });
}
