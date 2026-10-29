-- =====================================================================
-- HAREM CLUB · Script 01 · Les tables
-- A coller dans Supabase > SQL Editor, puis "Run".
-- Montants en FCFA (nombres entiers).
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- Réglages du club (une seule ligne)
-- ---------------------------------------------------------------------
create table if not exists public.settings (
  id               int primary key default 1 check (id = 1),
  club_name        text not null default 'Harem Club',
  phone            text default '90 08 74 65 / 90 98 98 29',
  ticket_header    text default 'HAREM CLUB',
  ticket_footer    text default 'Merci de votre visite',
  night_start_hour int  not null default 18 check (night_start_hour between 0 and 23),
  updated_at       timestamptz not null default now()
);
insert into public.settings (id) values (1) on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- L'équipe : patron, gérant (caissier), serveuses
-- ---------------------------------------------------------------------
create table if not exists public.members (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid unique references auth.users(id) on delete set null,
  login         text not null unique check (login ~ '^[a-z0-9._-]{3,30}$'),
  role          text not null check (role in ('patron', 'gerant', 'serveuse')),
  display_name  text not null,
  phone         text,
  active        boolean not null default true,
  created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Les tables du club
-- ---------------------------------------------------------------------
create table if not exists public.club_tables (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  zone        text not null default 'salle' check (zone in ('salle', 'vip', 'comptoir', 'terrasse')),
  is_fixed    boolean not null default true,
  active      boolean not null default true,
  sort_order  int not null default 0,
  created_by  uuid references public.members(id),
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Menu
-- ---------------------------------------------------------------------
create table if not exists public.categories (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now()
);

create table if not exists public.products (
  id              uuid primary key default gen_random_uuid(),
  category_id     uuid references public.categories(id),
  name            text not null,
  sale_price      int  not null check (sale_price >= 0),
  purchase_price  int  not null default 0 check (purchase_price >= 0),
  track_stock     boolean not null default true,   -- non pour les cocktails
  min_stock       int  not null default 0 check (min_stock >= 0),
  active          boolean not null default true,
  sort_order      int  not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (category_id, name)
);

create table if not exists public.suppliers (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  phone       text,
  note        text,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Soirées, notes, boissons, paiements
-- ---------------------------------------------------------------------
create table if not exists public.nights (
  id               uuid primary key default gen_random_uuid(),
  status           text not null default 'open' check (status in ('open', 'closed')),
  opened_by        uuid references public.members(id),
  opened_at        timestamptz not null default now(),
  opening_float    int not null default 0 check (opening_float >= 0),
  closed_by        uuid references public.members(id),
  closed_at        timestamptz,
  expected_cash    int,
  expected_momo    int,
  counted_cash     int,
  counted_momo     int,
  difference_cash  int,
  difference_momo  int,
  note             text
);
-- une seule soirée ouverte à la fois
create unique index if not exists nights_one_open on public.nights ((true)) where status = 'open';

create sequence if not exists public.ticket_seq;

create table if not exists public.tabs (
  id             uuid primary key default gen_random_uuid(),
  night_id       uuid not null references public.nights(id),
  table_id       uuid not null references public.club_tables(id),
  waitress_id    uuid not null references public.members(id),
  status         text not null default 'open' check (status in ('open', 'to_pay', 'paid', 'cancelled')),
  ticket_number  bigint unique,
  total          int not null default 0,
  paid_amount    int not null default 0,
  opened_at      timestamptz not null default now(),
  requested_at   timestamptz,
  paid_at        timestamptz,
  cashier_id     uuid references public.members(id),
  cancelled_by   uuid references public.members(id),
  cancel_reason  text
);
-- une seule note en cours par table
create unique index if not exists tabs_one_active_per_table
  on public.tabs (table_id) where status in ('open', 'to_pay');
create index if not exists tabs_night_idx on public.tabs (night_id);
create index if not exists tabs_waitress_idx on public.tabs (waitress_id);

create table if not exists public.tab_items (
  id              uuid primary key default gen_random_uuid(),
  tab_id          uuid not null references public.tabs(id) on delete cascade,
  product_id      uuid not null references public.products(id),
  product_name    text not null,                 -- nom figé au moment de la commande
  quantity        int  not null check (quantity > 0),
  unit_price      int  not null check (unit_price >= 0),  -- prix figé
  cost_price      int  not null default 0,               -- coût figé (caché aux serveuses)
  status          text not null default 'requested'
                  check (status in ('requested', 'served', 'refused', 'removed')),
  requested_at    timestamptz not null default now(),
  requested_by    uuid references public.members(id),
  served_by       uuid references public.members(id),
  served_at       timestamptz,
  removed_by      uuid references public.members(id),
  removed_at      timestamptz,
  removed_reason  text
);
create index if not exists tab_items_tab_idx on public.tab_items (tab_id);

create table if not exists public.payments (
  id           uuid primary key default gen_random_uuid(),
  tab_id       uuid not null references public.tabs(id),
  night_id     uuid not null references public.nights(id),
  method       text not null check (method in ('cash', 'mobile_money')),
  amount       int  not null check (amount > 0),
  received_by  uuid references public.members(id),
  created_at   timestamptz not null default now()
);
create index if not exists payments_tab_idx on public.payments (tab_id);

-- ---------------------------------------------------------------------
-- Caisse et dépenses
-- ---------------------------------------------------------------------
create table if not exists public.cash_movements (
  id          uuid primary key default gen_random_uuid(),
  night_id    uuid not null references public.nights(id),
  type        text not null check (type in ('in', 'out')),
  amount      int  not null check (amount > 0),
  reason      text not null,
  member_id   uuid references public.members(id),
  created_at  timestamptz not null default now()
);

create table if not exists public.expenses (
  id           uuid primary key default gen_random_uuid(),
  night_id     uuid references public.nights(id),
  label        text not null,
  category     text,
  amount       int  not null check (amount > 0),
  method       text not null default 'cash' check (method in ('cash', 'mobile_money')),
  from_till    boolean not null default true,   -- payé avec l'argent de la caisse
  supplier_id  uuid references public.suppliers(id),
  member_id    uuid references public.members(id),
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Stock
-- ---------------------------------------------------------------------
create table if not exists public.inventories (
  id            uuid primary key default gen_random_uuid(),
  nb_products   int not null default 0,
  nb_ecarts     int not null default 0,
  ecart_valeur  int not null default 0,
  note          text,
  member_id     uuid references public.members(id),
  created_at    timestamptz not null default now()
);

create table if not exists public.stock_entries (
  id           uuid primary key default gen_random_uuid(),
  product_id   uuid not null references public.products(id),
  quantity     int  not null check (quantity > 0),
  cost_price   int  not null default 0 check (cost_price >= 0),
  supplier_id  uuid references public.suppliers(id),
  note         text,
  member_id    uuid references public.members(id),
  created_at   timestamptz not null default now()
);

create table if not exists public.stock_movements (
  id            uuid primary key default gen_random_uuid(),
  product_id    uuid not null references public.products(id),
  type          text not null check (type in ('purchase', 'served', 'return', 'loss', 'adjustment', 'inventory')),
  quantity      int  not null,    -- positif = entrée, négatif = sortie
  tab_item_id   uuid references public.tab_items(id),
  entry_id      uuid references public.stock_entries(id),
  inventory_id  uuid references public.inventories(id),
  reason        text,
  member_id     uuid references public.members(id),
  created_at    timestamptz not null default now()
);
create index if not exists stock_movements_product_idx on public.stock_movements (product_id);

-- Stock actuel par boisson
create or replace view public.product_stock
with (security_invoker = true) as
select p.id as product_id,
       coalesce(sum(m.quantity), 0)::int as quantity
from public.products p
left join public.stock_movements m on m.product_id = p.id
where p.track_stock
group by p.id;

-- ---------------------------------------------------------------------
-- Mise à jour automatique de updated_at
-- ---------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists products_touch on public.products;
create trigger products_touch before update on public.products
  for each row execute function public.touch_updated_at();

drop trigger if exists settings_touch on public.settings;
create trigger settings_touch before update on public.settings
  for each row execute function public.touch_updated_at();
