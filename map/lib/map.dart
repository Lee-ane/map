// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_routes/google_maps_routes.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart' as xml;

class MapSample extends StatefulWidget {
  const MapSample({super.key});

  @override
  State<MapSample> createState() => MapSampleState();
}

class MapSampleState extends State<MapSample> {
  TextEditingController originController = TextEditingController();
  TextEditingController destiController = TextEditingController();
  String originSearch = '';
  String destiSearch = '';
  late LatLng searchLocation1;
  late LatLng searchLocation2;

  //kml
  String kmldata = '';
  int markerCount = 0;
  int polygonCount = 0;

  String locationMessage = '';

  late String lat;
  late String long;

  late GoogleMapController mapController;

  late BitmapDescriptor customMarkerIcon;

  //properties
  Set<Marker> markers = {};
  Set<Polyline> polyLines = {};
  Set<Polygon> polygonset = {};
  Set<Circle> circle = {};

  //color list
  List<int> colorlist = [];

  // cN
  List<LatLng> polylineCoordinate = [];
  List<LatLng> checkDistance = [];
  List<LatLng> cN = [];
  List<LatLng> coupon = [];

  //Zone
  List<List<LatLng>> zones = [];
  String nearestPolygonId = '';

  Map<PolylineId, Polyline> polylines = {};

  //Click markers
  LatLng? fromLocation;
  LatLng? toLocation;

  LatLng? location3;
  LatLng? location4;

  LatLng? currentLocation;

  // redZone Radius
  final double _redZoneRadius = 200.0;

  bool setting = false;

  bool distance = false;

  MapType _currentMapType = MapType.normal;

  late LatLng closest;

  bool isWithinBoundary = false;

  // get marker list inside a zone
  List<Marker> markersWithinSameBoundary = [];

  String polygonIdValue = '';

  LatLng? polypoints;

  String chooseZone = 'Choose your zone';

  List<String> zoneName = [];

  List<Marker> markersWithinBoundary = [];

  double latSum = 0.0;

  double lonSum = 0.0;

  MapsRoutes route = MapsRoutes();
  DistanceCalculator distanceCalculator = DistanceCalculator();
  String googleApiKey = 'AIzaSyDwlo11bBEgWSbLOvFAIyAy1-a1sECNT4I';
  String totalDistance = '';

  // default zoom
  static const CameraPosition _kGooglePlex = CameraPosition(
    target: LatLng(10.765193054035123, 106.70651742346368),
    zoom: 15,
  );

  @override
  void initState() {
    super.initState();
    setCustomMarker();
    getCurrentLocation();
    loadkmldata();
  }

