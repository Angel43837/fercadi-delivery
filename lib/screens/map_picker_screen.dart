import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
  LatLng _center = _kMaravatio;

  @override
  void initState() {
    super.initState();
    _mapCtrl = MapController();
    if (widget.initial != null) _center = widget.initial!;
  }

  @override
  void dispose() {
    _mapCtrl.dispose();
    super.dispose();
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
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 15.5,
              onPositionChanged: (pos, _) {
                if (pos.center != null) {
                  setState(() => _center = pos.center!);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.landing_test',
              ),
            ],
          ),

          // Pin fijo en el centro de la pantalla
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_on, color: AppConstants.primaryColor, size: 48),
                SizedBox(height: 24),
              ],
            ),
          ),

          // Instrucción superior
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppConstants.surfaceColor.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.pan_tool_alt_outlined,
                        color: Colors.white.withValues(alpha: 0.6), size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Mueve el mapa para colocar el pin en tu casa',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Botón confirmar
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
