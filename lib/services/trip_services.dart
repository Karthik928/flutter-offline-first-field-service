import 'dart:convert';
import 'dart:math'; // for session token
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:FieldService_app/config.dart';

// --- Add near your other imports and TripServices class ---
const String _apiKey = AppConfig.googleMapsApiKey;

class EtaResult {
  final int distanceMeters;
  final int durationSeconds;
  const EtaResult({
    required this.distanceMeters,
    required this.durationSeconds,
  });
}

class TripServices {
  static const String _routesBaseUrl =
      'https://routes.googleapis.com/directions/v2:computeRoutes';
  // Replace with your actual Google Maps API key

  // Base URLs for Google Maps APIs
  static const String _placesBaseUrl =
      "https://maps.googleapis.com/maps/api/place";
  static const String _geocodingBaseUrl =
      "https://maps.googleapis.com/maps/api/geocode";
  // static const String _directionsBaseUrl =
  //     "https://maps.googleapis.com/maps/api/directions";
  //static const String _routesBaseUrl =
  //   "https://routes.googleapis.com/directions/v2";
  // --- session token for Places billing/relevance ---
  static String? _sessionToken;
  static void startSearchSession([String? token]) {
    _sessionToken =
        token ??
        List.generate(24, (_) => Random().nextInt(16).toRadixString(16)).join();
  }

  static void endSearchSession() {
    _sessionToken = null;
  }