  //share preferences
  void loadkmldata() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String? storedKmlData = prefs.getString('kmldata');
    if (storedKmlData != null) {
      setState(() {
        kmldata = storedKmlData;
        _fetchdata(kmldata);
      });
    }
  }

  //import Files
  void _fetchxml() async {
    FilePickerResult? result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['xml']);

    if (result != null) {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      File file = File(result.files.single.path!);
      kmldata = await file.readAsString();

      await prefs.setString('kml', kmldata);

      setState(() {
        _fetchdata(kmldata);
        Navigator.pop(context);
      });
    }
  }

  //fetch XML data
  void _fetchdata(String kmldata) async {
    markers.clear();
    polygonCount = 0;
    markerCount = 0;
    cN.clear();
    polygonset.clear();

    var document = xml.XmlDocument.parse(kmldata);
    var placemarks = document.findAllElements('Placemark');

    for (var placemark in placemarks) {
      var name = placemark.findElements('name').first;
      var nameString = name.text;
      var color = placemark.findElements('styleUrl').first;
      var colorString = color.text;
      var hex = colorString.split('-')[1];
      var colors = int.parse('0xff$hex');
      colorlist.add(colors);
      var points = placemark.findElements('Point').toList();
      var polygons = placemark.findElements('Polygon').toList();

      if (points.isNotEmpty) {
        var pointsElement = points.first;
        var coordinatesElement =
            pointsElement.findElements('coordinates').single;
        var coordinates = coordinatesElement.text.split(',');
        var lat = double.parse(coordinates[1]);
        var lon = double.parse(coordinates[0]);
        var markerId = MarkerId(nameString);
        var marker = Marker(
            markerId: markerId,
            position: LatLng(lat, lon),
            infoWindow: InfoWindow(
              title: nameString,
            ));
        markers.add(marker);
        cN.add(LatLng(lat, lon));
        markerCount++;
      }

      if (polygons.isNotEmpty) {
        var polygonElement = polygons.first;
        var outerBoundary =
            polygonElement.findElements('outerBoundaryIs').first;
        var linearRing = outerBoundary.findElements('LinearRing').first;
        var coordinates = linearRing.findElements('coordinates').first;
        var coordinatesText = coordinates.text;
        var coordinateLines = coordinatesText.trim().split('\n');
        var zoneCoordinates = coordinateLines.map((line) {
          var parts = line.trim().split(',');
          var lat = double.parse(parts[1]);
          var lon = double.parse(parts[0]);
          return LatLng(lat, lon);
        }).toList();
        var polygonId = PolygonId(nameString);
        var polygonObj = Polygon(
          points: zoneCoordinates,
          fillColor: Color(colorlist[polygonCount]).withOpacity(0.2),
          strokeColor: Color(colorlist[polygonCount]),
          strokeWidth: 1,
          polygonId: polygonId,
          onTap: () {},
        );
        zones.add(zoneCoordinates);
        polygonset.add(polygonObj);
        polygonCount++;
        for (var i in polygonset) {
          if (i.points == zoneCoordinates) {
            zoneName.add(i.polygonId.value);
          }
        }
      }
    }
    setState(() {});
  }

// find the closest CN marker
  Future<LatLng> checkClosestLocation() async {
    double minDistance = double.infinity;
    getCurrentLocation();

    for (var cn in cN) {
      double distances = Geolocator.distanceBetween(currentLocation!.latitude,
          currentLocation!.longitude, cn.latitude, cn.longitude);
      if (distances < minDistance) {
        minDistance = distances;
        distance = !distance;
        totalDistance = '${(minDistance / 1000).toStringAsFixed(1)} km';
        closest = cn;
      }
    }
    markers.removeWhere((element) => element.position == closest);
    Marker closestCN = Marker(
        markerId: const MarkerId('closest_location'),
        position: closest,
        infoWindow: const InfoWindow(title: 'closest_Location'));
    markers.add(closestCN);
    return closest;
  }

// check if it within zone
  void checkLocationWithinBoundary(LatLng currentLocation) {
    for (final polygon in polygonset) {
      if (isPointInPolygon(currentLocation, polygon.points)) {
        polygonIdValue = polygon.polygonId.value;
        isWithinBoundary = true;
        break;
      }
    }
    if (isWithinBoundary) {
      mapController.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(
              currentLocation.latitude,
              currentLocation.longitude,
            ),
            zoom: 16,
          ),
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Center(
              child: Text(
                  'Current location is within $polygonIdValue, HCM City.')),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Center(
              child:
                  Text('Current location is outside of supported Districts')),
        ),
      );
    }
  }

