# Paso a producción — orden exacto para un solo día

Esto mueve todo el trabajo de seguridad/pagos de nov 2026 (ramas `fix/seguridad-dev` →
ya mezclada en `dev`) a la base real de GOGO Food (`dlukaxbcyetcdbdjjgct`) y al dinero
de verdad. **No hacer ningún paso de este documento sin decir "aplícalo" primero** —
hasta ahora todo se probó en modo ensayo (`begin`/`rollback`), nada se aplicó.

Estado verificado antes de escribir esto (nov 2026): producción tiene 18 pedidos reales,
2 restaurantes, 7 usuarios, 1 repartidor dado de alta por la web. Le faltan 15
migraciones y 2 Edge Functions (`create-tip-payment-intent`, `sweep-awaiting-payments`)
respecto a Pruebas — las 15 migraciones ya se probaron completas en modo ensayo contra
los datos reales de producción, **sin ningún error**.

---

## 1. Respaldo de la base

Antes de tocar nada:

```bash
export SUPABASE_ACCESS_TOKEN=<tu token>
supabase db dump --project-ref dlukaxbcyetcdbdjjgct -f respaldo_pre_produccion.sql
```

(Si `db dump` pide Docker y no lo tienes, usa el botón **"Download backup"** del
dashboard de Supabase: Project Settings → Database → Backups — Supabase ya hace
respaldos automáticos diarios, pero uno manual justo antes es más seguro.)

Guarda ese archivo fuera del repo (no se commitea — tendría datos reales de clientes).

## 2. Migraciones

```bash
cd fercadi-delivery
export SUPABASE_ACCESS_TOKEN=<tu token>
supabase link --project-ref dlukaxbcyetcdbdjjgct
supabase db push --linked
```

Esto aplica, en orden, las 15 migraciones faltantes (`20261103000000` en adelante). Ya
se probaron en modo ensayo sin errores — aun así, revisa la salida de cada una antes de
seguir al paso 3.

**Si algo falla aquí**: para — no sigas con los pasos de abajo. El error te va a decir
exactamente qué migración y por qué. Con los datos reales de producción el ensayo salió
limpio, así que un fallo en este paso significaría que algo cambió en producción entre
el ensayo y este momento (alguien insertó datos nuevos, por ejemplo) — revisa qué, y
si hace falta, para y pregúntame antes de seguir.

## 3. Secretos de Stripe y Vault

Estos NO van en ningún archivo — todo esto se corre a mano, en terminal o en el SQL
Editor del dashboard, con las llaves reales de producción a la vista solo tuya.

```bash
# Llave secreta de Stripe EN VIVO (no la de prueba) — dashboard.stripe.com, modo Live
supabase secrets set STRIPE_SECRET_KEY=sk_live_... --project-ref dlukaxbcyetcdbdjjgct
```

`STRIPE_WEBHOOK_SECRET` y el resto de los secretos de Supabase (`SUPABASE_*`) **ya
están configurados en producción** (confirmado al comparar contra Pruebas) — solo falta
confirmar que `STRIPE_WEBHOOK_SECRET` corresponda al webhook del **paso 5** de abajo
(si vas a crear un webhook nuevo, este valor cambia).

En el SQL Editor de producción (nunca en un archivo):

```sql
-- Guarda el service_role_key de PRODUCCIÓN (no el de Pruebas) para el cron de limpieza de pagos
select vault.create_secret(
  'TU_SERVICE_ROLE_KEY_DE_PRODUCCION',
  'gogo_service_role_key'
);
```

(La URL del cron ya va escrita literal en la migración — `ymztoayxzewghbethahv` en
Pruebas. **Ojo**: esa migración trae la URL de PRUEBAS escrita — antes de aplicarla en
producción, hay que cambiarla a `https://dlukaxbcyetcdbdjjgct.supabase.co` en una
migración nueva, igual que se hizo para Pruebas. Revisar esto ANTES del paso 2 si se
quiere automatizar — si no, el cron de producción le va a seguir pegando a Pruebas por
error.)

## 4. Desplegar las funciones faltantes

```bash
supabase functions deploy create-tip-payment-intent --project-ref dlukaxbcyetcdbdjjgct --use-api
supabase functions deploy sweep-awaiting-payments --project-ref dlukaxbcyetcdbdjjgct --use-api --no-verify-jwt
```

