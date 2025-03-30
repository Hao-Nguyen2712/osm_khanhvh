import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  final Location _location = Location();
  final TextEditingController _locationController = TextEditingController();
  bool isLoading = true;
  LatLng? _currentLocation;
  LatLng? _destinationLocation;
  List<LatLng> _route = [];

  @override
  void initState() {
    super.initState();
    _initializeLocation();

    _location.onLocationChanged.listen((LocationData locationData) {
      if (locationData.latitude != null && locationData.longitude != null) {
        setState(() {
          _currentLocation = LatLng(
            locationData.latitude!,
            locationData.longitude!,
          );
          isLoading = false; // set loading to false when location is found
        });
      }
    });
  }

  Future<void> _initializeLocation() async {
    if (!await _checkTheRequestPermission()) {
      return;
    }
  }

  Future<bool> _checkTheRequestPermission() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        return false;
      }
    }
    PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        return false;
      }
    }
    return true;
  }

  Future<void> _fetchCoordinatesPoint(String location) async {
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search?q=$location&format=json&addressdetails=1&limit=1',
    );

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data != null) {
        final lat = double.parse(data[0]['lat']);
        final lon = double.parse(data[0]['lon']);
        setState(() {
          _destinationLocation = LatLng(lat, lon);
        });

        await _fetchRoute();
      } else {
        errorMessage("Location not found");
      }
    } else {
      errorMessage("Location not found");
    }
  }

  Future<void> _fetchRoute() async {
    if (_currentLocation == null || _destinationLocation == null) {
      return;
    }
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/${_currentLocation!.longitude},${_currentLocation!.latitude};${_destinationLocation!.longitude},${_destinationLocation!.latitude}?overview=false',
    );
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final geometry = data['routes'][0]['geometry'];
      _decodePolyline(geometry);
    } else {
      errorMessage("Failed to fetch route . Please try again.");
    }
  }

  void _decodePolyline(String encodePolyline) {
    PolylinePoints polylinePoints = PolylinePoints();
    List<PointLatLng> points = polylinePoints.decodePolyline(encodePolyline);

    setState(() {
      _route =
          points
              .map((point) => LatLng(point.latitude, point.longitude))
              .toList();
    });
  }

  void errorMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _userCurrentLocation() async {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 15);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Current location not found")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        foregroundColor: Colors.white,
        title: const Text("OpenStreetMap"),
        backgroundColor: Colors.blue,
      ),
      body: Stack(
        children: [
          isLoading
              ? Center(child: CircularProgressIndicator())
              : FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentLocation ?? LatLng(0, 0),
                  initialZoom: 2,
                  minZoom: 0,
                  maxZoom: 100,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  ),
                  CurrentLocationLayer(
                    style: LocationMarkerStyle(
                      marker: DefaultLocationMarker(
                        child: Icon(Icons.location_pin, color: Colors.white),
                      ),
                      markerSize: Size(35, 35),
                      markerDirection: MarkerDirection.heading,
                    ),
                  ),
                  if (_destinationLocation != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _destinationLocation!,
                          child: Icon(
                            Icons.location_pin,
                            size: 40,
                            color: Colors.red,
                          ),
                          width: 50,
                          height: 50,
                        ),
                      ],
                    ),
                  if (_currentLocation != null && _route.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _route,
                          color: Colors.red,
                          strokeWidth: 5,
                        ),
                      ],
                    ),
                ],
              ),
          Positioned(
            top: 0,
            right: 0,
            left: 0,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _locationController,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: "Enter location",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.blue,
                      shape: const CircleBorder(),
                    ),
                    onPressed: () {
                      final location = _locationController.text.trim();
                      if (location.isNotEmpty) {
                        _fetchCoordinatesPoint(location);
                      }
                    },
                    icon: const Icon(Icons.search),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: Colors.blue,
        child: Icon(Icons.my_location, color: Colors.white, size: 30),
      ),
    );
  }
}
