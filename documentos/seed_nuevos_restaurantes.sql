-- ============================================================
-- Seed: platillos para Tacos Chuy y Carnitas + 10 restaurantes nuevos
-- Ejecutar en: Supabase Dashboard → SQL Editor → New Query
-- Las fotos son fotos de stock (Unsplash) de relleno — se pueden
-- cambiar después desde el panel del dueño de cada restaurante.
-- ============================================================

-- ── TACOS CHUY (ya existe, id 01f7b898-8051-4f4c-913d-03d36453295c) ──

INSERT INTO categories (id, restaurant_id, name, emoji_icon) VALUES
  ('c_chuy_tacos',    '01f7b898-8051-4f4c-913d-03d36453295c', 'Tacos',       '🌮'),
  ('c_chuy_quesa',    '01f7b898-8051-4f4c-913d-03d36453295c', 'Quesadillas', '🧀'),
  ('c_chuy_bebidas',  '01f7b898-8051-4f4c-913d-03d36453295c', 'Bebidas',     '🥤');

INSERT INTO products (id, category_id, restaurant_id, name, description, price, image_url, is_available) VALUES
  ('p_chuy_1', 'c_chuy_tacos',   '01f7b898-8051-4f4c-913d-03d36453295c', 'Taco de Pastor',     'Carne al pastor con piña, cebolla y cilantro', 15, 'https://images.unsplash.com/photo-1551504734-0ee6dc2b04ad?w=400&q=80', true),
  ('p_chuy_2', 'c_chuy_tacos',   '01f7b898-8051-4f4c-913d-03d36453295c', 'Taco de Bistec',     'Bistec de res a la plancha con cebolla',       18, 'https://images.unsplash.com/photo-1551504734-0ee6dc2b04ad?w=400&q=80', true),
  ('p_chuy_3', 'c_chuy_tacos',   '01f7b898-8051-4f4c-913d-03d36453295c', 'Taco de Chorizo',    'Chorizo rojo con papa',                        16, 'https://images.unsplash.com/photo-1551504734-0ee6dc2b04ad?w=400&q=80', true),
  ('p_chuy_4', 'c_chuy_quesa',   '01f7b898-8051-4f4c-913d-03d36453295c', 'Quesadilla de Queso','Tortilla de harina con queso oaxaca derretido', 35, 'https://images.unsplash.com/photo-1618040996337-56904b7850b9?w=400&q=80', true),
  ('p_chuy_5', 'c_chuy_quesa',   '01f7b898-8051-4f4c-913d-03d36453295c', 'Quesadilla de Flor de Calabaza', 'Con flor de calabaza y queso',     42, 'https://images.unsplash.com/photo-1618040996337-56904b7850b9?w=400&q=80', true),
  ('p_chuy_6', 'c_chuy_bebidas', '01f7b898-8051-4f4c-913d-03d36453295c', 'Agua de Horchata',   'Agua fresca de horchata, 500ml',                25, 'https://images.unsplash.com/photo-1571066811602-716837d681de?w=400&q=80', true),
  ('p_chuy_7', 'c_chuy_bebidas', '01f7b898-8051-4f4c-913d-03d36453295c', 'Refresco',           'Lata 355ml',                                    20, 'https://images.unsplash.com/photo-1581636625402-29b2a704ef13?w=400&q=80', true);

-- ── CARNITAS EL PUERCO (ya existe, id 12454866-098e-43e0-9dd2-50ae17982520) ──

INSERT INTO categories (id, restaurant_id, name, emoji_icon) VALUES
  ('c_carnitas_kilo', '12454866-098e-43e0-9dd2-50ae17982520', 'Carnitas por Kilo', '🐷'),
  ('c_carnitas_tacos','12454866-098e-43e0-9dd2-50ae17982520', 'Tacos',             '🌮'),
  ('c_carnitas_extra','12454866-098e-43e0-9dd2-50ae17982520', 'Antojitos',         '🫓'),
  ('c_carnitas_bebidas','12454866-098e-43e0-9dd2-50ae17982520', 'Bebidas',         '🥤');

