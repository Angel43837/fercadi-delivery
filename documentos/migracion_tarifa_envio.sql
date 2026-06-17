-- ============================================================
-- Migración: tarifa de envío por kilómetro (base $15 + $5/km)
-- Ejecutar en: Supabase Dashboard → SQL Editor → New Query → Run
-- ============================================================

-- 1. Columnas nuevas
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS lat double precision;
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS lng double precision;
ALTER TABLE orders      ADD COLUMN IF NOT EXISTS delivery_fee numeric DEFAULT 0;

-- 2. Coordenadas aproximadas para los restaurantes que ya existen
-- (centro de Maravatío: 19.8969, -100.4447 — ajusta después desde el
-- panel del dueño si quieres afinar la ubicación real de cada uno)
UPDATE restaurants SET lat = 19.8995, lng = -100.4470 WHERE id = '1';  -- McDonalds
UPDATE restaurants SET lat = 19.8940, lng = -100.4410 WHERE id = '2';  -- Starbucks
UPDATE restaurants SET lat = 19.9010, lng = -100.4395 WHERE id = '3';  -- Sushi Roll
UPDATE restaurants SET lat = 19.8950, lng = -100.4480 WHERE id = '01f7b898-8051-4f4c-913d-03d36453295c'; -- Tacos Chuy
UPDATE restaurants SET lat = 19.8920, lng = -100.4460 WHERE id = '12454866-098e-43e0-9dd2-50ae17982520'; -- Carnitas El Puerco
UPDATE restaurants SET lat = 19.9005, lng = -100.4430 WHERE id = 'r_pizzanostra';
UPDATE restaurants SET lat = 19.8960, lng = -100.4500 WHERE id = 'r_birria';
UPDATE restaurants SET lat = 19.8930, lng = -100.4400 WHERE id = 'r_mariscos';
UPDATE restaurants SET lat = 19.8985, lng = -100.4390 WHERE id = 'r_pollo';
UPDATE restaurants SET lat = 19.8945, lng = -100.4445 WHERE id = 'r_tortas';
UPDATE restaurants SET lat = 19.8970, lng = -100.4448 WHERE id = 'r_nieves';
UPDATE restaurants SET lat = 19.8915, lng = -100.4420 WHERE id = 'r_hotdogs';
UPDATE restaurants SET lat = 19.9020, lng = -100.4460 WHERE id = 'r_wok';
UPDATE restaurants SET lat = 19.8990, lng = -100.4500 WHERE id = 'r_alitas';
UPDATE restaurants SET lat = 19.8935, lng = -100.4470 WHERE id = 'r_pasteles';
