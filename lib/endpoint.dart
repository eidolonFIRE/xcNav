import 'package:latlong2/latlong.dart';
import 'package:xcnav/secrets.dart';

class Endpoint {
  String apiUrl;
  String avatarUrl;
  String token;
  String cert;

  Endpoint({required this.apiUrl, required this.avatarUrl, required this.token, required this.cert});
}

LatLng latlngAtLoading = LatLng(0, 0);
Endpoint? serverEndpoint;

void selectEndpoint(LatLng latlng) {
  latlngAtLoading = latlng;
  if (latlngAtLoading.longitude > -180 && latlngAtLoading.longitude < -50 && latlngAtLoading.latitude > 13) {
    serverEndpoint = endpointNorthAmerica;
  } else {
    // Default
    serverEndpoint = endpointNorthAmerica;
  }
}
