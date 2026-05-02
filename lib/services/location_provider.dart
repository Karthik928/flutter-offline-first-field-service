import 'package:geolocator/geolocator.dart';

class LocationProvider {
  Stream<Position>? _positionStream;

  Stream<Position> startListening() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    );
    return _positionStream!;
  }

  void stopListening() {
    _positionStream = null;
  }

  Future<Position?> getLastKnown() async {
    return Geolocator.getLastKnownPosition();
  }
}
