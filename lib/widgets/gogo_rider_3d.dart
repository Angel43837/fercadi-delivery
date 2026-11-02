import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

// Repartidor GOGO en moto, en 3D — gira solo y se puede girar con el dedo.
// El modelo (assets/models/gogo_rider.glb) se construyó en Blender a partir
// de la ilustración oficial del repartidor; se renderiza con <model-viewer>
// dentro de un WebView (model_viewer_plus), así que necesita la config de
// red de Android para localhost (res/xml/network_security_config.xml).
class GogoRider3D extends StatelessWidget {
  final double height;

  const GogoRider3D({super.key, this.height = 220});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const ModelViewer(
        src: 'assets/models/gogo_rider.glb',
        alt: 'Repartidor GOGO en su moto',
        autoRotate: true,
        autoRotateDelay: 0,
        rotationPerSecond: '30deg',
        cameraControls: true,
        disableZoom: true,
        disablePan: true,
        // Tres cuartos, un poco desde arriba — el mismo ángulo del render
        // vista_tres_cuartos.png.
        cameraOrbit: '35deg 75deg auto',
        interactionPrompt: InteractionPrompt.none,
        shadowIntensity: 0.6,
        exposure: 1.1,
        ar: false,
      ),
    );
  }
}
