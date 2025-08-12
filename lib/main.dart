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
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await _initializeBackgroundService();
  await _initializeNotifications();
  runApp(const MyApp());
}

Future<void> _initializeBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onStart,
      isForegroundMode: false,
      autoStart: false,
      notificationChannelId: 'trackme_location_channel',
      initialNotificationTitle: 'TrackMe is running',
      initialNotificationContent: 'Tracking location in background',
    ),
    iosConfiguration: IosConfiguration(),
  );
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  Timer.periodic(const Duration(seconds: 30), (timer) async {
    service.invoke('heartbeat', {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  });
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _initializeNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrackMe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        fontFamily: 'Inter',
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        cardTheme: CardTheme(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with TickerProviderStateMixin {
  final Completer<GoogleMapController> _mapController = Completer();
  StreamSubscription<Map<String, dynamic>?>? _bgSubscription;
  StreamSubscription<location_pkg.LocationData>? _positionStreamSubscription;
  final List<LatLng> _breadcrumbs = <LatLng>[];
  final Set<Polyline> _polylines = <Polyline>{};
  final Set<Marker> _markers = <Marker>{};
  final location_pkg.Location _location = location_pkg.Location();
  
  // Navigation state
  bool _isNavigating = false;
  bool _showSearchPanel = true;
  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  LatLng? _originLatLng;
  LatLng? _destinationLatLng;
  List<LatLng> _routePoints = [];
  LatLng? _currentLocation;
  LatLng? _lastRouteOrigin;
  DateTime? _lastRouteUpdate;
  static const Duration _routeRecalcInterval = Duration(seconds: 15);
  static const double _routeRecalcDistanceMeters = 50;
  
  // Animations
  late AnimationController _searchPanelController;
  late AnimationController _navigationPanelController;
  
  // Google Places API key
  static const String _apiKey = 'AIzaSyAOmvphuquc8n1-hPPm_zRoBC2opcw5m8c';

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
    _searchPanelController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _navigationPanelController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    

    
    // Start the search panel animation
    _searchPanelController.forward();
  }

  Future<void> _ensurePermissions() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        return;
      }
    }

    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    location_pkg.PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == location_pkg.PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != location_pkg.PermissionStatus.granted) {
        return;
      }
    }

    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = _location.onLocationChanged.listen(_onNewPosition);
  }

  void _listenBackgroundUpdates() {
    _bgSubscription = FlutterBackgroundService().on('heartbeat').listen((event) async {
      debugPrint('Background service heartbeat: ${event?['timestamp']}');
    });
  }

  Future<void> _onNewPosition(location_pkg.LocationData position) async {
    _onNewLatLng(LatLng(position.latitude!, position.longitude!));
  }

  Future<void> _onNewLatLng(LatLng latLng) async {
    setState(() {
      _currentLocation = latLng;
      _breadcrumbs.add(latLng);
      _markers
        ..removeWhere((m) => m.markerId.value == 'me')
        ..add(Marker(
          markerId: const MarkerId('me'),
          position: latLng,
          rotation: 0,
          anchor: const Offset(0.5, 0.5),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ));
      
      if (_isNavigating && _routePoints.isNotEmpty) {
        _updateRoutePolyline();
      } else {
        _polylines
          ..removeWhere((p) => p.polylineId.value == 'route')
          ..add(Polyline(
            polylineId: const PolylineId('route'),
            points: List<LatLng>.from(_breadcrumbs),
            width: 6,
            color: Colors.blueAccent,
          ));
      }
    });

    final controller = await _mapController.future;
    controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: latLng, zoom: 17),
      ),
    );

    if (_isNavigating && _destinationLatLng != null) {
      final now = DateTime.now();
      if (_lastRouteUpdate == null || now.difference(_lastRouteUpdate!) > _routeRecalcInterval) {
        final movedFar = _lastRouteOrigin == null
            ? true
            : _computeDistanceMeters(_lastRouteOrigin!, _currentLocation!) > _routeRecalcDistanceMeters;
        if (movedFar) {
          _lastRouteUpdate = now;
          _lastRouteOrigin = _currentLocation;
          _getDirections(_currentLocation!, _destinationLatLng!).then((points) {
            if (!mounted) return;
            setState(() {
              _routePoints = points;
            });
            _updateRoutePolyline();
          });
        }
      }
    }
  }

  void _updateRoutePolyline() {
    if (_routePoints.isEmpty) return;
    setState(() {
      _polylines
        ..removeWhere((p) => p.polylineId.value == 'route')
        ..add(Polyline(
          polylineId: const PolylineId('route'),
          points: List<LatLng>.from(_routePoints),
          width: 8,
          color: Colors.blue,
          geodesic: true,
        ));
    });
  }

  Future<List<LatLng>> _getDirections(LatLng origin, LatLng destination) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://maps.googleapis.com/maps/api/directions/json'
          '?origin=${origin.latitude},${origin.longitude}'
          '&destination=${destination.latitude},${destination.longitude}'
          '&mode=driving&alternatives=false'
          '&key=$_apiKey'
        ),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final polyline = route['overview_polyline']['points'];
          return _decodePolyline(polyline);
        }
        debugPrint('Directions API status: ${data['status']} message: ${data['error_message'] ?? 'none'}');
      }
    } catch (e) {
      debugPrint('Error getting directions: $e');
    }
    
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

      poly.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return poly;
  }

  Future<LatLng?> _geocodeAddress(String address) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json'
          '?address=${Uri.encodeComponent(address)}'
          '&key=$_apiKey'
        ),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final location = data['results'][0]['geometry']['location'];
          return LatLng(location['lat'], location['lng']);
        }
      }
    } catch (e) {
      debugPrint('Error geocoding address: $e');
    }
    
    return null;
  }

  Future<String> _getCurrentLocationAddress(LatLng location) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json'
          '?latlng=${location.latitude},${location.longitude}'
          '&key=$_apiKey'
        ),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          return data['results'][0]['formatted_address'];
        }
      }
    } catch (e) {
      debugPrint('Error getting current location address: $e');
    }
    
    return 'Current Location';
  }

  Future<void> _calculateRoute() async {
    if (_originLatLng == null || _destinationLatLng == null) return;
    
    _routePoints = await _getDirections(_originLatLng!, _destinationLatLng!);
    _updateRoutePolyline();

    if (_routePoints.length <= 2 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not fetch road route. Showing straight line. Enable Google Directions API for better routing.'),
          backgroundColor: Colors.orange,
        ),
      );
    }

    setState(() {
      _markers
        ..removeWhere((m) => m.markerId.value == 'origin')
        ..removeWhere((m) => m.markerId.value == 'destination')
        ..addAll([
          Marker(
            markerId: const MarkerId('origin'),
            position: _originLatLng!,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: const InfoWindow(title: 'Origin'),
          ),
          Marker(
            markerId: const MarkerId('destination'),
            position: _destinationLatLng!,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: const InfoWindow(title: 'Destination'),
          ),
        ]);
    });
    _lastRouteOrigin = _originLatLng;
    _lastRouteUpdate = DateTime.now();

    try {
      final controller = await _mapController.future;
      double minLat = _routePoints.first.latitude;
      double maxLat = _routePoints.first.latitude;
      double minLng = _routePoints.first.longitude;
      double maxLng = _routePoints.first.longitude;
      for (final p in _routePoints) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 60),
      );
    } catch (e) {
      debugPrint('Error fitting camera to route: $e');
    }
  }

  void _startNavigation() async {
    if (_destinationController.text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter destination'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Calculating route...'),
          backgroundColor: Colors.blue,
        ),
      );
    }
    
    if (_currentLocation == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please wait for location to be detected'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    
    _originLatLng = _currentLocation;
    
    final currentAddress = await _getCurrentLocationAddress(_currentLocation!);
    if (!mounted) return;
    _originController.text = currentAddress;
    
    final destinationLatLng = await _geocodeAddress(_destinationController.text);
    if (!mounted) return;
    
    if (destinationLatLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not find destination. Please check your input.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    _destinationLatLng = destinationLatLng;
    
    _calculateRoute().then((_) {
      setState(() {
        _isNavigating = true;
        _showSearchPanel = false;
      });
      
      // Save navigation state
      _saveNavigationState();
      
      FlutterBackgroundService().startService();
      
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

  double _computeDistanceMeters(LatLng a, LatLng b) {
    const double earthRadiusMeters = 6371000.0;
    final double dLat = _degToRad(b.latitude - a.latitude);
    final double dLng = _degToRad(b.longitude - a.longitude);
    final double lat1 = _degToRad(a.latitude);
    final double lat2 = _degToRad(b.latitude);
    final double h =
        _sin2(dLat / 2) + _sin2(dLng / 2) * math.cos(lat1) * math.cos(lat2);
    return 2 * earthRadiusMeters * math.asin(math.min(1, math.sqrt(h)));
  }

  double _degToRad(double deg) => deg * (3.141592653589793 / 180.0);
  double _sin2(double x) => math.sin(x) * math.sin(x);

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

  @override
  void dispose() {
    _bgSubscription?.cancel();
    _positionStreamSubscription?.cancel();
    _originController.dispose();
    _destinationController.dispose();
    _searchPanelController.dispose();
    _navigationPanelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Gradient Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF1E40AF),
                  Color(0xFF3B82F6),
                  Color(0xFF60A5FA),
                ],
              ),
            ),
          ),
          
          // Google Map
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(37.42796133580664, -122.085749655962),
              zoom: 14.4746,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            markers: _markers,
            polylines: _polylines,
            onMapCreated: (controller) => _mapController.complete(controller),
            mapType: MapType.normal,
          ),
          
          // Modern App Bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.menu, color: Color(0xFF1E40AF)),
                      onPressed: () {},
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        _isNavigating ? 'Navigating...' : 'TrackMe',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E40AF),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.refresh, color: Color(0xFF1E40AF)),
                      onPressed: _ensurePermissions,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Search Panel
          if (_showSearchPanel)
            Positioned(
              top: 100,
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
                          onPressed: _startNavigation,
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
              top: 100,
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
              bottom: 100,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 15,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: FloatingActionButton.extended(
                  onPressed: () async {
                    final service = FlutterBackgroundService();
                    final isRunning = await service.isRunning();
                    if (!mounted) return;
                    
                    if (isRunning) {
                      service.invoke('stopService');
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Background tracking stopped'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    } else {
                      service.startService();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Background tracking started'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                    setState(() {});
                  },
                  label: const Text(
                    'Background Service',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  icon: const Icon(Icons.location_on),
                  backgroundColor: const Color(0xFF1E40AF),
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
