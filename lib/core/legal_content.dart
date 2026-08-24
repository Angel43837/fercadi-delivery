// legal_content.dart
// Texto completo del Aviso de Privacidad y los Términos y Condiciones.
// Centralizado aquí para poder actualizarlo sin tocar las pantallas que lo
// muestran. Cambia PRIVACY_CONTACT_EMAIL y LEGAL_BUSINESS_NAME por los datos
// reales del negocio en cuanto los tengan definidos.

const String kPrivacyContactEmail = 'privacidad@fercadi.com';
const String kLegalBusinessName = 'Grupo Fercadi';
const String kLegalCity = 'Maravatío, Michoacán';

const String kLastUpdatedLegal = 'Agosto de 2026';

const String kPrivacyPolicy = '''
AVISO DE PRIVACIDAD

Última actualización: $kLastUpdatedLegal

$kLegalBusinessName ("GOGO Food", "nosotros"), con domicilio en $kLegalCity, México, es responsable del tratamiento de tus datos personales conforme a la Ley Federal de Protección de Datos Personales en Posesión de los Particulares.

1. DATOS PERSONALES QUE RECABAMOS

Para poder ofrecerte el servicio de pedidos y entrega a domicilio, recabamos:

• Datos de identificación y contacto: nombre, correo electrónico, teléfono.
• Dirección de entrega y ubicación (GPS), para calcular la zona de cobertura y rastrear tu pedido en tiempo real.
• Fotografía de perfil, si decides subir una.
• Historial de pedidos: qué pediste, en qué restaurante, fecha y monto.
• Datos de pago: los procesa directamente nuestro proveedor de pagos (Stripe); nosotros no almacenamos el número completo de tu tarjeta.
• Si inicias sesión con Google o Facebook, recibimos tu nombre, correo y foto de perfil públicos de esas plataformas.

No recabamos datos personales sensibles (salud, origen étnico, creencias religiosas, etc.).

2. FINALIDADES DEL TRATAMIENTO

Finalidades necesarias para el servicio:
• Crear y administrar tu cuenta.
• Procesar, entregar y dar seguimiento a tus pedidos.
• Cobrar el importe de tus compras.
• Conectarte con el restaurante y el repartidor asignados a tu pedido (compartimos solo lo necesario: tu nombre, dirección de entrega y teléfono, y — una vez que un repartidor acepta tu pedido — su nombre y foto se muestran a ti y viceversa).
• Brindarte soporte cuando lo solicites.
• Enviarte notificaciones sobre el estado de tus pedidos.

Finalidades secundarias (puedes decirnos que no si no quieres):
• Enviarte promociones u ofertas de restaurantes participantes.
• Analizar el uso de la app para mejorarla.

Si no quieres que usemos tus datos para las finalidades secundarias, escríbenos a $kPrivacyContactEmail.

3. TRANSFERENCIA DE DATOS

Compartimos tus datos únicamente con:
• El restaurante donde haces tu pedido (para prepararlo).
• El repartidor asignado (para entregarlo).
• Nuestro proveedor de pagos (Stripe), para procesar el cobro.
• Nuestro proveedor de infraestructura y base de datos (Supabase), que almacena la información en nuestro nombre bajo un contrato de confidencialidad.
• Autoridades, cuando la ley nos obligue a ello.

No vendemos tus datos personales a terceros.

4. DERECHOS ARCO

Tienes derecho a Acceder, Rectificar, Cancelar u Oponerte (derechos ARCO) al tratamiento de tus datos personales, así como a revocar el consentimiento que nos hayas otorgado. Para ejercer cualquiera de estos derechos, escríbenos a $kPrivacyContactEmail indicando tu nombre completo y el correo con el que te registraste. Responderemos en un plazo máximo de 20 días hábiles.

También puedes eliminar tu cuenta y tus datos directamente desde la app, en la sección de tu perfil.

5. USO DE UBICACIÓN

La app solicita acceso a tu ubicación para: detectar tu zona de cobertura (Maravatío/Acámbaro) y, si eres repartidor, transmitir tu posición en tiempo real durante una entrega activa. Puedes desactivar el acceso a tu ubicación desde los ajustes de tu teléfono, aunque esto puede limitar funciones del servicio.

6. CAMBIOS A ESTE AVISO

Podemos actualizar este aviso de privacidad. Cualquier cambio se publicará dentro de la app con su fecha de actualización.
''';

const String kTermsAndConditions = '''
TÉRMINOS Y CONDICIONES DE USO

Última actualización: $kLastUpdatedLegal

Estos Términos y Condiciones regulan el uso de la aplicación GOGO Food, operada por $kLegalBusinessName. Al crear una cuenta o usar la app, aceptas estos términos.

1. DESCRIPCIÓN DEL SERVICIO

GOGO Food es una plataforma que conecta a clientes con restaurantes locales en $kLegalCity para la compra y entrega a domicilio de alimentos. Actuamos como intermediarios entre el cliente, el restaurante y el repartidor — no preparamos ni somos dueños de los alimentos que se ofrecen en la plataforma.

2. CUENTA DE USUARIO

Debes proporcionar información verdadera al registrarte y eres responsable de mantener la confidencialidad de tu contraseña. Debes tener al menos 18 años para registrarte, o contar con el consentimiento de un tutor.

3. PEDIDOS Y PAGOS

Al hacer un pedido te comprometes a pagar el precio mostrado más los cargos de envío aplicables. Los pagos se procesan a través de Stripe. Los precios y la disponibilidad de los platillos los define cada restaurante y pueden cambiar sin previo aviso.

4. CANCELACIONES Y REEMBOLSOS

Un pedido puede cancelarse solo antes de que el restaurante comience a prepararlo. Si hay un problema con tu pedido (faltante, error, calidad), contáctanos a través de la app para resolverlo caso por caso.

5. RESPONSABILIDAD DEL RESTAURANTE Y EL REPARTIDOR

La calidad, higiene y preparación de los alimentos es responsabilidad exclusiva del restaurante correspondiente. GOGO Food facilita la conexión y el pago, pero no garantiza la calidad de los productos ofrecidos por terceros.

6. CONDUCTA DEL USUARIO

No está permitido: usar la app para fines ilícitos, intentar acceder sin autorización a cuentas de otros usuarios, ni acosar o amenazar a restaurantes, repartidores u otros clientes a través de la plataforma.

7. CUENTAS DE REPARTIDOR Y RESTAURANTE

Los repartidores y dueños de restaurante que se registran en la plataforma aceptan además las condiciones específicas de su rol (comisiones, zonas de cobertura, retiros de saldo) que se les presentan al darse de alta.

8. LIMITACIÓN DE RESPONSABILIDAD

En la medida permitida por la ley, GOGO Food no será responsable por daños indirectos derivados del uso de la plataforma, retrasos de terceros (restaurantes, repartidores) o interrupciones del servicio por causas fuera de nuestro control.

9. MODIFICACIONES

Podemos modificar estos términos en cualquier momento; los cambios se publicarán dentro de la app con su fecha de actualización. El uso continuado de la app tras un cambio implica su aceptación.

10. LEY APLICABLE

Estos términos se rigen por las leyes de los Estados Unidos Mexicanos. Cualquier controversia se someterá a los tribunales competentes de Michoacán.

11. CONTACTO

Dudas sobre estos términos: $kPrivacyContactEmail
''';
