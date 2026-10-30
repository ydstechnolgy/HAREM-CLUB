-- =====================================================================
-- HAREM CLUB · Script 12 · Catégorie « Autres »
-- Ajoute une catégorie « Autres » au menu, placée en dernier.
-- Le gérant y range tout ce qui n'est pas une boisson classique
-- (cigarettes, chicha, divers…) via Menu et tables > Boissons > Nouvelle boisson.
-- Relançable sans danger.
-- =====================================================================

insert into public.categories (name, sort_order)
values ('Autres', 99)
on conflict (name) do nothing;