  static Future<EtaResult> getTwoWheelerEta(
    LatLng origin,
    LatLng destination, {
    bool avoidTolls = false,
    bool avoidHighways = false,
    bool avoidFerries = false,
  }) async {
    final headers = {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': _apiKey, // reuse your existing key
      // Only ask for what we need
      'X-Goog-FieldMask': 'routes.distanceMeters,routes.duration',
    };

    final body = {
      "origin": {
        "location": {
          "latLng": {
            "latitude": origin.latitude,
            "longitude": origin.longitude,
          },
        },
      },
      "destination": {
        "location": {
          "latLng": {
            "latitude": destination.latitude,
            "longitude": destination.longitude,
          },
        },
      },
      "routeModifiers": {
        "avoidTolls": avoidTolls,
        "avoidHighways": avoidHighways,
        "avoidFerries": avoidFerries,
      },

      "travelMode": "TWO_WHEELER",
      "routingPreference": "TRAFFIC_AWARE",
      "computeAlternativeRoutes": false,
      // 👇 set slightly in the future to satisfy the API
      "departureTime": DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 2000))
          .toIso8601String(),
    };

    // final resp = await http
    //     .post(
    //       Uri.parse(_routesBaseUrl),
    //       headers: headers,
    //       body: jsonEncode(body),
    //     )
    //     .timeout(const Duration(seconds: 10));

    final resp = await _postRoutes(
      headers,
      body,
    ); // <— instead of http.post(...)
    if (resp.statusCode != 200) {
      throw Exception('Routes API HTTP ${resp.statusCode}: ${resp.body}');
    }

    if (resp.statusCode != 200) {
      throw Exception('ETA HTTP ${resp.statusCode}: ${resp.body}');
    }

    final data = jsonDecode(resp.body);
    final routes = (data['routes'] as List?) ?? const [];
    if (routes.isEmpty) {
      throw Exception('No route found for ETA');
    }

    final r = routes.first as Map<String, dynamic>;
    final distanceMeters = (r['distanceMeters'] as num?)?.toInt() ?? 0;
    final durationSeconds = _parseDurationSec(
      (r['duration'] as String?) ?? '0s',
    ); // reuses your helper

    return EtaResult(
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
    );
  }

  static Future<http.Response> _postRoutes(
    Map<String, String> headers,
    Map<String, dynamic> body,
  ) async {
    // First attempt (caller has already set departureTime ~+2 min)
    http.Response resp = await http
        .post(
          Uri.parse(_routesBaseUrl),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 12));

    // If server still complains about “future” timing, retry once with +5 min
    if (resp.statusCode != 200 && resp.body.toLowerCase().contains('future')) {
      body['departureTime'] = DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 5))
          .toIso8601String();

      resp = await http
          .post(
            Uri.parse(_routesBaseUrl),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 12));
    }

    return resp;
  }

  /// TWO_WHEELER, traffic-aware, single active route.
  static Future<DirectionsRoute> getTwoWheelerRoute(
    LatLng origin,
    LatLng destination, {
    bool avoidTolls = false,
    bool avoidHighways = false,
    bool avoidFerries = false,
  }) async {
    final headers = {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': _apiKey,
      // Only fetch fields we need (cheaper & faster)
      'X-Goog-FieldMask':
          'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline,routes.description',
    };

    final body = {
      "origin": {
        "location": {
          "latLng": {
            "latitude": origin.latitude,
            "longitude": origin.longitude,
          },
        },
      },
      "destination": {
        "location": {
          "latLng": {
            "latitude": destination.latitude,
            "longitude": destination.longitude,
          },
        },
      },
      "routeModifiers": {
        "avoidTolls": avoidTolls,
        "avoidHighways": avoidHighways,
        "avoidFerries": avoidFerries,
      },

      "travelMode": "TWO_WHEELER",
      "routingPreference": "TRAFFIC_AWARE",
      "computeAlternativeRoutes": false,
      // RFC3339 UTC time; "now" gives traffic-influenced ETAs
      "departureTime": DateTime.now().toUtc().toIso8601String(),
    };

    final resp = await _postRoutes(
      headers,
      body,
    ); // <— instead of http.post(...)
    if (resp.statusCode != 200) {
      throw Exception('Routes API HTTP ${resp.statusCode}: ${resp.body}');
    }

    if (resp.statusCode != 200) {
      throw Exception('Routes API HTTP ${resp.statusCode}: ${resp.body}');
    }

    final data = jsonDecode(resp.body);
    final routes = (data['routes'] as List?) ?? const [];
    if (routes.isEmpty) {
      throw Exception('No route returned by Routes API');
    }

    final r = routes.first as Map<String, dynamic>;
    final encoded = (r['polyline']?['encodedPolyline'] as String?) ?? '';
    final distanceMeters = (r['distanceMeters'] as num?)?.toInt() ?? 0;
    final durationSeconds = _parseDurationSec(
      (r['duration'] as String?) ?? '0s',
    ); // e.g. "123s"
    // 👇 NEW
    final summary = (r['description'] as String?) ?? 'Two-wheeler route';
    return DirectionsRoute(
      polylinePoints: _decodePolyline(encoded),
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      summary: summary, // 👈 REQUIRED by your model
    );
  }

  static int _parseDurationSec(String s) {
    // Routes API returns "123s" or "123.45s"
    if (!s.endsWith('s')) return 0;
    final v = s.substring(0, s.length - 1);
    return double.tryParse(v)?.round() ?? 0;
  }

  static List<LatLng> _decodePolyline(String encoded) {
    // Standard Google polyline decoder
    final List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      poly.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return poly;
  }

  // --- autocomplete ---
  static Future<List<PlacePrediction>> autocomplete(
    String input, {
    LatLng? biasCenter,
    int radiusMeters = 30000,
    List<String> countryCodes = const ['in'],
  }) async {
    final normalizedCountryCodes = countryCodes
        .map((code) => code.trim().toLowerCase())
        .where((code) => code.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final params = <String, String>{
      'input': input,
      'key': _apiKey,
      if (normalizedCountryCodes.isNotEmpty)
        'components': normalizedCountryCodes
            .map((code) => 'country:$code')
            .join('|'),
      if (biasCenter != null)
        'location': '${biasCenter.latitude},${biasCenter.longitude}',
      if (biasCenter != null) 'radius': '$radiusMeters',
    };
    final sessionToken = _sessionToken;
    if (sessionToken != null) {
      params['sessiontoken'] = sessionToken;
    }
    final url = Uri.parse(
      "$_placesBaseUrl/autocomplete/json",
    ).replace(queryParameters: params);
    final resp = await http.get(url).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    final data = json.decode(resp.body);
    final status = data['status'];
    if (status == 'OK') {
      final preds = (data['predictions'] as List? ?? const []);
      return preds.map((j) => PlacePrediction.fromJson(j)).toList();
    } else if (status == 'ZERO_RESULTS') {
      return const [];
    } else {
      throw Exception('Places Autocomplete error: $status');
    }
  }

  // --- place details by place_id ---
  static Future<PlaceDetails> fetchPlaceDetails(
    String placeId, {
    List<String> fields = const [
      'geometry',
      'name',
      'formatted_address',
      'types',
    ],
  }) async {
    final params = <String, String>{
      'place_id': placeId,
      'fields': fields.join(','),
      'key': _apiKey,
    };
    final sessionToken = _sessionToken;
    if (sessionToken != null) {
      params['sessiontoken'] = sessionToken;
    }
    final url = Uri.parse(
      "$_placesBaseUrl/details/json",
    ).replace(queryParameters: params);
    final resp = await http.get(url).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    final data = json.decode(resp.body);
    final status = data['status'];
    if (status == 'OK') {
      return PlaceDetails.fromJson(data['result']);
    } else {
      throw Exception('Place Details error: $status');
    }
  }

  /// Search for places using Google Places API
  static Future<List<PlaceResult>> searchPlaces(
    String query, {
    Map<String, String> countryFilters = const {},
  }) async {
    try {
      final normalizedQuery = query.trim();
      if (normalizedQuery.isEmpty) {
        return const [];
      }

      if (countryFilters.isEmpty) {
        return await _searchPlacesForQuery(normalizedQuery);
      }

      final matchesExplicitCountry = countryFilters.entries.any((entry) {
        final code = entry.key.trim().toLowerCase();
        final countryName = entry.value.trim().toLowerCase();
        final lowerQuery = normalizedQuery.toLowerCase();
        return lowerQuery.contains(countryName) || lowerQuery.contains(code);
      });

      if (matchesExplicitCountry) {
        return await _searchPlacesForQuery(normalizedQuery);
      }

      final allResults = <PlaceResult>[];
      final seenPlaceIds = <String>{};

      for (final entry in countryFilters.entries) {
        final countryCode = entry.key.trim().toLowerCase();
        final countryName = entry.value.trim();
        if (countryCode.isEmpty || countryName.isEmpty) continue;

        final scopedQuery = '$normalizedQuery, $countryName';
        final scopedResults = await _searchPlacesForQuery(
          scopedQuery,
          regionCode: countryCode,
        );

        for (final result in scopedResults) {
          if (result.placeId.isEmpty || seenPlaceIds.add(result.placeId)) {
            allResults.add(result);
          }
        }
      }

      return allResults;
    } catch (e) {
      debugPrint('Search places error: $e');
      throw Exception('Failed to search places: $e');
    }
  }

  static Future<List<PlaceResult>> _searchPlacesForQuery(
    String query, {
    String? regionCode,
  }) async {
    final url = Uri.parse(
      '$_placesBaseUrl/textsearch/json',
    ).replace(
      queryParameters: {
        'query': query,
        'key': _apiKey,
        if (regionCode != null && regionCode.trim().isNotEmpty)
          'region': regionCode.trim().toLowerCase(),
      },
    );

    final response = await http.get(url).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP error: ${response.statusCode}');
    }

    final data = json.decode(response.body);
    final status = data['status'];

    if (status == 'OK') {
      final results = data['results'] as List? ?? const [];
      return results.map((result) => PlaceResult.fromJson(result)).toList();
    }

    if (status == 'ZERO_RESULTS') {
      return const [];
    }

    throw Exception('Places API error: $status');
  }

  /// Get place details using Google Places API
  static Future<PlaceDetails?> getPlaceDetails(String placeId) async {
    try {
      final url = Uri.parse(
        "$_placesBaseUrl/details/json?place_id=$placeId&fields=geometry,formatted_address,name&key=$_apiKey",
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK') {
          return PlaceDetails.fromJson(data['result']);
        } else {
          throw Exception('Place details API error: ${data['status']}');
        }
      } else {
        throw Exception('HTTP error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Get place details error: $e');
      throw Exception('Failed to get place details: $e');
    }
  }

  /// Reverse geocoding using Google Geocoding API
  static Future<GeocodingResult?> reverseGeocode(LatLng location) async {
    try {
      final url = Uri.parse(
        "$_geocodingBaseUrl/json?latlng=${location.latitude},${location.longitude}&key=$_apiKey",
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          return GeocodingResult.fromJson(data['results'][0]);
        } else {
          throw Exception('Geocoding API error: ${data['status']}');
        }
      } else {
        throw Exception('HTTP error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Reverse geocode error: $e');
      throw Exception('Failed to reverse geocode: $e');
    }
  }

  /// Get directions using Google Directions API
  static Future<List<DirectionsRoute>> getDirections(
    LatLng origin,
    LatLng destination, {
    String travelMode = "driving",
  }) async {
    final url = Uri.parse(
      "https://maps.googleapis.com/maps/api/directions/json"
      "?origin=${origin.latitude},${origin.longitude}"
      "&destination=${destination.latitude},${destination.longitude}"
      "&mode=$travelMode"
      "&alternatives=true" // <<— key line
      "&key=$_apiKey",
    );

    final response = await http.get(url).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP error: ${response.statusCode}');
    }

    final data = json.decode(response.body);
    if (data['status'] != 'OK' || (data['routes'] as List).isEmpty) {
      throw Exception('Directions API error: ${data['status']}');
    }

    // Parse ALL routes
    final routesJson = (data['routes'] as List).cast<Map<String, dynamic>>();
    debugPrint("Directions routes count: ${routesJson.length}"); // <-- log it
    return routesJson.map(DirectionsRoute.fromJson).toList();
  }

  /// Get advanced routes using Google Routes API (v2)
  static Future<RoutesResult?> getAdvancedRoutes(
    LatLng origin,
    LatLng destination, {
    String travelMode = "DRIVE",
  }) async {
    try {
      final url = Uri.parse(_routesBaseUrl);

      final requestBody = {
        "origin": {
          "location": {
            "latLng": {
              "latitude": origin.latitude,
              "longitude": origin.longitude,
            },
          },
        },
        "destination": {
          "location": {
            "latLng": {
              "latitude": destination.latitude,
              "longitude": destination.longitude,
            },
          },
        },
        "travelMode": travelMode,
        "routingPreference": "TRAFFIC_AWARE",
        "computeAlternativeRoutes": true,
        "routeModifiers": {
          "avoidTolls": false,
          "avoidHighways": false,
          "avoidFerries": false,
        },
      };

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
        },
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return RoutesResult.fromJson(data);
      } else {
        throw Exception('HTTP error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Get advanced routes error: $e');
      throw Exception('Failed to get advanced routes: $e');
    }
  }

  /// Decode polyline from Google Maps API
  static List<LatLng> decodePolyline(String polyline) {
    List<LatLng> points = [];
    int index = 0, len = polyline.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = polyline.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = polyline.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }
}