INSERT INTO products (id, category_id, restaurant_id, name, description, price, image_url, is_available) VALUES
  ('p_carnitas_1', 'c_carnitas_kilo',    '12454866-098e-43e0-9dd2-50ae17982520', 'Kilo de Carnitas Surtidas', 'Maciza, costilla y cuerito',          280, 'https://images.unsplash.com/photo-1599974579688-8dbdd335c77f?w=400&q=80', true),
  ('p_carnitas_2', 'c_carnitas_kilo',    '12454866-098e-43e0-9dd2-50ae17982520', 'Medio Kilo de Maciza',      'Solo carne maciza',                    145, 'https://images.unsplash.com/photo-1599974579688-8dbdd335c77f?w=400&q=80', true),
  ('p_carnitas_3', 'c_carnitas_tacos',   '12454866-098e-43e0-9dd2-50ae17982520', 'Taco de Carnitas',          'Carnitas con salsa verde y cebolla',   18, 'https://images.unsplash.com/photo-1551504734-0ee6dc2b04ad?w=400&q=80', true),
  ('p_carnitas_4', 'c_carnitas_extra',   '12454866-098e-43e0-9dd2-50ae17982520', 'Orden de Cuerito',          'Cuerito de cerdo en salsa',             45, 'https://images.unsplash.com/photo-1599974579688-8dbdd335c77f?w=400&q=80', true),
  ('p_carnitas_5', 'c_carnitas_bebidas', '12454866-098e-43e0-9dd2-50ae17982520', 'Agua de Jamaica',           'Agua fresca de jamaica, 500ml',        25, 'https://images.unsplash.com/photo-1571066811602-716837d681de?w=400&q=80', true);

-- ============================================================
-- 10 RESTAURANTES NUEVOS
-- ============================================================

-- 1. Pizza Nostra
INSERT INTO restaurants (id, name, description, address, emoji_icon, rating, likes, is_open, owner_id) VALUES
  ('r_pizzanostra', 'Pizza Nostra', 'Pizza artesanal al horno de leña', 'Av. Lázaro Cárdenas 45, Maravatío', '🍕', 4.4, 0, true, NULL);
INSERT INTO categories (id, restaurant_id, name, emoji_icon) VALUES
  ('c_pizza_pizzas',  'r_pizzanostra', 'Pizzas',  '🍕'),
  ('c_pizza_bebidas', 'r_pizzanostra', 'Bebidas', '🥤');
