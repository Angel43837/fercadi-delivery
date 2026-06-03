import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../core/constants.dart';

const _kMaravatio = LatLng(19.8969, -100.4447);
const _kDefaultZoom = 17.5; // nivel calle — se ven las casas

class MapPickerScreen extends StatefulWidget {
  final LatLng? initial;
  const MapPickerScreen({super.key, this.initial});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  late final MapController _mapCtrl;
  LatLng _center = _kMaravatio;
  bool _locating = false;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _mapCtrl = MapController();
    if (widget.initial != null) {
      _center = widget.initial!;
      // Zoom al punto guardado después de que el mapa esté listo
      WidgetsBinding.instance.addPostFrameCallback((_) => _moveMap(_center, _kDefaultZoom));
    } else {
      // Sin posición previa → ir al GPS del usuario
      _goToGps();
    }
  }

  @override
  void dispose() {
    _mapCtrl.dispose();
    super.dispose();
  }

  Future<void> _goToGps() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (!mounted) return;
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _locating = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      final gps = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _center  = gps;
        _locating = false;
      });
      _moveMap(gps, _kDefaultZoom);
    } catch (_) {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _moveMap(LatLng pos, double zoom) {
    if (!_mapReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _moveMap(pos, zoom));
      return;
    }
    try { _mapCtrl.move(pos, zoom); } catch (_) {}
  }

  void _zoomIn()  => _moveMap(_center, (_mapCtrl.camera.zoom + 1).clamp(3, 20));
  void _zoomOut() => _moveMap(_center, (_mapCtrl.camera.zoom - 1).clamp(3, 20));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      appBar: AppBar(
        backgroundColor: AppConstants.surfaceColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context, null),
        ),
        title: const Text('¿Dónde te lo entregamos?',
            style: TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: Stack(
        children: [
          // ── Mapa ────────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: _kDefaultZoom,
              onMapReady: () => setState(() => _mapReady = true),
              onPositionChanged: (pos, _) {
                if (pos.center != null) setState(() => _center = pos.center!);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.landing_test',
              ),
            ],
          ),

          // ── Pin fijo al centro ───────────────────────────────────────────────
          IgnorePointer(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_on,
                      color: AppConstants.primaryColor, size: 52,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black.withValues(alpha: 0.5))]),
                  const SizedBox(height: 26),
                ],
              ),
            ),
          ),

          // ── Instrucción superior ─────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.pan_tool_alt_outlined,
                          color: Colors.white.withValues(alpha: 0.7), size: 16),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text('Mueve el mapa para poner el pin en tu casa',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12)),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),

          // ── Botones de zoom (derecha) ────────────────────────────────────────
          Positioned(
            right: 14,
            bottom: 110,
            child: Column(children: [
              _ZoomBtn(icon: Icons.add, onTap: _zoomIn),
              const SizedBox(height: 6),
              _ZoomBtn(icon: Icons.remove, onTap: _zoomOut),
            ]),
          ),

          // ── Botón GPS (esquina derecha-abajo) ────────────────────────────────
          Positioned(
            right: 14,
            bottom: 200,
            child: FloatingActionButton.small(
              heroTag: 'gps_btn',
              backgroundColor: Colors.white,
              onPressed: _locating ? null : _goToGps,
              tooltip: 'Ir a mi ubicación',
              child: _locating
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black54))
                  : const Icon(Icons.my_location, color: Colors.black87, size: 20),
            ),
          ),

          // ── Botón confirmar ──────────────────────────────────────────────────
          Positioned(
            left: 16, right: 16, bottom: 32,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, _center),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Confirmar ubicación',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Botón de zoom ─────────────────────────────────────────────────────────────
class _ZoomBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ZoomBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6)],
        ),
        child: Icon(icon, color: Colors.black87, size: 22),
      ),
    );
  }
}
