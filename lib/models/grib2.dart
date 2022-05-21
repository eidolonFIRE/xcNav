import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/material.dart';

class GridConfig {
  final int numX;
  final int numY;
  final double la1;
  final double lo1;
  final double dX;
  final double dY;
  final double latRef;
  GridConfig({
    required this.numX,
    required this.numY,
    required this.la1,
    required this.lo1,
    required this.dX,
    required this.dY,
    required this.latRef,
  });
}

class Section {
  final int start;
  final int end;
  String? product;
  GridConfig? gridConfig;

  /// Isobaric Surface (Pa)
  double? baroElev;
  List<List<double>>? data;

  Uint8List offsetData(Uint8List _data) => _data.sublist(start, end);

  Section(this.start, this.end);
}

const Map<String, String> lutProduct = {
  "0,0": "TMP", // Temperature
  "0,6": "DPT", // Dewpoint
  "2,2": "UGRD", // Wind "U" velocity
  "2,3": "VGRD", // Wind "V" velocity
};

const Map<int, String> lutSurfaceType = {
  0: "Reserved",
  1: "Ground or Water Surface",
  2: "Cloud Base Level",
  3: "Level of Cloud Tops",
  4: "Level of 0o C Isotherm",
  5: "Level of Adiabatic Condensation Lifted from the Surface",
  6: "Maximum Wind Level",
  7: "Tropopause",
  8: "Nominal Top of the Atmosphere",
  9: "Sea Bottom",
  10: "Entire Atmosphere",
  11: "Cumulonimbus Base (CB) 	m",
  12: "Cumulonimbus Top (CT) 	m",
  13: "Lowest level where vertically integrated cloud cover exceeds the specified percentage (cloud base for a given percentage cloud cover) 	%",
  14: "Level of free convection (LFC)",
  15: "Convection condensation level (CCL)",
  16: "Level of neutral buoyancy or equilibrium (LNB)",
  20: "Isothermal Level	K",
  21: "Lowest level where mass density exceeds the specified value(base for a given threshold of mass density) 	kg m-3",
  22: "Highest level where mass density exceeds the specified value (top for a given threshold of mass density) 	kg m-3",
  23: "Lowest level where air concentration exceeds the specified value (base for a given threshold of air concentration 	Bq m-3",
  24: "Highest level where air concentration exceeds the specified value (top for a given threshold of air concentration) 	Bq m-3",
  25: "Highest level where radar reflectivity exceeds the specified value (echo top for a given threshold of reflectivity) 	dBZ",
  100: "Isobaric Surface	Pa",
  101: "Mean Sea Level",
  102: "Specific Altitude Above Mean Sea Level	m",
  103: "Specified Height Level Above Ground	m",
  104: "Sigma Level",
  105: "Hybrid Level",
  106: "Depth Below Land Surface	m",
  107: "Isentropic (theta) Level	K",
  108: "Level at Specified Pressure Difference from Ground to Level	Pa",
  109: "Potential Vorticity Surface	K m2 kg-1 s-1",
  110: "Reserved",
  111: "Eta Level",
  112: "Reserved",
  113: "Logarithmic Hybrid Level",
  114: "Snow Level 	Numeric",
  115: "Sigma height level (see Note 4)",
  116: "Reserved",
  117: "Mixed Layer Depth	m",
  118: "Hybrid Height Level",
  119: "Hybrid Pressure Level",
  150: "Generalized Vertical Height Coordinate (see Note 4)",
  151: "Soil level (See Note 5) 	Numeric",
  160: "Depth Below Sea Level	m",
  161: "Depth Below Water Surface 	m",
  162: "Lake or River Bottom",
  163: "Bottom Of Sediment Layer",
  164: "Bottom Of Thermally Active Sediment Layer",
  165: "Bottom Of Sediment Layer Penetrated By Thermal Wave",
  166: "Mixing Layer",
  167: "Bottom of Root Zone",
  168: "Ocean Model Level 	Numeric",
  169:
      "Ocean level defined by water density (sigma-theta) difference from near-surface to level (see Note 7) 	kg m-3",
  170:
      "Ocean level defined by water potential temperature difference from near-surface to level (see Note 7) 	K",
  174: "Top Surface of Ice on Sea, Lake or River",
  175: "Top Surface of Ice, under Snow, on Sea, Lake or River",
  176: "Bottom Surface (underside) Ice on Sea, Lake or River",
  177: "Deep Soil (of indefinite depth)",
  178: "Reserved",
  179: "Top Surface of Glacier Ice and Inland Ice",
  180: "Deep Inland or Glacier Ice (of indefinite depth)",
  181: "Grid Tile Land Fraction as a Model Surface",
  182: "Grid Tile Water Fraction as a Model Surface",
  183: "Grid Tile Ice Fraction on Sea, Lake or River as a Model Surface",
  184: "Grid Tile Glacier Ice and Inland Ice Fraction as a Model Surface",
  200: "Entire atmosphere (considered as a single layer)",
  201: "Entire ocean (considered as a single layer)",
  204: "Highest tropospheric freezing level",
  206: "Grid scale cloud bottom level",
  207: "Grid scale cloud top level",
  209: "Boundary layer cloud bottom level",
  210: "Boundary layer cloud top level",
  211: "Boundary layer cloud layer",
  212: "Low cloud bottom level",
  213: "Low cloud top level",
  214: "Low cloud layer",
  215: "Cloud ceiling",
  216: "Effective Layer Top Level 	m",
  217: "Effective Layer Bottom Level 	m",
  218: "Effective Layer 	m",
  220: "Planetary Boundary Layer",
  221: "Layer Between Two Hybrid Levels",
  222: "Middle cloud bottom level",
  223: "Middle cloud top level",
  224: "Middle cloud layer",
  232: "High cloud bottom level",
  233: "High cloud top level",
  234: "High cloud layer",
  235: "Ocean Isotherm Level (1/10 ° C)",
  236: "Layer between two depths below ocean surface",
  237: "Bottom of Ocean Mixed Layer (m)",
  238: "Bottom of Ocean Isothermal Layer (m)",
  239: "Layer Ocean Surface and 26C Ocean Isothermal Level",
  240: "Ocean Mixed Layer",
  241: "Ordered Sequence of Data",
  242: "Convective cloud bottom level",
  243: "Convective cloud top level",
  244: "Convective cloud layer",
  245: "Lowest level of the wet bulb zero",
  246: "Maximum equivalent potential temperature level",
  247: "Equilibrium level",
  248: "Shallow convective cloud bottom level",
  249: "Shallow convective cloud top level",
  251: "Deep convective cloud bottom level",
  252: "Deep convective cloud top level",
  253: "Lowest bottom level of supercooled liquid water layer",
  254: "Highest top level of supercooled liquid water layer",
};

