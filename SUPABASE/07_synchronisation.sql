-- =====================================================================
-- HAREM CLUB · Script 07 · Préparation de la synchronisation PowerSync
-- Ajoute une colonne « club » à chaque table : PowerSync s'en sert pour
-- envoyer à chaque appareil seulement ce que son rôle permet de voir.
-- Peut être relancé sans danger.
-- =====================================================================

do $$
declare t text;
begin
  foreach t in array array['settings', 'members', 'club_tables', 'categories', 'products', 'suppliers',
                           'nights', 'tabs', 'tab_items', 'payments', 'cash_movements', 'expenses',
                           'inventories', 'stock_entries', 'stock_movements']
  loop
    execute format('alter table public.%I add column if not exists club text not null default %L', t, 'harem');
  end loop;
end $$;

-- Les colonnes lisibles par l'application (le prix d'achat et le coût restent cachés)
grant select (club) on public.products to authenticated;
grant select (club) on public.tab_items to authenticated;
