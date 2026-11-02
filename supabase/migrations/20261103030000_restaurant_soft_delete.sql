-- Bloque 4, punto 21: deleteRestaurant() ya no borra filas (ver
-- supabase_service.dart) — desactiva el restaurante con
-- approval_status='eliminado' en vez de borrar la fila, para no perder el
-- historial de productos/pedidos/calificaciones. Hace falta permitir este
-- nuevo valor en el check existente.
alter table public.restaurants
  drop constraint if exists restaurants_approval_status_check;
alter table public.restaurants
  add constraint restaurants_approval_status_check
  check (approval_status in ('pendiente', 'en_revision', 'correcciones_solicitadas', 'aprobado', 'rechazado', 'eliminado'));
