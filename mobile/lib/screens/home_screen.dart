import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MapController _mapController = MapController();

  // Coordinates for Santa Cruz de la Sierra center
  final LatLng _sczCenter = const LatLng(-17.783, -63.180);

  String _mapStyle = 'voyager'; // 'voyager', 'osm', 'satellite', or 'dark'

  // State lists
  List<dynamic> _lines = [];
  bool _isLoadingLines = false;

  // Selected Line State
  int? _selectedLineId;
  Map<String, dynamic>? _selectedLineDetails;
  bool _isLoadingLineDetails = false;
  int _routeViewMode = 0; // 0: Ambos, 1: Ida, 2: Retorno

  // Near Me State
  double _searchRadius = 500.0;
  List<dynamic> _nearLines = [];
  bool _isSearchingNear = false;
  LatLng? _nearSearchCenter;

  // Route Planning State
  LatLng? _startPoint;
  LatLng? _endPoint;
  bool _isSelectingStart = false;
  bool _isSelectingEnd = false;
  String _routingMode = 'smart'; // smart vs official
  String _routingMetric = 'time'; // time vs distance
  Map<String, dynamic>? _optimalRouteResult;
  bool _isCalculatingRoute = false;
  List<dynamic> _alternativeRoutes = [];
  int _selectedRouteIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadLines();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // API Call: Fetch all lines
  Future<void> _loadLines() async {
    setState(() => _isLoadingLines = true);
    try {
      final data = await ApiService.getLines();
      setState(() {
        _lines = data;
        _isLoadingLines = false;
      });
    } catch (e) {
      setState(() => _isLoadingLines = false);
      _showErrorSnackBar('Error cargando líneas: $e');
    }
  }

  // API Call: Fetch line details (stops, geometry)
  Future<void> _selectLine(int lineId) async {
    setState(() {
      _selectedLineId = lineId;
      _isLoadingLineDetails = true;
      _optimalRouteResult = null; // Clear route if viewing a single line
    });
    try {
      final data = await ApiService.getLineDetails(lineId);
      setState(() {
        _selectedLineDetails = data;
        _isLoadingLineDetails = false;
      });

      // Fit map to show the line bounds
      _fitMapToLinePoints();
    } catch (e) {
      setState(() => _isLoadingLineDetails = false);
      _showErrorSnackBar('Error cargando recorrido: $e');
    }
  }

  // Fit map viewport to show the selected line's points
  void _fitMapToLinePoints() {
    if (_selectedLineDetails == null) return;
    final routes = _selectedLineDetails!['routes'] as List;
    final List<LatLng> allPoints = [];

    for (var r in routes) {
      final points = r['points'] as List;
      for (var p in points) {
        allPoints.add(LatLng(p['latitud'], p['longitud']));
      }
    }

    if (allPoints.isNotEmpty) {
      final bounds = LatLngBounds.fromPoints(allPoints);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(50.0),
        ),
      );
    }
  }

  // API Call: Fetch lines near map click coordinates
  Future<void> _searchNearLines(LatLng coords) async {
    setState(() {
      _nearSearchCenter = coords;
      _isSearchingNear = true;
      _nearLines = [];
    });

    try {
      final data = await ApiService.getLinesNear(coords.latitude, coords.longitude, radius: _searchRadius);
      setState(() {
        _nearLines = data;
        _isSearchingNear = false;
      });
      if (data.isEmpty) {
        _showInfoSnackBar('No se encontraron líneas en un radio de ${_searchRadius.toInt()}m');
      }
    } catch (e) {
      setState(() => _isSearchingNear = false);
      _showErrorSnackBar('Error buscando líneas cercanas: $e');
    }
  }

  // API Call: Calculate optimal path with Dijkstra
  Future<void> _calculateRoute() async {
    if (_startPoint == null || _endPoint == null) {
      _showErrorSnackBar('Debes seleccionar un punto de origen y un punto de destino.');
      return;
    }

    setState(() {
      _isCalculatingRoute = true;
      _selectedLineId = null; // Clear single line view
      _selectedLineDetails = null;
      _alternativeRoutes = [];
      _selectedRouteIndex = 0;
      _optimalRouteResult = null;
    });

    try {
      final data = await ApiService.getOptimalRoute(
        _startPoint!.latitude,
        _startPoint!.longitude,
        _endPoint!.latitude,
        _endPoint!.longitude,
        mode: _routingMode,
        metric: _routingMetric,
      );

      setState(() {
        _isCalculatingRoute = false;
        if (data != null && data['routes'] != null) {
          _alternativeRoutes = data['routes'] as List;
          if (_alternativeRoutes.isNotEmpty) {
            _selectedRouteIndex = 0;
            _optimalRouteResult = _alternativeRoutes[0];
          }
        }
      });

      if (_alternativeRoutes.isEmpty) {
        _showErrorSnackBar('No se pudo encontrar ninguna ruta para conectar los dos puntos.');
      } else {
        _fitMapToRouteResult();
      }
    } catch (e) {
      setState(() => _isCalculatingRoute = false);
      _showErrorSnackBar('Error calculando ruta: $e');
    }
  }

  // Fit map viewport to show the calculated Dijkstra path
  void _fitMapToRouteResult() {
    if (_optimalRouteResult == null) return;
    final List<LatLng> allPoints = [];
    final legs = _optimalRouteResult!['legs'] as List;

    for (var leg in legs) {
      final points = leg['points'] as List;
      for (var p in points) {
        allPoints.add(LatLng(p['lat'], p['lon']));
      }
    }

    if (allPoints.isNotEmpty) {
      final bounds = LatLngBounds.fromPoints(allPoints);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(60.0),
        ),
      );
    }
  }

  // Swap Origin and Destination
  void _swapPoints() {
    if (_startPoint == null && _endPoint == null) return;
    setState(() {
      final temp = _startPoint;
      _startPoint = _endPoint;
      _endPoint = temp;
      _optimalRouteResult = null;
    });
    _showInfoSnackBar('Puntos de Origen y Destino intercambiados.');
  }

  // Get current device position using Geolocator package
  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showErrorSnackBar('El servicio de GPS está desactivado. Habilítalo en tu dispositivo.');
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showErrorSnackBar('Permiso de GPS denegado.');
        return null;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      _showErrorSnackBar('Los permisos de GPS están denegados permanentemente.');
      return null;
    } 

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
    } catch (e) {
      _showErrorSnackBar('No se pudo obtener la ubicación GPS. Intenta de nuevo.');
      return null;
    }
  }

  // Trigger using current location
  Future<void> _useCurrentLocation() async {
    _showInfoSnackBar('Obteniendo tu ubicación satelital...');
    final position = await _getCurrentLocation();
    
    LatLng targetLocation;
    String locationName;

    if (position != null) {
      targetLocation = LatLng(position.latitude, position.longitude);
      locationName = 'Mi ubicación GPS';
    } else {
      // Fallback
      targetLocation = const LatLng(-17.783207, -63.182140);
      locationName = 'Plaza Central 24 de Septiembre (Simulada)';
      _showInfoSnackBar('No se obtuvo GPS. Usando Plaza 24 de Septiembre.');
    }

    setState(() {
      _startPoint = targetLocation;
      _optimalRouteResult = null;
    });

    _mapController.move(targetLocation, 15.5);
    _tabController.animateTo(2); // Route Planner tab
    _showInfoSnackBar('Origen: $locationName');
  }

  // Map Click Handler
  void _handleMapTap(TapPosition tapPosition, LatLng point) {
    if (_isSelectingStart) {
      setState(() {
        _startPoint = point;
        _isSelectingStart = false;
        _optimalRouteResult = null;
      });
      _showInfoSnackBar('Origen (A) establecido.');
    } else if (_isSelectingEnd) {
      setState(() {
        _endPoint = point;
        _isSelectingEnd = false;
        _optimalRouteResult = null;
      });
      _showInfoSnackBar('Destino (B) establecido.');
    } else {
      _showMapTapOptions(point);
    }
  }

  void _showMapTapOptions(LatLng point) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF171923),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20.0),
          topRight: Radius.circular(20.0),
        ),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Punto Seleccionado',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.0),
                ),
                const SizedBox(height: 4),
                Text(
                  'Coordenadas: ${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12.0),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0x1F00E676),
                    child: Icon(Icons.location_on, color: Colors.green),
                  ),
                  title: const Text('Establecer como Origen (Punto A)', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _startPoint = point;
                      _optimalRouteResult = null;
                    });
                    _tabController.animateTo(2); // Switch to Route Planner
                    _showInfoSnackBar('Origen establecido.');
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0x1FEEFF41),
                    child: Icon(Icons.flag, color: Colors.redAccent),
                  ),
                  title: const Text('Establecer como Destino (Punto B)', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _endPoint = point;
                      _optimalRouteResult = null;
                    });
                    _tabController.animateTo(2); // Switch to Route Planner
                    _showInfoSnackBar('Destino establecido.');
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0x1F0D99FF),
                    child: Icon(Icons.directions_bus, color: Color(0xFF0D99FF)),
                  ),
                  title: const Text('Buscar líneas de microbús cercanas', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _tabController.animateTo(1); // Switch to Cerca de mí
                    _searchNearLines(point);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Helpers
  void _showErrorSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  void _showInfoSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF0D99FF)),
    );
  }

  Color _parseHexColor(String? hexString) {
    if (hexString == null || hexString.isEmpty) return const Color(0xFF0D99FF);
    final hex = hexString.replaceAll('#', '');
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    return const Color(0xFF0D99FF);
  }

  double _calculateBearing(LatLng p1, LatLng p2) {
    final double lat1 = p1.latitude * math.pi / 180.0;
    final double lon1 = p1.longitude * math.pi / 180.0;
    final double lat2 = p2.latitude * math.pi / 180.0;
    final double lon2 = p2.longitude * math.pi / 180.0;

    final double dLon = lon2 - lon1;
    final double y = math.sin(dLon) * math.cos(lat2);
    final double x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    return math.atan2(y, x);
  }

  void _addDirectionalArrows(List<LatLng> points, List<Marker> markers, Color color) {
    if (points.length < 2) return;

    // Draw an arrow marker approximately every 12 points for clean density
    int interval = 12;
    if (points.length > 80) {
      interval = (points.length / 10).round();
    }
    if (interval < 2) interval = 2;

    for (int i = 0; i < points.length - 1; i += interval) {
      int nextIndex = i + 1;
      if (nextIndex >= points.length) break;

      final p1 = points[i];
      final p2 = points[nextIndex];

      final midPoint = LatLng(
        (p1.latitude + p2.latitude) / 2.0,
        (p1.longitude + p2.longitude) / 2.0,
      );

      final bearing = _calculateBearing(p1, p2);

      markers.add(
        Marker(
          point: midPoint,
          width: 24.0,
          height: 24.0,
          child: Transform.rotate(
            angle: bearing,
            child: Icon(
              Icons.navigation,
              size: 14.0,
              color: color,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Generate map layers dynamically based on state
    final List<Polyline> polylines = [];
    final List<Marker> markers = [];

    // 1. Draw Selected Line Routes
    if (_selectedLineDetails != null) {
      final routes = _selectedLineDetails!['routes'] as List;
      final Color lineColor = _parseHexColor(_selectedLineDetails!['line']['color_linea']);

      for (var r in routes) {
        final rId = r['id_ruta']; // 1: Ida, 2: Retorno
        if (_routeViewMode == 0 || (_routeViewMode == 1 && rId == 1) || (_routeViewMode == 2 && rId == 2)) {
          final pointsList = r['points'] as List;
          final List<LatLng> polyPoints = pointsList.map((p) => LatLng(p['latitud'], p['longitud'])).toList();

          // Outbound (Ida) has solid lines. Inbound (Retorno) has dashed lines for clarity.
          polylines.add(
            Polyline(
              points: polyPoints,
              color: lineColor,
              strokeWidth: 4.0,
              pattern: rId == 2 
                  ? StrokePattern.dashed(segments: const [10, 10]) 
                  : const StrokePattern.solid(),
            ),
          );

          // Add arrows along the route showing direction of travel
          _addDirectionalArrows(polyPoints, markers, lineColor);

          // Add Start (Green) and End (Red) markers for the routes
          if (polyPoints.isNotEmpty) {
            markers.add(
              Marker(
                point: polyPoints.first,
                width: 32.0,
                height: 32.0,
                child: const Icon(Icons.play_circle_fill, color: Colors.green, size: 28.0),
              ),
            );
            markers.add(
              Marker(
                point: polyPoints.last,
                width: 32.0,
                height: 32.0,
                child: const Icon(Icons.stop_circle, color: Colors.red, size: 28.0),
              ),
            );

            // Add bus stop icons along the route
            for (var p in pointsList) {
              if (p['stop'] == 'S') {
                markers.add(
                  Marker(
                    point: LatLng(p['latitud'], p['longitud']),
                    width: 20.0,
                    height: 20.0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: lineColor, width: 2.5),
                      ),
                      child: const Center(
                        child: Icon(Icons.directions_bus, size: 10.0, color: Colors.black87),
                      ),
                    ),
                  ),
                );
              }
            }
          }
        }
      }
    }

    // 2. Draw Dijkstra Optimal Route Path
    if (_optimalRouteResult != null) {
      final legs = _optimalRouteResult!['legs'] as List;
      for (var leg in legs) {
        final type = leg['type'];
        final pointsList = leg['points'] as List;
        final List<LatLng> polyPoints = pointsList.map((p) => LatLng(p['lat'], p['lon'])).toList();

        if (type == 'WALK') {
          // Draw walking paths as dotted grey lines
          polylines.add(
            Polyline(
              points: polyPoints,
              color: Colors.grey.shade500,
              strokeWidth: 4.5,
              pattern: StrokePattern.dashed(segments: const [5, 5]),
            ),
          );
        } else if (type == 'TRAVEL') {
          // Draw travel paths in the specific microbus line color
          final color = _parseHexColor(leg['lineColor']);
          polylines.add(
            Polyline(
              points: polyPoints,
              color: color,
              strokeWidth: 5.5,
            ),
          );

          // Add arrows along the travel route leg showing direction of travel
          _addDirectionalArrows(polyPoints, markers, color);

          // Add bus stop dots along the optimal path
          for (var p in pointsList) {
            if (p['stop'] == 'S') {
              markers.add(
                Marker(
                  point: LatLng(p['lat'], p['lon']),
                  width: 20.0,
                  height: 20.0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 2.5),
                    ),
                    child: const Center(
                      child: Icon(Icons.directions_bus, size: 10.0, color: Colors.black87),
                    ),
                  ),
                ),
              );
            }
          }
        }

        // Add Transfer indicator flags
        if (type == 'TRANSFER') {
          final pt = pointsList.first;
          markers.add(
            Marker(
              point: LatLng(pt['lat'], pt['lon']),
              width: 32.0,
              height: 32.0,
              child: const Icon(Icons.sync_alt, color: Colors.orange, size: 28.0),
            ),
          );
        }
      }
    }

    // 3. Draw Start (A) and End (B) interactive routing pins
    if (_startPoint != null) {
      markers.add(
        Marker(
          point: _startPoint!,
          width: 45.0,
          height: 45.0,
          alignment: Alignment.topCenter,
          child: const Icon(Icons.location_on, color: Colors.green, size: 40.0),
        ),
      );
    }
    if (_endPoint != null) {
      markers.add(
        Marker(
          point: _endPoint!,
          width: 45.0,
          height: 45.0,
          alignment: Alignment.topCenter,
          child: const Icon(Icons.location_on, color: Colors.red, size: 40.0),
        ),
      );
    }

    // 4. Draw Near Me search center marker
    if (_nearSearchCenter != null) {
      markers.add(
        Marker(
          point: _nearSearchCenter!,
          width: 30.0,
          height: 30.0,
          child: const Icon(Icons.gps_fixed, color: Color(0xFF0D99FF), size: 24.0),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF12141C), // Premium dark theme
      body: Stack(
        children: [
          // 1. Leaflet GIS Map Layer
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _sczCenter,
              initialZoom: 13.5,
              maxZoom: 18.0,
              minZoom: 10.0,
              onTap: _handleMapTap,
            ),
            children: [
              if (_mapStyle == 'satellite') ...[
                TileLayer(
                  urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                  maxZoom: 18.0,
                ),
                TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_only_labels/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  maxZoom: 18.0,
                ),
              ] else if (_mapStyle == 'osm') ...[
                TileLayer(
                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  maxZoom: 18.0,
                ),
              ] else if (_mapStyle == 'voyager') ...[
                TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  maxZoom: 18.0,
                ),
              ] else ...[
                TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  maxZoom: 18.0,
                ),
              ],
              PolylineLayer(polylines: polylines),
              MarkerLayer(markers: markers),
            ],
          ),

          // 2. Floating App Bar header with premium backdrop blur
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 15,
            right: 15,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18.0),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  decoration: BoxDecoration(
                    color: const Color(0xCC131520), // Translucent premium dark
                    borderRadius: BorderRadius.circular(18.0),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                    boxShadow: const [
                      BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D99FF).withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.directions_bus, color: Color(0xFF0D99FF), size: 24.0),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SIG Microbuses SCZ',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.0),
                            ),
                            Text(
                              'Santa Cruz de la Sierra',
                              style: TextStyle(color: Colors.white54, fontSize: 11.0),
                            ),
                          ],
                        ),
                      ),
                      if (_isLoadingLineDetails || _isSearchingNear || _isCalculatingRoute)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.0, color: Color(0xFF0D99FF)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Floating Action Buttons (Map style, Center, and Set mock location)
          Positioned(
            right: 15,
            top: MediaQuery.of(context).padding.top + 80,
            child: Column(
              children: [
                // Map Style Toggle (Voyager -> OSM -> Satellite -> Dark)
                FloatingActionButton.small(
                  heroTag: 'styleBtn',
                  onPressed: () {
                    setState(() {
                      if (_mapStyle == 'voyager') {
                        _mapStyle = 'osm';
                        _showInfoSnackBar('Mapa: Color Clásico (OSM)');
                      } else if (_mapStyle == 'osm') {
                        _mapStyle = 'satellite';
                        _showInfoSnackBar('Mapa: Satélite Híbrido');
                      } else if (_mapStyle == 'satellite') {
                        _mapStyle = 'dark';
                        _showInfoSnackBar('Mapa: Modo Oscuro');
                      } else {
                        _mapStyle = 'voyager';
                        _showInfoSnackBar('Mapa: Color Suave (Voyager)');
                      }
                    });
                  },
                  backgroundColor: const Color(0xFF171923),
                  foregroundColor: const Color(0xFF0D99FF),
                  tooltip: 'Estilo de Mapa',
                  child: Icon(
                    _mapStyle == 'voyager'
                        ? Icons.map_outlined
                        : _mapStyle == 'osm'
                            ? Icons.satellite_alt
                            : _mapStyle == 'satellite'
                                ? Icons.dark_mode
                                : Icons.wb_sunny,
                  ),
                ),
                const SizedBox(height: 10),
                // Recenter Map
                FloatingActionButton.small(
                  heroTag: 'centerBtn',
                  onPressed: () {
                    _mapController.move(_sczCenter, 13.5);
                    _showInfoSnackBar('Mapa centrado en Santa Cruz.');
                  },
                  backgroundColor: const Color(0xFF171923),
                  foregroundColor: const Color(0xFF0D99FF),
                  tooltip: 'Centrar Mapa',
                  child: const Icon(Icons.gps_fixed),
                ),
                const SizedBox(height: 10),
                // GPS Location / Mi Ubicación Button
                FloatingActionButton.small(
                  heroTag: 'mockLocBtn',
                  onPressed: _useCurrentLocation,
                  backgroundColor: const Color(0xFF171923),
                  foregroundColor: Colors.greenAccent,
                  tooltip: 'Mi Ubicación GPS',
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),

          // 3. Sliding Bottom Control Sheet with premium glassmorphism
          DraggableScrollableSheet(
            initialChildSize: 0.35,
            minChildSize: 0.15,
            maxChildSize: 0.90,
            builder: (BuildContext context, ScrollController scrollController) {
              return ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24.0),
                  topRight: Radius.circular(24.0),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xEC171923), // Translucent dark
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(24.0),
                        topRight: Radius.circular(24.0),
                      ),
                      border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.0),
                      boxShadow: const [
                        BoxShadow(color: Colors.black87, blurRadius: 15, offset: Offset(0, -4)),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Handle indicator
                        const SizedBox(height: 8),
                        Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2.5),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Pill-styled Navigation Segmented Control
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(14.0),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: TabBar(
                            controller: _tabController,
                            indicator: BoxDecoration(
                              color: const Color(0xFF0D99FF).withOpacity(0.18),
                              borderRadius: BorderRadius.circular(10.0),
                              border: Border.all(color: const Color(0xFF0D99FF).withOpacity(0.35), width: 1.2),
                            ),
                            indicatorSize: TabBarIndicatorSize.tab,
                            dividerColor: Colors.transparent,
                            labelColor: const Color(0xFF0D99FF),
                            unselectedLabelColor: Colors.white54,
                            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0),
                            tabs: const [
                              Tab(text: 'Líneas'),
                              Tab(text: 'Cerca'),
                              Tab(text: 'Ruta Óptima'),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildLinesTab(scrollController),
                              _buildNearMeTab(scrollController),
                              _buildRoutePlannerTab(scrollController),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // TAB 1: Browse bus lines
  Widget _buildLinesTab(ScrollController scrollController) {
    if (_isLoadingLines) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF0D99FF)));
    }

    return Column(
      children: [
        if (_selectedLineDetails != null) ...[
          // Control buttons when a line is selected
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            color: Colors.white.withOpacity(0.02),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Línea ${_selectedLineDetails!['line']['nombre_linea']}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.0),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedLineId = null;
                      _selectedLineDetails = null;
                    });
                  },
                  icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                  label: const Text('Limpiar', style: TextStyle(color: Colors.redAccent)),
                )
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: _buildToggleButton('Ambos', _routeViewMode == 0, () {
                    setState(() => _routeViewMode = 0);
                  }),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildToggleButton('Ida (Sólido)', _routeViewMode == 1, () {
                    setState(() => _routeViewMode = 1);
                  }),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildToggleButton('Vuelta (Doble)', _routeViewMode == 2, () {
                    setState(() => _routeViewMode = 2);
                  }),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...(_selectedLineDetails!['routes'] as List).map((r) {
                  final rId = r['id_ruta'];
                  final dist = r['total_distancia_km'];
                  final timeHrs = r['total_tiempo_horas'];
                  final timeMin = timeHrs * 60;

                  // Only show details for the route selected by current view mode
                  if (_routeViewMode == 0 || (_routeViewMode == 1 && rId == 1) || (_routeViewMode == 2 && rId == 2)) {
                    final label = rId == 1 ? 'Ida' : 'Vuelta';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Row(
                        children: [
                          Icon(rId == 1 ? Icons.arrow_forward : Icons.arrow_back, color: const Color(0xFF0D99FF), size: 14),
                          const SizedBox(width: 6),
                          Text(
                            '$label: ${dist.toStringAsFixed(2)} km • ${timeMin.toStringAsFixed(0)} min',
                            style: const TextStyle(color: Colors.white70, fontSize: 13.0),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                }).toList(),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            itemCount: _lines.length,
            itemBuilder: (context, index) {
              final line = _lines[index];
              final lineId = line['id_linea'];
              final isSelected = _selectedLineId == lineId;
              final lineColor = _parseHexColor(line['color_linea']);

              final displayName = line['nombre_linea'].toString().trim();
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0x1F0D99FF) : const Color(0x0AFFFFFF),
                  borderRadius: BorderRadius.circular(14.0),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF0D99FF) : Colors.white.withOpacity(0.05),
                    width: isSelected ? 1.5 : 1.0,
                  ),
                  boxShadow: isSelected 
                      ? [BoxShadow(color: const Color(0xFF0D99FF).withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))]
                      : null,
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                  leading: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      color: lineColor,
                      borderRadius: BorderRadius.circular(8.0),
                      boxShadow: [
                        BoxShadow(
                          color: lineColor.withOpacity(0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  title: Text(
                    'Línea $displayName',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15.0),
                  ),
                  subtitle: const Text(
                    'Microbuses de Santa Cruz',
                    style: TextStyle(color: Colors.white38, fontSize: 11.5),
                  ),
                  trailing: Icon(
                    Icons.chevron_right, 
                    color: isSelected ? const Color(0xFF0D99FF) : Colors.white38,
                  ),
                  onTap: () => _selectLine(lineId),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // TAB 2: Identify lines near a clicked location
  Widget _buildNearMeTab(ScrollController scrollController) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16.0),
      children: [
        const Text(
          '¿Qué líneas pasan por aquí?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.0),
        ),
        const SizedBox(height: 6),
        const Text(
          'Toca cualquier parte del mapa para marcar un punto y buscar qué líneas de microbús pasan cerca de él.',
          style: TextStyle(color: Colors.white54, fontSize: 12.0),
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            const Text('Radio de búsqueda: ', style: TextStyle(color: Colors.white70)),
            Text('${_searchRadius.toInt()} metros', style: const TextStyle(color: Color(0xFF0D99FF), fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: _searchRadius,
          min: 100.0,
          max: 1500.0,
          divisions: 14,
          activeColor: const Color(0xFF0D99FF),
          inactiveColor: Colors.white24,
          onChanged: (val) {
            setState(() => _searchRadius = val);
            if (_nearSearchCenter != null) {
              _searchNearLines(_nearSearchCenter!);
            }
          },
        ),
        const Divider(color: Colors.white12, height: 20),
        if (_isSearchingNear)
          const Center(child: CircularProgressIndicator(color: Color(0xFF0D99FF)))
        else if (_nearSearchCenter == null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Icon(Icons.touch_app, size: 40, color: Colors.grey[600]),
                  const SizedBox(height: 10),
                  const Text('Haz clic en el mapa para iniciar', style: TextStyle(color: Colors.white38)),
                ],
              ),
            ),
          )
        else if (_nearLines.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Text('Ninguna línea encontrada en este radio.', style: TextStyle(color: Colors.white38)),
            ),
          )
        else ...[
          Text('Líneas encontradas (${_nearLines.length}):', style: const TextStyle(color: Colors.white70, fontSize: 13.0)),
          const SizedBox(height: 8),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _nearLines.length,
            itemBuilder: (context, idx) {
              final item = _nearLines[idx];
              final color = _parseHexColor(item['color_linea']);
              final displayName = item['nombre_linea'].toString().trim();
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 6.0),
                decoration: BoxDecoration(
                  color: const Color(0x0AFFFFFF),
                  borderRadius: BorderRadius.circular(14.0),
                  border: Border.all(color: Colors.white.withOpacity(0.04)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                  leading: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(8.0),
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  title: Text('Línea $displayName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Pasa por esta zona', style: TextStyle(color: Colors.white30, fontSize: 11.5)),
                  trailing: const Icon(Icons.map, color: Color(0xFF0D99FF)),
                  onTap: () {
                    _selectLine(item['id_linea']);
                  },
                ),
              );
            },
          ),
        ]
      ],
    );
  }

  Widget _buildTimelineStep({
    required IconData icon,
    required Color color,
    required String labelTop,
    required String labelBottom,
    required bool showLeftLine,
    required bool showRightLine,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: showLeftLine
                  ? Container(height: 2.5, color: const Color(0xFF8CFF2F))
                  : const SizedBox.shrink(),
            ),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF171923), width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.4),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            Expanded(
              child: showRightLine
                  ? Container(height: 2.5, color: const Color(0xFF8CFF2F))
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          labelTop,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          labelBottom,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 9.5,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildHorizontalTimeline(Map<String, dynamic> route) {
    final List<dynamic> legs = (route['legs'] as List).where((leg) {
      if (leg['type'] == 'TRANSFER') return true;
      final time = leg['time'] as double;
      final dist = leg['distance'] as double;
      return time > 0.1 || dist > 0.01;
    }).toList();

    return Row(
      children: legs.asMap().entries.map((entry) {
        final idx = entry.key;
        final leg = entry.value;
        final type = leg['type'];
        final time = leg['time'] as double;
        final dist = leg['distance'] as double;

        IconData iconData = Icons.directions_walk;
        Color themeColor = const Color(0xFF8CFF2F); // Lime green
        String labelTop = "";
        String labelBottom = "${time.toStringAsFixed(1)} min";

        if (type == 'WALK') {
          iconData = Icons.directions_walk;
          themeColor = const Color(0xFF8CFF2F);
          if (dist < 1.0) {
            labelTop = "${(dist * 1000).toStringAsFixed(0)} m.";
          } else {
            labelTop = "${dist.toStringAsFixed(2)} km";
          }
        } else if (type == 'TRAVEL') {
          iconData = Icons.directions_bus;
          final hexColor = leg['lineColor'];
          themeColor = _parseHexColor(hexColor);
          labelTop = "Línea ${leg['lineName']?.toString().trim()}";
        } else if (type == 'TRANSFER') {
          iconData = Icons.sync_alt;
          themeColor = Colors.orangeAccent;
          labelTop = "Transbordo";
        }

        final showLeftLine = idx > 0;
        final showRightLine = idx < legs.length - 1;

        return Expanded(
          child: _buildTimelineStep(
            icon: iconData,
            color: themeColor,
            labelTop: labelTop,
            labelBottom: labelBottom,
            showLeftLine: showLeftLine,
            showRightLine: showRightLine,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAlternativeRouteCard(Map<String, dynamic> route, int index) {
    final isSelected = index == _selectedRouteIndex;
    
    // Calculate transfers
    final transfersCount = (route['legs'] as List).where((l) => l['type'] == 'TRANSFER').length;
    final transfersText = transfersCount == 0 
        ? 'Sin transbordos' 
        : (transfersCount == 1 ? '1 transbordo' : '$transfersCount transbordos');
    
    final totalTime = route['totalTimeMin'] as double;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: const Color(0xFF171923), // Dark grey
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: isSelected ? const Color(0xFF8CFF2F) : Colors.white.withOpacity(0.08),
          width: isSelected ? 2.0 : 1.0,
        ),
        boxShadow: [
          if (isSelected)
            BoxShadow(
              color: const Color(0xFF8CFF2F).withOpacity(0.12),
              blurRadius: 10,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            )
          else
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16.0),
          onTap: () {
            setState(() {
              _selectedRouteIndex = index;
              _optimalRouteResult = route;
            });
            _fitMapToRouteResult();
          },
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Badge (Time and transbordo)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withOpacity(0.85), // Dark green background
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: const Color(0xFF8CFF2F).withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tiempo total: ${totalTime.toStringAsFixed(0)} min.',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        transfersText,
                        style: const TextStyle(
                          color: Color(0xFFE0E0E0),
                          fontWeight: FontWeight.w500,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Horizontal Timeline
                _buildHorizontalTimeline(route),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // TAB 3: Path planner (Dijkstra)
  Widget _buildRoutePlannerTab(ScrollController scrollController) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16.0),
      children: [
        const Text(
          'Encuentra tu ruta óptima',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.0),
        ),
        const SizedBox(height: 12),
        // Point A Selector
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _isSelectingStart = true;
                    _isSelectingEnd = false;
                  });
                  _showInfoSnackBar('Toca en cualquier parte del mapa para marcar el Origen (A).');
                },
                icon: Icon(Icons.play_circle_filled, color: _isSelectingStart ? Colors.orange : Colors.green),
                label: Text(
                  _isSelectingStart
                      ? 'Toca el mapa...'
                      : (_startPoint == null
                          ? 'Marcar Origen (Punto A)'
                          : 'Origen: (${_startPoint!.latitude.toStringAsFixed(5)}, ${_startPoint!.longitude.toStringAsFixed(5)})'),
                  style: TextStyle(color: _isSelectingStart ? Colors.orange : Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _isSelectingStart ? Colors.orange : Colors.green.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                ),
              ),
            ),
            if (_startPoint != null)
              IconButton(
                onPressed: () => setState(() {
                  _startPoint = null;
                  _optimalRouteResult = null;
                }),
                icon: const Icon(Icons.clear, color: Colors.white54),
              )
          ],
        ),
        // Swap Button / Quick Swap Control
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _swapPoints,
                icon: const Icon(Icons.swap_vert_circle, color: Color(0xFF0D99FF), size: 28.0),
                tooltip: 'Intercambiar Origen y Destino',
              ),
              const Text('Intercambiar Origen/Destino', style: TextStyle(color: Colors.white38, fontSize: 11.0)),
            ],
          ),
        ),
        // Point B Selector
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _isSelectingEnd = true;
                    _isSelectingStart = false;
                  });
                  _showInfoSnackBar('Toca en cualquier parte del mapa para marcar el Destino (B).');
                },
                icon: Icon(Icons.stop_circle_rounded, color: _isSelectingEnd ? Colors.orange : Colors.red),
                label: Text(
                  _isSelectingEnd
                      ? 'Toca el mapa...'
                      : (_endPoint == null
                          ? 'Marcar Destino (Punto B)'
                          : 'Destino: (${_endPoint!.latitude.toStringAsFixed(5)}, ${_endPoint!.longitude.toStringAsFixed(5)})'),
                  style: TextStyle(color: _isSelectingEnd ? Colors.orange : Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _isSelectingEnd ? Colors.orange : Colors.red.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                ),
              ),
            ),
            if (_endPoint != null)
              IconButton(
                onPressed: () => setState(() {
                  _endPoint = null;
                  _optimalRouteResult = null;
                }),
                icon: const Icon(Icons.clear, color: Colors.white54),
              )
          ],
        ),
        const SizedBox(height: 12),
        // Routing Configurations (Smart vs Official, Time vs Distance)
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8.0,
          runSpacing: 4.0,
          children: [
            const Text('Criterio: ', style: TextStyle(color: Colors.white70)),
            ChoiceChip(
              label: const Text('Menor Tiempo'),
              selected: _routingMetric == 'time',
              onSelected: (val) {
                if (val) setState(() => _routingMetric = 'time');
              },
              selectedColor: const Color(0xFF0D99FF),
              backgroundColor: Colors.white10,
              labelStyle: const TextStyle(color: Colors.white),
            ),
            ChoiceChip(
              label: const Text('Menor Distancia'),
              selected: _routingMetric == 'distance',
              onSelected: (val) {
                if (val) setState(() => _routingMetric = 'distance');
              },
              selectedColor: const Color(0xFF0D99FF),
              backgroundColor: Colors.white10,
              labelStyle: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8.0,
          runSpacing: 4.0,
          children: [
            const Text('Transbordos: ', style: TextStyle(color: Colors.white70)),
            ChoiceChip(
              label: const Text('Inteligente (Intersecciones)'),
              selected: _routingMode == 'smart',
              onSelected: (val) {
                if (val) setState(() => _routingMode = 'smart');
              },
              selectedColor: const Color(0xFF0D99FF),
              backgroundColor: Colors.white10,
              labelStyle: const TextStyle(color: Colors.white),
            ),
            ChoiceChip(
              label: const Text('Oficial (Tabla)'),
              selected: _routingMode == 'official',
              onSelected: (val) {
                if (val) setState(() => _routingMode = 'official');
              },
              selectedColor: const Color(0xFF0D99FF),
              backgroundColor: Colors.white10,
              labelStyle: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 15),
        ElevatedButton(
          onPressed: _isCalculatingRoute ? null : _calculateRoute,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0D99FF),
            padding: const EdgeInsets.symmetric(vertical: 14.0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
          ),
          child: _isCalculatingRoute
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),
                )
              : const Text('Calcular Ruta Óptima', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.0, color: Colors.white)),
        ),
        const Divider(color: Colors.white12, height: 30),

        // 4. DISPLAY ROUTE RESULTS
        if (_alternativeRoutes.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              'Opciones de ruta encontradas:',
              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14.0),
            ),
          ),
          ..._alternativeRoutes.asMap().entries.map((entry) {
            return _buildAlternativeRouteCard(entry.value, entry.key);
          }),
          const SizedBox(height: 10),
          const Divider(color: Colors.white12, height: 20),
        ],

        if (_optimalRouteResult != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              'Itinerario de viaje (Opción ${_selectedRouteIndex + 1}):',
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14.0),
            ),
          ),
          const SizedBox(height: 8),

          // Render step-by-step route directions as interactive card list
          ...(_optimalRouteResult!['legs'] as List).asMap().entries.map((entry) {
            final leg = entry.value;
            final type = leg['type'];
            final desc = leg['description'];
            final dist = leg['distance'] as double;
            final time = leg['time'] as double;

            IconData icon = Icons.directions_walk;
            Color iconColor = Colors.grey;

            if (type == 'TRAVEL') {
              icon = Icons.directions_bus;
              iconColor = _parseHexColor(leg['lineColor']);
            } else if (type == 'TRANSFER') {
              icon = Icons.sync_alt;
              iconColor = Colors.orange;
            }

            return GestureDetector(
              onTap: () {
                final points = leg['points'] as List;
                if (points.isNotEmpty) {
                  final firstPt = points.first;
                  final lat = (firstPt['lat'] ?? firstPt['latitud']) as double;
                  final lon = (firstPt['lon'] ?? firstPt['longitud']) as double;
                  _mapController.move(LatLng(lat, lon), 16.0);
                  _showInfoSnackBar('Ubicando tramo: $desc');
                }
              },
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 6.0),
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(14.0),
                  border: Border(
                    left: BorderSide(
                      color: iconColor,
                      width: 5.0,
                    ),
                    top: BorderSide(color: Colors.white.withOpacity(0.03)),
                    right: BorderSide(color: Colors.white.withOpacity(0.03)),
                    bottom: BorderSide(color: Colors.white.withOpacity(0.03)),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: iconColor.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: iconColor, size: 20.0),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (type == 'TRAVEL') ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                                  decoration: BoxDecoration(
                                    color: iconColor,
                                    borderRadius: BorderRadius.circular(6.0),
                                  ),
                                  child: Text(
                                    leg['lineName'].toString().trim(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11.0,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: Text(
                                  type == 'TRAVEL' 
                                      ? 'Viajar en Microbús'
                                      : type == 'WALK'
                                          ? 'Caminar'
                                          : 'Realizar Transbordo',
                                  style: TextStyle(
                                    color: iconColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            desc,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              fontSize: 13.0,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.schedule, size: 12, color: Colors.white38),
                              const SizedBox(width: 4),
                              Text(
                                '${time.toStringAsFixed(1)} min',
                                style: const TextStyle(color: Colors.white38, fontSize: 11.0),
                              ),
                              if (type != 'TRANSFER') ...[
                                const SizedBox(width: 12),
                                const Icon(Icons.straighten, size: 12, color: Colors.white38),
                                const SizedBox(width: 4),
                                Text(
                                  '${dist.toStringAsFixed(2)} km',
                                  style: const TextStyle(color: Colors.white38, fontSize: 11.0),
                                ),
                              ],
                              const Spacer(),
                              const Text(
                                'Ver en mapa',
                                style: TextStyle(color: Color(0xFF0D99FF), fontSize: 11.0, fontWeight: FontWeight.bold),
                              ),
                              const Icon(Icons.chevron_right, size: 14, color: Color(0xFF0D99FF)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ]
      ],
    );
  }

  Widget _buildToggleButton(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0D99FF) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(
            color: isSelected ? const Color(0xFF0D99FF) : Colors.white.withOpacity(0.05),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white60,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12.0,
            ),
          ),
        ),
      ),
    );
  }
}
