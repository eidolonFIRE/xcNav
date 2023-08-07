import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/airports.dart';
import 'package:xcnav/models/flight_plan.dart';
import 'package:xml/xml.dart';

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

  test('iFlightPlanner - no airports', () {
    const str =
        "https://www.iflightplanner.com/AviationCharts/?Map=hybrid&GS=26&Route=35.5418/-82.5527-35.5753/-82.6567-35.619/-82.646-35.7038/-82.5744-35.7093/-82.5639";
    final uri = Uri.parse(str);

    final route = uri.queryParameters["Route"] ?? "";
    final plan = FlightPlan.fromiFlightPlanner("my plan", route);

    expect(plan.waypoints.length, 1);
    expect(plan.waypoints.values.first.latlng.length, 5);
  });

  test('iFlightPlanner - no airports', () {
    const str =
        "https://www.iflightplanner.com/AviationCharts/?Map=hybrid&GS=26&Route=1Q4-35.5418/-82.5527-35.5753/-82.6567-35.619/-82.646-35.7038/-82.5744-35.7093/-82.5639";
    final uri = Uri.parse(str);

    final route = uri.queryParameters["Route"] ?? "";
    final plan = FlightPlan.fromiFlightPlanner("my plan", route);

    expect(plan.waypoints.length, 2);
    expect(plan.waypoints.values.last.latlng.length, 6);
  });

  test('kml - google-earth-desktop', () async {
    final file = File.fromUri(Uri.parse("test/fixtures/google_earth_desktop.kml"));
    final document = XmlDocument.parse(await file.readAsString()).getElement("kml")!.getElement("Document")!;
    final folders = document.findAllElements("Folder").toList();

    final plan = FlightPlan.fromKml("test", document, folders);

    expect(plan.waypoints.length, 2);

    // inspect airport
    expect(plan.waypoints.values.toList()[0].name, "New Jerusalem");
    expect(plan.waypoints.values.toList()[0].icon, "airport");

    // inspect path
    expect(plan.waypoints.values.toList()[1].name, "Untitled Path");
    expect(plan.waypoints.values.toList()[1].color, 0xffff007f);
  });

  test("kml - google drive map", () async {
    final file = File.fromUri(Uri.parse("test/fixtures/google_drive_map.kml"));
    final document = XmlDocument.parse(await file.readAsString()).getElement("kml")!.getElement("Document")!;
    final folders = document.findAllElements("Folder").toList();
    final plan = FlightPlan.fromKml("test", document, folders);

    expect(plan.waypoints.length, 27);

    // inspect airport
    final wpAirport = plan.waypoints.values.where((element) => element.name.contains("Oakdale")).first;
    expect(wpAirport.color, 0xff0288d1);

    // inspect path
    final wpPath = plan.waypoints.values.where((element) => element.isPath).first;
    expect(wpPath.color, 0xffffea00);
  });

  test("kml - google earth web", () async {
    final file = File.fromUri(Uri.parse("test/fixtures/google_earth_web.kml"));
    final document = XmlDocument.parse(await file.readAsString()).getElement("kml")!.getElement("Document")!;
    final folders = document.findAllElements("Folder").toList();
    final plan = FlightPlan.fromKml("test", document, folders);

    expect(plan.waypoints.length, 3);

    // inspect airport
    final wpAirport = plan.waypoints.values.where((element) => element.name.contains("runway")).first;
    expect(wpAirport.icon, "airport");
    expect(wpAirport.color, 0xff000000);

    // inspect camp
    final wpCamp = plan.waypoints.values.where((element) => element.name.contains("camping")).first;
    expect(wpCamp.icon, "camp");
    expect(wpCamp.color, 0xFFEF5350);

    // inspect path
    final wpPath = plan.waypoints.values.where((element) => element.isPath).first;
    expect(wpPath.color, 0xFFFBC02D);
  });
}
