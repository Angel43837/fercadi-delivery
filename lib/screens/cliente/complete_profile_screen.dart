// complete_profile_screen.dart
// Último paso del alta por teléfono: nombre + foto (opcional). Solo se
// muestra para cuentas de teléfono nuevas — verificado el código, la cuenta
// ya existe en Supabase Auth pero todavía no tiene rol ni nombre.
//
// Reutiliza tal cual el patrón ya probado en profile_screen.dart para elegir
// y subir la foto (recorte circular, conversión a WebP, timeout + try/catch
// con aviso claro si algo falla) — no se reinventa nada nuevo ahí, solo se
// recorta a lo mínimo que hace falta aquí (sin "reenfocar foto", eso es una
// función de edición posterior que vive en profile_screen.dart).

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';

class CompleteProfileScreen extends StatefulWidget {
  final String? returnTo;
  const CompleteProfileScreen({super.key, this.returnTo});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _nameCtrl = TextEditingController();
  String? _photoPath;
  bool _photoUploading = false;
  String? _uploadStage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Si por algún motivo se llega aquí con una cuenta que ya tiene rol
    // (deep link viejo, doble tap, back navigation) no hay nada que
    // completar — se sigue de largo en vez de dejar al usuario varado.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = Supabase.instance.client.auth.currentUser;
      final hasRole = user?.appMetadata['role'] != null || user?.userMetadata?['role'] != null;
      if (hasRole && mounted) _goNext();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  String get _userId => Supabase.instance.client.auth.currentUser?.id ?? 'guest';

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

    setState(() => _photoUploading = true);
    try {
      await _doPickPhotoFlow(xfile).timeout(const Duration(seconds: 150));
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Se quedó pegado en: $_uploadStage. Intenta de nuevo.'),
            backgroundColor: Colors.redAccent));
      }
    } catch (e) {
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
    final userId = _userId;
    if (kIsWeb) {
      setState(() => _uploadStage = 'leyendo imagen');
      final bytes = await xfile.readAsBytes();
      setState(() => _uploadStage = 'subiendo');
      final remoteUrl = await SupabaseService.uploadProfilePhotoBytes(bytes, userId);
      if (!mounted) return;
      setState(() => _photoPath = remoteUrl);
      if (remoteUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo subir la foto (${SupabaseService.lastUploadError}). Intenta de nuevo.'),
            backgroundColor: Colors.redAccent));
      }
    } else {
      setState(() => _uploadStage = 'preparando archivo');
      final appDir = await getApplicationDocumentsDirectory();
      final originalPath = p.join(appDir.path, 'profile_photo_original.jpg');
      await File(xfile.path).copy(originalPath);

      setState(() => _uploadStage = 'recortando');
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      final croppedPath = await _cropImage(originalPath).timeout(
        const Duration(seconds: 90),
        onTimeout: () => throw TimeoutException('recorte de foto'),
      );
      if (croppedPath == null || !mounted) return;

      setState(() => _uploadStage = 'preparando archivo');
      final destPath = p.join(appDir.path, 'profile_photo_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(croppedPath).copy(destPath);
      setState(() => _uploadStage = 'convirtiendo y subiendo');
      final remoteUrl = await SupabaseService.uploadProfilePhoto(destPath, userId);
      if (!mounted) return;
      setState(() => _photoPath = remoteUrl ?? destPath);
      if (remoteUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo subir la foto (${SupabaseService.lastUploadError}) — solo se ve en este dispositivo.'),
            backgroundColor: Colors.redAccent));
      }
    }
  }

  void _showPhotoPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined, color: Colors.white),
            title: const Text('Tomar foto', style: TextStyle(color: Colors.white)),
            onTap: () { Navigator.pop(ctx); _pickPhoto(ImageSource.camera); },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: Colors.white),
            title: const Text('Elegir de la galería', style: TextStyle(color: Colors.white)),
            onTap: () { Navigator.pop(ctx); _pickPhoto(ImageSource.gallery); },
          ),
        ]),
      ),
    );
  }

  void _goNext() {
    final target = (widget.returnTo != null && widget.returnTo!.isNotEmpty) ? widget.returnTo! : '/restaurants';
    if (mounted) context.go(target);
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Escribe tu nombre para continuar'), backgroundColor: Colors.redAccent));
      return;
    }
    setState(() => _saving = true);
    try {
      // role: 'cliente' es lo que hace que esta cuenta cuente, de aquí en
      // adelante, como una cuenta ya completa (ver el chequeo de isNewUser
      // en phone_otp_flow.dart y el guard de initState arriba).
      await Supabase.instance.client.auth.updateUser(UserAttributes(data: {
        'role': 'cliente',
        'custom_name': name,
        if (_photoPath != null && _photoPath!.startsWith('http')) 'custom_avatar_url': _photoPath,
        'accepted_terms_at': DateTime.now().toIso8601String(),
      }));
      // El JWT recién emitido no trae todavía el app_metadata que acaba de
      // escribir el trigger sync_role_to_app_metadata — sin este refresh, la
      // siguiente pantalla (protegida por rol) podría rechazar al usuario
      // como si no tuviera cuenta de cliente todavía. Mismo arreglo ya usado
      // en el registro real del sitio web (realSubmission.ts).
      await Supabase.instance.client.auth.refreshSession();

      final user = Supabase.instance.client.auth.currentUser;
      await AuthService.saveSession(
        user?.id ?? _userId,
        '/restaurants',
        phone: user?.phone,
      );
      await AuthService.saveDisplayName(name);
      if (_photoPath != null) await AuthService.saveProfilePhoto(_photoPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo guardar tu perfil: $e'), backgroundColor: Colors.redAccent));
        setState(() => _saving = false);
      }
      return;
    }
    if (mounted) setState(() => _saving = false);
    _goNext();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Text('¡Ya casi!', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 6),
              Text('Cuéntanos cómo te llamas para tu cuenta GOGO',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
              const SizedBox(height: 32),
              Center(
                child: GestureDetector(
                  onTap: _photoUploading ? null : _showPhotoPicker,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircleAvatar(
                        radius: 52,
                        backgroundColor: AppConstants.surfaceColor,
                        backgroundImage: _photoPath != null
                            ? (_photoPath!.startsWith('http')
                                ? NetworkImage(_photoPath!)
                                : FileImage(File(_photoPath!)) as ImageProvider)
                            : null,
                        child: _photoPath == null
                            ? const Icon(Icons.person, size: 48, color: Colors.white38)
                            : null,
                      ),
                      Positioned(
                        bottom: 0, right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: AppConstants.primaryColor, shape: BoxShape.circle),
                          child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                        ),
                      ),
                      if (_photoUploading)
                        const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    ],
                  ),
                ),
              ),
              if (_photoUploading && _uploadStage != null) ...[
                const SizedBox(height: 8),
                Center(child: Text(_uploadStage!, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12))),
              ],
              const SizedBox(height: 28),
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Tu nombre',
                  labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                  prefixIcon: const Icon(Icons.person_outline, color: Colors.white70),
                  filled: true,
                  fillColor: AppConstants.surfaceColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppConstants.primaryColor, width: 1.5)),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: (_saving || _photoUploading) ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: _saving
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('CREAR CUENTA', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
