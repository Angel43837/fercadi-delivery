-- Registro de qué versión de los Términos y del Aviso de Privacidad aceptó
-- cada cuenta, y cuándo — hoy el checkbox de "Acepto los Términos..." en
-- login_screen.dart (alta de cliente) no deja ningún rastro real: no se
-- guarda qué versión del texto existía en ese momento ni la fecha exacta,
-- solo queda `accepted_terms_at` suelto en user_metadata (ver
-- login_screen.dart, Supabase.auth.signUp data) sin versión asociada.
-- Si el texto legal cambia después, no hay manera de saber qué aceptó
-- cada cuenta ni cuándo.
--
-- Deliberadamente SIN ningún candado que bloquee el alta si esto falla —
-- es un registro de cumplimiento, no un requisito para poder registrarse
-- (el checkbox en la UI ya es el candado real). Las inserciones las hace
-- el cliente (login_screen.dart) directo contra esta tabla, mejor
-- esfuerzo, después de que signUp() ya tuvo éxito.

begin;

create table public.legal_acceptances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id),
  document text not null check (document in ('terms', 'privacy')),
  version text not null,
  accepted_at timestamptz not null default now()
);

alter table public.legal_acceptances enable row level security;

-- El usuario solo puede registrar SU propia aceptación (no la de otra
-- cuenta) y solo puede ver la suya; Admin puede ver todas (auditoría de
-- cumplimiento real si algún día se necesita demostrar qué se aceptó).
create policy "insert_own_legal_acceptance" on public.legal_acceptances
  for insert with check (user_id = auth.uid());

create policy "select_own_legal_acceptance" on public.legal_acceptances
  for select using (user_id = auth.uid() or is_admin());

commit;