/// Data models for Google Maps API responses

class PlaceResult {
  final String placeId;
  final String name;
  final String formattedAddress;
  final LatLng location;
  final double rating;
  final List<String> types;

  PlaceResult({
    required this.placeId,
    required this.name,
    required this.formattedAddress,
    required this.location,
    required this.rating,
    required this.types,
  });

  factory PlaceResult.fromJson(Map<String, dynamic> json) {
    return PlaceResult(
      placeId: json['place_id'] ?? '',
      name: json['name'] ?? '',
      formattedAddress: json['formatted_address'] ?? '',
      location: LatLng(
        json['geometry']['location']['lat']?.toDouble() ?? 0.0,
        json['geometry']['location']['lng']?.toDouble() ?? 0.0,
      ),
      rating: json['rating']?.toDouble() ?? 0.0,
      types: List<String>.from(json['types'] ?? []),
    );
  }
}

class PlaceDetails {
  final String name;
  final String formattedAddress;
  final LatLng location;

  PlaceDetails({
    required this.name,
    required this.formattedAddress,
    required this.location,
  });

  factory PlaceDetails.fromJson(Map<String, dynamic> json) {
    return PlaceDetails(
      name: json['name'] ?? '',
      formattedAddress: json['formatted_address'] ?? '',
      location: LatLng(
        json['geometry']['location']['lat']?.toDouble() ?? 0.0,
        json['geometry']['location']['lng']?.toDouble() ?? 0.0,
      ),
    );
  }
}

