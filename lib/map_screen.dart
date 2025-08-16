import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as location_pkg;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:google_places_flutter/model/prediction.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth/login_screen.dart';
import 'profile/profile_screen.dart';
import 'feedback/visit_feedback_list_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final List<LatLng> _breadcrumbs = [];
  
  location_pkg.LocationData? _currentLocation;
  final location_pkg.Location _location = location_pkg.Location();
  LatLng? _destinationLatLng;
  LatLng? _originLatLng;
  List<LatLng> _routePoints = [];
  
  bool _isNavigating = false;
  bool _showSearchPanel = true;
  bool _isBackgroundServiceRunning = false;
  String _navigationPurpose = '';
  String? _activeSessionId;
  String? _lastEncodedPolyline;
  LatLng? _lastSavedActualPoint;
  DateTime? _lastSavedActualPointAt;
  
  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  
  StreamSubscription<location_pkg.LocationData>? _locationSubscription;
  StreamSubscription<Map<String, dynamic>?>? _bgSubscription;
  
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  
  static const String _apiKey = 'AIzaSyAOmvphuquc8n1-hPPm_zRoBC2opcw5m8c';
  
  // Route recalculation variables
  LatLng? _lastRouteOrigin;
  DateTime? _lastRouteUpdate;
  static const Duration _routeRecalcInterval = Duration(minutes: 5);
  static const double _routeRecalcDistanceMeters = 100.0;

  // Calculate distance between two points in meters
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000; // Earth's radius in meters
    final double lat1Rad = point1.latitude * math.pi / 180;
    final double lat2Rad = point2.latitude * math.pi / 180;
    final double deltaLatRad = (point2.latitude - point1.latitude) * math.pi / 180;
    final double deltaLngRad = (point2.longitude - point1.longitude) * math.pi / 180;

    final double a = math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
        math.cos(lat1Rad) * math.cos(lat2Rad) *
        math.sin(deltaLngRad / 2) * math.sin(deltaLngRad / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  // Calculate bounds for a list of points
  LatLngBounds _calculateBounds(List<LatLng> points) {
    double minLat = points[0].latitude;
    double maxLat = points[0].latitude;
    double minLng = points[0].longitude;
    double maxLng = points[0].longitude;

    for (final point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadNavigationState();
    _ensurePermissions();
    _listenBackgroundUpdates();
    _setupAppLifecycleListener();
  }

  void _initializeAnimations() {
    // Animation setup for future use
  }

  // Save navigation state to persistent storage
  Future<void> _saveNavigationState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isNavigating', _isNavigating);
    await prefs.setBool('showSearchPanel', _showSearchPanel);
    await prefs.setString('destinationText', _destinationController.text);
    await prefs.setString('originText', _originController.text);
    
    if (_destinationLatLng != null) {
      await prefs.setDouble('destLat', _destinationLatLng!.latitude);
      await prefs.setDouble('destLng', _destinationLatLng!.longitude);
    }
    
    if (_originLatLng != null) {
      await prefs.setDouble('originLat', _originLatLng!.latitude);
      await prefs.setDouble('originLng', _originLatLng!.longitude);
    }
  }

  // Load navigation state from persistent storage
  Future<void> _loadNavigationState() async {
    final prefs = await SharedPreferences.getInstance();
    final isNavigating = prefs.getBool('isNavigating') ?? false;
    final showSearchPanel = prefs.getBool('showSearchPanel') ?? true;
    final destinationText = prefs.getString('destinationText') ?? '';
    final originText = prefs.getString('originText') ?? '';
    
    setState(() {
      _isNavigating = isNavigating;
      _showSearchPanel = showSearchPanel;
      _destinationController.text = destinationText;
      _originController.text = originText;
    });
    
    // Restore coordinates if they exist
    final destLat = prefs.getDouble('destLat');
    final destLng = prefs.getDouble('destLng');
    if (destLat != null && destLng != null) {
      _destinationLatLng = LatLng(destLat, destLng);
    }
    
    final originLat = prefs.getDouble('originLat');
    final originLng = prefs.getDouble('originLng');
    if (originLat != null && originLng != null) {
      _originLatLng = LatLng(originLat, originLng);
    }
    
    // If we were navigating, restore the route
    if (_isNavigating && _destinationLatLng != null) {
      _calculateRoute();
      // Start background service if we were navigating
      FlutterBackgroundService().startService();
    }
  }

  // Clear saved navigation state
  Future<void> _clearNavigationState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isNavigating');
    await prefs.remove('showSearchPanel');
    await prefs.remove('destinationText');
    await prefs.remove('originText');
    await prefs.remove('destLat');
    await prefs.remove('destLng');
    await prefs.remove('originLat');
    await prefs.remove('originLng');
  }

  Future<void> _ensurePermissions() async {
    
    // Request location service
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) return;
    }
    
    // Request notification permission for Android 13+
    if (await Permission.notification.request().isGranted) {
      debugPrint('Notification permission granted');
    }
    
    // Request location permissions
    location_pkg.PermissionStatus permissionStatus = await _location.hasPermission();
    if (permissionStatus == location_pkg.PermissionStatus.denied) {
      permissionStatus = await _location.requestPermission();
      if (permissionStatus != location_pkg.PermissionStatus.granted) {
        return;
      }
    }
    // Request background permission as well (Android Q+ / iOS Always)
    await Permission.locationAlways.request();
    // Start with background mode disabled; we'll enable it when navigation starts
    try {
      await _location.enableBackgroundMode(enable: false);
    } catch (_) {}
    
    // Start location updates
    _locationSubscription = _location.onLocationChanged.listen(_onNewPosition);
  }

  Future<void> _onNewPosition(location_pkg.LocationData position) async {
    final newLocation = LatLng(position.latitude!, position.longitude!);
    
    setState(() {
      _currentLocation = position;
      _breadcrumbs.add(newLocation);
      
      // Update user marker
      _markers.removeWhere((marker) => marker.markerId.value == 'user');
      _markers.add(
        Marker(
          markerId: const MarkerId('user'),
          position: newLocation,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'Your Location'),
        ),
      );
    });
    
    // Center map on user's location on first position update
    if (_mapController != null && _breadcrumbs.length == 1) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(newLocation, 15.0),
      );
    }
    
    // Update route polyline if navigating
    if (_isNavigating && _destinationLatLng != null) {
      _updateRoutePolyline();
      // Update live location to Firestore for active session
      if (_activeSessionId != null) {
        try {
          FirebaseFirestore.instance
              .collection('navigation_sessions')
              .doc(_activeSessionId)
              .update({
            'lastLocation': {
              'lat': position.latitude,
              'lng': position.longitude,
            },
            'lastUpdatedAt': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          // ignore errors to not disturb navigation UX
        }

        // Persist actual travelled path to a subcollection with light throttling
        try {
          final currentLatLng = LatLng(position.latitude!, position.longitude!);
          final shouldSavePoint = _lastSavedActualPoint == null ||
              _calculateDistance(currentLatLng, _lastSavedActualPoint!) > 25 ||
              (_lastSavedActualPointAt == null ||
                  DateTime.now().difference(_lastSavedActualPointAt!).inSeconds > 20);
          if (shouldSavePoint) {
            await FirebaseFirestore.instance
                .collection('navigation_sessions')
                .doc(_activeSessionId)
                .collection('route_points')
                .add({
              'lat': position.latitude,
              'lng': position.longitude,
              'recordedAt': FieldValue.serverTimestamp(),
            });
            _lastSavedActualPoint = currentLatLng;
            _lastSavedActualPointAt = DateTime.now();
          }
        } catch (e) {
          // ignore
        }
      }
    }
  }

  void _updateRoutePolyline() {
    if (_currentLocation == null || _destinationLatLng == null) return;
    
    final currentLatLng = LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!);
    
    // Check if we need to recalculate the route
    final shouldRecalculate = _lastRouteOrigin == null ||
        _lastRouteUpdate == null ||
        DateTime.now().difference(_lastRouteUpdate!) > _routeRecalcInterval ||
        _calculateDistance(currentLatLng, _lastRouteOrigin!) > _routeRecalcDistanceMeters;
    
    if (shouldRecalculate) {
      _calculateRoute();
      _lastRouteOrigin = currentLatLng;
      _lastRouteUpdate = DateTime.now();
    } else {
      // Update the route polyline with the existing route points
      if (_routePoints.isNotEmpty) {
        setState(() {
          _polylines.removeWhere((polyline) => polyline.polylineId.value == 'route');
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              points: _routePoints,
              color: Colors.blue,
              width: 5,
            ),
          );
        });
      }
    }
  }

  Future<List<LatLng>> _getDirections(LatLng origin, LatLng destination) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?'
        'origin=${origin.latitude},${origin.longitude}&'
        'destination=${destination.latitude},${destination.longitude}&'
        'mode=driving&'
        'alternatives=true&'
        'key=$_apiKey',
      );
      
      final response = await http.get(url);
      final data = json.decode(response.body);
      
      if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
        // Use the first (fastest) route
        final points = data['routes'][0]['overview_polyline']['points'];
        final route = _decodePolyline(points);
        _lastEncodedPolyline = points;
        // Persist route polyline to Firestore if a session is active
        if (_activeSessionId != null) {
          // ignore: unawaited_futures
          _saveRouteToFirestore(points, route);
        }
        
        // Add destination marker if not already present
        setState(() {
          _markers.removeWhere((marker) => marker.markerId.value == 'destination');
          _markers.add(
            Marker(
              markerId: const MarkerId('destination'),
              position: destination,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
              infoWindow: InfoWindow(title: _destinationController.text),
            ),
          );
        });
        
        return route;
      } else {
        debugPrint('Directions API error: ${data['status']} - ${data['error_message'] ?? 'Unknown error'}');
      }
    } catch (e) {
      debugPrint('Error getting directions: $e');
    }
    
    // Fallback to straight line
    return [origin, destination];
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      final p = LatLng((lat / 1E5).toDouble(), (lng / 1E5).toDouble());
      poly.add(p);
    }
    return poly;
  }

  Future<void> _saveRouteToFirestore(String encoded, List<LatLng> points) async {
    if (_activeSessionId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('navigation_sessions')
          .doc(_activeSessionId)
          .update({
        'routePolylineEncoded': encoded,
        'routePolylinePoints': points
            .map((p) => {
                  'lat': p.latitude,
                  'lng': p.longitude,
                })
            .toList(),
        'routeUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // ignore Firestore write errors to not affect UX
    }
  }

  Future<void> _saveInitialRouteToFirestore(String encoded, List<LatLng> points) async {
    if (_activeSessionId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('navigation_sessions')
          .doc(_activeSessionId)
          .set({
        'routePolylineEncodedInitial': encoded,
        'routePolylinePointsInitial': points
            .map((p) => {
                  'lat': p.latitude,
                  'lng': p.longitude,
                })
            .toList(),
        'routeInitialSavedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      // ignore
    }
  }

  Future<String> _getCurrentLocationAddress(LatLng location) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?'
        'latlng=${location.latitude},${location.longitude}&'
        'key=$_apiKey',
      );
      
      final response = await http.get(url);
      final data = json.decode(response.body);
      
      if (data['status'] == 'OK' && data['results'].isNotEmpty) {
        return data['results'][0]['formatted_address'];
      }
    } catch (e) {
      debugPrint('Error getting address: $e');
    }
    
    return 'Current Location';
  }

  Future<LatLng?> _geocodeAddress(String address) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?'
        'address=${Uri.encodeComponent(address)}&'
        'key=$_apiKey',
      );
      
      final response = await http.get(url);
      final data = json.decode(response.body);
      
      if (data['status'] == 'OK' && data['results'].isNotEmpty) {
        final location = data['results'][0]['geometry']['location'];
        return LatLng(location['lat'], location['lng']);
      }
    } catch (e) {
      debugPrint('Error geocoding address: $e');
    }
    
    return null;
  }

  Future<void> _calculateRoute() async {
    if (_currentLocation == null || _destinationLatLng == null) return;
    
    final origin = LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!);
    final routePoints = await _getDirections(origin, _destinationLatLng!);
    
    setState(() {
      _routePoints = routePoints;
      _polylines.removeWhere((polyline) => polyline.polylineId.value == 'route');
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: routePoints,
          color: Colors.blue,
          width: 5,
        ),
      );
    });
    
    // Update map camera to show the entire route
    if (_mapController != null && routePoints.length > 1) {
      final bounds = _calculateBounds(routePoints);
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 50.0),
      );
    }
  }

  Future<void> _askPurposeAndStart() async {
    String purpose = '';
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        const Color primary = Color(0xFF1E40AF);
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.flag, color: primary, size: 30),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Navigation purpose',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Purpose (e.g., Client visit, Delivery, Inspection)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => purpose = v.trim(),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              if (purpose.isEmpty) return;
                              _navigationPurpose = purpose;
                              Navigator.of(ctx).pop();
                            },
                            child: const Text('OK'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (_navigationPurpose.isNotEmpty) {
      _startNavigation();
    }
  }

  void _startNavigation() {
    if (_destinationController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a destination'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    if (_currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait for location to be available'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    _originLatLng = LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!);
    
    _getCurrentLocationAddress(_originLatLng!).then((address) {
      _originController.text = address;
    });
    
    _geocodeAddress(_destinationController.text).then((latLng) {
      if (latLng != null) {
        _destinationLatLng = latLng;
        
        _calculateRoute().then((_) async {
          setState(() {
            _isNavigating = true;
            _showSearchPanel = false;
          });
          
          // Save navigation state
          _saveNavigationState();
          
          FlutterBackgroundService().startService();
          // Enable background location updates and tighten update policy for navigation
          try {
            await _location.enableBackgroundMode(enable: true);
            await _location.changeSettings(
              accuracy: location_pkg.LocationAccuracy.high,
              interval: 3000,
              distanceFilter: 10,
            );
          } catch (_) {}
          
          // Create Firestore session document
          try {
            final userId = FirebaseAuth.instance.currentUser?.uid;
            if (userId != null) {
              final sessionRef = await FirebaseFirestore.instance
                  .collection('navigation_sessions')
                  .add({
                'userId': userId,
                'purpose': _navigationPurpose,
                'startedAt': FieldValue.serverTimestamp(),
                'origin': {
                  'lat': _originLatLng!.latitude,
                  'lng': _originLatLng!.longitude,
                  'address': _originController.text,
                },
                'destination': {
                  'lat': _destinationLatLng!.latitude,
                  'lng': _destinationLatLng!.longitude,
                  'address': _destinationController.text,
                },
                'status': 'active',
              });
              _activeSessionId = sessionRef.id;
              // Save initial route polyline for this session if available
              if (_lastEncodedPolyline != null && _routePoints.isNotEmpty) {
                // ignore: unawaited_futures
                _saveRouteToFirestore(_lastEncodedPolyline!, _routePoints);
                // Also persist the initial full route once for history
                // ignore: unawaited_futures
                _saveInitialRouteToFirestore(_lastEncodedPolyline!, _routePoints);
              }
            }
          } catch (e) {
            // ignore errors so navigation continues
          }

          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              _showNavigationNotification();
            }
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Navigation started!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not find the destination address'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    });
  }

  void _stopNavigation() {
    setState(() {
      _isNavigating = false;
      _showSearchPanel = true;
      _routePoints.clear();
      _originController.clear();
      _destinationController.clear();
    });
    
    // Clear saved navigation state
    _clearNavigationState();
    
    FlutterBackgroundService().invoke('stopService');
    _hideNavigationNotification();
    // Disable background mode to save battery
    // Best-effort; ignore any errors
    // ignore: unawaited_futures
    _location.enableBackgroundMode(enable: false);

    // Mark Firestore session ended
    if (_activeSessionId != null) {
      try {
        FirebaseFirestore.instance
            .collection('navigation_sessions')
            .doc(_activeSessionId)
            .update({
          'status': 'ended',
          'endedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        // ignore
      }
    }
    _activeSessionId = null;
    _navigationPurpose = '';
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Navigation stopped'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _showNavigationNotification() async {
    if (!_isNavigating) return;
    
    try {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'trackme_navigation',
        'TrackMe Navigation',
        channelDescription: 'Navigation notifications',
        importance: Importance.high,
        priority: Priority.high,
        ongoing: true,
        autoCancel: false,
      );
      
      const NotificationDetails platformChannelSpecifics =
          NotificationDetails(android: androidPlatformChannelSpecifics);
      
      await flutterLocalNotificationsPlugin.show(
        0,
        'TrackMe Navigation',
        'Navigating to: ${_destinationController.text}',
        platformChannelSpecifics,
      );
    } catch (e) {
      debugPrint('Error showing navigation notification: $e');
    }
  }

  void _hideNavigationNotification() async {
    try {
      await flutterLocalNotificationsPlugin.cancel(0);
    } catch (e) {
      debugPrint('Error hiding navigation notification: $e');
    }
  }

  void _setupAppLifecycleListener() {
    SystemChannels.lifecycle.setMessageHandler((msg) async {
      if (msg == AppLifecycleState.paused.toString()) {
        if (_isNavigating) {
          _showNavigationNotification();
        }
      } else if (msg == AppLifecycleState.resumed.toString()) {
        if (_isNavigating) {
          _hideNavigationNotification();
        }
      }
      return null;
    });
  }

  void _listenBackgroundUpdates() {
    _bgSubscription = FlutterBackgroundService().on('heartbeat').listen((event) {
      debugPrint('Background service heartbeat: $event');
    });
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    _locationSubscription?.cancel();
    _bgSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isNavigating ? 'Navigating...' : 'TrackMe',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.deepPurple,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.feedback, color: Colors.white),
            tooltip: 'Visit Feedback',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VisitFeedbackListScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.person, color: Colors.white),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ProfileScreen(),
                ),
              );
            },
          ),
          if (_isNavigating)
            IconButton(
              icon: const Icon(Icons.stop, color: Colors.white),
              onPressed: _stopNavigation,
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _ensurePermissions,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
            },
            initialCameraPosition: const CameraPosition(
              target: LatLng(20.5937, 78.9629), // India center coordinates
              zoom: 5,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            markers: _markers,
            polylines: _polylines,
          ),
          
          // My Location Button
          Positioned(
            bottom: 100,
            right: 16,
            child: FloatingActionButton(
              onPressed: () {
                if (_currentLocation != null && _mapController != null) {
                  final location = LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!);
                  _mapController!.animateCamera(
                    CameraUpdate.newLatLngZoom(location, 15.0),
                  );
                }
              },
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1E40AF),
              child: const Icon(Icons.my_location),
            ),
          ),
          
          // Search Panel
          if (_showSearchPanel)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E40AF).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.location_on,
                              color: Color(0xFF1E40AF),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Where to?',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // Origin field
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: TextField(
                          controller: _originController,
                          enabled: false,
                          decoration: InputDecoration(
                            labelText: 'From',
                            labelStyle: TextStyle(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                            prefixIcon: Container(
                              margin: const EdgeInsets.all(8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.my_location,
                                color: Colors.green,
                                size: 20,
                              ),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Destination field
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: GooglePlaceAutoCompleteTextField(
                          textEditingController: _destinationController,
                          googleAPIKey: _apiKey,
                          inputDecoration: InputDecoration(
                            labelText: 'To',
                            labelStyle: TextStyle(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                            prefixIcon: Container(
                              margin: const EdgeInsets.all(8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.location_on,
                                color: Colors.red,
                                size: 20,
                              ),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                          debounceTime: 800,
                          countries: const ["us", "in"],
                          isLatLngRequired: true,
                          getPlaceDetailWithLatLng: (Prediction prediction) {
                            debugPrint("Destination: ${prediction.lat} ${prediction.lng}");
                          },
                          itemClick: (Prediction prediction) {
                            _destinationController.text = prediction.description ?? "";
                            _destinationController.selection = TextSelection.fromPosition(
                              TextPosition(offset: _destinationController.text.length),
                            );
                          },
                          seperatedBuilder: const Divider(),
                          isCrossBtnShown: true,
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Start Navigation Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _askPurposeAndStart,
                          icon: const Icon(Icons.directions, size: 24),
                          label: const Text(
                            'Start Navigation',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E40AF),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          
          // Navigation Info Panel
          if (_isNavigating && !_showSearchPanel)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E40AF).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.directions,
                          color: Color(0xFF1E40AF),
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Navigating to',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _destinationController.text,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: _stopNavigation,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          
          // Floating Action Button
          if (!_isNavigating)
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton.extended(
                onPressed: () {
                  setState(() {
                    _isBackgroundServiceRunning = !_isBackgroundServiceRunning;
                  });
                  
                  if (_isBackgroundServiceRunning) {
                    FlutterBackgroundService().startService();
                  } else {
                    FlutterBackgroundService().invoke('stopService');
                  }
                },
                icon: Icon(_isBackgroundServiceRunning ? Icons.stop : Icons.play_arrow),
                label: Text(_isBackgroundServiceRunning ? 'Stop' : 'Start'),
                backgroundColor: const Color(0xFF1E40AF),
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}
