import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../core/constants.dart';

const _kMaravatio = LatLng(19.8969, -100.4447);

class MapPickerScreen extends StatefulWidget {
  final LatLng? initial;
  const MapPickerScreen({super.key, this.initial});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  late final MapController _mapCtrl;
  LatLng   _center      = _kMaravatio;
  LatLng?  _gpsPos;         // última posición GPS recibida
  double   _gpsAccuracy = 999; // metros de precisión
  bool     _locating    = false;
  bool     _mapReady    = false;
  bool     _userMoved   = false; // el usuario arrastró el mapa manualmente

  StreamSubscription<Position>? _gpsSub;

  @override
  void initState() {
    super.initState();
    _mapCtrl = MapController();
    if (widget.initial != null) {
      _center = widget.initial!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _moveMap(_center, 18.0));
    } else {
      _goToGps();
    }
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _mapCtrl.dispose();
    super.dispose();
  }

  Future<void> _goToGps() async {
    _gpsSub?.cancel();
    setState(() { _locating = true; _userMoved = false; });

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

      // Suscripción al stream — se actualiza cada vez que llega un fix más preciso
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        ),
      ).listen((pos) {
        if (!mounted) return;
        // Solo actualiza si mejora la precisión Y el usuario no ha movido el mapa
        if (pos.accuracy < _gpsAccuracy) {
          final gps = LatLng(pos.latitude, pos.longitude);
          setState(() {
            _gpsPos      = gps;
            _gpsAccuracy = pos.accuracy;
            if (!_userMoved) _center = gps;
          });
          if (!_userMoved) {
            // Zoom en función de la precisión
            final zoom = pos.accuracy < 10 ? 19.0
                       : pos.accuracy < 25 ? 18.0
                       : pos.accuracy < 60 ? 17.0
                       : 16.0;
            _moveMap(gps, zoom);
          }
          // Si ya tenemos precisión menor a 10m, paramos de buscar
          if (pos.accuracy < 10) {
            _gpsSub?.cancel();
            if (mounted) setState(() => _locating = false);
          }
        }
      });

      // Timeout: después de 15s paramos aunque no hayamos llegado a 10m
      Future.delayed(const Duration(seconds: 15), () {
        _gpsSub?.cancel();
        if (mounted) setState(() => _locating = false);
      });
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

  void _zoomIn()  {
    try { _mapCtrl.move(_mapCtrl.camera.center, (_mapCtrl.camera.zoom + 1).clamp(3, 21)); } catch (_) {}
  }
  void _zoomOut() {
    try { _mapCtrl.move(_mapCtrl.camera.center, (_mapCtrl.camera.zoom - 1).clamp(3, 21)); } catch (_) {}
  }

  String get _accuracyLabel {
    if (_gpsAccuracy > 500) return '';
    if (_gpsAccuracy < 10)  return 'GPS exacto';
    return '±${_gpsAccuracy.toStringAsFixed(0)} m';
  }

  Color get _accuracyColor {
    if (_gpsAccuracy < 15)  return Colors.green;
    if (_gpsAccuracy < 50)  return Colors.orange;
    return Colors.red;
  }

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
      body: Stack(children: [

        // ── Mapa ──────────────────────────────────────────────────────────────
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: 15.0,
            onMapReady: () => setState(() => _mapReady = true),
            onPositionChanged: (pos, hasGesture) {
              if (pos.center != null) {
                setState(() {
                  _center = pos.center!;
                  if (hasGesture) _userMoved = true; // usuario movió el mapa
                });
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.example.landing_test',
            ),
            // Círculo de precisión GPS (azul)
            if (_gpsPos != null && _gpsAccuracy < 200)
              CircleLayer(circles: [
                CircleMarker(
                  point: _gpsPos!,
                  radius: _gpsAccuracy,
                  useRadiusInMeter: true,
                  color: Colors.blue.withValues(alpha: 0.12),
                  borderColor: Colors.blue.withValues(alpha: 0.5),
                  borderStrokeWidth: 1.5,
                ),
              ]),
          ],
        ),

        // ── Pin fijo al centro (donde el usuario confirma) ────────────────────
        IgnorePointer(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                decoration: BoxDecoration(
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 10, spreadRadius: 2)],
                ),
                child: Icon(Icons.location_on, color: AppConstants.primaryColor, size: 52),
              ),
              const SizedBox(height: 26),
            ]),
          ),
        ),

        // ── Instrucción + precisión GPS ───────────────────────────────────────
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(Icons.pan_tool_alt_outlined,
                      color: Colors.white.withValues(alpha: 0.7), size: 16),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _userMoved
                          ? 'Pin en esta posición — arrastra para ajustar'
                          : 'Mueve el mapa para poner el pin exacto en tu casa',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12),
                    ),
                  ),
                ]),
              ),
              if (_accuracyLabel.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_locating)
                      const SizedBox(width: 10, height: 10,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white))
                    else
                      Icon(Icons.gps_fixed, size: 12, color: _accuracyColor),
                    const SizedBox(width: 5),
                    Text(_accuracyLabel,
                        style: TextStyle(color: _accuracyColor, fontSize: 11, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ],
            ]),
          ),
        ),

        // ── Botón GPS ─────────────────────────────────────────────────────────
        Positioned(
          right: 14, bottom: 210,
          child: FloatingActionButton.small(
            heroTag: 'gps_btn',
            backgroundColor: Colors.white,
            onPressed: _locating ? null : _goToGps,
            tooltip: 'Ir a mi ubicación',
            child: _locating
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black54))
                : const Icon(Icons.my_location, color: Colors.black87, size: 20),
          ),
        ),

        // ── Botones zoom ──────────────────────────────────────────────────────
        Positioned(
          right: 14, bottom: 115,
          child: Column(children: [
            _ZoomBtn(icon: Icons.add, onTap: _zoomIn),
            const SizedBox(height: 6),
            _ZoomBtn(icon: Icons.remove, onTap: _zoomOut),
          ]),
        ),

        // ── Botón confirmar ───────────────────────────────────────────────────
        Positioned(
          left: 16, right: 16, bottom: 32,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, _center),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Confirmar ubicación',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
          ),
        ),
      ]),
    );
  }
}

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
