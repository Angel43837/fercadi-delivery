import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ── Redes sociales oficiales de GOGO ────────────────────────────────────────
// ⚠️ PENDIENTE: confirmar las direcciones reales con el negocio. Estos son
// los únicos lugares donde se definen — cambiarlas aquí las cambia en toda
// la app. Un link dejado en '' oculta su icono sin tocar nada más.
const String kGogoFacebookUrl = 'https://www.facebook.com/gogofoodmx';
const String kGogoInstagramUrl = 'https://www.instagram.com/gogofoodmx';
const String kGogoTikTokUrl = 'https://www.tiktok.com/@gogofoodmx';

// Fila de iconos de redes sociales (perfil → "Síguenos"). Cada icono abre la
// página en la app o navegador correspondiente.
class SocialLinksRow extends StatelessWidget {
  const SocialLinksRow({super.key});

  Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el enlace')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final redes = <(String, IconData, Color, String)>[
      ('Facebook', FontAwesomeIcons.facebookF, const Color(0xFF1877F2), kGogoFacebookUrl),
      ('Instagram', FontAwesomeIcons.instagram, const Color(0xFFE4405F), kGogoInstagramUrl),
      ('TikTok', FontAwesomeIcons.tiktok, const Color(0xFF9E9E9E), kGogoTikTokUrl),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final (nombre, icono, color, url) in redes)
          if (url.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Material(
                color: color.withValues(alpha: 0.12),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _open(context, url),
                  child: Tooltip(
                    message: nombre,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: FaIcon(icono, color: color, size: 22),
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
