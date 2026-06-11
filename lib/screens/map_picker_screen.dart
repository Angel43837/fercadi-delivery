// map_picker_screen.dart
// Pantalla para seleccionar una ubicación en el mapa.
// El usuario mueve el mapa y un pin en el centro indica el punto seleccionado.
// Se usa en el perfil (dirección de entrega) y en el checkout.
// Retorna un LatLng con las coordenadas seleccionadas al hacer pop.

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../core/constants.dart';

class MapPickerScreen extends StatefulWidget {
  final ll.LatLng? initial;
  const MapPickerScreen({super.key, this.initial});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  GoogleMapController? _mapCtrl;
  LatLng _center = const LatLng(19.8969, -100.4447);
  double _gpsAccuracy = 999;
  bool _locating = false;
  bool _userInteracted = false;
  bool _disposed = false;
  StreamSubscription<Position>? _gpsSub;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _center = LatLng(widget.initial!.latitude, widget.initial!.longitude);
    } else {
      _goToGps();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _gpsSub?.cancel();
    _mapCtrl?.dispose();
    _mapCtrl = null;
    super.dispose();
  }

  Future<void> _goToGps() async {
    _gpsSub?.cancel();
    setState(() { _locating = true; _gpsAccuracy = 999; _userInteracted = false; });

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

      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        ),
      ).listen((pos) {
        if (_disposed || !mounted) return;
        if (pos.accuracy < _gpsAccuracy) {
          final gps = LatLng(pos.latitude, pos.longitude);
          setState(() {
            _center = gps;
            _gpsAccuracy = pos.accuracy;
          });
          if (!_userInteracted) {
            final zoom = pos.accuracy < 10 ? 19.0
                       : pos.accuracy < 25 ? 18.0
                       : pos.accuracy < 60 ? 17.0
                       : 16.0;
            _mapCtrl?.animateCamera(CameraUpdate.newCameraPosition(
              CameraPosition(target: gps, zoom: zoom),
            ));
          }
          if (pos.accuracy < 10) {
            _gpsSub?.cancel();
            if (mounted) setState(() => _locating = false);
          }
        }
      });

      Future.delayed(const Duration(seconds: 15), () {
        _gpsSub?.cancel();
        if (!_disposed && mounted) setState(() => _locating = false);
      });
    } catch (_) {
      if (mounted) setState(() => _locating = false);
    }
  }

  String get _accuracyLabel {
    if (_gpsAccuracy > 500) return '';
    if (_gpsAccuracy < 10) return 'GPS exacto';
    return '±${_gpsAccuracy.toStringAsFixed(0)} m';
  }

  Color get _accuracyColor {
    if (_gpsAccuracy < 15) return Colors.green;
    if (_gpsAccuracy < 50) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return _buildWebFallback(context);
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

        // ── Mapa Google Maps ──────────────────────────────────────────────────
        GoogleMap(
          initialCameraPosition: CameraPosition(target: _center, zoom: 15.0),
          onMapCreated: (ctrl) {
            _mapCtrl = ctrl;
            if (widget.initial != null) {
              ctrl.animateCamera(CameraUpdate.newCameraPosition(
                CameraPosition(target: _center, zoom: 18.0),
              ));
            }
          },
          onCameraMoveStarted: () => setState(() => _userInteracted = true),
          onCameraMove: (pos) => setState(() => _center = pos.target),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: false,
        ),

        // ── Pin fijo al centro ────────────────────────────────────────────────
        IgnorePointer(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                decoration: BoxDecoration(
                  boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 10,
                    spreadRadius: 2,
                  )],
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
                      _userInteracted
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
                        style: TextStyle(
                            color: _accuracyColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ],
            ]),
          ),
        ),

        // ── Botón GPS ─────────────────────────────────────────────────────────
        Positioned(
          right: 14, bottom: 260,
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
          right: 14, bottom: 165,
          child: Column(children: [
            _ZoomBtn(icon: Icons.add,    onTap: () => _mapCtrl?.animateCamera(CameraUpdate.zoomIn())),
            const SizedBox(height: 6),
            _ZoomBtn(icon: Icons.remove, onTap: () => _mapCtrl?.animateCamera(CameraUpdate.zoomOut())),
          ]),
        ),

        // ── Botón confirmar ───────────────────────────────────────────────────
        Positioned(
          left: 16, right: 16, bottom: 60,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.pop(
              context,
              ll.LatLng(_center.latitude, _center.longitude),
            ),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Confirmar ubicación',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
          ),
        ),
      ]),
    );
  }

  Widget _buildWebFallback(BuildContext context) {
    final ctrl = TextEditingController(
      text: '${_center.latitude.toStringAsFixed(6)}, ${_center.longitude.toStringAsFixed(6)}',
    );
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
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.location_on, color: AppConstants.primaryColor, size: 48),
            const SizedBox(height: 16),
            const Text(
              'El mapa no está disponible en web.\nIngresa tu dirección manualmente:',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Dirección de entrega',
                labelStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: AppConstants.surfaceColor,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppConstants.primaryColor)),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(
                  context,
                  ll.LatLng(_center.latitude, _center.longitude),
                ),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Confirmar ubicación',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15)),
              ),
            ),
          ],
        ),
      ),
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
