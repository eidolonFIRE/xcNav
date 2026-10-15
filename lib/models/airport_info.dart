import 'package:latlong2/latlong.dart';

/// OpenAIP airport types we don't show (heliports and closed aerodromes)
const _ignoredTypes = {4, 7, 8};

const _frequencyTypeNames = {
  0: "Approach",
  1: "Apron",
  2: "Arrival",
  3: "Center",
  4: "CTAF",
  5: "Delivery",
  6: "Departure",
  7: "FIS",
  8: "Gliding",
  9: "Ground",
  10: "Info",
  11: "Multicom",
  12: "Unicom",
  13: "Radar",
  14: "Tower",
  15: "ATIS",
  16: "Radio",
  17: "Other",
  18: "AIRMET",
  19: "AWOS",
  20: "Lights",
  21: "VOLMET",
  22: "AFIS",
  23: "ASOS",
  24: "AWIS",
  25: "Emergency",
  26: "Clearance",
  27: "RCO",
  28: "GCO",
  29: "FSS",
  30: "Class C",
  31: "Class B",
  32: "VFR Advisory",
  33: "TRSA",
};

/// Frequency types that are useful to the pilot talking to / listening to the local traffic, shown first.
const _localTypes = {4, 11, 12, 14, 16, 22, 9, 15, 19, 23};

class AirportFrequency {
  /// MHz, e.g. "122.800"
  final String value;

  /// OpenAIP frequency type enum
  final int type;
  final String name;
  final bool primary;

  const AirportFrequency({required this.value, required this.type, this.name = "", this.primary = false});

  String get typeName => _frequencyTypeNames[type] ?? "Other";

  bool get isLocal => _localTypes.contains(type);

  static AirportFrequency? fromOpenAip(dynamic data) {
    if (data is! Map || data["value"] is! String) return null;
    return AirportFrequency(
        value: data["value"],
        type: data["type"] is int ? data["type"] : 17,
        name: data["name"]?.toString() ?? "",
        primary: data["primary"] == true);
  }

  Map<String, dynamic> toJson() => {"v": value, "t": type, "n": name, "p": primary};

  AirportFrequency.fromJson(Map<String, dynamic> data)
      : value = data["v"],
        type = data["t"],
        name = data["n"] ?? "",
        primary = data["p"] ?? false;
}

/// Airport from OpenAIP
class AirportInfo {
  final String id;
  final String name;

  /// ICAO (or IATA / alt identifier when there's no ICAO code)
  final String? code;

  /// OpenAIP airport type enum
  final int type;
  final LatLng latlng;

  /// Meters MSL
  final double? elevation;
  final bool private;
  final List<AirportFrequency> frequencies;

  const AirportInfo(
      {required this.id,
      required this.name,
      this.code,
      required this.type,
      required this.latlng,
      this.elevation,
      this.private = false,
      this.frequencies = const []});

  /// Parse an item from the OpenAIP v2 core API (`/api/airports`). Returns null if unusable.
  static AirportInfo? fromOpenAip(Map<String, dynamic> data) {
    final geometry = data["geometry"];
    if (geometry is! Map || geometry["type"] != "Point") return null;
    final coords = geometry["coordinates"];
    if (coords is! List || coords.length < 2 || coords[0] is! num || coords[1] is! num) return null;

    final elevation = data["elevation"];
    final frequencies = (data["frequencies"] is List ? data["frequencies"] as List : [])
        .map(AirportFrequency.fromOpenAip)
        .nonNulls
        .toList();
    // Local traffic frequencies first, then primary
    frequencies.sort((a, b) {
      if (a.isLocal != b.isLocal) return a.isLocal ? -1 : 1;
      if (a.primary != b.primary) return a.primary ? -1 : 1;
      return 0;
    });

    final code = [data["icaoCode"], data["iataCode"], data["altIdentifier"]]
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .firstOrNull;

    return AirportInfo(
        id: data["_id"]?.toString() ?? "",
        name: data["name"]?.toString() ?? "",
        code: code,
        type: data["type"] is int ? data["type"] : 0,
        latlng: LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble()),
        // OpenAIP airport elevation is always meters MSL
        elevation: elevation is Map && elevation["value"] is num ? (elevation["value"] as num).toDouble() : null,
        private: data["private"] == true,
        frequencies: frequencies);
  }

  bool get isRelevant => !_ignoredTypes.contains(type);

  bool get hasTower => frequencies.any((e) => e.type == 14);

  /// Waypoint name: "KPAO" or the airport name when there's no code
  String get shortName => code ?? name;

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        if (code != null) "code": code,
        "type": type,
        "lat": latlng.latitude,
        "lng": latlng.longitude,
        if (elevation != null) "elev": elevation,
        if (private) "private": true,
        "freq": frequencies.map((e) => e.toJson()).toList(),
      };

  static AirportInfo fromJson(Map<String, dynamic> data) => AirportInfo(
      id: data["id"],
      name: data["name"],
      code: data["code"],
      type: data["type"],
      latlng: LatLng((data["lat"] as num).toDouble(), (data["lng"] as num).toDouble()),
      elevation: (data["elev"] as num?)?.toDouble(),
      private: data["private"] ?? false,
      frequencies: (data["freq"] as List).map((e) => AirportFrequency.fromJson(e)).toList());
}
