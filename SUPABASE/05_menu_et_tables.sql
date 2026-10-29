-- =====================================================================
-- HAREM CLUB · Script 05 · Menu du Harem Club et tables de départ
-- Repris du menu papier. Les prix se changent ensuite dans le logiciel.
-- Les boissons d'une même ligne du menu sont séparées pour suivre le
-- stock de chacune. Les cocktails n'ont pas de suivi de stock.
-- Peut être relancé sans créer de doublons.
-- =====================================================================

do $$
declare
  v_cat uuid;
  v_order int;
  v_item record;
begin
  for v_item in
    select * from (values
      -- catégorie, ordre catégorie, boisson, prix, suivi du stock
      ('Whiskies et liqueurs', 1, 'Highland Park 12',              105000, true),
      ('Whiskies et liqueurs', 1, 'Macallan 12',                   110000, true),
      ('Whiskies et liqueurs', 1, 'Glenfiddich 12',                 60000, true),
      ('Whiskies et liqueurs', 1, 'Hennessy',                       60000, true),
      ('Whiskies et liqueurs', 1, 'Double Black 75cl',              60000, true),
      ('Whiskies et liqueurs', 1, 'Glenfiddich 15',                 70000, true),
      ('Whiskies et liqueurs', 1, 'Grand Marnier',                  70000, true),
      ('Whiskies et liqueurs', 1, 'Amaretto',                       70000, true),
      ('Whiskies et liqueurs', 1, 'Double Black 1L',                65000, true),
      ('Whiskies et liqueurs', 1, 'Rémy Martin',                    65000, true),
      ('Whiskies et liqueurs', 1, 'Don Julio',                      75000, true),
      ('Whiskies et liqueurs', 1, 'Black Label',                    50000, true),
      ('Whiskies et liqueurs', 1, 'Chivas',                         50000, true),
      ('Whiskies et liqueurs', 1, 'Dimple',                         50000, true),
      ('Whiskies et liqueurs', 1, 'Red Label',                      40000, true),
      ('Whiskies et liqueurs', 1, 'Jack Daniel''s',                 40000, true),
      ('Whiskies et liqueurs', 1, 'Baileys',                        40000, true),
      ('Whiskies et liqueurs', 1, 'Cognac VSOP XO Bourgeoisie',     50000, true),
      ('Whiskies et liqueurs', 1, 'Grant''s',                       25000, true),

      ('Eaux de vie',          2, 'Gordon''s Gin',                  30000, true),
      ('Eaux de vie',          2, 'Beefeater',                      30000, true),
      ('Eaux de vie',          2, 'Absolut',                        25000, true),
      ('Eaux de vie',          2, 'Rhum St James',                  25000, true),
      ('Eaux de vie',          2, 'Rhum Bacardi',                   25000, true),
      ('Eaux de vie',          2, 'Cointreau',                      40000, true),
      ('Eaux de vie',          2, 'Vodka',                          20000, true),
      ('Eaux de vie',          2, 'Vodka Belvedere',                65000, true),
      ('Eaux de vie',          2, 'Vodka Grey Goose',               55000, true),

      ('Champagnes',           3, 'Laurent Perrier',                50000, true),
      ('Champagnes',           3, 'Duchesse',                       50000, true),
      ('Champagnes',           3, 'Moët Charidon',                  60000, true),
      ('Champagnes',           3, 'Gobillard & Fils',               60000, true),
      ('Champagnes',           3, 'Moët Brut',                      65000, true),
      ('Champagnes',           3, 'Ruinart Brut',                   95000, true),
      ('Champagnes',           3, 'Ruinart Blanc',                 145000, true),
      ('Champagnes',           3, 'Veuve Clicquot',                 70000, true),
      ('Champagnes',           3, 'Belaire',                        45000, true),

      ('Vins et mousseux',     4, 'Vin I',                          12000, true),
      ('Vins et mousseux',     4, 'Vin II',                         15000, true),
      ('Vins et mousseux',     4, 'Vin mousseux I',                 15000, true),
      ('Vins et mousseux',     4, 'Vin mousseux II',                20000, true),

      ('Bières',               5, 'Pils',                            2000, true),
      ('Bières',               5, 'Djama',                           2000, true),
      ('Bières',               5, 'Beaufort',                        2000, true),
      ('Bières',               5, 'Guinness',                        2500, true),
      ('Bières',               5, 'Despe',                           2500, true),
      ('Bières',               5, 'XXL',                             2500, true),
      ('Bières',               5, 'Smirnoff',                        2500, true),
      ('Bières',               5, 'Red',                             2500, true),
      ('Bières',               5, 'Heineken',                        2500, true),

      ('Sucreries',            6, 'Soda',                            1000, true),
      ('Sucreries',            6, 'Tonic',                           1000, true),
      ('Sucreries',            6, 'Coca',                            1000, true),
      ('Sucreries',            6, 'Sprite',                          1000, true),
      ('Sucreries',            6, 'Eau 50cl',                         500, true),
      ('Sucreries',            6, 'Café',                            1500, false),

      ('Cocktails',            7, 'Cocktail Harem',                  3500, false),
      ('Cocktails',            7, 'Virgin Mojito',                   3500, false),
      ('Cocktails',            7, 'Exotic',                          3500, false),
      ('Cocktails',            7, 'Red Colada',                      3500, false),

      ('Cocktails alcoolisés', 8, 'Cocktail Harem alcoolisé',        4500, false),
      ('Cocktails alcoolisés', 8, 'Maserati Vodka',                  4500, false),
      ('Cocktails alcoolisés', 8, 'Mojito Ananas',                   4500, false),
      ('Cocktails alcoolisés', 8, 'Mojito Passion',                  4500, false),
      ('Cocktails alcoolisés', 8, 'Piña Colada',                     4500, false)
    ) as t(category, cat_order, name, price, track)
  loop
    insert into public.categories (name, sort_order) values (v_item.category, v_item.cat_order)
    on conflict (name) do nothing;
    select id into v_cat from public.categories where name = v_item.category;
    select coalesce(max(sort_order) + 1, 0) into v_order from public.products where category_id = v_cat;
    insert into public.products (category_id, name, sale_price, track_stock, sort_order)
    values (v_cat, v_item.name, v_item.price, v_item.track, v_order)
    on conflict (category_id, name) do nothing;
  end loop;
end $$;

-- Tables de départ (à adapter : renommer, désactiver ou en ajouter dans le logiciel)
insert into public.club_tables (name, zone, is_fixed, sort_order)
select 'Table ' || n, 'salle', true, n from generate_series(1, 10) as n
on conflict (name) do nothing;

insert into public.club_tables (name, zone, is_fixed, sort_order)
select 'VIP ' || n, 'vip', true, 100 + n from generate_series(1, 4) as n
on conflict (name) do nothing;

insert into public.club_tables (name, zone, is_fixed, sort_order)
values ('Comptoir', 'comptoir', true, 200)
on conflict (name) do nothing;