int _int32(int i, Uint8List d) =>
    (d[i] << 24) + (d[i + 1] << 16) + (d[i + 2] << 8) + (d[i + 3]);

List<Section> parseRawFile(Uint8List data) {
  List<Section> sections = [];

  // Find "GRIB" sections
  int _sectionStart = 0;
  int _sectionEnd = 0;
  for (int i = 0; i < data.length - 3; i++) {
    if (String.fromCharCodes(data.sublist(i, min(i + 4, data.length - 1))) ==
        "GRIB") _sectionStart = i;
    if (String.fromCharCodes(data.sublist(i, min(i + 4, data.length - 1))) ==
        "7777") {
      _sectionEnd = i;
      sections.add(Section(_sectionStart, _sectionEnd));
      // debugPrint("Section: $_sectionStart - $_sectionEnd");
    }
  }

  // Process Each GRIB section
  for (var _s in sections) {
    // debugPrint("\n=== Section: ${_s.start} (${_s.end - _s.start})");
    // debugPrint("GRIB version: ${_s.offsetData(data)[7]}");
    var d = _s.offsetData(data).sublist(16);

    // --- Identification
    // debugPrint("--- ${d[4]}) Identification (${_int32(0, d)})");
    final timestamp =
        DateTime((d[12] << 8) + (d[13]), d[14], d[15], d[16], d[17], d[18]);
    // debugPrint("Date: ${timestamp.toString()}");
    d = d.sublist(_int32(0, d));

    // --- Grid Definition
    // debugPrint("--- ${d[4]}) Grid Definition (${_int32(0, d)})");
    if (d[4] == 3) {
      //
    } else {
      // debugPrint("Expected Grid Definition");
      continue;
    }
    final gridTemplate = (d[12] << 8) + d[13];

    if (gridTemplate == 30) {
      // debugPrint("Grid Template: ${gridTemplate}");
    } else {
      // debugPrint("Unsupported Grid Template (${gridTemplate})");
      continue;
    }
    int numX = _int32(30, d);
    int numY = _int32(34, d);
    double la1 = _int32(38, d) * 10e-7;
    double lo1 = _int32(42, d) * 10e-7 - 360;
    double dX = _int32(55, d) * 10e-3;
    double dY = _int32(59, d) * 10e-3;
    double latRef = _int32(47, d) * 10e-7;
    // debugPrint("Grid: $numX x $numY");
    // debugPrint("Origin LatLng: $la1, $lo1");
    // debugPrint("Grid step size: $dX x $dY");
    // debugPrint("Latitude Ref: $latRef");
    // debugPrint("Project Center Mode: ${d[63].toRadixString(2)}");
    // debugPrint("Scanning Mode: ${d[64].toRadixString(2)}");

    // debugPrint("Meridian 1: ${_int32(65, d) * 10e-7}");
    // debugPrint("Meridian 2: ${_int32(65, d) * 10e-7}");

    _s.gridConfig = GridConfig(
        numX: numX,
        numY: numY,
        la1: la1,
        lo1: lo1,
        dX: dX,
        dY: dY,
        latRef: latRef);

    d = d.sublist(_int32(0, d));

    // --- Product Definition
    // debugPrint("--- ${d[4]}) Product Definition (${_int32(0, d)})");
    if (d[4] == 4) {
      // debugPrint("product table type: ${(d[7] << 8) + d[8]}");
    } else {
      // debugPrint("Unknown Layer Type");
      continue;
    }
    final prodCat = d[9];
    final prodParam = d[10];
    final prodName =
        lutProduct[prodCat.toString() + "," + prodParam.toString()] ??
            "Unknown";

    // debugPrint("Surface Type: ${lutSurfaceType[d[22]] ?? "Unknown"}");

    // debugPrint("Surface offset: ${(d[5] << 8) + d[6]}");
    final scale = d[23];
    final scaleV = _int32(24, d) / pow(10, scale);
    // debugPrint("Surface height: $scaleV");

    // debugPrint("Product: $prodName ($prodCat, $prodParam)");

    d = d.sublist(_int32(0, d));

    // --- Data Representation
    // debugPrint("--- ${d[4]}) Data Representation (${_int32(0, d)})");
    if (d[4] == 5) {
      // final numPoints = _int32(5, d);
      // debugPrint("Grid Type: ${(d[9] << 8) + d[10]}");
    } else {
      // debugPrint("Expected Data Representation Section");
      continue;
    }

    final refValue = ByteData.sublistView(d.sublist(11, 11 + 4)).getFloat32(0);
    final binScale = (d[15] << 8) + d[16];
    final decScale = (d[17] << 8) + d[18];
    final bitWidth = d[19];
    final dataType = d[20] == 0 ? "Float" : "Int";
    // debugPrint("Grid Config... Ref:$refValue, Bin:$binScale, Dec:$decScale, BW:$bitWidth, DT:$dataType");

    d = d.sublist(_int32(0, d));

    // --- Bitmap header
    // debugPrint("--- ${d[4]}) Bitmap Header (${_int32(0, d)})");
    if (d[4] == 6 && d[5] == 255) {
      d = d.sublist(_int32(0, d));
    } else {
      // debugPrint("Expected a bitmap header");
      continue;
    }

    // --- Bitmap data
    // debugPrint("--- ${d[4]}) Bitmap Data (${_int32(0, d)})");
    if (d[4] == 7) {
      //
    } else {
      // debugPrint("Expected bitmap data");
      continue;
    }
    final bitmapLen = _int32(0, d) - 5;
    // debugPrint("Bitmap: $bitmapLen bytes");

    d = d.sublist(5);

    // --- Parse bitmap values
    if (bitmapLen > 0) {
      int mask(int width) => ((0x1 << width) - 1);
      List<List<double>> bitmap = [];
      int bitOffset = 0;
      for (int y = 0; y < numY; y++) {
        bitmap.add([]);
        for (int x = 0; x < numX; x++) {
          int v = 0;
          int bitRem = bitWidth;
          while (bitRem > 0) {
            // final sGap = bitOffset % 8; // gap ahead
            final eGap = max(0, 8 - ((bitOffset % 8) + bitRem)); // gap after
            final bitsToConsume = min(bitRem, 8 - (bitOffset % 8));

            v = v << bitsToConsume;
            v |= (d[(bitOffset / 8).floor()] >> eGap) & mask(bitsToConsume);

            bitRem -= bitsToConsume;
            bitOffset += bitsToConsume;
          }

          double fv =
              ((v + refValue) / pow(10.0, decScale) * pow(2.0, binScale));

          // K to F: (K - 273.15) × 9/5 + 32
          // K to C: K - 273.15

          if (prodCat == 0) {
            // Convert K to F
            fv = (fv - 273.15) * 9 / 5 + 32;
          }

          bitmap.last.add(fv);
        }
      }

      for (var each in bitmap) {
        String line =
            each.map((e) => e.toStringAsFixed(1).padLeft(7)).toList().join(" ");
        // debugPrint(line);
      }

      _s.product = prodName;
      _s.baroElev = scaleV / 100;
      _s.data = bitmap;
    }
  }
  return sections;
}