class GeocodingResult {
  final String formattedAddress;
  final List<AddressComponent> addressComponents;

  GeocodingResult({
    required this.formattedAddress,
    required this.addressComponents,
  });

  factory GeocodingResult.fromJson(Map<String, dynamic> json) {
    return GeocodingResult(
      formattedAddress: json['formatted_address'] ?? '',
      addressComponents:
          (json['address_components'] as List?)
              ?.map((component) => AddressComponent.fromJson(component))
              .toList() ??
          [],
    );
  }
}

class AddressComponent {
  final String longName;
  final String shortName;
  final List<String> types;

  AddressComponent({
    required this.longName,
    required this.shortName,
    required this.types,
  });

  factory AddressComponent.fromJson(Map<String, dynamic> json) {
    return AddressComponent(
      longName: json['long_name'] ?? '',
      shortName: json['short_name'] ?? '',
      types: List<String>.from(json['types'] ?? []),
    );
  }
}

class DirectionsResult {
  final List<LatLng> polylinePoints;
  final double distance; // in meters
  final double duration; // in seconds
  final String summary;

  DirectionsResult({
    required this.polylinePoints,
    required this.distance,
    required this.duration,
    required this.summary,
  });

  factory DirectionsResult.fromJson(Map<String, dynamic> json) {
    final leg = json['legs'][0];
    final polyline = json['overview_polyline']['points'];

    return DirectionsResult(
      polylinePoints: TripServices.decodePolyline(polyline),
      distance: leg['distance']['value']?.toDouble() ?? 0.0,
      duration: leg['duration']['value']?.toDouble() ?? 0.0,
      summary: json['summary'] ?? '',
    );
  }
}

