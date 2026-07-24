import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';

class RepartidorPlusScreen extends StatefulWidget {
  const RepartidorPlusScreen({super.key});
  @override
  State<RepartidorPlusScreen> createState() => _RepartidorPlusScreenState();
}

class _RepartidorPlusScreenState extends State<RepartidorPlusScreen>
    with TickerProviderStateMixin {
  static const Color _bg      = Color(0xFFFF5722);
  static const Color _card    = Color(0xFFE64A19);
  static const Color _blue    = Color(0xFF27AEEB);
  static const Color _blueLight = Color(0xFF60A5FA);
  static const Color _gold    = Color(0xFFFFD700);
  static const Color _yellow  = Color(0xFFFFEB3B);

  // Datos del rider
  String _nombre = 'Repartidor';
  String? _avatarUrl;
  String _phone = '';
  int    _coins        = 0;
  int    _repartos     = 0;
  double _dinero       = 0;
  double _porcentaje   = 15.4;
  int    _nivel        = 1;
  int    _nivelProgress = 40;
  int    _nivelTotal   = 100;

  // Gasolina y km
  double _precioGas      = 23.50; // default, se actualiza con CRE
  double _rendimiento    = 40.0;  // km por litro, editable en perfil
  double _kmHoy          = 0.0;
  Position? _lastPos;
  StreamSubscription<Position>? _gpsSub;

  double get _costoGasHoy => _rendimiento > 0 ? (_kmHoy / _rendimiento) * _precioGas : 0;
  double get _gananciaNeta => _dinero - _costoGasHoy;

  late AnimationController _revealController;
  late AnimationController _flipController;
  late Animation<double> _flipAnim;
  late AnimationController _logroController;
  late Animation<Offset> _logroSlide;
  Map<String, dynamic>? _logroActivo;
  Timer? _logroTimer;

  static const _logros = [
    {'repartos': 1,  'emoji': '🚀', 'titulo': '¡Primer Paso!',     'desc': 'Completaste tu primer reparto'},
    {'repartos': 3,  'emoji': '🔥', 'titulo': '¡En Racha!',        'desc': '3 repartos completados'},
    {'repartos': 5,  'emoji': '⚡', 'titulo': '¡Velocista!',        'desc': '5 repartos — vas volando'},
    {'repartos': 10, 'emoji': '🏆', 'titulo': '¡Veterano!',        'desc': '10 repartos en tu historial'},
    {'repartos': 25, 'emoji': '👑', 'titulo': '¡Leyenda!',         'desc': '25 repartos — eres élite'},
    {'repartos': 50, 'emoji': '💎', 'titulo': '¡Diamante!',        'desc': '50 repartos completados'},
  ];

  // Pedidos
  List<Map<String, dynamic>> _pedidosPendientes = [];
  final Set<String> _rechazadosIds  = {};
  final Set<String> _aceptandoIds   = {};
  Timer? _orderTimer;

  bool _statsExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _fetchGasPrice();
    if (!kIsWeb) _startGPS();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..addListener(() => setState(() {}));
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _flipAnim = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
    _logroController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _logroSlide = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _logroController, curve: Curves.elasticOut));
    _loadOrders();
    _orderTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadOrders());
  }

  @override
  void dispose() {
    _revealController.dispose();
    _flipController.dispose();
    _logroController.dispose();
    _logroTimer?.cancel();
    _gpsSub?.cancel();
    _orderTimer?.cancel();
    super.dispose();
  }

  void _checkLogros(int prevRepartos) {
    for (final logro in _logros) {
      final threshold = logro['repartos'] as int;
      if (prevRepartos < threshold && _repartos >= threshold) {
        _mostrarLogro(logro);
        break;
      }
    }
  }

  void _mostrarLogro(Map<String, dynamic> logro) {
    _logroTimer?.cancel();
    setState(() => _logroActivo = logro);
    _logroController.forward(from: 0);
    _logroTimer = Timer(const Duration(seconds: 4), () {
      _logroController.reverse().then((_) {
        if (mounted) setState(() => _logroActivo = null);
      });
    });
  }

  Future<void> _loadOrders() async {
    try {
      final data = await SupabaseService.getOrdersForRepartidor();
      if (!mounted) return;
      final pendientes = data
          .where((o) =>
              o['status'] == 'pending' && !_rechazadosIds.contains(o['id'] as String))
          .toList();
      setState(() => _pedidosPendientes = pendientes);
    } catch (_) {}
  }

  Future<void> _aceptarPedido(String orderId) async {
    if (_aceptandoIds.contains(orderId)) return;
    _aceptandoIds.add(orderId);
    try {
      final pedido = _pedidosPendientes.firstWhere((o) => o['id'] == orderId);
      final total  = (pedido['total'] as num?)?.toDouble() ?? 0.0;
      await SupabaseService.updateOrderStatus(orderId, 'accepted');
      final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
      if (uid.isNotEmpty) {
        await SupabaseService.incrementRiderStats(
          uid,
          coinsAdd:    500,
          repartosAdd: 1,
          dineroAdd:   total,
        );
        final prev = _repartos;
        setState(() {
          _coins    += 500;
          _repartos += 1;
          _dinero   += total;
        });
        _checkLogros(prev);
      }
      setState(() => _pedidosPendientes.removeWhere((o) => o['id'] == orderId));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Error al aceptar el pedido. Intenta de nuevo.'),
          backgroundColor: Color(0xFFE53935),
          duration: Duration(seconds: 3),
        ));
      }
    } finally {
      _aceptandoIds.remove(orderId);
    }
  }

  void _rechazarPedido(String orderId) {
    setState(() {
      _rechazadosIds.add(orderId);
      _pedidosPendientes.removeWhere((o) => o['id'] == orderId);
    });
  }

  // Extrae un campo de texto; si el valor es JSON, busca la clave indicada.
  String _safeField(dynamic val, String jsonKey) {
    if (val == null) return '';
    final s = val.toString().trim();
    if (s.startsWith('{')) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        return m[jsonKey] as String? ?? m['name'] as String? ?? s;
      } catch (_) {}
    }
    return s;
  }

  Future<void> _fetchGasPrice() async {
    try {
      final res = await http.get(
        Uri.parse('https://publicacionexterna.azurewebsites.net/publicaciones/prices'),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final matches = RegExp(r'type="regular">(\d+\.?\d*)<').allMatches(res.body);
        final prices = matches
            .map((m) => double.tryParse(m.group(1)!) ?? 0.0)
            .where((p) => p > 15 && p < 40)
            .toList();
        if (prices.isNotEmpty && mounted) {
          final avg = prices.reduce((a, b) => a + b) / prices.length;
          setState(() => _precioGas = double.parse(avg.toStringAsFixed(2)));
        }
      }
    } catch (_) {} // queda el default $23.50
  }

  Future<void> _startGPS() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm != LocationPermission.whileInUse && perm != LocationPermission.always) return;
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen((pos) {
      if (_lastPos != null && mounted) {
        final dist = Geolocator.distanceBetween(
          _lastPos!.latitude, _lastPos!.longitude,
          pos.latitude, pos.longitude,
        ) / 1000;
        setState(() => _kmHoy += dist);
      }
      _lastPos = pos;
    });
  }

  void _toggleFlip() {
    if (_flipController.isCompleted) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
  }

  void _loadUser() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final meta = user.userMetadata;
    setState(() {
      _nombre      = (meta?['name'] as String?) ?? user.email?.split('@').first ?? 'Rider';
      _avatarUrl   = meta?['avatar_url'] as String?;
      _phone       = (meta?['phone'] as String?) ?? '';
      _rendimiento = (meta?['rendimiento'] as num?)?.toDouble() ?? 40.0;
    });
    _loadStats(user.id);
  }

  Future<void> _loadStats(String uid) async {
    final stats = await SupabaseService.getRiderStats(uid);
    if (!mounted || stats.isEmpty) return;
    setState(() {
      _coins          = (stats['coins']          as int?)    ?? _coins;
      _repartos       = (stats['repartos']        as int?)    ?? _repartos;
      _dinero         = (stats['dinero']          as num?)?.toDouble() ?? _dinero;
      _nivel          = (stats['nivel']           as int?)    ?? _nivel;
      _nivelProgress  = (stats['nivel_progress']  as int?)    ?? _nivelProgress;
    });
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: kIsWeb ? ImageSource.gallery : ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return;

    try {
      final bytes = await picked.readAsBytes();
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final path = 'avatars/$userId.jpg';

      await Supabase.instance.client.storage
          .from('rider-avatars')
          .uploadBinary(path, bytes,
              fileOptions: const FileOptions(
                  contentType: 'image/jpeg', upsert: true));

      final url = Supabase.instance.client.storage
          .from('rider-avatars')
          .getPublicUrl(path);

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {'avatar_url': url}),
      );
      if (mounted) setState(() => _avatarUrl = '$url?t=${DateTime.now().millisecondsSinceEpoch}');
    } catch (_) {}
  }

  Future<void> _saveProfile(String nombre, String phone) async {
    await Supabase.instance.client.auth.updateUser(
      UserAttributes(data: {'name': nombre, 'phone': phone, 'rendimiento': _rendimiento}),
    );
    if (mounted) setState(() { _nombre = nombre; _phone = phone; });
  }

  void _showProfileSheet() {
    final nameCtrl  = TextEditingController(text: _nombre);
    final phoneCtrl = TextEditingController(text: _phone);
    final rendCtrl  = TextEditingController(text: _rendimiento.toStringAsFixed(0));
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFBF360C),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.white38,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),
              const Text('Mi perfil',
                  style: TextStyle(color: Colors.white,
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),

              // Avatar con overlay de cámara
              GestureDetector(
                onTap: () async {
                  Navigator.pop(ctx);
                  await _pickAvatar();
                  if (mounted) _showProfileSheet();
                },
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: Colors.orange.shade900,
                      backgroundImage: _avatarUrl != null
                          ? NetworkImage(_avatarUrl!) : null,
                      child: _avatarUrl == null
                          ? const Icon(Icons.person, size: 48, color: Colors.white)
                          : null,
                    ),
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: _gold,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFBF360C), width: 2),
                        ),
                        child: const Icon(Icons.camera_alt_rounded,
                            size: 16, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text('Toca la foto para cambiarla',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 24),

              // Nombre
              _sheetField(
                controller: nameCtrl,
                label: 'Nombre completo',
                icon: Icons.person_outline,
              ),
              const SizedBox(height: 14),

              // Teléfono
              _sheetField(
                controller: phoneCtrl,
                label: 'Teléfono',
                icon: Icons.phone_outlined,
                type: TextInputType.phone,
              ),
              const SizedBox(height: 14),

              // Rendimiento moto
              _sheetField(
                controller: rendCtrl,
                label: 'Rendimiento moto (km/L)',
                icon: Icons.local_gas_station_outlined,
                type: TextInputType.number,
              ),
              const SizedBox(height: 24),

              // Guardar
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: saving ? null : () async {
                    setS(() => saving = true);
                    final rend = double.tryParse(rendCtrl.text.trim());
                    if (rend != null && rend > 0 && mounted) {
                      setState(() => _rendimiento = rend);
                    }
                    await _saveProfile(
                        nameCtrl.text.trim(), phoneCtrl.text.trim());
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: saving
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.black54, strokeWidth: 2.5))
                      : const Text('GUARDAR CAMBIOS',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? type,
  }) {
    return TextField(
      controller: controller,
      keyboardType: type,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        prefixIcon: Icon(icon, color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white54, width: 1.5)),
      ),
    );
  }

  Future<void> _logout() async {
    await AuthService.clearSession();
    if (mounted) context.go('/login');
  }

  String _formatNum(num n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(0)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toStringAsFixed(0);
  }

  String _formatMoney(double n) {
    final s = n.toStringAsFixed(0);
    final result = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) result.write(',');
      result.write(s[i]);
    }
    return result.toString();
  }

  Widget _buildLogroBanner() {
    final logro = _logroActivo;
    if (logro == null) return const SizedBox.shrink();
    return Positioned(
      top: 20,
      left: 20,
      right: 20,
      child: SlideTransition(
        position: _logroSlide,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _gold.withValues(alpha: 0.6), width: 1.5),
              boxShadow: [
                BoxShadow(color: _gold.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 2),
              ],
            ),
            child: Row(children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: _gold.withValues(alpha: 0.5)),
                ),
                child: Center(
                  child: Text(logro['emoji'] as String,
                      style: const TextStyle(fontSize: 26)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('¡LOGRO DESBLOQUEADO!',
                      style: TextStyle(color: _gold, fontSize: 10,
                          fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 3),
                  Text(logro['titulo'] as String,
                      style: const TextStyle(color: Colors.white,
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(logro['desc'] as String,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 12)),
                ],
              )),
              const SizedBox(width: 8),
              Icon(Icons.workspace_premium_rounded, color: _gold, size: 28),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
        child: ListView(
          children: [
            // ── Card naranja con esquinas redondeadas abajo ───────────────
            Container(
              decoration: const BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 18),
                  _buildStatsCard(),
                  const SizedBox(height: 14),
                  _buildBanner(),
                  const SizedBox(height: 16),
                  // Toggle stats
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _statsExpanded = !_statsExpanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Container(
                          width: 28, height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white38,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _statsExpanded ? 'Ocultar estadísticas' : 'Ver estadísticas',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const Spacer(),
                        Icon(
                          _statsExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: Colors.white70, size: 20,
                        ),
                      ]),
                    ),
                  ),
                  if (_statsExpanded) ...[
                    const SizedBox(height: 10),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: _buildHeatmap()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildDonut(5000000, 'AL NIVEL', _blueLight, 0.70)),
                    ]),
                    const SizedBox(height: 12),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: _buildNivelCard()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildDonut(3000000, '55,844 PX', _yellow, 0.55)),
                    ]),
                  ],
                ],
              ),
            ),
            // ── Pedidos sobre fondo negro ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _pedidosPendientes.isEmpty
                        ? 'Esperando pedidos...'
                        : 'Pedidos disponibles (${_pedidosPendientes.length})',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        letterSpacing: 0.3),
                  ),
                  const SizedBox(height: 12),
                  if (_pedidosPendientes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white24,
                          ),
                        ),
                      ),
                    )
                  else
                    ..._pedidosPendientes.map((p) => _buildOrderCard(p)),
                ],
              ),
            ),
          ],
        ),
      ),
        ),
        _buildLogroBanner(),
      ],
    );
  }

  Widget _buildHeader() {
    final nombreCapital = _nombre.isNotEmpty
        ? _nombre[0].toUpperCase() + _nombre.substring(1)
        : _nombre;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Fila superior: espaciador + botones
        Row(
          children: [
            const Spacer(),
            GestureDetector(
              onTap: () => context.push('/tienda-rider', extra: _coins),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.storefront_rounded,
                    color: Colors.white70, size: 18),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _logout,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.logout_rounded,
                    color: Colors.white70, size: 18),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Fila inferior: avatar+nombre izq, coins der
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _showProfileSheet,
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.orange.shade900,
                    backgroundImage: _avatarUrl != null
                        ? NetworkImage(_avatarUrl!) : null,
                    child: _avatarUrl == null
                        ? const Icon(Icons.person, size: 40, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
                Text('Hola $nombreCapital',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                const Text('Maravatío, Mich.',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Coins',
                    style: TextStyle(color: Colors.white70, fontSize: 11)),
                Row(children: [
                  Text(
                    _formatMoney(_coins.toDouble()),
                    style: const TextStyle(
                        color: _gold, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 4),
                  const Text('🪙', style: TextStyle(fontSize: 14)),
                ]),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatsCard() {
    return AnimatedBuilder(
      animation: _flipAnim,
      builder: (context, _) {
        final angle = _flipAnim.value * pi;
        final isFront = angle < pi / 2;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle),
          child: isFront
              ? _statsCardFront()
              : Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(pi),
                  child: _statsCardBack(),
                ),
        );
      },
    );
  }

  void _showRetos() {
    const orange = _bg;
    final retos = [
      {'titulo': '5 entregas hoy',        'desc': 'Completa 5 pedidos en un día',          'progreso': 3, 'meta': 5,   'reward': 200, 'icon': Icons.delivery_dining_rounded},
      {'titulo': 'Velocista',             'desc': 'Entrega en menos de 20 min (3 veces)',  'progreso': 1, 'meta': 3,   'reward': 350, 'icon': Icons.timer_rounded},
      {'titulo': 'Semana perfecta',       'desc': 'Trabaja los 7 días de la semana',       'progreso': 4, 'meta': 7,   'reward': 800, 'icon': Icons.calendar_month_rounded},
      {'titulo': 'Gana \$500 hoy',        'desc': 'Acumula \$500 en ganancias del día',    'progreso': 0, 'meta': 500, 'reward': 500, 'icon': Icons.attach_money_rounded, 'esDinero': true},
      {'titulo': 'Sube de nivel',         'desc': 'Llega al nivel 2 esta semana',          'progreso': 40,'meta': 100, 'reward': 1000,'icon': Icons.trending_up_rounded},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: ctrl,
            padding: const EdgeInsets.all(20),
            children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 18),
              Row(children: [
                Container(padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.sports_esports_rounded, color: orange, size: 22)),
                const SizedBox(width: 12),
                const Text('Retos activos', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                    child: const Text('Esta semana', style: TextStyle(color: orange, fontSize: 12, fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 6),
              Text('Completa retos para ganar coins extra', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13)),
              const SizedBox(height: 20),
              ...retos.map((r) {
                final prog  = (r['progreso'] as int).toDouble();
                final meta  = (r['meta'] as int).toDouble();
                final frac  = (prog / meta).clamp(0.0, 1.0);
                final listo = frac >= 1.0;
                final esDinero = r['esDinero'] == true;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: listo ? orange.withValues(alpha: 0.12) : const Color(0xFF242424),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: listo ? orange.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(r['icon'] as IconData, color: listo ? orange : Colors.white54, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(r['titulo'] as String,
                          style: TextStyle(color: listo ? orange : Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: listo ? orange : const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Text('🪙', style: TextStyle(fontSize: 12)),
                            const SizedBox(width: 3),
                            Text('+${r['reward']}', style: TextStyle(
                                color: listo ? Colors.white : Colors.white60, fontSize: 12, fontWeight: FontWeight.bold)),
                          ])),
                    ]),
                    const SizedBox(height: 6),
                    Text(r['desc'] as String, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: frac,
                        minHeight: 6,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation<Color>(listo ? orange : _blueLight),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(
                        esDinero ? '\$${prog.toStringAsFixed(0)} / \$${meta.toStringAsFixed(0)}' : '${prog.toInt()} / ${meta.toInt()}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                      ),
                      if (listo)
                        const Text('¡Listo! Reclamar', style: TextStyle(color: orange, fontSize: 11, fontWeight: FontWeight.bold)),
                    ]),
                  ]),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showRetiros() {
    const orange = _bg;
    final historial = [
      {'fecha': '28 Jun 2026', 'monto': 850.0,  'estado': 'Depositado', 'metodo': 'BBVA *4821'},
      {'fecha': '21 Jun 2026', 'monto': 1200.0, 'estado': 'Depositado', 'metodo': 'BBVA *4821'},
      {'fecha': '14 Jun 2026', 'monto': 950.0,  'estado': 'Depositado', 'metodo': 'BBVA *4821'},
      {'fecha': '7 Jun 2026',  'monto': 700.0,  'estado': 'Depositado', 'metodo': 'OXXO Pay'},
    ];
    final saldoDisponible = _dinero;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: ctrl,
            padding: const EdgeInsets.all(20),
            children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 18),
              Row(children: [
                Container(padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.account_balance_wallet_rounded, color: orange, size: 22)),
                const SizedBox(width: 12),
                const Text('Retiros', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 20),
              // Saldo disponible
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [orange, _card], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Saldo disponible', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
                  const SizedBox(height: 6),
                  Text('\$${saldoDisponible.toStringAsFixed(0)} MXN',
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Retiro solicitado — se procesará en 1-2 días hábiles'),
                          backgroundColor: Color(0xFF22C55E),
                          duration: Duration(seconds: 4),
                        ));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: orange,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Solicitar retiro', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              Text('Mínimo de retiro: \$200 MXN · Procesado en 1-2 días hábiles',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              const Text('Historial', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 12),
              ...historial.map((h) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF242424),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded, color: Color(0xFF22C55E), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(h['metodo'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(h['fecha'] as String, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('-\$${(h['monto'] as double).toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(h['estado'] as String, style: const TextStyle(color: Color(0xFF22C55E), fontSize: 11)),
                  ]),
                ]),
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statsCardFront() {
    return GestureDetector(
      onTap: _toggleFlip,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        decoration: BoxDecoration(
          color: _blue,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(children: [
          Row(children: [
            Expanded(
              flex: 2,
              child: Column(children: [
                Text('$_repartos',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 38, fontWeight: FontWeight.w900)),
                const Text('Repartos',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
            Container(width: 1, height: 55, color: Colors.white24),
            Expanded(
              flex: 3,
              child: Column(children: [
                Text('+${_porcentaje.toStringAsFixed(1)}%',
                    style: const TextStyle(
                        color: _gold, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('\$${_formatMoney(_dinero)} mxm',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
                const Text('Dinero acumulado',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          // Ganancia neta del día
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              // km recorridos
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_kmHoy.toStringAsFixed(1)} km',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                const Text('Hoy', style: TextStyle(color: Colors.white54, fontSize: 10)),
              ]),
              const SizedBox(width: 10),
              Container(width: 1, height: 30, color: Colors.white24),
              const SizedBox(width: 10),
              // Costo gasolina
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('-\$${_costoGasHoy.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 15, fontWeight: FontWeight.bold)),
                Text('Gas \$${_precioGas.toStringAsFixed(2)}/L',
                    style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ]),
              const Spacer(),
              // Ganancia neta
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('\$${_gananciaNeta.toStringAsFixed(0)} neta',
                    style: const TextStyle(
                        color: _gold, fontSize: 17, fontWeight: FontWeight.w900)),
                const Text('después de gas',
                    style: TextStyle(color: Colors.white54, fontSize: 10)),
              ]),
            ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: _showRetos,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.sports_esports_rounded, color: _bg, size: 17),
                    SizedBox(width: 6),
                    Text('RETOS',
                        style: TextStyle(
                            color: _bg, fontWeight: FontWeight.bold,
                            fontSize: 12, letterSpacing: 0.8)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: _showRetiros,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                      color: _bg, borderRadius: BorderRadius.circular(20)),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 17),
                    SizedBox(width: 6),
                    Text('RETIROS',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold,
                            fontSize: 12, letterSpacing: 0.8)),
                  ]),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _statsCardBack() {
    final nombreCapital = _nombre.isNotEmpty
        ? _nombre[0].toUpperCase() + _nombre.substring(1)
        : _nombre;
    return GestureDetector(
      onTap: _toggleFlip,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _blue,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(children: [
          // Avatar
          CircleAvatar(
            radius: 38,
            backgroundColor: Colors.white24,
            backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
            child: _avatarUrl == null
                ? const Icon(Icons.person, size: 38, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('\$${_formatMoney(_dinero)} mxm',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('${_formatMoney(_coins.toDouble())} Coin 🪙',
                    style: const TextStyle(color: _gold, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${_formatNum(_nivelProgress * 1000)} PX',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 6),
                Text('Jugador  $nombreCapital',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Nivel
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded, color: _yellow, size: 42),
              Text('Nivel $_nivel',
                  style: const TextStyle(
                      color: _yellow, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _buildBanner() {
    final revealed = _revealController.value;
    return SizedBox(
      height: 140,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth;
            return Stack(
              fit: StackFit.expand,
              children: [
                // Fondo: RETOS siempre atrás
                Row(children: [
                  Container(
                    width: 110,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF6D28D9), Color(0xFF4C1D95)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Center(
                        child: Text('🏆', style: TextStyle(fontSize: 52))),
                  ),
                  const Expanded(
                    child: ColoredBox(
                      color: _card,
                      child: Center(
                        child: Text('RETOS',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 3)),
                      ),
                    ),
                  ),
                ]),
                // Cortina: imagen del rider — draggable hacia la izquierda
                GestureDetector(
                  onHorizontalDragUpdate: (d) {
                    final newVal = (_revealController.value - d.delta.dx / cardWidth)
                        .clamp(0.0, 1.0);
                    _revealController.value = newVal;
                  },
                  onHorizontalDragEnd: (d) {
                    final vel = d.primaryVelocity ?? 0;
                    double target;
                    if (vel < -400) {
                      target = 1.0;
                    } else if (vel > 400) {
                      target = 0.0;
                    } else {
                      target = _revealController.value >= 0.5 ? 1.0 : 0.0;
                    }
                    _revealController.animateTo(target, curve: Curves.easeOut);
                  },
                  child: Transform.translate(
                    offset: Offset(-cardWidth * revealed, 0),
                    child: Image.asset(
                      'assets/images/banner_rider.png',
                      fit: BoxFit.cover,
                      width: cardWidth,
                      height: double.infinity,
                    ),
                  ),
                ),
                // Botón tap — abre o cierra completo
                Positioned(
                  right: 10, top: 8, bottom: 8,
                  child: GestureDetector(
                    onTap: () {
                      final target = revealed >= 0.5 ? 0.0 : 1.0;
                      _revealController.animateTo(target, curve: Curves.easeOut);
                    },
                    child: Container(
                      width: 36,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Center(
                        child: Icon(
                          revealed >= 0.5
                              ? Icons.keyboard_double_arrow_left_rounded
                              : Icons.keyboard_double_arrow_right_rounded,
                          color: _bg,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeatmap() {
    final rng = Random(42);
    const blues = [
      Color(0xFF7C3AED),
      Color(0xFF1D4ED8),
      Color(0xFF60A5FA),
      Color(0xFF93C5FD),
    ];
    const cols = 9;
    const rows = 7;
    const gap  = 3.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Frecuencia',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (_, constraints) {
            final cell = (constraints.maxWidth - gap * (cols - 1)) / cols;
            return Column(
              children: List.generate(rows, (row) => Padding(
                padding: const EdgeInsets.only(bottom: gap),
                child: Row(
                  children: List.generate(cols, (col) {
                    final v = rng.nextInt(4);
                    return Container(
                      margin: col < cols - 1
                          ? const EdgeInsets.only(right: gap)
                          : null,
                      width: cell, height: cell,
                      decoration: BoxDecoration(
                        color: blues[v],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              )),
            );
          }),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('—', style: TextStyle(color: Colors.white54, fontSize: 9)),
              const SizedBox(width: 4),
              ...blues.map((c) => Container(
                margin: const EdgeInsets.only(right: 3),
                width: 10, height: 10,
                decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
              )),
              const SizedBox(width: 4),
              const Text('+', style: TextStyle(color: Colors.white54, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDonut(double value, String subtitle, Color color, double progress) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Puntos',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 12),
          Center(
            child: SizedBox(
              width: 90, height: 90,
              child: CustomPaint(
                painter: _DonutPainter(progress: progress, color: color),
                child: Center(
                  child: Text(
                    _formatNum(value),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(subtitle,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildNivelCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.star_rounded, color: _gold, size: 38),
              Positioned(
                top: -4, right: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF7C2D12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$_nivel',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$_nivelProgress/$_nivelTotal',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _nivelProgress / _nivelTotal,
              backgroundColor: Colors.orange.shade900,
              valueColor: const AlwaysStoppedAnimation<Color>(_gold),
              minHeight: 9,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$_nivelProgress/$_nivelTotal',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> pedido) {
    final orderId     = pedido['id'] as String;
    final restaurante = (pedido['restaurants'] as Map?)?['name'] as String? ?? 'Restaurante';
    final total       = (pedido['total'] as num?)?.toDouble() ?? 0.0;
    final cliente     = _safeField(pedido['customer_name'], 'name');
    final direccion   = _safeField(pedido['address'], 'address');
    final items       = (pedido['order_items'] as List?)?.length ?? 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFF7043),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: _bg.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.fastfood_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(restaurante,
                            style: const TextStyle(color: Colors.white,
                                fontWeight: FontWeight.bold, fontSize: 14),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Text('\$${total.toStringAsFixed(0)} MXN',
                          style: const TextStyle(color: Colors.white,
                              fontWeight: FontWeight.bold, fontSize: 13)),
                    ]),
                    const SizedBox(height: 2),
                    Text('$items producto${items == 1 ? '' : 's'}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12)),
                    if (direccion.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        Icon(Icons.location_on_outlined,
                            color: Colors.white.withValues(alpha: 0.75), size: 13),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(direccion,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    ],
                    if (cliente.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(children: [
                        Icon(Icons.person_outline_rounded,
                            color: Colors.white.withValues(alpha: 0.75), size: 13),
                        const SizedBox(width: 4),
                        Text(cliente,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
                      ]),
                    ],
                  ],
                )),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.3)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _rechazarPedido(orderId),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53935),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.close_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 5),
                      Text('RECHAZAR', style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.4)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: () => _aceptarPedido(orderId),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _bg),
                    ),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.check_rounded, color: _bg, size: 18),
                      SizedBox(width: 5),
                      Text('ACEPTAR PEDIDO', style: TextStyle(color: _bg,
                          fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.4)),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

}

class _DonutPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _DonutPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 11.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (min(size.width, size.height) - strokeWidth) / 2;

    canvas.drawCircle(
      center, radius,
      Paint()
        ..color = Colors.white12
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.progress != progress || old.color != color;
}