// get list markers within same zone
  List<Marker> getMarkersWithinSameBoundary() {
    List<Marker> markersWithinSameBoundary = [];

    for (final Marker marker in markers) {
      LatLng markerLocation = marker.position;
      bool isWithinBoundary = false;

      for (final List<LatLng> zone in zones) {
        if (isPointInSamePolygon(currentLocation!, zone) &&
            isPointInSamePolygon(markerLocation, zone)) {
          isWithinBoundary = true;
          break;
        }
      }

      if (isWithinBoundary) {
        markersWithinSameBoundary.add(marker);
      }
    }

    return markersWithinSameBoundary;
  }

  bool isPointInSamePolygon(LatLng point, List<LatLng> polygon) {
    bool isInside = false;
    int j = polygon.length - 1;

    for (int i = 0; i < polygon.length; i++) {
      if ((polygon[i].latitude < point.latitude &&
              polygon[j].latitude >= point.latitude) ||
          (polygon[j].latitude < point.latitude &&
              polygon[i].latitude >= point.latitude)) {
        if (polygon[i].longitude +
                (point.latitude - polygon[i].latitude) /
                    (polygon[j].latitude - polygon[i].latitude) *
                    (polygon[j].longitude - polygon[i].longitude) <
            point.longitude) {
          isInside = !isInside;
        }
      }
      j = i;
    }

    return isInside;
  }

  bool isPointInPolygon(LatLng point, List<LatLng> polygon) {
    bool isInside = false;
    int j = polygon.length - 1;

    for (int i = 0; i < polygon.length; i++) {
      if ((polygon[i].latitude < point.latitude &&
              polygon[j].latitude >= point.latitude) ||
          (polygon[j].latitude < point.latitude &&
              polygon[i].latitude >= point.latitude)) {
        if (polygon[i].longitude +
                (point.latitude - polygon[i].latitude) /
                    (polygon[j].latitude - polygon[i].latitude) *
                    (polygon[j].longitude - polygon[i].longitude) <
            point.longitude) {
          isInside = !isInside;
        }
      }
      j = i;
    }

    return isInside;
  }

// get the current location
  Future<LatLng> getCurrentLocation() async {
    LocationPermission permission;
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.deniedForever) {
        return Future.error('Unable to get your location');
      }
    }

    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    currentLocation = LatLng(position.latitude, position.longitude);
    Marker currentMarker = Marker(
        markerId: const MarkerId('current_location'),
        position: currentLocation!,
        infoWindow: const InfoWindow(title: 'Current Location'));
    setState(() {
      checkLocationWithinBoundary(currentLocation!);
      circle.add(Circle(
          circleId: const CircleId('Current-circle'),
          radius: _redZoneRadius,
          center: LatLng(currentLocation!.latitude, currentLocation!.longitude),
          fillColor: Colors.red.withOpacity(0.3),
          strokeColor: Colors.red,
          strokeWidth: 2));
      checkDistance.add(currentLocation!);
      markers.add(currentMarker);
    });
    return currentLocation!;
  }

//find route
  void getPolyPoints() async {
    PolylinePoints polylinePoints = PolylinePoints();

    try {
      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        googleApiKey,
        PointLatLng(fromLocation!.latitude, fromLocation!.longitude),
        PointLatLng(toLocation!.latitude, toLocation!.longitude),
      );

      if (result.errorMessage != null && result.errorMessage!.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Center(child: Text('Too much request please try later')),
          ),
        );
      } else if (result.points.isNotEmpty) {
        for (var point in result.points) {
          polylineCoordinate.add(LatLng(point.latitude, point.longitude));
        }
        setState(() {
          addPolyLine();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Center(child: Text('Routing'))),
          );
          distance = !distance;
          totalDistance = distanceCalculator
              .calculateRouteDistance(polylineCoordinate, decimals: 1);
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Center(child: Text('No route found')),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Center(child: Text('Error: $e')),
        ),
      );
    }
  }

// add route line
  addPolyLine() {
    PolylineId id = const PolylineId("poly");
    Polyline polyline = Polyline(
        polylineId: id,
        color: Colors.blue,
        width: 10,
        points: polylineCoordinate);
    polylines[id] = polyline;
    setState(() {});
  }

//check nearest polygon
  void checkNearestPolygon(LatLng currentLocation) {
    double minDistance = double.infinity;
    String nearestId = '';

    for (var polygon in polygonset) {
      List<LatLng> points = polygon.points;
      double distance = double.infinity;

      for (int i = 0; i < points.length; i++) {
        double d = _calculateDistance(currentLocation, points[i]);
        if (d < distance) {
          distance = d;
        }
      }

      if (distance < minDistance) {
        minDistance = distance;
        nearestId = polygon.polygonId.value;
      }
    }

    setState(() {
      nearestPolygonId = nearestId;
      if (isWithinBoundary == false) {
        if (polygonset.isNotEmpty) {
          polygonset.retainWhere(
              (polygon) => polygon.polygonId.value == nearestPolygonId);
          distance = !distance;
          totalDistance = '${(minDistance / 100).toStringAsFixed(1)} km';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Center(
                child: Text('The nearest district is $nearestPolygonId')),
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Center(child: Text('Having trouble finding nearest district.')),
          ));
        }
      }
    });
  }

  double _calculateDistance(LatLng pos1, LatLng pos2) {
    const double earthRadius = 6371000;
    double lat1 = pos1.latitude * pi / 180;
    double lat2 = pos2.latitude * pi / 180;
    double lon1 = pos1.longitude * pi / 180;
    double lon2 = pos2.longitude * pi / 180;

    double dLat = lat2 - lat1;
    double dLon = lon2 - lon1;

    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    double distance = earthRadius * c; // Distance in meters
    return distance;
  }

