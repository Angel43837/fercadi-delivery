// map_picker_screen.dart
// Pantalla para seleccionar una ubicación en el mapa.
// Móvil: Google Maps (google_maps_flutter)
// Web: OpenStreetMap via flutter_map
// El pin queda fijo al centro y el usuario mueve el mapa para ajustar.
// Retorna LatLng al hacer pop.

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../core/constants.dart';
import '../services/geocoding_service.dart';

class MapPickerScreen extends StatefulWidget {
  final ll.LatLng? initial;
  const MapPickerScreen({super.key, this.initial});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  // ── Google Maps (móvil) ──────────────────────────────────────────────────
  gm.GoogleMapController? _gmCtrl;
  gm.LatLng _gmCenter = const gm.LatLng(19.8969, -100.4447);

  // ── flutter_map (web) ────────────────────────────────────────────────────
  final _fmCtrl = MapController();
  ll.LatLng _fmCenter = const ll.LatLng(19.8969, -100.4447);

  // ── Estado compartido ────────────────────────────────────────────────────
  double _gpsAccuracy = 999;
  bool _locating = false;
  bool _userInteracted = false;
  bool _disposed = false;
  bool _searching = false;
  StreamSubscription<Position>? _gpsSub;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _gmCenter = gm.LatLng(widget.initial!.latitude, widget.initial!.longitude);
      _fmCenter = ll.LatLng(widget.initial!.latitude, widget.initial!.longitude);
      _userInteracted = true;
    } else {
      _goToGps();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _gpsSub?.cancel();
    _gmCtrl?.dispose();
    _gmCtrl = null;
    _searchCtrl.dispose();
    super.dispose();
  }

  ll.LatLng get _currentCenter => kIsWeb
      ? _fmCenter
      : ll.LatLng(_gmCenter.latitude, _gmCenter.longitude);

  Future<void> _searchAddress() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;
    setState(() => _searching = true);
    try {
      final result = await GeocodingService.searchAddress(query);
      if (!mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se encontró esa dirección')),
        );
        return;
      }
      if (kIsWeb) {
        final pos = ll.LatLng(result.lat, result.lng);
        setState(() { _fmCenter = pos; _userInteracted = true; });
        _fmCtrl.move(pos, 17.0);
      } else {
        final pos = gm.LatLng(result.lat, result.lng);
        setState(() { _gmCenter = pos; _userInteracted = true; });
        _gmCtrl?.animateCamera(gm.CameraUpdate.newCameraPosition(
          gm.CameraPosition(target: pos, zoom: 17.0),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al buscar la dirección')),
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
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
          setState(() => _gpsAccuracy = pos.accuracy);
          if (!_userInteracted) {
            final zoom = pos.accuracy < 10 ? 19.0
                       : pos.accuracy < 25 ? 18.0
                       : pos.accuracy < 60 ? 17.0
                       : 16.0;
            if (kIsWeb) {
              final gps = ll.LatLng(pos.latitude, pos.longitude);
              setState(() => _fmCenter = gps);
              _fmCtrl.move(gps, zoom);
            } else {
              final gps = gm.LatLng(pos.latitude, pos.longitude);
              setState(() => _gmCenter = gps);
              _gmCtrl?.animateCamera(gm.CameraUpdate.newCameraPosition(
                gm.CameraPosition(target: gps, zoom: zoom),
              ));
            }
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

  void _confirm() => Navigator.pop(context, _currentCenter);

  @override
  Widget build(BuildContext context) {
    return kIsWeb ? _buildWebMap() : _buildMobileMap();
  }

  // ── Web: flutter_map con OpenStreetMap ───────────────────────────────────
  Widget _buildWebMap() {
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

        // ── Mapa OpenStreetMap ───────────────────────────────────────────
        FlutterMap(
          mapController: _fmCtrl,
          options: MapOptions(
            initialCenter: _fmCenter,
            initialZoom: 16.0,
            onPositionChanged: (position, hasGesture) {
              if (hasGesture && position.center != null) {
                setState(() {
                  _fmCenter = position.center!;
                  _userInteracted = true;
                });
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.fercadi.app',
            ),
          ],
        ),

        // ── Pin fijo al centro ───────────────────────────────────────────
        IgnorePointer(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                decoration: BoxDecoration(
                  boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 10, spreadRadius: 2,
                  )],
                ),
                child: Icon(Icons.location_on,
                    color: AppConstants.primaryColor, size: 42),
              ),
              const SizedBox(height: 30),
            ]),
          ),
        ),

        // ── Buscador + instrucción ───────────────────────────────────────
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8)],
                ),
                child: Row(children: [
                  const SizedBox(width: 12),
                  const Icon(Icons.search, color: Colors.black54, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(color: Colors.black87, fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Busca tu calle o colonia...',
                        hintStyle: TextStyle(color: Colors.black38, fontSize: 14),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      onSubmitted: (_) => _searchAddress(),
                      textInputAction: TextInputAction.search,
                    ),
                  ),
                  if (_searching)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppConstants.primaryColor)),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.arrow_forward, color: AppConstants.primaryColor, size: 20),
                      onPressed: _searchAddress,
                    ),
                ]),
              ),
              const SizedBox(height: 8),
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
                          : 'Mueve el mapa para poner el pin en tu casa',
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

        // ── Botón GPS ────────────────────────────────────────────────────
        Positioned(
          right: 14, bottom: 160,
          child: FloatingActionButton.small(
            heroTag: 'gps_web',
            backgroundColor: Colors.white,
            onPressed: _locating ? null : _goToGps,
            tooltip: 'Ir a mi ubicación',
            child: _locating
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black54))
                : const Icon(Icons.my_location, color: Colors.black87, size: 20),
          ),
        ),

        // ── Botones zoom ─────────────────────────────────────────────────
        Positioned(
          right: 14, bottom: 220,
          child: Column(children: [
            _ZoomBtn(icon: Icons.add,    onTap: () => _fmCtrl.move(_fmCenter, _fmCtrl.camera.zoom + 1)),
            const SizedBox(height: 6),
            _ZoomBtn(icon: Icons.remove, onTap: () => _fmCtrl.move(_fmCenter, _fmCtrl.camera.zoom - 1)),
          ]),
        ),

        // ── Botón confirmar ──────────────────────────────────────────────
        Positioned(
          left: 16, right: 16, bottom: 60,
          child: ElevatedButton.icon(
            onPressed: _confirm,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Confirmar ubicación',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
          ),
        ),
      ]),
    );
  }

  // ── Móvil: Google Maps ───────────────────────────────────────────────────
  Widget _buildMobileMap() {
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

        gm.GoogleMap(
          initialCameraPosition: gm.CameraPosition(target: _gmCenter, zoom: 15.0),
          onMapCreated: (ctrl) {
            _gmCtrl = ctrl;
            if (widget.initial != null) {
              ctrl.animateCamera(gm.CameraUpdate.newCameraPosition(
                gm.CameraPosition(target: _gmCenter, zoom: 18.0),
              ));
            }
          },
          onCameraMoveStarted: () => setState(() => _userInteracted = true),
          onCameraMove: (pos) => setState(() => _gmCenter = pos.target),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: false,
        ),

        IgnorePointer(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                decoration: BoxDecoration(
                  boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 10, spreadRadius: 2,
                  )],
                ),
                child: Icon(Icons.location_on, color: AppConstants.primaryColor, size: 36),
              ),
              const SizedBox(height: 26),
            ]),
          ),
        ),

        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8)],
                ),
                child: Row(children: [
                  const SizedBox(width: 12),
                  const Icon(Icons.search, color: Colors.black54, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(color: Colors.black87, fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Busca tu calle o colonia...',
                        hintStyle: TextStyle(color: Colors.black38, fontSize: 14),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      onSubmitted: (_) => _searchAddress(),
                      textInputAction: TextInputAction.search,
                    ),
                  ),
                  if (_searching)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppConstants.primaryColor)),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.arrow_forward, color: AppConstants.primaryColor, size: 20),
                      onPressed: _searchAddress,
                    ),
                ]),
              ),
              const SizedBox(height: 8),
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
                        style: TextStyle(color: _accuracyColor, fontSize: 11, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ],
            ]),
          ),
        ),

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

        Positioned(
          right: 14, bottom: 165,
          child: Column(children: [
            _ZoomBtn(icon: Icons.add,    onTap: () => _gmCtrl?.animateCamera(gm.CameraUpdate.zoomIn())),
            const SizedBox(height: 6),
            _ZoomBtn(icon: Icons.remove, onTap: () => _gmCtrl?.animateCamera(gm.CameraUpdate.zoomOut())),
          ]),
        ),

        Positioned(
          left: 16, right: 16, bottom: 60,
          child: ElevatedButton.icon(
            onPressed: _confirm,
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
