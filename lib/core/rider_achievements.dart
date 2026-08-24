// rider_achievements.dart
// Medallas por repartos completados — usadas en repartidor_plus_screen.dart
// (el rider las ve al desbloquearlas) y en tracking_screen.dart (el cliente
// las ve en el detalle de SU repartidor, calculadas con el mismo umbral).
class RiderAchievement {
  final int repartos;
  final String emoji;
  final String titulo;
  final String desc;

  const RiderAchievement({
    required this.repartos,
    required this.emoji,
    required this.titulo,
    required this.desc,
  });
}

const List<RiderAchievement> kRiderAchievements = [
  RiderAchievement(repartos: 1,  emoji: '🚀', titulo: '¡Primer Paso!', desc: 'Completó su primer reparto'),
  RiderAchievement(repartos: 3,  emoji: '🔥', titulo: '¡En Racha!',    desc: '3 repartos completados'),
  RiderAchievement(repartos: 5,  emoji: '⚡', titulo: '¡Velocista!',   desc: '5 repartos — va volando'),
  RiderAchievement(repartos: 10, emoji: '🏆', titulo: '¡Veterano!',    desc: '10 repartos en su historial'),
  RiderAchievement(repartos: 25, emoji: '👑', titulo: '¡Leyenda!',     desc: '25 repartos — es élite'),
  RiderAchievement(repartos: 50, emoji: '💎', titulo: '¡Diamante!',    desc: '50 repartos completados'),
];
