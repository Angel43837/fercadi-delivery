// profile_screen.dart
// Pantalla de perfil del usuario.
// Permite al usuario configurar:
//   - Nombre y foto de perfil
//   - Dirección de entrega predeterminada (GPS, mapa o texto manual)
//   - Método de pago preferido (efectivo, tarjeta)
//   - Datos de tarjeta bancaria
//   - CLABE interbancaria (solo para repartidores)
// También tiene los botones de cerrar sesión y reiniciar la app.

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/supabase_service.dart';
import 'map_picker_screen.dart';

const _avatarColors = [
  AppConstants.primaryColor,
  Color(0xFFFF6D00),
  Color(0xFF00BFA5),
  Color(0xFF7C4DFF),
  Color(0xFF2196F3),
  Color(0xFFFFB300),
  Colors.green,
  Colors.redAccent,
];

const _paymentOptions = [
  (value: 'cash',  label: 'Efectivo',  subtitle: 'Pago al repartidor', icon: Icons.money),
  (value: 'card',  label: 'Tarjeta',   subtitle: 'Crédito o débito',   icon: Icons.credit_card),
];

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameCtrl    = TextEditingController();
  final _clabeCtrl   = TextEditingController();
  String  _payment    = 'cash';
  int     _colorIndex = 0;
  bool    _loading    = true;
  String  _email      = '';
  String  _role       = '';
  String? _photoPath;
  String  _originalName  = '';
  bool    _photoChanged  = false;
  bool    _photoUploading = false;
  // Diagnóstico temporal: en qué paso va la subida de foto ahora mismo —
  // se muestra en pantalla junto al círculo de carga para saber exactamente
  // dónde se traba, sin depender de que un timeout dispare a tiempo. Quitar
  // una vez resuelto el bug de la foto que se queda cargando.
  String? _uploadStage;
  String  _zona          = 'maravatio';

  bool get _isDirty => _photoChanged || _nameCtrl.text.trim() != _originalName;

  // Ubicación de entrega
  String  _addrText    = '';
  double? _addrLat;
  double? _addrLng;
  bool    _addrLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final name    = await AuthService.getDisplayName();
    final payment = await AuthService.getPreferredPayment();
    final color   = await AuthService.getAvatarColorIndex();
    final session = await AuthService.getSession();
    final photo   = await AuthService.getProfilePhoto();
    final clabe   = await AuthService.getCLABE();
    final defAddr = await AuthService.getDefaultAddress();
    final zona    = await AuthService.getZona();
    // El rol real siempre se saca de la sesión activa de Supabase (misma
    // fuente que usa el router para proteger rutas) — la sesión "legacy"
    // de AuthService puede quedar con datos de otra cuenta/rol anterior
    // en el mismo dispositivo (ej. repartidor y cliente comparten teléfono).
    final supaUser = SupabaseService.useMock ? null : Supabase.instance.client.auth.currentUser;
    final realRole = (supaUser?.appMetadata['role'] ?? supaUser?.userMetadata?['role']) as String?;
    if (!mounted) return;
    setState(() {
      _nameCtrl.text  = name;
      _originalName   = name;
      _payment        = payment;
      _colorIndex     = color;
      _email          = supaUser?.email ?? session?.email ?? '';
      _role           = realRole ?? session?.role ?? '';
      _photoPath      = photo;
      _clabeCtrl.text = clabe;
      _zona           = zona;
      if (defAddr != null) {
        _addrText = defAddr['address'] as String? ?? '';
        _addrLat  = (defAddr['lat'] as num?)?.toDouble();
        _addrLng  = (defAddr['lng'] as num?)?.toDouble();
      }
      _loading = false;
    });
  }

  void _showZonaPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('Cambiar zona de entrega',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
          ),
          const SizedBox(height: 8),
          for (final z in const [('maravatio', 'Maravatío'), ('acambaro', 'Acámbaro')])
            ListTile(
              leading: Icon(
                _zona == z.$1 ? Icons.radio_button_checked : Icons.radio_button_off,
                color: AppConstants.primaryColor,
              ),
              title: Text(z.$2, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                if (_zona == z.$1) return;
                setState(() => _zona = z.$1);
                AuthService.saveZona(z.$1);
                // Confirmación inmediata — el efecto real (la lista de
                // restaurantes filtrada) solo se ve hasta regresar a esa
                // pantalla, así que sin esto parece que no pasó nada.
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Zona cambiada a ${z.$2}'),
                  backgroundColor: AppConstants.primaryColor,
                  duration: const Duration(seconds: 2),
                ));
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _showLocationPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('Cambiar dirección de entrega',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppConstants.primaryColor.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.my_location, color: AppConstants.primaryColor, size: 20)),
            title: const Text('Usar mi ubicación actual', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: Text('El GPS detecta dónde estás', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
            onTap: () { Navigator.pop(context); _pickByGPS(); },
          ),
          ListTile(
            leading: Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF2196F3).withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.map_outlined, color: Color(0xFF2196F3), size: 20)),
            title: const Text('Elegir en el mapa', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: Text('Mueve el pin a tu dirección', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
            onTap: () {
              final initial = (_addrLat != null && _addrLng != null)
                  ? LatLng(_addrLat!, _addrLng!)
                  : null;
              Navigator.pop(context);
              _pickByMap(initial);
            },
          ),
          ListTile(
            leading: Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF00BFA5).withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.edit_location_outlined, color: Color(0xFF00BFA5), size: 20)),
            title: const Text('Escribir dirección', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: Text('Ingresa tu dirección manualmente', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
            onTap: () { Navigator.pop(context); _pickManual(); },
          ),
          ListTile(
            leading: Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppConstants.primaryColor.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.map_rounded, color: AppConstants.primaryColor, size: 20)),
            title: const Text('Zona de entrega', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: Text(_zona == 'acambaro' ? 'Acámbaro' : 'Maravatío',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
            onTap: () { Navigator.pop(context); _showZonaPicker(); },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _pickByGPS() async {
    setState(() => _addrLoading = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high))
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      await _pickByMap(LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      if (!mounted) return;
      setState(() => _addrLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo obtener tu ubicación GPS'),
            backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _pickByMap(LatLng? initial) async {
    final result = await Navigator.push<LatLng>(
      context, MaterialPageRoute(builder: (_) => MapPickerScreen(initial: initial)));
    if (result == null || !mounted) return;
    setState(() => _addrLoading = true);
    final addr = await LocationService.reverseGeocode(result.latitude, result.longitude);
    if (!mounted) return;
    final text = addr ?? '${result.latitude.toStringAsFixed(4)}, ${result.longitude.toStringAsFixed(4)}';
    setState(() { _addrText = text; _addrLat = result.latitude; _addrLng = result.longitude; _addrLoading = false; });
    await AuthService.saveAddress(label: 'Casa', address: text, lat: result.latitude, lng: result.longitude);
  }

  void _pickManual() {
    final ctrl = TextEditingController(text: _addrText);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Escribe tu dirección', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Calle, número, colonia...',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            filled: true,
            fillColor: AppConstants.surface2Color,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            prefixIcon: const Icon(Icons.location_on_outlined, color: AppConstants.primaryColor, size: 20),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar', style: TextStyle(color: Colors.white.withValues(alpha: 0.5)))),
          TextButton(
            onPressed: () async {
              final text = ctrl.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx);
              setState(() { _addrText = text; _addrLat = null; _addrLng = null; });
              await AuthService.saveAddress(label: 'Casa', address: text);
            },
            child: const Text('Guardar', style: TextStyle(color: AppConstants.primaryColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Solo guarda — no navega. Se lanza sin esperar (fire-and-forget) desde el
  // botón de regreso para que la pantalla nunca se quede pegada esperando
  // una respuesta de red; cada llamada interna ya tiene su propio timeout.
  Future<void> _save() async {
    try {
      await AuthService.saveDisplayName(_nameCtrl.text);
      await AuthService.savePreferredPayment(_payment);
      await AuthService.saveAvatarColorIndex(_colorIndex);
      await AuthService.saveProfilePhoto(_photoPath);
      await AuthService.saveCLABE(_clabeCtrl.text);
    } catch (_) {}
  }

  void _saveAndExit() {
    _save();
    context.go('/restaurants');
  }

  // A diferencia de _saveAndExit, aquí sí se espera a que termine de guardar
  // (incluye la llamada a Supabase) antes de confirmar, ya que el usuario se
  // queda en la pantalla — no hay riesgo de que se trabe la navegación.
  Future<void> _saveTapped() async {
    await _save();
    if (!mounted) return;
    setState(() {
      _originalName  = _nameCtrl.text.trim();
      _photoChanged  = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Cambios guardados'),
      backgroundColor: AppConstants.primaryColor,
      duration: Duration(seconds: 2),
    ));
  }

  // Abre el recorte estilo WhatsApp: cuadro/círculo para hacer zoom y mover
  // la foto y elegir qué parte se ve. Devuelve null si el usuario cancela.
  Future<String?> _cropImage(String sourcePath) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressQuality: 90,
      maxWidth: 800,
      maxHeight: 800,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Ajustar foto',
          toolbarColor: AppConstants.surfaceColor,
          toolbarWidgetColor: Colors.white,
          statusBarLight: false,
          backgroundColor: AppConstants.bgColor,
          activeControlsWidgetColor: AppConstants.primaryColor,
          cropStyle: CropStyle.circle,
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: 'Ajustar foto',
          cropStyle: CropStyle.circle,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          rotateClockwiseButtonHidden: true,
          doneButtonTitle: 'Listo',
          cancelButtonTitle: 'Cancelar',
        ),
      ],
    );
    return cropped?.path;
  }

  // Supabase sube cada foto nueva a la MISMA url (mismo nombre de archivo por
  // usuario), así que Image.network la mostraba en caché y no se veía la foto
  // nueva. Se le agrega un parámetro de versión para forzar que se vuelva a
  // descargar; Supabase ignora esa parte de la url y sirve el archivo igual.
  String? _withCacheBust(String? url) =>
      url == null ? null : '$url?v=${DateTime.now().millisecondsSinceEpoch}';

  // Borra copias locales viejas de la foto — si se reusa el mismo nombre de
  // archivo, Image.file la muestra desde caché aunque el contenido cambió.
  Future<void> _cleanOldLocalPhotos(Directory appDir) async {
    try {
      await for (final f in appDir.list()) {
        final name = p.basename(f.path);
        if (f is File && name.startsWith('profile_photo_') && name.endsWith('.jpg') &&
            name != 'profile_photo_original.jpg') {
          await f.delete();
        }
      }
    } catch (_) {}
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? xfile;
    try {
      xfile = await picker.pickImage(source: source, imageQuality: 90, maxWidth: 1200);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo abrir la cámara/galería.'),
            backgroundColor: Colors.redAccent));
      }
      return;
    }
    if (xfile == null || !mounted) return;

    // Antes no había ningún indicador ni try/catch general aquí — si algo
    // fallaba a medio camino (ej. el recorte, no solo la subida) la pantalla
    // se quedaba tal cual, sin aviso y sin que nada se apagara.
    setState(() => _photoUploading = true);
    try {
      // Límite de tiempo TOTAL sobre todo el proceso (recorte + conversión +
      // subida + guardado) — de respaldo, además de los límites que ya tiene
      // cada paso por separado: si algo se cuelga en un punto que no
      // contábamos, esto igual garantiza que el círculo de carga se apague.
      await _doPickPhotoFlow(xfile).timeout(const Duration(seconds: 150));
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Se quedó pegado en: $_uploadStage. Intenta de nuevo.'),
            backgroundColor: Colors.redAccent));
      }
    } catch (e) {
      // Cualquier otro fallo inesperado (recorte, lectura de archivo, etc.)
      // — antes esto se perdía en silencio y la pantalla se quedaba igual,
      // sin foto nueva y sin ningún aviso de qué pasó.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error en "$_uploadStage": $e'),
            backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() { _photoUploading = false; _uploadStage = null; });
    }
  }

  Future<void> _doPickPhotoFlow(XFile xfile) async {
    final userId = _email.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

    if (kIsWeb) {
      // En web: leer bytes directamente y subir a Supabase (sin recorte)
      setState(() => _uploadStage = 'leyendo imagen');
      final bytes = await xfile.readAsBytes();
      setState(() => _uploadStage = 'subiendo');
      final remoteUrl = await SupabaseService.uploadProfilePhotoBytes(bytes, userId);
      if (!mounted) return;
      setState(() { _photoPath = _withCacheBust(remoteUrl); _photoChanged = true; });
      if (remoteUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo subir la foto (${SupabaseService.lastUploadError}). Intenta de nuevo.'),
            backgroundColor: Colors.redAccent));
      }
    } else {
      // Se guarda el original sin recortar aparte — así "Reenfocar foto" puede
      // volver a abrir el recorte después sin perder calidad.
      setState(() => _uploadStage = 'preparando archivo');
      final appDir      = await getApplicationDocumentsDirectory();
      final originalPath = p.join(appDir.path, 'profile_photo_original.jpg');
      await File(xfile.path).copy(originalPath);

      setState(() => _uploadStage = 'recortando');
      // Presentar la pantalla de recorte justo cuando la cámara/galería
      // todavía se está cerrando puede hacer que iOS nunca la muestre de
      // verdad — el await se queda esperando un "listo" que no va a
      // llegar porque la pantalla nunca apareció. Esta pausa corta deja
      // que la animación de cierre anterior termine primero.
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      final croppedPath = await _cropImage(originalPath).timeout(
        const Duration(seconds: 90),
        onTimeout: () => throw TimeoutException('recorte de foto'),
      );
      if (croppedPath == null || !mounted) return; // canceló el recorte

      setState(() => _uploadStage = 'preparando archivo');
      await _cleanOldLocalPhotos(appDir);
      final destPath = p.join(appDir.path, 'profile_photo_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(croppedPath).copy(destPath);
      setState(() => _uploadStage = 'convirtiendo y subiendo');
      final remoteUrl = await SupabaseService.uploadProfilePhoto(destPath, userId);
      if (!mounted) return;
      setState(() { _photoPath = _withCacheBust(remoteUrl) ?? destPath; _photoChanged = true; });
      // Si la subida falla, _photoPath se queda con la ruta local — se ve
      // bien en esta pantalla pero NO se guarda en la cuenta (otros
      // usuarios/dispositivos nunca la verían) — avisar en vez de fallar en silencio.
      if (remoteUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo subir la foto (${SupabaseService.lastUploadError}) — solo se ve en este dispositivo.'),
            backgroundColor: Colors.redAccent));
      }
    }
    setState(() => _uploadStage = 'guardando en tu cuenta');
    // Se guarda de inmediato (no hasta tocar "Guardar") — si el usuario sale
    // con el gesto de deslizar de iOS ninguno de los botones del AppBar se
    // llega a ejecutar, y la foto recién elegida se perdía.
    final saved = await AuthService.saveProfilePhoto(_photoPath);
    // La subida a Storage pudo salir bien pero este segundo paso (guardarla
    // en la cuenta) fallar aparte — sin este aviso se queda solo en este
    // dispositivo sin que nadie se entere.
    if (saved == false && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('La foto se subió pero no se pudo guardar en tu cuenta. Intenta de nuevo.'),
          backgroundColor: Colors.redAccent));
    }
  }

  // Vuelve a abrir el recorte sobre la foto ya puesta, para ajustar el
  // encuadre sin tener que elegir la foto de nuevo (como "editar" en WhatsApp).
  Future<void> _refocusPhoto() async {
    if (kIsWeb || _photoPath == null) return;
    setState(() => _photoUploading = true);
    try {
      // Mismo respaldo que _pickPhoto(): un límite total además de los que
      // ya tiene cada paso por separado.
      await _doRefocusPhotoFlow().timeout(const Duration(seconds: 150));
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('La foto tardó demasiado en procesarse. Intenta de nuevo.'),
            backgroundColor: Colors.redAccent));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo procesar la foto. Intenta de nuevo.'),
            backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _photoUploading = false);
    }
  }

  Future<void> _doRefocusPhotoFlow() async {
    final appDir       = await getApplicationDocumentsDirectory();
    final originalPath = p.join(appDir.path, 'profile_photo_original.jpg');
    String? sourcePath;

      if (await File(originalPath).exists()) {
        sourcePath = originalPath;
      } else if (_photoPath!.startsWith('http')) {
        // No hay copia local del original (ej. foto puesta antes de esta
        // función, o en otro dispositivo) — se descarga la ya subida para
        // poder recortarla de nuevo.
        try {
          final response = await http.get(Uri.parse(_photoPath!)).timeout(const Duration(seconds: 15));
          if (response.statusCode == 200) {
            await File(originalPath).writeAsBytes(response.bodyBytes);
            sourcePath = originalPath;
          }
        } catch (_) {}
      } else {
        sourcePath = _photoPath;
      }
      if (sourcePath == null || !mounted) return;

      // Misma pausa que _pickPhoto(): dejar que cualquier pantalla anterior
      // termine de cerrarse antes de presentar el recorte.
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      final croppedPath = await _cropImage(sourcePath).timeout(
        const Duration(seconds: 90),
        onTimeout: () => throw TimeoutException('recorte de foto'),
      );
      if (croppedPath == null || !mounted) return;

      await _cleanOldLocalPhotos(appDir);
      final destPath = p.join(appDir.path, 'profile_photo_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(croppedPath).copy(destPath);
      final userId    = _email.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final remoteUrl = await SupabaseService.uploadProfilePhoto(destPath, userId);
      if (!mounted) return;
      setState(() { _photoPath = _withCacheBust(remoteUrl) ?? destPath; _photoChanged = true; });
      if (remoteUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo subir la foto — solo se ve en este dispositivo. Intenta de nuevo.'),
            backgroundColor: Colors.redAccent));
      }
      final saved = await AuthService.saveProfilePhoto(_photoPath);
      if (saved == false && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('La foto se subió pero no se pudo guardar en tu cuenta. Intenta de nuevo.'),
            backgroundColor: Colors.redAccent));
      }
  }

  void _showPhotoPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.surfaceColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: AppConstants.primaryColor),
            title: const Text('Tomar foto', style: TextStyle(color: Colors.white)),
            onTap: () { Navigator.pop(context); _pickPhoto(ImageSource.camera); },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: AppConstants.primaryColor),
            title: const Text('Elegir de galería', style: TextStyle(color: Colors.white)),
            onTap: () { Navigator.pop(context); _pickPhoto(ImageSource.gallery); },
          ),
          if (_photoPath != null && !kIsWeb)
            ListTile(
              leading: const Icon(Icons.center_focus_strong, color: AppConstants.primaryColor),
              title: const Text('Reenfocar foto', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(context); _refocusPhoto(); },
            ),
          if (_photoPath != null)
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.redAccent.withValues(alpha: 0.8)),
              title: Text('Quitar foto', style: TextStyle(color: Colors.redAccent.withValues(alpha: 0.8))),
              onTap: () { Navigator.pop(context); setState(() { _photoPath = null; _photoChanged = true; }); },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _clabeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppConstants.primaryColor)),
      );
    }

    final avatarColor = _avatarColors[_colorIndex % _avatarColors.length];
    final initials = _nameCtrl.text.trim().isEmpty
        ? '?'
        : _nameCtrl.text.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();

    // Colores adaptativos para las tarjetas internas
    final cardBg     = isDark ? AppConstants.surfaceColor : Colors.white;
    final cardText   = isDark ? Colors.white : Colors.black87;
    final cardSub    = isDark ? Colors.white.withValues(alpha: 0.4) : Colors.black54;
    final cardDiv    = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.07);
    final cardChev   = isDark ? Colors.white.withValues(alpha: 0.3) : Colors.black38;
    final inputText  = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          // Guarda en segundo plano y regresa al instante — no espera a la
          // red, así nunca se queda pegada en esta pantalla.
          onPressed: _saveAndExit,
        ),
        title: const Text('Mi perfil', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_isDirty)
            TextButton(
              onPressed: _saveTapped,
              child: const Text('Guardar',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              final router = GoRouter.of(context);
              await AuthService.clearSession();
              if (!mounted) return;
              router.go('/login');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [

          // ── Avatar / Foto ───────────────────────────────────────────────────
          Center(
            child: Column(children: [
              GestureDetector(
                onTap: _photoUploading ? null : _showPhotoPicker,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 96, height: 96,
                      decoration: BoxDecoration(
                        color: avatarColor,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: avatarColor.withValues(alpha: 0.4), blurRadius: 20, spreadRadius: 2)],
                      ),
                      child: _photoPath != null
                          ? ClipOval(child: _ProfileImage(path: _photoPath!, size: 96))
                          : Center(
                              child: Text(initials,
                                  style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                            ),
                    ),
                    if (_photoUploading)
                      Container(
                        width: 96, height: 96,
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Center(
                          child: SizedBox(
                            width: 32, height: 32,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: AppConstants.primaryColor, shape: BoxShape.circle),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _photoUploading && _uploadStage != null ? _uploadStage! : 'Toca para cambiar foto',
                style: TextStyle(
                  color: _photoUploading ? Colors.white : Colors.white.withValues(alpha: 0.55),
                  fontSize: 11,
                  fontWeight: _photoUploading ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 12),
              if (_photoPath == null) ...[
                Text('Elige un color para tu avatar',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_avatarColors.length, (i) {
                    final selected = i == _colorIndex;
                    return GestureDetector(
                      onTap: () => setState(() => _colorIndex = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        width: selected ? 34 : 28, height: selected ? 34 : 28,
                        decoration: BoxDecoration(
                          color: _avatarColors[i],
                          shape: BoxShape.circle,
                          border: selected ? Border.all(color: Colors.white, width: 2.5) : null,
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 28),

          // ── Nombre ──────────────────────────────────────────────────────────
          _SectionLabel('Nombre'),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            style: TextStyle(color: inputText, fontSize: 16),
            onChanged: (_) => setState(() {}),
            decoration: _inputDeco('Tu nombre', Icons.person_outline),
          ),
          const SizedBox(height: 6),
          Text(_email, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
          const SizedBox(height: 28),

          // ── Dirección de entrega y método de pago (solo cliente) ─────────────
          // El repartidor no pide comida ni le entregan a él — estos campos
          // son del rol cliente y no deben mezclarse entre pantallas.
          if (_role != 'repartidor') ...[
            _SectionLabel('Dirección de entrega'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showLocationPicker,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16)),
                child: _addrLoading
                    ? const Center(child: SizedBox(width: 24, height: 24,
                        child: CircularProgressIndicator(color: AppConstants.primaryColor, strokeWidth: 2)))
                    : Row(children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: AppConstants.primaryColor.withValues(alpha: 0.12), shape: BoxShape.circle),
                          child: const Icon(Icons.location_on, color: AppConstants.primaryColor, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            _addrText.isEmpty ? 'Sin dirección guardada' : _addrText,
                            style: TextStyle(
                                color: _addrText.isEmpty ? cardSub : cardText, fontSize: 14),
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          const Text('Toca para cambiar',
                              style: TextStyle(color: AppConstants.primaryColor, fontSize: 11)),
                        ])),
                        Icon(Icons.chevron_right, color: cardChev),
                      ]),
              ),
            ),
            const SizedBox(height: 28),

            _SectionLabel('Método de pago preferido'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: List.generate(_paymentOptions.length, (i) {
                  final opt      = _paymentOptions[i];
                  final selected = _payment == opt.value;
                  final isLast   = i == _paymentOptions.length - 1;
                  return Column(children: [
                    InkWell(
                      borderRadius: BorderRadius.vertical(
                        top:    i == 0  ? const Radius.circular(16) : Radius.zero,
                        bottom: isLast  ? const Radius.circular(16) : Radius.zero,
                      ),
                      onTap: () => setState(() => _payment = opt.value),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(children: [
                          Icon(opt.icon,
                              color: selected ? AppConstants.primaryColor : cardSub, size: 24),
                          const SizedBox(width: 14),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(opt.label, style: TextStyle(
                                color: selected ? AppConstants.primaryColor : cardText,
                                fontWeight: FontWeight.w600, fontSize: 15)),
                            Text(opt.subtitle, style: TextStyle(color: cardSub, fontSize: 12)),
                          ])),
                          Container(
                            width: 22, height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: selected ? AppConstants.primaryColor : cardChev, width: 2),
                            ),
                            child: selected
                                ? Center(child: Container(width: 11, height: 11,
                                    decoration: const BoxDecoration(
                                        shape: BoxShape.circle, color: AppConstants.primaryColor)))
                                : null,
                          ),
                        ]),
                      ),
                    ),
                    if (!isLast) Divider(height: 1, color: cardDiv, indent: 16, endIndent: 16),
                  ]);
                }),
              ),
            ),
            const SizedBox(height: 28),
          ],

          // ── CLABE interbancaria (solo repartidor) ────────────────────────────
          if (_role == 'repartidor') ...[
            _SectionLabel('Cuenta bancaria para recibir pagos'),
            const SizedBox(height: 8),
            TextField(
              controller: _clabeCtrl,
              style: TextStyle(color: inputText, fontSize: 16, letterSpacing: 1.5),
              keyboardType: TextInputType.number,
              maxLength: 18,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _inputDeco('CLABE interbancaria (18 dígitos)', Icons.account_balance_outlined)
                  .copyWith(counterText: ''),
            ),
            const SizedBox(height: 28),
          ],

          // Nota: el pago con tarjeta se procesa siempre con Stripe (PaymentSheet)
          // directo en el checkout — no se guarda ningún dato de tarjeta aquí.

          // ── Sesión ──────────────────────────────────────────────────────────
          _SectionLabel('Sesión'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: const Icon(Icons.logout, color: Colors.orange, size: 20),
                ),
                title: Text('Cerrar sesión', style: TextStyle(color: cardText, fontWeight: FontWeight.w600)),
                subtitle: Text('Mantiene tus datos guardados', style: TextStyle(color: cardSub, fontSize: 12)),
                trailing: Icon(Icons.chevron_right, color: cardChev),
                onTap: () async {
                  final router = GoRouter.of(context);
                  await AuthService.clearSession();
                  if (!mounted) return;
                  router.go('/login');
                },
              ),
            ]),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }


  InputDecoration _inputDeco(String hint, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.3) : Colors.black38),
      prefixIcon: Icon(icon, color: AppConstants.primaryColor, size: 20),
      filled: true,
      fillColor: isDark ? AppConstants.surfaceColor : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppConstants.primaryColor, width: 1.5)),
    );
  }
}

// ── Widgets pequeños ──────────────────────────────────────────────────────────

class _ProfileImage extends StatelessWidget {
  final String path;
  final double size;
  const _ProfileImage({required this.path, required this.size});

  @override
  Widget build(BuildContext context) {
    if (path.startsWith('http')) {
      return Image.network(path, fit: BoxFit.cover, width: size, height: size,
          errorBuilder: (_, e, s) => const Icon(Icons.person, color: Colors.white));
    }
    return Image.file(File(path), fit: BoxFit.cover, width: size, height: size,
        errorBuilder: (_, e, s) => const Icon(Icons.person, color: Colors.white));
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, shadows: [
          Shadow(color: Colors.black26, blurRadius: 4),
        ]));
  }
}
