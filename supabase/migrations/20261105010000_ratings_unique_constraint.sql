-- Bloque 2, punto 5: nada impedía calificar el mismo pedido 2 veces —
-- ratings no tenía ninguna restricción sobre (order_id, is_driver), así que
-- cada vez que se reabría el diálogo de calificación (p. ej. el cliente
-- reintentando la propina después de cerrar y volver a entrar al pedido)
-- insertaba una fila nueva en vez de actualizar la misma.
alter table public.ratings
  add constraint ratings_order_driver_unique unique (order_id, is_driver);