class RoutesResult {
  final List<Route> routes;

  RoutesResult({required this.routes});

  factory RoutesResult.fromJson(Map<String, dynamic> json) {
    return RoutesResult(
      routes:
          (json['routes'] as List?)
              ?.map((route) => Route.fromJson(route))
              .toList() ??
          [],
    );
  }
}

class Route {
  final List<LatLng> polylinePoints;
  final double distance; // in meters
  final double duration; // in seconds
  final String displayName;
  final List<String> warnings;

  Route({
    required this.polylinePoints,
    required this.distance,
    required this.duration,
    required this.displayName,
    required this.warnings,
  });

  factory Route.fromJson(Map<String, dynamic> json) {
    final polyline = json['polyline']['encodedPolyline'];
    final leg = json['legs'][0];

    return Route(
      polylinePoints: TripServices.decodePolyline(polyline),
      distance: leg['distanceMeters']?.toDouble() ?? 0.0,
      duration: leg['duration']?.replaceAll('s', '')?.toDouble() ?? 0.0,
      displayName: json['displayName'] ?? '',
      warnings: List<String>.from(json['warnings'] ?? []),
    );
  }
}

class PlacePrediction {
  final String placeId;
  final String mainText;
  final String secondaryText;
  final List<String> types;

  PlacePrediction({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
    required this.types,
  });

  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    final fmt = json['structured_formatting'] ?? {};
    return PlacePrediction(
      placeId: json['place_id'] ?? '',
      mainText: fmt['main_text'] ?? (json['description'] ?? ''),
      secondaryText: fmt['secondary_text'] ?? '',
      types: List<String>.from(json['types'] ?? []),
    );
  }
}

class DirectionsRoute {
  final List<LatLng> polylinePoints;
  final int distanceMeters; // total across legs
  final int durationSeconds; // total across legs
  final String summary; // route summary (e.g., road names)

  DirectionsRoute({
    required this.polylinePoints,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.summary,
  });

  factory DirectionsRoute.fromJson(Map<String, dynamic> json) {
    final legs = (json['legs'] as List).cast<Map<String, dynamic>>();
    final totalDistance = legs.fold<int>(
      0,
      (sum, l) => sum + (l['distance']['value'] as int),
    );
    final totalDuration = legs.fold<int>(
      0,
      (sum, l) => sum + (l['duration']['value'] as int),
    );

    final encoded = json['overview_polyline']['points'] as String;
    return DirectionsRoute(
      polylinePoints: _decodePolyline(encoded),
      distanceMeters: totalDistance,
      durationSeconds: totalDuration,
      summary: (json['summary'] as String?) ?? '',
    );
  }

  static List<LatLng> _decodePolyline(String encoded) {
    // Standard polyline decoder
    List<LatLng> points = [];
    int index = 0, lat = 0, lng = 0;

    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}