// search
  void originAddress() async {
    try {
      List<Location> locations = await locationFromAddress(originSearch);
      setState(() {
        searchLocation1 = LatLng(locations[0].latitude, locations[0].longitude);
      });
      if (fromLocation == null) {
        setState(() {
          fromLocation = searchLocation1;
          checkLocationWithinBoundary(fromLocation!);
          markers.add(Marker(
              markerId: const MarkerId('from_location'),
              position: searchLocation1,
              icon: customMarkerIcon,
              infoWindow: InfoWindow(
                  title:
                      '${fromLocation!.latitude}, ${fromLocation!.longitude}')));
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Center(child: Text('Your beginning already exist')),
          ),
        );
      }
      mapController.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: searchLocation1,
            zoom: 19,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Center(child: Text('$e')),
        ),
      );
    }
  }

// search destination
  void destiAddress() async {
    try {
      List<Location> locations = await locationFromAddress(destiSearch);
      setState(() {
        searchLocation2 = LatLng(locations[0].latitude, locations[0].longitude);
      });
      if (toLocation == null) {
        setState(() {
          toLocation = searchLocation2;
          checkLocationWithinBoundary(toLocation!);
          markers.add(Marker(
              markerId: const MarkerId('to_location'),
              position: searchLocation2,
              icon: customMarkerIcon,
              infoWindow: InfoWindow(
                  title: '${toLocation!.latitude}, ${toLocation!.longitude}')));
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Center(child: Text('Your destination already exist')),
          ),
        );
      }
      mapController.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: searchLocation2,
            zoom: 19,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Center(child: Text('$e')),
        ),
      );
    }
  }

