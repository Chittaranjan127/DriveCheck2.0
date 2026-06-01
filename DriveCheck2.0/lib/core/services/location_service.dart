import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Thin wrapper around `geolocator` for one-shot current-location reads.
///
/// Returns `null` (rather than throwing) when the service is disabled or
/// the user denies permission — callers should treat that as "distance
/// is unknown" and degrade the UI gracefully instead of error-popping.
class LocationService {
  static final LocationService instance = LocationService._();
  LocationService._();

  Future<Position?> getCurrent() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        debugPrint('[location] service disabled');
        return null;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        debugPrint('[location] permission denied');
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (e) {
      debugPrint('[location] fetch failed: $e');
      return null;
    }
  }

  /// Straight-line distance in kilometres between two coordinates.
  /// Uses geolocator's haversine implementation.
  double distanceKm(double lat1, double lon1, double lat2, double lon2) =>
      Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000;
}