INSERT INTO products (id, category_id, restaurant_id, name, description, price, image_url, is_available) VALUES
  ('p_pizza_1', 'c_pizza_pizzas',  'r_pizzanostra', 'Pizza Pepperoni',      'Mediana, doble pepperoni y queso mozzarella', 145, 'https://images.unsplash.com/photo-1628840042765-356cda07504e?w=400&q=80', true),
  ('p_pizza_2', 'c_pizza_pizzas',  'r_pizzanostra', 'Pizza Hawaiana',       'Jamón, piña y queso',                          139, 'https://images.unsplash.com/photo-1628840042765-356cda07504e?w=400&q=80', true),
  ('p_pizza_3', 'c_pizza_pizzas',  'r_pizzanostra', 'Pizza Vegetariana',    'Pimiento, champiñón, cebolla y aceitunas',     135, 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=400&q=80', true),
  ('p_pizza_4', 'c_pizza_bebidas', 'r_pizzanostra', 'Refresco 2L',          'Bebida de cola, 2 litros',                      45, 'https://images.unsplash.com/photo-1581636625402-29b2a704ef13?w=400&q=80', true);

-- 2. Birria El Compa
INSERT INTO restaurants (id, name, description, address, emoji_icon, rating, likes, is_open, owner_id) VALUES
  ('r_birria', 'Birria El Compa', 'Birria de res estilo Jalisco, desde temprano', 'Calle Hidalgo 12, Maravatío', '🌮', 4.7, 0, true, NULL);
INSERT INTO categories (id, restaurant_id, name, emoji_icon) VALUES
  ('c_birria_platos',  'r_birria', 'Birria',   '🍲'),
  ('c_birria_bebidas', 'r_birria', 'Bebidas',  '🥤');
INSERT INTO products (id, category_id, restaurant_id, name, description, price, image_url, is_available) VALUES
  ('p_birria_1', 'c_birria_platos',  'r_birria', 'Taco de Birria',     'Tortilla bañada en consomé, con queso',        20, 'https://images.unsplash.com/photo-1599974579688-8dbdd335c77f?w=400&q=80', true),
  ('p_birria_2', 'c_birria_platos',  'r_birria', 'Plato de Birria',    'Media orden con consomé, cebolla y limón',     95, 'https://images.unsplash.com/photo-1599974579688-8dbdd335c77f?w=400&q=80', true),
  ('p_birria_3', 'c_birria_platos',  'r_birria', 'Consomé Extra',      'Vaso de consomé de birria',                    25, 'https://images.unsplash.com/photo-1547592180-85f173990554?w=400&q=80', true),
  ('p_birria_4', 'c_birria_bebidas', 'r_birria', 'Agua de Tamarindo',  'Agua fresca, 500ml',                           25, 'https://images.unsplash.com/photo-1571066811602-716837d681de?w=400&q=80', true);

-- 3. Mariscos La Sirena
INSERT INTO restaurants (id, name, description, address, emoji_icon, rating, likes, is_open, owner_id) VALUES
  ('r_mariscos', 'Mariscos La Sirena', 'Mariscos frescos y ceviches', 'Av. Morelos 88, Maravatío', '🦐', 4.5, 0, true, NULL);
INSERT INTO categories (id, restaurant_id, name, emoji_icon) VALUES
  ('c_mar_ceviches', 'r_mariscos', 'Ceviches', '🥗'),
  ('c_mar_platos',   'r_mariscos', 'Platillos','🦐'),
  ('c_mar_bebidas',  'r_mariscos', 'Bebidas',  '🥤');
INSERT INTO products (id, category_id, restaurant_id, name, description, price, image_url, is_available) VALUES
  ('p_mar_1', 'c_mar_ceviches', 'r_mariscos', 'Ceviche de Camarón',  'Camarón fresco con limón, pepino y cilantro', 110, 'https://images.unsplash.com/photo-1565680018434-b513d5e5fd47?w=400&q=80', true),
  ('p_mar_2', 'c_mar_platos',   'r_mariscos', 'Camarones a la Diabla','Camarones en salsa picante, con arroz',      145, 'https://images.unsplash.com/photo-1565680018434-b513d5e5fd47?w=400&q=80', true),
  ('p_mar_3', 'c_mar_platos',   'r_mariscos', 'Filete de Pescado Empanizado', 'Filete con ensalada y arroz',        125, 'https://images.unsplash.com/photo-1565680018434-b513d5e5fd47?w=400&q=80', true),
  ('p_mar_4', 'c_mar_bebidas',  'r_mariscos', 'Cerveza',             'Cerveza clara 355ml',                          40, 'https://images.unsplash.com/photo-1581636625402-29b2a704ef13?w=400&q=80', true);

-- 4. Pollo Feliz
INSERT INTO restaurants (id, name, description, address, emoji_icon, rating, likes, is_open, owner_id) VALUES
  ('r_pollo', 'Pollo Feliz', 'Pollo asado al carbón con su recetita secreta', 'Calle Juárez 34, Maravatío', '🍗', 4.6, 0, true, NULL);
INSERT INTO categories (id, restaurant_id, name, emoji_icon) VALUES
  ('c_pollo_platos',   'r_pollo', 'Pollo Asado', '🍗'),
  ('c_pollo_ensaladas','r_pollo', 'Ensaladas',   '🥗'),
  ('c_pollo_bebidas',  'r_pollo', 'Bebidas',     '🥤');
INSERT INTO products (id, category_id, restaurant_id, name, description, price, image_url, is_available) VALUES
  ('p_pollo_1', 'c_pollo_platos',    'r_pollo', 'Pollo Entero',       'Pollo entero asado al carbón con tortillas',  220, 'https://images.unsplash.com/photo-1598103442097-8b74394b95c6?w=400&q=80', true),
  ('p_pollo_2', 'c_pollo_platos',    'r_pollo', 'Medio Pollo',        'Medio pollo asado con papas y ensalada',      125, 'https://images.unsplash.com/photo-1598103442097-8b74394b95c6?w=400&q=80', true),
  ('p_pollo_3', 'c_pollo_ensaladas', 'r_pollo', 'Ensalada de la Casa','Lechuga, jitomate, cebolla morada y limón',    35, 'https://images.unsplash.com/photo-1540420773420-3366772f4999?w=400&q=80', true),
  ('p_pollo_4', 'c_pollo_bebidas',   'r_pollo', 'Refresco',           'Lata 355ml',                                    20, 'https://images.unsplash.com/photo-1581636625402-29b2a704ef13?w=400&q=80', true);

-- 5. Tortas Don Memo
INSERT INTO restaurants (id, name, description, address, emoji_icon, rating, likes, is_open, owner_id) VALUES
  ('r_tortas', 'Tortas Don Memo', 'Las tortas más grandes de Maravatío', 'Av. Revolución 7, Maravatío', '🥪', 4.3, 0, true, NULL);
INSERT INTO categories (id, restaurant_id, name, emoji_icon) VALUES
  ('c_tortas_platos',  'r_tortas', 'Tortas',  '🥪'),
  ('c_tortas_bebidas', 'r_tortas', 'Bebidas', '🥤');
INSERT INTO products (id, category_id, restaurant_id, name, description, price, image_url, is_available) VALUES
  ('p_tortas_1', 'c_tortas_platos',  'r_tortas', 'Torta de Pierna',   'Pierna de cerdo, aguacate, frijoles y jalapeño', 55, 'https://images.unsplash.com/photo-1553979459-d2229ba7433b?w=400&q=80', true),
  ('p_tortas_2', 'c_tortas_platos',  'r_tortas', 'Torta de Milanesa', 'Milanesa de res empanizada con todo',            58, 'https://images.unsplash.com/photo-1553979459-d2229ba7433b?w=400&q=80', true),
  ('p_tortas_3', 'c_tortas_platos',  'r_tortas', 'Torta Cubana',      'Jamón, queso, pierna, milanesa y chorizo',       68, 'https://images.unsplash.com/photo-1553979459-d2229ba7433b?w=400&q=80', true),
  ('p_tortas_4', 'c_tortas_bebidas', 'r_tortas', 'Agua de Limón',     'Agua fresca, 500ml',                             22, 'https://images.unsplash.com/photo-1571066811602-716837d681de?w=400&q=80', true);

-- 6. Nieves Tepa
INSERT INTO restaurants (id, name, description, address, emoji_icon, rating, likes, is_open, owner_id) VALUES
  ('r_nieves', 'Nieves Tepa', 'Nieves y paletas artesanales de la región', 'Plaza Principal, Maravatío', '🍦', 4.8, 0, true, NULL);
INSERT INTO categories (id, restaurant_id, name, emoji_icon) VALUES
  ('c_nieves_nieves',  'r_nieves', 'Nieves',   '🍦'),
  ('c_nieves_paletas', 'r_nieves', 'Paletas',  '🍡');
INSERT INTO products (id, category_id, restaurant_id, name, description, price, image_url, is_available) VALUES
  ('p_nieves_1', 'c_nieves_nieves',  'r_nieves', 'Nieve de Limón',     'Nieve artesanal de limón con leche',  28, 'https://images.unsplash.com/photo-1497034825429-c343d7c6a68a?w=400&q=80', true),
  ('p_nieves_2', 'c_nieves_nieves',  'r_nieves', 'Nieve de Tequila',   'Nieve artesanal sabor tequila',        35, 'https://images.unsplash.com/photo-1497034825429-c343d7c6a68a?w=400&q=80', true),
  ('p_nieves_3', 'c_nieves_paletas', 'r_nieves', 'Paleta de Fresa',    'Paleta de agua de fresa natural',      18, 'https://images.unsplash.com/photo-1497034825429-c343d7c6a68a?w=400&q=80', true);

-- 7. Hot Dogs El Gringo
INSERT INTO restaurants (id, name, description, address, emoji_icon, rating, likes, is_open, owner_id) VALUES
  ('r_hotdogs', 'Hot Dogs El Gringo', 'Hot dogs estilo Sonora', 'Calle Madero 21, Maravatío', '🌭', 4.2, 0, true, NULL);
INSERT INTO categories (id, restaurant_id, name, emoji_icon) VALUES
  ('c_hd_platos',  'r_hotdogs', 'Hot Dogs', '🌭'),
  ('c_hd_papas',   'r_hotdogs', 'Papas',    '🍟'),
  ('c_hd_bebidas', 'r_hotdogs', 'Bebidas',  '🥤');
INSERT INTO products (id, category_id, restaurant_id, name, description, price, image_url, is_available) VALUES
  ('p_hd_1', 'c_hd_platos',  'r_hotdogs', 'Hot Dog Sonora',     'Tocino, frijoles, jitomate, cebolla y mostaza', 45, 'https://images.unsplash.com/photo-1612392061787-2d078b3e573d?w=400&q=80', true),
  ('p_hd_2', 'c_hd_platos',  'r_hotdogs', 'Hot Dog Sencillo',   'Salchicha, mostaza y catsup',                    30, 'https://images.unsplash.com/photo-1612392061787-2d078b3e573d?w=400&q=80', true),
  ('p_hd_3', 'c_hd_papas',   'r_hotdogs', 'Papas Gajo',         'Porción de papas gajo con queso',                40, 'https://images.unsplash.com/photo-1573080496219-bb080dd4f877?w=400&q=80', true),
  ('p_hd_4', 'c_hd_bebidas', 'r_hotdogs', 'Refresco',           'Lata 355ml',                                      20, 'https://images.unsplash.com/photo-1581636625402-29b2a704ef13?w=400&q=80', true);

-- 8. Wok Express
INSERT INTO restaurants (id, name, description, address, emoji_icon, rating, likes, is_open, owner_id) VALUES
  ('r_wok', 'Wok Express', 'Comida china rápida estilo cantonés', 'Av. Lázaro Cárdenas 102, Maravatío', '🥡', 4.1, 0, true, NULL);
INSERT INTO categories (id, restaurant_id, name, emoji_icon) VALUES
  ('c_wok_platos',  'r_wok', 'Platillos', '🥡'),
  ('c_wok_bebidas', 'r_wok', 'Bebidas',   '🥤');
INSERT INTO products (id, category_id, restaurant_id, name, description, price, image_url, is_available) VALUES
  ('p_wok_1', 'c_wok_platos',  'r_wok', 'Arroz Frito con Pollo', 'Arroz frito con pollo, huevo y verduras', 75, 'https://images.unsplash.com/photo-1585032226651-759b368d7246?w=400&q=80', true),
  ('p_wok_2', 'c_wok_platos',  'r_wok', 'Chow Mein de Res',      'Fideo frito con res y verduras',          85, 'https://images.unsplash.com/photo-1585032226651-759b368d7246?w=400&q=80', true),
  ('p_wok_3', 'c_wok_platos',  'r_wok', 'Pollo Agridulce',       'Pollo empanizado en salsa agridulce',     88, 'https://images.unsplash.com/photo-1585032226651-759b368d7246?w=400&q=80', true),
  ('p_wok_4', 'c_wok_bebidas', 'r_wok', 'Té Helado',             'Té helado de durazno, 500ml',             25, 'https://images.unsplash.com/photo-1571066811602-716837d681de?w=400&q=80', true);

-- 9. Alitas Buffalo MX
INSERT INTO restaurants (id, name, description, address, emoji_icon, rating, likes, is_open, owner_id) VALUES
  ('r_alitas', 'Alitas Buffalo MX', 'Alitas bañadas en salsas de la casa', 'Calle Allende 9, Maravatío', '🍗', 4.5, 0, true, NULL);
INSERT INTO categories (id, restaurant_id, name, emoji_icon) VALUES
  ('c_alitas_platos', 'r_alitas', 'Alitas',  '🍗'),
  ('c_alitas_papas',  'r_alitas', 'Papas',   '🍟'),
  ('c_alitas_bebidas','r_alitas', 'Bebidas', '🥤');
INSERT INTO products (id, category_id, restaurant_id, name, description, price, image_url, is_available) VALUES
  ('p_alitas_1', 'c_alitas_platos', 'r_alitas', '10 Alitas BBQ',      'Alitas bañadas en salsa BBQ',          110, 'https://images.unsplash.com/photo-1527477396000-e27163b481c2?w=400&q=80', true),
  ('p_alitas_2', 'c_alitas_platos', 'r_alitas', '10 Alitas Mango Habanero', 'Alitas en salsa de mango habanero', 115, 'https://images.unsplash.com/photo-1527477396000-e27163b481c2?w=400&q=80', true),
  ('p_alitas_3', 'c_alitas_papas',  'r_alitas', 'Papas a la Francesa','Porción mediana de papas fritas',       40, 'https://images.unsplash.com/photo-1573080496219-bb080dd4f877?w=400&q=80', true),
  ('p_alitas_4', 'c_alitas_bebidas','r_alitas', 'Cerveza',            'Cerveza clara 355ml',                    40, 'https://images.unsplash.com/photo-1581636625402-29b2a704ef13?w=400&q=80', true);

-- 10. Pastelería Dulce Hogar
INSERT INTO restaurants (id, name, description, address, emoji_icon, rating, likes, is_open, owner_id) VALUES
  ('r_pasteles', 'Pastelería Dulce Hogar', 'Pasteles, postres y café de grano', 'Av. Morelos 15, Maravatío', '🧁', 4.6, 0, true, NULL);
INSERT INTO categories (id, restaurant_id, name, emoji_icon) VALUES
  ('c_past_pasteles', 'r_pasteles', 'Pasteles', '🧁'),
  ('c_past_cafe',      'r_pasteles', 'Café',     '☕');
INSERT INTO products (id, category_id, restaurant_id, name, description, price, image_url, is_available) VALUES
  ('p_past_1', 'c_past_pasteles', 'r_pasteles', 'Rebanada de Pastel de Chocolate', 'Pastel húmedo de chocolate con ganache', 45, 'https://images.unsplash.com/photo-1578985545062-69928b1d9587?w=400&q=80', true),
  ('p_past_2', 'c_past_pasteles', 'r_pasteles', 'Rebanada de Pastel Tres Leches',  'Clásico pastel tres leches',             40, 'https://images.unsplash.com/photo-1578985545062-69928b1d9587?w=400&q=80', true),
  ('p_past_3', 'c_past_cafe',     'r_pasteles', 'Café Americano',                 'Café de grano recién hecho',             32, 'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=400&q=80', true),
  ('p_past_4', 'c_past_cafe',     'r_pasteles', 'Capuchino',                      'Espresso con leche espumada',            40, 'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=400&q=80', true);
