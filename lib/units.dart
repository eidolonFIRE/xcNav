import 'package:xcnav/models/geo.dart';

enum DisplayUnitsSpeed {
  mph,
  kts,
  kph,
  mps,
}

enum DisplayUnitsVario {
  fpm,
  mps,
}

enum DisplayUnitsDist {
  imperial,
  metric,
}

enum DisplayUnitsFuel {
  liter,
  gal,
}

const Map<DisplayUnitsSpeed, String> unitStrSpeed = {
  DisplayUnitsSpeed.mph: " mph",
  DisplayUnitsSpeed.kts: " kts",
  DisplayUnitsSpeed.kph: " kph",
  DisplayUnitsSpeed.mps: " m/s",
};

const Map<DisplayUnitsVario, String> unitStrVario = {
  DisplayUnitsVario.fpm: " ft/m",
  DisplayUnitsVario.mps: " m/s",
};

const Map<DisplayUnitsDist, String> unitStrDistFine = {
  DisplayUnitsDist.imperial: " ft",
  DisplayUnitsDist.metric: " m",
};

const Map<DisplayUnitsDist, String> unitStrDistCoarse = {
  DisplayUnitsDist.imperial: " mi",
  DisplayUnitsDist.metric: " km",
};

const Map<DisplayUnitsDist, String> unitStrDistCoarseVerbal = {
  DisplayUnitsDist.imperial: " mile",
  DisplayUnitsDist.metric: " kilometer",
};

const Map<DisplayUnitsFuel, String> unitStrFuel = {
  DisplayUnitsFuel.liter: " L",
  DisplayUnitsFuel.gal: " gal",
};

double convertDistValueFine(DisplayUnitsDist mode, double value) {
  switch (mode) {
    case DisplayUnitsDist.imperial:
      return value * meters2Feet;
    case DisplayUnitsDist.metric:
      return value;
  }
}

double convertDistValueCoarse(DisplayUnitsDist mode, double value) {
  switch (mode) {
    case DisplayUnitsDist.imperial:
      return value * meters2Miles;
    case DisplayUnitsDist.metric:
      return value / 1000;
  }
}

double convertSpeedValue(DisplayUnitsSpeed mode, double value) {
  switch (mode) {
    case DisplayUnitsSpeed.mph:
      return value * 3.6 * km2Miles;
    case DisplayUnitsSpeed.kph:
      return value / 60 * 1000;
    case DisplayUnitsSpeed.kts:
      return value * 1.943844;
    case DisplayUnitsSpeed.mps:
      return value;
  }
}

double convertVarioValue(DisplayUnitsVario mode, double value) {
  switch (mode) {
    case DisplayUnitsVario.fpm:
      return value * 60 * meters2Feet;
    case DisplayUnitsVario.mps:
      return value;
  }
}

double convertFuelValue(DisplayUnitsFuel mode, double value) {
  switch (mode) {
    case DisplayUnitsFuel.gal:
      return value / 3.785411784;
    case DisplayUnitsFuel.liter:
      return value;
  }
}
