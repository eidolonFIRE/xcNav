import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/models/vector.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/wind.dart';

class MockMyTelemetry extends MyTelemetry {
  MockMyTelemetry();
}

void main() {
  late Wind wind;

  setUp(() {
    wind = Wind();
  });

  double round(double value) {
    return (value * 100).round() / 100;
  }

  test("not enough samples", () {
    wind.handleVector(Vector(-0.01, 10));
    wind.handleVector(Vector(0, 10));

    expect(wind.result != null, false);
  });

  test("nill wind", () {
    wind.handleVector(Vector(-0.01, 10));
    wind.handleVector(Vector(0, 10));
    wind.handleVector(Vector(pi / 4, 10));
    wind.handleVector(Vector(pi / 4, 10));
    wind.handleVector(Vector(pi / 2, 10));
    wind.handleVector(Vector(pi / 2, 10));

    expect(wind.result != null, true, reason: "Wind Solution");
    expect(round(wind.result!.airspeed), 10.0, reason: "Airspeed");
    expect(round(wind.result!.windSpd), 0.0, reason: "Wind Speed");
    // expect(round(wind.result!.windHdg), 3.93, reason: "Wind Heading");
  });

  test("wind1", () {
    wind.handleVector(Vector(0, 15));
    wind.handleVector(Vector(pi / 4, 13));
    wind.handleVector(Vector(pi / 3, 12));
    wind.handleVector(Vector(pi / 2, 10));
    wind.handleVector(Vector(pi, 5));

    expect(wind.result != null, true, reason: "Wind Solution");
    expect(round(wind.result!.airspeed), 10.02, reason: "Airspeed");
    expect(round(wind.result!.windSpd), 4.82, reason: "Wind Speed");
    expect(round(wind.result!.windHdg), 0.13, reason: "Wind Heading");
  });

  test("wind2", () {
    wind.handleVector(Vector(0, 15));
    wind.handleVector(Vector(-pi / 4, 13));
    wind.handleVector(Vector(-pi / 3, 12));
    wind.handleVector(Vector(-pi / 2, 10));
    wind.handleVector(Vector(-pi, 5));

    expect(wind.result != null, true, reason: "Wind Solution");
    expect(round(wind.result!.airspeed), 10.02, reason: "Airspeed");
    expect(round(wind.result!.windSpd), 4.82, reason: "Wind Speed");
    expect(round(wind.result!.windHdg), 6.16, reason: "Wind Heading");
  });

  test("wind3", () {
    wind.handleVector(Vector(-1.8057157752057609, 17.35097410404365));
    wind.handleVector(Vector(-1.3318501519122217, 15.323218213770156));
    wind.handleVector(Vector(-1.5969167056437565, 16.94417899477183));
    wind.handleVector(Vector(-0.968084569649244, 11.56592203225453));
    wind.handleVector(Vector(-0.9123416729919135, 12.184427660573109));
    wind.handleVector(Vector(-0.6903214304128802, 10.082189753271702));
    wind.handleVector(Vector(-0.8308429189369527, 11.735298680815694));
    wind.handleVector(Vector(-0.9031709203234624, 11.554889685107575));
    wind.handleVector(Vector(-0.9448499889474835, 11.357269736991558));
    wind.handleVector(Vector(-0.08195407349844804, 7.989080855986737));
    wind.handleVector(Vector(0.761547754672944, 7.590191846506757));
    wind.handleVector(Vector(0.5502768373465166, 9.723522874010202));
    wind.handleVector(Vector(0.8819468623314072, 8.452958577472227));
    wind.handleVector(Vector(1.3756159192617572, 10.692717852916237));
    wind.handleVector(Vector(1.7278189032276992, 11.513194918299316));
    wind.handleVector(Vector(2.059783429416318, 14.939705715956071));
    wind.handleVector(Vector(2.218073654864102, 15.410328467088373));
    wind.handleVector(Vector(1.902845343065703, 13.553408388173949));
    wind.handleVector(Vector(1.958899119623785, 12.663146934595716));
    wind.handleVector(Vector(2.365981309170243, 15.842542872952846));
    expect(wind.result != null, true, reason: "Wind Solution");
    expect(round(wind.result!.airspeed), 15.05, reason: "Airspeed");
    expect(round(wind.result!.windSpd), 6.81, reason: "Wind Speed");
    expect(round(wind.result!.windHdg), 3.53, reason: "Wind Heading");
  });

  test("wind4", () {
    wind.handleVector(Vector(-0.5108861036234996, 18.776286308145906));
    wind.handleVector(Vector(-0.6503151135347236, 19.47714893965392));
    wind.handleVector(Vector(-0.5820982224463074, 20.598967156702372));
    wind.handleVector(Vector(-0.7112759976910168, 19.674271846497838));
    wind.handleVector(Vector(-0.5677726766112963, 20.98374388014814));
    wind.handleVector(Vector(-0.3482426263262236, 19.545193570203956));
    wind.handleVector(Vector(0.12921105282040934, 18.22338333593861));
    wind.handleVector(Vector(0.6057486513819758, 15.933788642716666));
    wind.handleVector(Vector(0.7215931152797078, 14.754720118581336));
    wind.handleVector(Vector(0.8743687639179311, 13.30591781862364));
    wind.handleVector(Vector(0.9580992968412669, 12.472236932700486));
    wind.handleVector(Vector(1.0318928363427609, 12.873355894209618));
    wind.handleVector(Vector(1.0109637977387032, 12.983953806855759));
    wind.handleVector(Vector(1.7667186277955604, 10.389679088572704));
    wind.handleVector(Vector(1.4389230255219319, 10.953364025966462));
    wind.handleVector(Vector(2.1686513153671183, 9.203312570525002));
    wind.handleVector(Vector(2.3115260258936745, 10.139069323100651));
    wind.handleVector(Vector(2.886041595095086, 9.871987478728867));
    wind.handleVector(Vector(2.9877947315941835, 10.322150472226724));
    wind.handleVector(Vector(2.717538594598394, 9.763390238417596));
    wind.handleVector(Vector(-2.8236070950255434, 11.781251509873686));
    wind.handleVector(Vector(-2.2159669972305562, 14.260998192266097));
    wind.handleVector(Vector(-1.9473324735475361, 16.979216945593954));
    wind.handleVector(Vector(-1.5933593699016486, 18.09136591940928));
    wind.handleVector(Vector(-1.1134879354306917, 20.62732549461773));
    wind.handleVector(Vector(-0.7294634381536137, 20.8009773114575));
    wind.handleVector(Vector(-0.3793437570901792, 19.0310738898536));
    wind.handleVector(Vector(-0.5121235325711859, 19.394973163594425));
    wind.handleVector(Vector(-0.15810662009050863, 19.119195249902127));
    wind.handleVector(Vector(-0.28539939365552286, 18.405446346092084));
    wind.handleVector(Vector(-0.06562769784011939, 17.569349899871174));
    wind.handleVector(Vector(-0.23280785221590802, 18.65863873930486));
    expect(wind.result != null, true, reason: "Wind Solution");
    expect(round(wind.result!.airspeed), 14.92, reason: "Airspeed");
    expect(round(wind.result!.windSpd), 5.25, reason: "Wind Speed");
    expect(round(wind.result!.windHdg), 5.48, reason: "Wind Heading");
  });
}
