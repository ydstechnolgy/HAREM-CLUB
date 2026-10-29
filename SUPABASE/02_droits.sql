-- =====================================================================
-- HAREM CLUB · Script 02 · Qui peut voir et faire quoi
-- Patron : tout. Gérant : tout sauf l'équipe. Serveuse : ses tables.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Fonctions de droits
-- ---------------------------------------------------------------------
create or replace function public.my_member_id()
returns uuid language sql stable security definer set search_path = public as $$
  select id from public.members where user_id = auth.uid() and active
$$;

create or replace function public.my_role()
returns text language sql stable security definer set search_path = public as $$
  select role from public.members where user_id = auth.uid() and active
$$;

create or replace function public.is_member()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.members where user_id = auth.uid() and active)
$$;

create or replace function public.is_patron()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role() = 'patron', false)
$$;

-- patron ou gérant
create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role() in ('patron', 'gerant'), false)
$$;

create or replace function public.owns_tab(p_tab_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.tabs t
                 where t.id = p_tab_id and t.waitress_id = public.my_member_id())
$$;

-- ---------------------------------------------------------------------
-- Personne d'autre que les membres connectés
-- ---------------------------------------------------------------------
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;

-- ---------------------------------------------------------------------
-- Sécurité par ligne sur toutes les tables
-- ---------------------------------------------------------------------
alter table public.settings        enable row level security;
alter table public.members         enable row level security;
alter table public.club_tables     enable row level security;
alter table public.categories      enable row level security;
alter table public.products        enable row level security;
alter table public.suppliers       enable row level security;
alter table public.nights          enable row level security;
alter table public.tabs            enable row level security;
alter table public.tab_items       enable row level security;
alter table public.payments        enable row level security;
alter table public.cash_movements  enable row level security;
alter table public.expenses        enable row level security;
alter table public.inventories     enable row level security;
alter table public.stock_entries   enable row level security;
alter table public.stock_movements enable row level security;

-- Réglages : tout le monde lit, patron et gérant modifient
drop policy if exists settings_read on public.settings;
create policy settings_read on public.settings for select using (public.is_member());
drop policy if exists settings_write on public.settings;
create policy settings_write on public.settings for update using (public.is_staff()) with check (public.is_staff());

-- Équipe : patron et gérant voient tout, la serveuse se voit elle-même.
-- Créer ou modifier un compte passe par les fonctions du script 04.
drop policy if exists members_read on public.members;
create policy members_read on public.members for select
  using (public.is_staff() or user_id = auth.uid());

-- Tables du club, catégories, boissons : tout le monde lit, patron et gérant modifient
drop policy if exists club_tables_read on public.club_tables;
create policy club_tables_read on public.club_tables for select using (public.is_member());
drop policy if exists club_tables_write on public.club_tables;
create policy club_tables_write on public.club_tables for all using (public.is_staff()) with check (public.is_staff());

drop policy if exists categories_read on public.categories;
create policy categories_read on public.categories for select using (public.is_member());
drop policy if exists categories_write on public.categories;
create policy categories_write on public.categories for all using (public.is_staff()) with check (public.is_staff());

drop policy if exists products_read on public.products;
create policy products_read on public.products for select using (public.is_member());
drop policy if exists products_write on public.products;
create policy products_write on public.products for all using (public.is_staff()) with check (public.is_staff());

-- Fournisseurs : patron et gérant
drop policy if exists suppliers_all on public.suppliers;
create policy suppliers_all on public.suppliers for all using (public.is_staff()) with check (public.is_staff());

-- Soirées : tout le monde lit (la serveuse doit savoir si la soirée est ouverte)
drop policy if exists nights_read on public.nights;
create policy nights_read on public.nights for select using (public.is_member());

-- Notes : patron et gérant voient tout, la serveuse voit seulement les siennes
drop policy if exists tabs_read on public.tabs;
create policy tabs_read on public.tabs for select
  using (public.is_staff() or waitress_id = public.my_member_id());

drop policy if exists tab_items_read on public.tab_items;
create policy tab_items_read on public.tab_items for select
  using (public.is_staff() or public.owns_tab(tab_id));

drop policy if exists payments_read on public.payments;
create policy payments_read on public.payments for select
  using (public.is_staff() or public.owns_tab(tab_id));

-- Caisse, dépenses, stock : patron et gérant seulement (lecture ;
-- les écritures passent par les fonctions du script 03)
drop policy if exists cash_movements_read on public.cash_movements;
create policy cash_movements_read on public.cash_movements for select using (public.is_staff());

drop policy if exists expenses_read on public.expenses;
create policy expenses_read on public.expenses for select using (public.is_staff());

drop policy if exists inventories_read on public.inventories;
create policy inventories_read on public.inventories for select using (public.is_staff());

drop policy if exists stock_entries_read on public.stock_entries;
create policy stock_entries_read on public.stock_entries for select using (public.is_staff());

drop policy if exists stock_movements_read on public.stock_movements;
create policy stock_movements_read on public.stock_movements for select using (public.is_staff());

-- ---------------------------------------------------------------------
-- Prix d'achat et coûts : jamais lisibles directement depuis l'application.
-- Les rapports du patron et du gérant passent par des fonctions.
-- ---------------------------------------------------------------------
revoke select on public.products from authenticated;
grant select (id, category_id, name, sale_price, track_stock, min_stock, active,
              sort_order, created_at, updated_at)
  on public.products to authenticated;

revoke select on public.tab_items from authenticated;
grant select (id, tab_id, product_id, product_name, quantity, unit_price, status,
              requested_at, requested_by, served_by, served_at, removed_by,
              removed_at, removed_reason)
  on public.tab_items to authenticated;

-- Les écritures sur les notes, la caisse et le stock passent par les fonctions
revoke insert, update, delete on public.nights, public.tabs, public.tab_items,
  public.payments, public.cash_movements, public.expenses, public.inventories,
  public.stock_entries, public.stock_movements, public.members
  from authenticated;
