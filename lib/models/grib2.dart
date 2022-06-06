import 'dart:typed_data';
import 'dart:math';

// import 'package:flutter/material.dart';

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
  "1,1": "RH", // Relative Humidity
  "2,2": "UGRD", // Wind "U" velocity
  "2,3": "VGRD", // Wind "V" velocity
};

int _int32(int i, Uint8List d) => (d[i] << 24) + (d[i + 1] << 16) + (d[i + 2] << 8) + (d[i + 3]);

List<Section> parseRawFile(Uint8List data) {
  List<Section> sections = [];

  // Find "GRIB" sections
  int _sectionStart = 0;
  int _sectionEnd = 0;
  for (int i = 0; i < data.length; i++) {
    if (String.fromCharCodes(data.sublist(i, min(i + 4, data.length - 1))) == "GRIB") _sectionStart = i;
    if (i == data.length - 1 || String.fromCharCodes(data.sublist(i, min(i + 8, data.length - 1))) == "7777GRIB") {
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
    // final timestamp = DateTime((d[12] << 8) + (d[13]), d[14], d[15], d[16], d[17], d[18]);
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
    double dX = _int32(55, d) * 10e-4;
    double dY = _int32(59, d) * 10e-4;
    double latRef = _int32(47, d) * 10e-7;
    // debugPrint("Grid: $numX x $numY");
    // debugPrint("Origin LatLng: $la1, $lo1");
    // debugPrint("Grid step size: $dX x $dY");
    // debugPrint("Latitude Ref: $latRef");
    // debugPrint("Project Center Mode: ${d[63].toRadixString(2)}");
    // debugPrint("Scanning Mode: ${d[64].toRadixString(2)}");

    // debugPrint("Meridian 1: ${_int32(65, d) * 10e-7}");
    // debugPrint("Meridian 2: ${_int32(65, d) * 10e-7}");

    _s.gridConfig = GridConfig(numX: numX, numY: numY, la1: la1, lo1: lo1, dX: dX, dY: dY, latRef: latRef);

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
    final prodName = lutProduct[prodCat.toString() + "," + prodParam.toString()] ?? "Unknown";
    final surfaceType = d[22];
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
    // final dataType = d[20] == 0 ? "Float" : "Int";
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

          double fv = ((v + refValue) / pow(10.0, decScale) * pow(2.0, binScale));

          // K to F: (K - 273.15) × 9/5 + 32
          // K to C: K - 273.15

          if (prodCat == 0) {
            // Convert K to F
            fv = (fv - 273.15); // * 9 / 5 + 32;
          }

          bitmap.last.add(fv);
        }
      }

      // for (var each in bitmap) {
      //   String line =
      //       each.map((e) => e.toStringAsFixed(1).padLeft(7)).toList().join(" ");
      // debugPrint(line);
      // }

      _s.product = prodName;
      // For surface type 103, force to ground level (default ambient barometric pressure)
      _s.baroElev = surfaceType == 103 ? 1013.25 : scaleV / 100;
      _s.data = bitmap;
    }
  }
  return sections;
}
