class TimeZone {
  final String code;
  final String name;
  final Duration offset;
  TimeZone(this.code, this.name, this.offset);
}

final timezones = {
  "UTC": TimeZone("UTC", "COORDINATED UNIVERSAL TIME", const Duration()),
  "AST": TimeZone("AST", "ATLANTIC STANDARD TIME", const Duration(hours: -4)),
  "EST": TimeZone("EST", "EASTERN STANDARD TIME", const Duration(hours: -5)),
  "EDT": TimeZone("EDT", "EASTERN DAYLIGHT TIME", const Duration(hours: -4)),
  "CST": TimeZone("CST", "CENTRAL STANDARD TIME", const Duration(hours: -6)),
  "CDT": TimeZone("CDT", "CENTRAL DAYLIGHT TIME", const Duration(hours: -5)),
  "MST": TimeZone("MST", "MOUNTAIN STANDARD TIME", const Duration(hours: -7)),
  "MDT": TimeZone("MDT", "MOUNTAIN DAYLIGHT TIME", const Duration(hours: -6)),
  "PST": TimeZone("PST", "PACIFIC STANDARD TIME", const Duration(hours: -8)),
  "PDT": TimeZone("PDT", "PACIFIC DAYLIGHT TIME", const Duration(hours: -7)),
  "AKST": TimeZone("AKST", "ALASKA TIME", const Duration(hours: -9)),
  "AKDT": TimeZone("AKDT", "ALASKA DAYLIGHT TIME", const Duration(hours: -8)),
  "HST": TimeZone("HST", "HAWAII STANDARD TIME", const Duration(hours: -10)),
  "HAST": TimeZone("HAST", "HAWAII-ALEUTIAN STANDARD TIME", const Duration(hours: -10)),
  "HADT": TimeZone("HADT", "HAWAII-ALEUTIAN DAYLIGHT TIME", const Duration(hours: -9)),
  "SST": TimeZone("SST", "SAMOA STANDARD TIME", const Duration(hours: -11)),
  "SDT": TimeZone("SDT", "SAMOA DAYLIGHT TIME", const Duration(hours: -10)),
  "CHST": TimeZone("CHST", "CHAMORRO STANDARD TIME", const Duration(hours: 10)),
  "Guam": TimeZone("Guam", "Guam", const Duration(hours: 10)),
};