El resto de las funciones ya están desplegadas en producción — conviene de todos modos
re-desplegar las que se tocaron en esta ronda para que tengan el código más reciente:

```bash
supabase functions deploy create-payment-intent --project-ref dlukaxbcyetcdbdjjgct --use-api
supabase functions deploy reject-order --project-ref dlukaxbcyetcdbdjjgct --use-api
supabase functions deploy stripe-webhook --project-ref dlukaxbcyetcdbdjjgct --use-api --no-verify-jwt
supabase functions deploy delete-account --project-ref dlukaxbcyetcdbdjjgct --use-api
```

## 5. Webhook de Stripe en vivo

Producción ya tiene un webhook configurado (de julio 2026) — antes de asumir que sirve:

1. Entra a Stripe en **modo Live** (no Test) → Workbench → Destinos de eventos.
2. Busca si ya hay un destino apuntando a
   `https://dlukaxbcyetcdbdjjgct.supabase.co/functions/v1/stripe-webhook`.
3. Si existe y está en la MISMA cuenta de Stripe que vas a usar para cobrar de verdad
   (verifica el ID de cuenta, `acct_...`, contra el de tu `sk_live_...`), solo confirma
   que escuche los 6 eventos: `payment_intent.succeeded`, `payment_intent.payment_failed`,
   `payment_intent.canceled`, `customer.subscription.created/updated/deleted`.
4. Si no existe o es de otra cuenta, créalo igual que se hizo en Pruebas (ver CLAUDE.md,
   sección de Stripe) y actualiza `STRIPE_WEBHOOK_SECRET` con el secreto nuevo.

## 6. Merge de `dev` → `main`

```bash
git checkout main
git pull origin main
git merge dev
git push origin main
```

(Hasta ahora `main` nunca se tocó en toda esta ronda, por regla — este es el único
momento en que se toca.)

## 7. Build de la app con llaves live

Ver `documentos/tiendas/GUIA_TIENDAS.md`, sección 5 — build de Android (AAB) e iOS (IPA)
con `--dart-define` de producción.

## 8. Pedido real chiquito y su reembolso

Con la app ya instalada desde el build de producción (no desde Xcode/Android Studio en
modo debug):

1. Haz un pedido real, barato, pagando con tarjeta de verdad (la tuya).
2. Confirma que llega al panel del dueño, que un repartidor lo pueda tomar y marcar
   como entregado.
3. Cancélalo o pide el reembolso (o simplemente reembólsalo desde Stripe/Admin) para no
   quedarte con el cargo.
4. Confirma en el dashboard de Stripe (modo Live) que el cargo y el reembolso aparecen
   correctos.

## 9. Qué revisar en las primeras horas

- `cron.job_run_details` en producción — que el sweep de pagos corra cada 10 min sin
  401 (mismo problema que tuvimos en Pruebas con el secreto de Vault mal puesto).
- La tabla `alerts` — cualquier fila nueva con `category = 'pagos'` necesita revisión
  humana (son los casos que el código ahora deja sin tocar en vez de adivinar).
- Sentry (si el DSN de producción está configurado) — picos de errores nuevos.
- El webhook de Stripe (Developers → Webhooks → tu endpoint → intentos recientes) — que
  no haya entregas fallidas repetidas.

## Si algo sale mal

- **Una migración falla a medio camino**: Postgres hace rollback automático de esa
  migración completa (son transaccionales) — las anteriores ya aplicadas se quedan,
  pero esa y las siguientes no. Corrige el problema y vuelve a correr `db push`.
- **El webhook no llega / la cuenta de Stripe no es la correcta**: pagos con tarjeta se
  quedarían en `awaiting_payment` sin confirmarse solos — el cron de sweep los
  resolvería consultando a Stripe directo después de 30 min, así que no se pierde
  dinero, solo se tarda. Mientras tanto, usa `confirm` manual
  (`create-payment-intent` acción `confirm`) si hace falta resolver uno urgente.
- **Hay que revertir el build de la tienda**: Google Play permite "Halt rollout" en el
  release en curso; Apple no permite retirar una versión ya aprobada, pero sí puedes
  subir una nueva versión corregida de inmediato (no hay forma de "deshacer" una
  versión live en App Store).
- **Hay que revertir el merge a `main`**: `git revert` del commit de merge (nunca
  `reset --hard` sobre una rama que ya se compartió/puede estar desplegada).
