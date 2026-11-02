-- Bloque 4, punto 20: broadcastRiderPresence hace un upsert sobre
-- rider_locations, pero solo había política de SELECT para admin/jefe de
-- flota — el propio rider nunca podía leer su fila. La primera vez
-- funcionaba (la fila no existía todavía, era un INSERT puro); de ahí en
-- adelante el upsert fallaba en silencio (el error se traga en un
-- try/catch) porque el UPDATE necesita poder leer de vuelta la fila para
-- regresarla, y esa lectura no estaba permitida.
create policy "read_own_rider_location" on public.rider_locations
  for select using (rider_id = auth.uid());
