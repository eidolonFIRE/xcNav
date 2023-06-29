import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/airports.dart';
import 'package:xcnav/models/flight_plan.dart';

void main() {
  setUpAll(() {
    String data = File.fromUri(Uri.file("assets/airports.json")).readAsStringSync();
    loadAirports(data);
  });
  test('iFlightPlanner - first negative', () {
    const str =
        "https://www.iFlightPlanner.com/AviationCharts/?Map=sectional&GS=26&Route=-36.0605/-121.8563-36.9684/-120.3372-36.8597/-120.263-36.8684/-120.3839-36.6836/-120.4525-36.5282/-120.3949--37.3918/-120.9283-3O1";
    final uri = Uri.parse(str);

    final route = uri.queryParameters["Route"] ?? "";
    final plan = FlightPlan.fromiFlightPlanner("my plan", route);

    expect(plan.waypoints.length, 2);
    expect(plan.waypoints.values.toList()[0].latlng.length, 8);
    expect(plan.waypoints.values.toList()[0].latlng[0].latitude < -36, true);
    expect(plan.waypoints.values.toList()[0].latlng[0].longitude < -121, true);

    expect(plan.waypoints.values.toList()[1].latlng.length, 1);
    expect(plan.waypoints.values.toList()[1].name, "3O1 - Gustine");
  });

  test('iFlightPlanner - first positive', () {
    const str =
        "https://www.iFlightPlanner.com/AviationCharts/?Map=sectional&GS=26&Route=36.0605/-121.8563-36.9684/-120.3372-36.8597/-120.263-36.8684/-120.3839-36.6836/-120.4525-36.5282/-120.3949--37.3918/-120.9283-3O1";

    final uri = Uri.parse(str);

    final route = uri.queryParameters["Route"] ?? "";
    final plan = FlightPlan.fromiFlightPlanner("my plan", route);

    expect(plan.waypoints.length, 2);
    expect(plan.waypoints.values.toList()[0].latlng.length, 8);
    expect(plan.waypoints.values.toList()[0].latlng[0].latitude > 36, true);
    expect(plan.waypoints.values.toList()[0].latlng[0].longitude < -121, true);

    expect(plan.waypoints.values.toList()[1].latlng.length, 1);
    expect(plan.waypoints.values.toList()[1].name, "3O1 - Gustine");
  });

  test('iFlightPlanner - first airport', () {
    const str =
        "https://www.iFlightPlanner.com/AviationCharts/?Map=sectional&GS=26&Route=1Q4-36.0605/-121.8563-36.9684/-120.3372-36.8597/-120.263-36.8684/-120.3839-36.6836/-120.4525-36.5282/-120.3949--37.3918/-120.9283-3O1";

    final uri = Uri.parse(str);

    final route = uri.queryParameters["Route"] ?? "";
    final plan = FlightPlan.fromiFlightPlanner("my plan", route);

    expect(plan.waypoints.length, 3);
    expect(plan.waypoints.values.toList()[0].latlng.length, 1);
    expect(plan.waypoints.values.toList()[0].name, "1Q4 - New Jerusalem");
    expect(plan.waypoints.values.toList()[1].latlng.length, 9);
    expect(plan.waypoints.values.toList()[1].latlng[0].latitude > 36, true);
    expect(plan.waypoints.values.toList()[1].latlng[0].longitude < -121, true);
    expect(plan.waypoints.values.toList()[1].latlng.last.latitude > 37, true);
    expect(plan.waypoints.values.toList()[1].latlng.last.longitude < -120, true);

    expect(plan.waypoints.values.toList()[2].latlng.length, 1);
    expect(plan.waypoints.values.toList()[2].name, "3O1 - Gustine");
  });
}
