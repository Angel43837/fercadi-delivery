// welcome_screen.dart
// Pantalla de bienvenida que se muestra ANTES del login, cuando no hay
// sesión activa (ver splash_screen.dart). Ofrece 3 caminos:
//   - "Inicio de sesión" -> /login (formulario normal)
//   - "Invitado"          -> /restaurants directo, sin cuenta (el modo
//                            invitado ya existe a nivel de router — ver
//                            _guestBrowsable en router.dart — esta pantalla
//                            solo agrega la puerta de entrada directa)
//   - "Crear cuenta"       -> /login en modo registro (LoginScreen ya
//                            soporta esto vía startInSignUp)
//
// La curva y la foto (assets/images/welcome_bg.jpg) vienen del diseño real
// ("Rectangle 93.svg", exportado de Figma) — la foto estaba embebida como
// base64 dentro del propio SVG, y el trazo de la curva es el mismo path
// que trae ese archivo, solo escalado al tamaño real de pantalla (el
// diseño usa un lienzo de referencia de 380×911).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/constants.dart';

// Medidas exactas del diseño (lienzo de referencia 380×911), convertidas a
// fracción del ancho/alto real para que se vea igual en cualquier pantalla.
const double _bgLeftFrac   = -120 / 380;
const double _bgWidthFrac  = 499.3941345214844 / 380;

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: AppConstants.primaryColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Foto real recortada con la forma exacta del diseño
          ClipPath(
            clipper: _BlobClipper(),
            child: Stack(children: [
              Positioned(
                left: size.width * _bgLeftFrac,
                top: 0,
                width: size.width * _bgWidthFrac,
                height: size.height,
                child: Image.asset('assets/images/welcome_bg.jpg', fit: BoxFit.cover),
              ),
            ]),
          ),
          // Contenido: logo apilado + botones
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(flex: 3),
                  // Logo apilado: 137×158, recorrido un poco hacia abajo y
                  // a la derecha (a pedido del dueño, viendo la pantalla real).
                  Transform.translate(
                    offset: const Offset(75, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Image.asset('assets/images/gogofood_go1.png', height: 62),
                        const SizedBox(height: 2),
                        Image.asset('assets/images/gogofood_go2.png', height: 62),
                        const SizedBox(height: 6),
                        Image.asset('assets/images/gogofood_word.png', height: 26),
                      ],
                    ),
                  ),
                  const Spacer(flex: 4),
                  _WelcomeButton(
                    label: 'INICIO DE SESIÓN',
                    backgroundColor: const Color(0xFF0CB6F4),
                    textColor: Colors.white,
                    insetColor: Colors.black,
                    insetAlpha: 0x3D / 255,
                    onTap: () => context.push('/login'),
                  ),
                  const SizedBox(height: 9),
                  _WelcomeButton(
                    label: 'INVITADO',
                    backgroundColor: Colors.white,
                    textColor: AppConstants.primaryColor,
                    onTap: () => context.go('/restaurants'),
                  ),
                  const SizedBox(height: 8),
                  _WelcomeButton(
                    label: 'CREAR CUENTA',
                    backgroundColor: const Color(0xFFFF4C00),
                    textColor: Colors.white,
                    insetColor: const Color(0xFFDA3A00),
                    insetAlpha: 0.55,
                    onTap: () => context.push('/login', extra: {'signUp': true}),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Botón de la contrabarda: 388×62, radio 24, sombra exterior
// 0px 1px 3.8px 1px #0000006E en los 3, y opcionalmente un brillo
// interior (inset) aproximado con un degradado de arriba hacia abajo
// (Flutter no tiene box-shadow inset nativo).
class _WelcomeButton extends StatelessWidget {
  const _WelcomeButton({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    required this.onTap,
    this.insetColor,
    this.insetAlpha = 0,
  });

  final String label;
  final Color backgroundColor;
  final Color textColor;
  final VoidCallback onTap;
  final Color? insetColor;
  final double insetAlpha;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 62,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0x6E / 255),
              offset: const Offset(0, 1),
              blurRadius: 3.8,
              spreadRadius: 1,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (insetColor != null)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        insetColor!.withValues(alpha: insetAlpha),
                        insetColor!.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.75],
                    ),
                  ),
                ),
              ),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Forma exacta ("blob") del archivo de diseño Rectangle 93.svg, escalada
// del lienzo de referencia (380×911) al tamaño real de la pantalla.
class _BlobClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final sx = size.width / 380;
    final sy = size.height / 911;
    Offset p(double x, double y) => Offset(x * sx, y * sy);

    final path = Path()
      ..moveTo(p(-14.2228, 0).dx, p(-14.2228, 0).dy)
      ..lineTo(p(323.5, 0).dx, p(323.5, 0).dy)
      ..cubicTo(
        p(323.5, 0).dx, p(323.5, 0).dy,
        p(-56.2955, 376.909).dx, p(-56.2955, 376.909).dy,
        p(255, 657).dx, p(255, 657).dy,
      )
      ..cubicTo(
        p(566.295, 937.091).dx, p(566.295, 937.091).dy,
        p(223.776, 1017.43).dx, p(223.776, 1017.43).dy,
        p(-14.2228, 733.571).dx, p(-14.2228, 733.571).dy,
      )
      ..cubicTo(
        p(-252.222, 449.707).dx, p(-252.222, 449.707).dy,
        p(-14.2228, 0).dx, p(-14.2228, 0).dy,
        p(-14.2228, 0).dx, p(-14.2228, 0).dy,
      )
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