// custom marker
  void setCustomMarker() async {
    final response = await http
        .get(Uri.parse('https://assets.mapquestapi.com/icon/v2/marker@2x.png'));
    final bytes = response.bodyBytes;
    customMarkerIcon = BitmapDescriptor.fromBytes(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SizedBox(
            child: Stack(
              children: [
                //map
                GoogleMap(
                  mapType: _currentMapType,
                  initialCameraPosition: _kGooglePlex,
                  onMapCreated: (GoogleMapController controller) {
                    mapController = controller;
                  },
                  //properties
                  markers: markers,
                  circles: circle,
                  polygons: polygonset,
                  polylines: Set<Polyline>.of(polylines.values),
                  onTap: (LatLng location) {
                    if (location3 == null) {
                      setState(() {
                        location3 = location;
                        markers.add(Marker(
                            markerId: const MarkerId('location3'),
                            position: location,
                            icon: customMarkerIcon,
                            infoWindow: InfoWindow(
                                title:
                                    '${location3!.latitude}, ${location3!.longitude}')));
                      });
                    } else if (location4 == null) {
                      setState(() {
                        location4 = location;
                        markers.add(Marker(
                            markerId: const MarkerId('location4'),
                            position: location,
                            icon: customMarkerIcon,
                            infoWindow: InfoWindow(
                                title:
                                    '${location4!.latitude}, ${location4!.longitude}')));
                      });
                    }
                  },
                ),
                //choose zone
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                          width: screenWidth * 0.4,
                          height: screenHeight * 0.05,
                          decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(25),
                              border: Border.all(color: Colors.black)),
                          child: Center(
                            child: TextButton(
                              onPressed: () {
                                zoneName.isEmpty
                                    ? ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                        const SnackBar(
                                          content: Center(
                                              child: Text(
                                                  'Hiện không có zone nào tồn tại.')),
                                        ),
                                      )
                                    : showDialog(
                                        context: context,
                                        builder: (context) => SimpleDialog(
                                          title:
                                              const Text('Danh sách các zone'),
                                          children: zoneName
                                              .map((zone) => InkWell(
                                                    onTap: () {
                                                      setState(() {
                                                        chooseZone = zone;
                                                        Navigator.pop(context);
                                                        for (final polygon
                                                            in polygonset) {
                                                          if (zone ==
                                                              polygon.polygonId
                                                                  .value) {
                                                            for (Marker marker
                                                                in markers) {
                                                              if (isPointInPolygon(
                                                                  marker
                                                                      .position,
                                                                  polygon
                                                                      .points)) {
                                                                markersWithinBoundary
                                                                    .add(
                                                                        marker);
                                                                latSum = 0.0;
                                                                lonSum = 0.0;
                                                                for (LatLng point
                                                                    in polygon
                                                                        .points) {
                                                                  latSum += point
                                                                      .latitude;
                                                                  lonSum += point
                                                                      .longitude;
                                                                }
                                                                mapController
                                                                    .animateCamera(
                                                                  CameraUpdate
                                                                      .newCameraPosition(
                                                                    CameraPosition(
                                                                      target:
                                                                          LatLng(
                                                                        latSum /
                                                                            polygon.points.length,
                                                                        lonSum /
                                                                            polygon.points.length,
                                                                      ),
                                                                      zoom: 16,
                                                                    ),
                                                                  ),
                                                                );
                                                              }
                                                            }
                                                          }
                                                        }
                                                        showDialog(
                                                          context: context,
                                                          builder: (context) {
                                                            return Scaffold(
                                                                backgroundColor:
                                                                    Colors
                                                                        .transparent,
                                                                body: Align(
                                                                  alignment:
                                                                      Alignment
                                                                          .centerRight,
                                                                  child: Container(
                                                                      width: screenWidth * 0.7,
                                                                      height: screenHeight * 1,
                                                                      decoration: const BoxDecoration(color: Colors.white),
                                                                      child: Scaffold(
                                                                        appBar:
                                                                            AppBar(
                                                                          title:
                                                                              const Text('Marker list'),
                                                                          leading:
                                                                              IconButton(
                                                                            onPressed:
                                                                                () {
                                                                              setState(() {
                                                                                markersWithinBoundary.clear();
                                                                                Navigator.pop(context);
                                                                              });
                                                                            },
                                                                            icon:
                                                                                const Icon(Icons.arrow_back),
                                                                          ),
                                                                        ),
                                                                        body: ListView
                                                                            .builder(
                                                                          itemCount:
                                                                              markersWithinBoundary.length,
                                                                          itemBuilder:
                                                                              (context, index) {
                                                                            final marker =
                                                                                markersWithinBoundary[index];
                                                                            return ListTile(
                                                                              title: Text(marker.markerId.value),
                                                                            );
                                                                          },
                                                                        ),
                                                                      )),
                                                                ));
                                                          },
                                                        );
                                                      });
                                                    },
                                                    child: ListTile(
                                                      title: Text(zone),
                                                    ),
                                                  ))
                                              .toList(),
                                        ),
                                      );
                              },
                              child: Text(
                                chooseZone,
                                style: const TextStyle(color: Colors.black),
                              ),
                            ),
                          ))),
                ),
                //search
                Padding(
                  padding: const EdgeInsets.only(top: 10, right: 10),
                  child: Align(
                      alignment: Alignment.topRight,
                      child: Container(
                        height: screenHeight * 0.05,
                        width: screenWidth * 0.1,
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(100),
                            color: const Color(0xff343431)),
                        child: IconButton(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) {
                                  return Scaffold(
                                    backgroundColor: Colors.transparent,
                                    body: Column(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10),
                                          child: TextField(
                                            decoration: InputDecoration(
                                              fillColor: Colors.white,
                                              filled: true,
                                              labelText: 'Origin',
                                              suffixIcon: IconButton(
                                                  icon:
                                                      const Icon(Icons.search),
                                                  onPressed: originAddress),
                                            ),
                                            controller: originController,
                                            onChanged: (value) {
                                              originSearch =
                                                  originController.text;
                                            },
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10),
                                          child: TextField(
                                            decoration: InputDecoration(
                                              fillColor: Colors.white,
                                              filled: true,
                                              labelText: 'Destination',
                                              suffixIcon: IconButton(
                                                  icon:
                                                      const Icon(Icons.search),
                                                  onPressed: () {
                                                    setState(() {
                                                      destiAddress;
                                                    });
                                                  }),
                                            ),
                                            controller: destiController,
                                            onChanged: (value) {
                                              destiSearch =
                                                  destiController.text;
                                            },
                                          ),
                                        ),
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(right: 340),
                                          child: IconButton(
                                              icon: Icon(
                                                  Icons.arrow_back_rounded,
                                                  color: Colors.amber[800]),
                                              onPressed: () {
                                                Navigator.pop(context);
                                              }),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                            icon: Icon(
                              Icons.search,
                              color: Colors.amber[600],
                            )),
                      )),
                ),
                // current location
                Padding(
                  padding: const EdgeInsets.only(right: 12, bottom: 100),
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      width: screenWidth * 0.1,
                      height: screenHeight * 0.05,
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(100),
                          color: const Color(0xff343431)),
                      child: IconButton(
                        onPressed: () async {
                          LatLng currentLocation = await getCurrentLocation();
                          mapController.animateCamera(
                            CameraUpdate.newCameraPosition(
                              CameraPosition(
                                target: LatLng(
                                  currentLocation.latitude,
                                  currentLocation.longitude,
                                ),
                                zoom: 17,
                              ),
                            ),
                          );
                        },
                        icon: Icon(Icons.gps_fixed_sharp,
                            color: Colors.amber[600]),
                      ),
                    ),
                  ),
                ),
                //map type
                Padding(
                  padding: const EdgeInsets.only(right: 10, top: 60),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      width: screenWidth * 0.1,
                      height: screenHeight * 0.05,
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(100),
                          color: const Color(0xff343431)),
                      child: IconButton(
                        onPressed: () {
                          setState(() {
                            _currentMapType =
                                (_currentMapType == MapType.normal)
                                    ? MapType.satellite
                                    : MapType.normal;
                          });
                        },
                        icon: Icon(
                          Icons.map,
                          color: Colors.amber[600],
                        ),
                      ),
                    ),
                  ),
                ),
                //Export
                Padding(
                  padding: const EdgeInsets.only(right: 10, top: 110),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(100),
                          color: const Color(0xff343431)),
                      width: screenWidth * 0.1,
                      height: screenHeight * 0.05,
                      child: IconButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) {
                              return Scaffold(
                                  backgroundColor: Colors.transparent,
                                  body: Center(
                                    child: Container(
                                        width: screenWidth * 0.5,
                                        height: screenHeight * 0.2,
                                        decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(25)),
                                        child: Column(
                                          children: [
                                            const Align(
                                              alignment: Alignment.topLeft,
                                              child: CloseButton(
                                                color: Colors.red,
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                _fetchxml();
                                              },
                                              child: const Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Padding(
                                                    padding: EdgeInsets.only(
                                                        right: 10),
                                                    child: Icon(
                                                      Icons
                                                          .cloud_download_outlined,
                                                      color: Colors.black,
                                                    ),
                                                  ),
                                                  Text(
                                                    'Import XML',
                                                    style: TextStyle(
                                                        color: Colors.black),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                setState(() {
                                                  markers.clear();
                                                  polygonCount = 0;
                                                  markerCount = 0;
                                                  cN.clear();
                                                  polygonset.clear();
                                                });
                                              },
                                              child: const Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Padding(
                                                    padding: EdgeInsets.only(
                                                        right: 10),
                                                    child: Icon(
                                                      Icons.delete,
                                                      color: Colors.black,
                                                    ),
                                                  ),
                                                  Text(
                                                    'Remove data',
                                                    style: TextStyle(
                                                        color: Colors.black),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        )),
                                  ));
                            },
                          );
                        },
                        icon: Icon(
                          Icons.arrow_outward_sharp,
                          color: Colors.amber[600],
                        ),
                      ),
                    ),
                  ),
                ),
                //options
                Padding(
                  padding: const EdgeInsets.only(left: 10, bottom: 10),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Container(
                      width: screenWidth * 0.12,
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(100),
                          color: const Color(0xff343431)),
                      child: TextButton(
                        onPressed: () {
                          setState(() {
                            setting = !setting;
                          });
                        },
                        child: Icon(
                          Icons.arrow_drop_up_sharp,
                          color: Colors.amber[600],
                        ),
                      ),
                    ),
                  ),
                ),
                // Route
                Visibility(
                  visible: setting,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10, bottom: 160),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Container(
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(100),
                            color: const Color(0xff343431)),
                        width: screenWidth * 0.12,
                        child: TextButton(
                          onPressed: () async {
                            if (fromLocation != null && toLocation != null) {
                              setState(() {
                                getPolyPoints();
                              });
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Center(
                                          child: Text(
                                              'Please set your location and destination first'))));
                            }
                          },
                          onLongPress: () {
                            setState(() {
                              polylineCoordinate.clear();
                              distance = false;
                              totalDistance = '0';
                            });
                          },
                          child: Icon(
                            Icons.line_axis_rounded,
                            color: Colors.amber[600],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // refresh
                Visibility(
                  visible: setting,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10, bottom: 60),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Container(
                        width: screenWidth * 0.12,
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(100),
                            color: const Color(0xff343431)),
                        child: IconButton(
                          onPressed: () async {
                            markers.clear();
                            setState(() {
                              distance = false;
                              fromLocation = null;
                              toLocation = null;
                              location3 = null;
                              location4 = null;
                              circle.clear();
                              zoneName.clear();
                              _fetchdata(kmldata);
                            });
                          },
                          icon: Icon(
                            Icons.refresh,
                            color: Colors.amber[600],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Find nearest Polygon
                Visibility(
                  visible: setting,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10, bottom: 110),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Container(
                        width: screenWidth * 0.12,
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(100),
                            color: const Color(0xff343431)),
                        child: TextButton(
                          onPressed: () async {
                            checkLocationWithinBoundary(currentLocation!);
                            if (isWithinBoundary == false) {
                              checkNearestPolygon(currentLocation!);
                            } else {
                              setState(() {
                                totalDistance = '';
                                checkClosestLocation();
                                markersWithinSameBoundary =
                                    getMarkersWithinSameBoundary();
                              });
                              showDialog(
                                context: context,
                                builder: (context) {
                                  return Scaffold(
                                      backgroundColor: Colors.transparent,
                                      body: Align(
                                        alignment: Alignment.centerRight,
                                        child: Container(
                                            width: screenWidth * 0.7,
                                            height: screenHeight * 1,
                                            decoration: const BoxDecoration(
                                                color: Colors.white),
                                            child: Scaffold(
                                              appBar: AppBar(
                                                title:
                                                    const Text('Marker list'),
                                              ),
                                              body: ListView.builder(
                                                itemCount:
                                                    markersWithinSameBoundary
                                                        .length,
                                                itemBuilder: (context, index) {
                                                  final marker =
                                                      markersWithinSameBoundary[
                                                          index];
                                                  return ListTile(
                                                    title: Text(
                                                        marker.markerId.value),
                                                  );
                                                },
                                              ),
                                            )),
                                      ));
                                },
                              );
                            }
                          },
                          onLongPress: () {
                            setState(() {
                              try {
                                polygonset.clear();
                                polygonCount = 0;
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Center(child: Text('Error: $e')),
                                  ),
                                );
                              }
                            });
                          },
                          child: Icon(
                            Icons.square_outlined,
                            color: Colors.amber[600],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                //distance
                Visibility(
                  visible: distance,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                          width: 200,
                          height: 50,
                          decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(15.0)),
                          child: Align(
                            alignment: Alignment.center,
                            child: Text(totalDistance,
                                style: const TextStyle(fontSize: 25.0)),
                          )),
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
