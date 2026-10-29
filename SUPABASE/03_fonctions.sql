-- =====================================================================
-- HAREM CLUB · Script 03 · Les fonctions du serveur
-- Soirée, notes, bar, encaissement, caisse, stock, rapports.
-- Chaque fonction vérifie le rôle avant d'agir.
-- Les identifiants (p_id) peuvent être fournis par l'appareil : renvoyer
-- deux fois la même action (hors ligne) ne la fait qu'une fois.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Outils internes
-- ---------------------------------------------------------------------
create or replace function public._require_member()
returns uuid language plpgsql stable security definer set search_path = public as $$
declare v uuid := public.my_member_id();
begin
  if v is null then raise exception 'Compte non autorisé'; end if;
  return v;
end $$;

create or replace function public._require_staff()
returns uuid language plpgsql stable security definer set search_path = public as $$
declare v uuid := public._require_member();
begin
  if not public.is_staff() then raise exception 'Réservé au patron et au gérant'; end if;
  return v;
end $$;

create or replace function public.current_night_id()
returns uuid language sql stable security definer set search_path = public as $$
  select id from public.nights where status = 'open' limit 1
$$;

create or replace function public._recalc_tab(p_tab_id uuid)
returns int language plpgsql security definer set search_path = public as $$
declare v_total int;
begin
  select coalesce(sum(quantity * unit_price), 0) into v_total
  from public.tab_items where tab_id = p_tab_id and status = 'served';
  update public.tabs set total = v_total where id = p_tab_id;
  return v_total;
end $$;

-- Charge une note et vérifie que l'appelant peut y toucher
create or replace function public._load_tab(p_tab_id uuid)
returns public.tabs language plpgsql security definer set search_path = public as $$
declare v_tab public.tabs; v_me uuid := public._require_member();
begin
  select * into v_tab from public.tabs where id = p_tab_id for update;
  if not found then raise exception 'Note introuvable'; end if;
  if not public.is_staff() and v_tab.waitress_id <> v_me then
    raise exception 'Cette note appartient à une autre serveuse';
  end if;
  return v_tab;
end $$;

-- ---------------------------------------------------------------------
-- Soirée
-- ---------------------------------------------------------------------
create or replace function public.open_night(p_opening_float int default 0, p_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_me uuid := public._require_staff(); v_id uuid := coalesce(p_id, gen_random_uuid());
begin
  if exists (select 1 from public.nights where id = v_id) then return v_id; end if;
  if public.current_night_id() is not null then
    raise exception 'Une soirée est déjà ouverte';
  end if;
  insert into public.nights (id, opened_by, opening_float)
  values (v_id, v_me, greatest(coalesce(p_opening_float, 0), 0));
  return v_id;
end $$;

create or replace function public.close_night(p_counted_cash int, p_counted_momo int default 0, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public._require_staff();
  v_night public.nights;
  v_cash_pay int; v_momo_pay int; v_in int; v_out int; v_exp int;
  v_exp_cash int; v_exp_momo int;
begin
  select * into v_night from public.nights where status = 'open' for update;
  if not found then raise exception 'Aucune soirée ouverte'; end if;

  if exists (select 1 from public.tabs where night_id = v_night.id and status in ('open', 'to_pay')) then
    raise exception 'Des notes sont encore ouvertes : encaissez-les ou annulez-les avant la clôture';
  end if;

  select coalesce(sum(p.amount) filter (where p.method = 'cash'), 0),
         coalesce(sum(p.amount) filter (where p.method = 'mobile_money'), 0)
    into v_cash_pay, v_momo_pay
  from public.payments p join public.tabs t on t.id = p.tab_id
  where p.night_id = v_night.id and t.status = 'paid';

  select coalesce(sum(amount) filter (where type = 'in'), 0),
         coalesce(sum(amount) filter (where type = 'out'), 0)
    into v_in, v_out
  from public.cash_movements where night_id = v_night.id;

  select coalesce(sum(amount) filter (where method = 'cash'), 0),
         coalesce(sum(amount) filter (where method = 'mobile_money'), 0)
    into v_exp_cash, v_exp_momo
  from public.expenses where night_id = v_night.id and from_till;

  update public.nights set
    status          = 'closed',
    closed_by       = v_me,
    closed_at       = now(),
    expected_cash   = opening_float + v_cash_pay + v_in - v_out - v_exp_cash,
    expected_momo   = v_momo_pay - v_exp_momo,
    counted_cash    = coalesce(p_counted_cash, 0),
    counted_momo    = coalesce(p_counted_momo, 0),
    difference_cash = coalesce(p_counted_cash, 0) - (opening_float + v_cash_pay + v_in - v_out - v_exp_cash),
    difference_momo = coalesce(p_counted_momo, 0) - (v_momo_pay - v_exp_momo),
    note            = p_note
  where id = v_night.id
  returning * into v_night;

  return jsonb_build_object(
    'night_id', v_night.id,
    'expected_cash', v_night.expected_cash, 'counted_cash', v_night.counted_cash,
    'difference_cash', v_night.difference_cash,
    'expected_momo', v_night.expected_momo, 'counted_momo', v_night.counted_momo,
    'difference_momo', v_night.difference_momo);
end $$;

-- ---------------------------------------------------------------------
-- Tables du club
-- La serveuse peut créer une table provisoire ; patron et gérant
-- peuvent aussi créer des tables fixes.
-- ---------------------------------------------------------------------
create or replace function public.create_table(p_name text, p_zone text default 'salle',
                                               p_fixed boolean default false, p_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_me uuid := public._require_member(); v_id uuid := coalesce(p_id, gen_random_uuid());
begin
  if exists (select 1 from public.club_tables where id = v_id) then return v_id; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'Donnez un nom à la table'; end if;
  insert into public.club_tables (id, name, zone, is_fixed, created_by, sort_order)
  values (v_id, trim(p_name), coalesce(p_zone, 'salle'),
          coalesce(p_fixed, false) and public.is_staff(), v_me,
          coalesce((select max(sort_order) + 1 from public.club_tables), 0));
  return v_id;
exception when unique_violation then
  raise exception 'Une table porte déjà ce nom';
end $$;

-- ---------------------------------------------------------------------
-- Notes (serveuse)
-- ---------------------------------------------------------------------
create or replace function public.open_tab(p_table_id uuid, p_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_me uuid := public._require_member(); v_id uuid := coalesce(p_id, gen_random_uuid());
        v_night uuid := public.current_night_id();
begin
  if exists (select 1 from public.tabs where id = v_id) then return v_id; end if;
  if v_night is null then raise exception 'La soirée n''est pas encore ouverte'; end if;
  if not exists (select 1 from public.club_tables where id = p_table_id and active) then
    raise exception 'Table introuvable';
  end if;
  insert into public.tabs (id, night_id, table_id, waitress_id)
  values (v_id, v_night, p_table_id, v_me);
  return v_id;
exception when unique_violation then
  raise exception 'Cette table a déjà une note en cours';
end $$;

-- p_items = [{"id": "<uuid facultatif>", "product_id": "<uuid>", "quantity": 2}, ...]
create or replace function public.add_items(p_tab_id uuid, p_items jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_tab public.tabs := public._load_tab(p_tab_id);
  v_me uuid := public.my_member_id();
  v_item jsonb; v_prod public.products; v_item_id uuid; v_qty int; v_count int := 0;
begin
  if v_tab.status <> 'open' then
    raise exception 'Cette note n''est plus ouverte';
  end if;
  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    v_item_id := coalesce((v_item->>'id')::uuid, gen_random_uuid());
    continue when exists (select 1 from public.tab_items where id = v_item_id);
    v_qty := (v_item->>'quantity')::int;
    if v_qty is null or v_qty <= 0 then raise exception 'Quantité invalide'; end if;
    select * into v_prod from public.products where id = (v_item->>'product_id')::uuid and active;
    if not found then raise exception 'Boisson introuvable ou retirée du menu'; end if;
    insert into public.tab_items (id, tab_id, product_id, product_name, quantity,
                                  unit_price, cost_price, requested_by)
    values (v_item_id, p_tab_id, v_prod.id, v_prod.name, v_qty,
            v_prod.sale_price, v_prod.purchase_price, v_me);
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

-- La serveuse annule une boisson pas encore servie
create or replace function public.cancel_request(p_item_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_item public.tab_items; v_tab public.tabs;
begin
  select * into v_item from public.tab_items where id = p_item_id for update;
  if not found then raise exception 'Boisson introuvable'; end if;
  v_tab := public._load_tab(v_item.tab_id);
  if v_item.status <> 'requested' then
    raise exception 'Cette boisson a déjà été traitée par le bar';
  end if;
  update public.tab_items
     set status = 'removed', removed_by = public.my_member_id(), removed_at = now(),
         removed_reason = 'Annulée avant service'
   where id = p_item_id;
end $$;

-- Demander l'encaissement : la note part au gérant
create or replace function public.request_payment(p_tab_id uuid)
returns int language plpgsql security definer set search_path = public as $$
declare v_tab public.tabs := public._load_tab(p_tab_id); v_total int;
begin
  if v_tab.status = 'to_pay' then return v_tab.total; end if;
  if v_tab.status <> 'open' then raise exception 'Cette note n''est plus ouverte'; end if;
  if exists (select 1 from public.tab_items where tab_id = p_tab_id and status = 'requested') then
    raise exception 'Des boissons attendent encore le bar';
  end if;
  v_total := public._recalc_tab(p_tab_id);
  if v_total = 0 then raise exception 'La note est vide'; end if;
  update public.tabs set status = 'to_pay', requested_at = now() where id = p_tab_id;
  return v_total;
end $$;

-- Le client recommande après avoir demandé la facture
create or replace function public.reopen_tab(p_tab_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_tab public.tabs := public._load_tab(p_tab_id);
begin
  if v_tab.status = 'open' then return; end if;
  if v_tab.status <> 'to_pay' then raise exception 'Cette note ne peut plus être rouverte'; end if;
  if v_tab.paid_amount > 0 then raise exception 'Un paiement a déjà été reçu sur cette note'; end if;
  update public.tabs set status = 'open', requested_at = null where id = p_tab_id;
end $$;

-- ---------------------------------------------------------------------
-- Bar (gérant)
-- ---------------------------------------------------------------------
create or replace function public.serve_items(p_item_ids uuid[])
returns int language plpgsql security definer set search_path = public as $$
declare v_me uuid := public._require_staff(); v_item record; v_count int := 0;
begin
  for v_item in
    select i.*, p.track_stock, t.status as tab_status
    from public.tab_items i
    join public.products p on p.id = i.product_id
    join public.tabs t on t.id = i.tab_id
    where i.id = any(p_item_ids) and i.status = 'requested'
    for update of i
  loop
    if v_item.tab_status <> 'open' then
      raise exception 'La note de cette boisson n''est plus ouverte';
    end if;
    update public.tab_items set status = 'served', served_by = v_me, served_at = now()
     where id = v_item.id;
    if v_item.track_stock then
      insert into public.stock_movements (product_id, type, quantity, tab_item_id, member_id)
      values (v_item.product_id, 'served', -v_item.quantity, v_item.id, v_me);
    end if;
    perform public._recalc_tab(v_item.tab_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

create or replace function public.refuse_items(p_item_ids uuid[], p_reason text default 'Rupture de stock')
returns int language plpgsql security definer set search_path = public as $$
declare v_me uuid := public._require_staff(); v_count int;
begin
  update public.tab_items
     set status = 'refused', removed_by = v_me, removed_at = now(),
         removed_reason = coalesce(nullif(trim(p_reason), ''), 'Rupture de stock')
   where id = any(p_item_ids) and status = 'requested';
  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- Retirer une boisson déjà servie (casse, erreur). p_restock = la bouteille revient en stock.
create or replace function public.remove_item(p_item_id uuid, p_reason text, p_restock boolean default false)
returns int language plpgsql security definer set search_path = public as $$
declare v_me uuid := public._require_staff(); v_item record; v_total int;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Indiquez la raison'; end if;
  select i.*, p.track_stock, t.status as tab_status, t.paid_amount
    into v_item
  from public.tab_items i
  join public.products p on p.id = i.product_id
  join public.tabs t on t.id = i.tab_id
  where i.id = p_item_id
  for update of i;
  if not found then raise exception 'Boisson introuvable'; end if;
  if v_item.status <> 'served' then raise exception 'Seule une boisson servie peut être retirée'; end if;
  if v_item.tab_status not in ('open', 'to_pay') then raise exception 'Cette note est déjà clôturée'; end if;

  update public.tab_items
     set status = 'removed', removed_by = v_me, removed_at = now(), removed_reason = trim(p_reason)
   where id = p_item_id;

  if p_restock and v_item.track_stock then
    insert into public.stock_movements (product_id, type, quantity, tab_item_id, reason, member_id)
    values (v_item.product_id, 'return', v_item.quantity, v_item.id, trim(p_reason), v_me);
  end if;

  v_total := public._recalc_tab(v_item.tab_id);
  if v_total < v_item.paid_amount then
    raise exception 'Le total deviendrait inférieur à ce qui a déjà été payé';
  end if;
  return v_total;
end $$;

-- ---------------------------------------------------------------------
-- Encaissement (gérant) · paiement en une ou plusieurs fois
-- ---------------------------------------------------------------------
create or replace function public.record_payment(p_tab_id uuid, p_method text, p_amount int, p_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me uuid := public._require_staff(); v_tab public.tabs; v_id uuid := coalesce(p_id, gen_random_uuid());
        v_remaining int;
begin
  select * into v_tab from public.tabs where id = p_tab_id for update;
  if not found then raise exception 'Note introuvable'; end if;

  if not exists (select 1 from public.payments where id = v_id) then
    if v_tab.status <> 'to_pay' then
      raise exception 'Cette note n''attend pas d''encaissement';
    end if;
    if p_method not in ('cash', 'mobile_money') then raise exception 'Mode de paiement inconnu'; end if;
    v_remaining := v_tab.total - v_tab.paid_amount;
    if p_amount is null or p_amount <= 0 then raise exception 'Montant invalide'; end if;
    if p_amount > v_remaining then
      raise exception 'Montant trop élevé : il reste % FCFA à payer', v_remaining;
    end if;

    insert into public.payments (id, tab_id, night_id, method, amount, received_by)
    values (v_id, p_tab_id, v_tab.night_id, p_method, p_amount, v_me);

    update public.tabs set paid_amount = paid_amount + p_amount where id = p_tab_id
    returning * into v_tab;

    if v_tab.paid_amount >= v_tab.total then
      update public.tabs set status = 'paid', paid_at = now(), cashier_id = v_me,
                             ticket_number = nextval('public.ticket_seq')
       where id = p_tab_id
      returning * into v_tab;
    end if;
  end if;

  return jsonb_build_object('status', v_tab.status, 'total', v_tab.total,
                            'paid', v_tab.paid_amount, 'remaining', v_tab.total - v_tab.paid_amount,
                            'ticket_number', v_tab.ticket_number);
end $$;

-- Annuler une note. Une note payée (ou partiellement payée) : patron seulement.
create or replace function public.cancel_tab(p_tab_id uuid, p_reason text, p_restock boolean default true)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := public._require_staff(); v_tab public.tabs; v_item record;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'Indiquez la raison'; end if;
  select * into v_tab from public.tabs where id = p_tab_id for update;
  if not found then raise exception 'Note introuvable'; end if;
  if v_tab.status = 'cancelled' then return; end if;
  if (v_tab.status = 'paid' or v_tab.paid_amount > 0) and not public.is_patron() then
    raise exception 'Seul le patron peut annuler une note déjà payée';
  end if;

  if p_restock then
    for v_item in
      select i.* from public.tab_items i join public.products p on p.id = i.product_id
      where i.tab_id = p_tab_id and i.status = 'served' and p.track_stock
    loop
      insert into public.stock_movements (product_id, type, quantity, tab_item_id, reason, member_id)
      values (v_item.product_id, 'return', v_item.quantity, v_item.id, 'Note annulée', v_me);
    end loop;
  end if;

  update public.tab_items set status = 'removed', removed_by = v_me, removed_at = now(),
         removed_reason = 'Note annulée'
   where tab_id = p_tab_id and status = 'requested';

  update public.tabs set status = 'cancelled', cancelled_by = v_me, cancel_reason = trim(p_reason)
   where id = p_tab_id;
end $$;

-- ---------------------------------------------------------------------
-- Caisse et dépenses (gérant)
-- ---------------------------------------------------------------------
create or replace function public.add_cash_movement(p_type text, p_amount int, p_reason text, p_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_me uuid := public._require_staff(); v_id uuid := coalesce(p_id, gen_random_uuid());
        v_night uuid := public.current_night_id();
begin
  if exists (select 1 from public.cash_movements where id = v_id) then return v_id; end if;
  if v_night is null then raise exception 'Aucune soirée ouverte'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Indiquez la raison'; end if;
  insert into public.cash_movements (id, night_id, type, amount, reason, member_id)
  values (v_id, v_night, p_type, p_amount, trim(p_reason), v_me);
  return v_id;
end $$;

create or replace function public.record_expense(p_label text, p_amount int, p_method text default 'cash',
                                                 p_from_till boolean default true, p_category text default null,
                                                 p_supplier_id uuid default null, p_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_me uuid := public._require_staff(); v_id uuid := coalesce(p_id, gen_random_uuid());
        v_night uuid := public.current_night_id();
begin
  if exists (select 1 from public.expenses where id = v_id) then return v_id; end if;
  if p_from_till and v_night is null then
    raise exception 'Aucune soirée ouverte pour payer depuis la caisse';
  end if;
  insert into public.expenses (id, night_id, label, category, amount, method, from_till, supplier_id, member_id)
  values (v_id, v_night, p_label, p_category, p_amount, coalesce(p_method, 'cash'),
          coalesce(p_from_till, true), p_supplier_id, v_me);
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- Stock (gérant)
-- ---------------------------------------------------------------------
create or replace function public.receive_stock(p_product_id uuid, p_quantity int, p_cost_price int default 0,
                                                p_supplier_id uuid default null, p_note text default null,
                                                p_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_me uuid := public._require_staff(); v_id uuid := coalesce(p_id, gen_random_uuid());
begin
  if exists (select 1 from public.stock_entries where id = v_id) then return v_id; end if;
  if not exists (select 1 from public.products where id = p_product_id and track_stock) then
    raise exception 'Boisson introuvable ou sans suivi de stock';
  end if;
  insert into public.stock_entries (id, product_id, quantity, cost_price, supplier_id, note, member_id)
  values (v_id, p_product_id, p_quantity, coalesce(p_cost_price, 0), p_supplier_id, p_note, v_me);
  insert into public.stock_movements (product_id, type, quantity, entry_id, member_id)
  values (p_product_id, 'purchase', p_quantity, v_id, v_me);
  if coalesce(p_cost_price, 0) > 0 then
    update public.products set purchase_price = p_cost_price where id = p_product_id;
  end if;
  return v_id;
end $$;

-- p_type : 'loss' (casse, vol : quantité négative) ou 'adjustment' (correction)
create or replace function public.adjust_stock(p_product_id uuid, p_quantity int, p_type text, p_reason text,
                                               p_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_me uuid := public._require_staff(); v_id uuid := coalesce(p_id, gen_random_uuid());
begin
  if exists (select 1 from public.stock_movements where id = v_id) then return v_id; end if;
  if p_type not in ('loss', 'adjustment') then raise exception 'Type inconnu'; end if;
  if coalesce(p_quantity, 0) = 0 then raise exception 'Quantité invalide'; end if;
  if p_type = 'loss' and p_quantity > 0 then raise exception 'Une perte doit être négative'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Indiquez la raison'; end if;
  insert into public.stock_movements (id, product_id, type, quantity, reason, member_id)
  values (v_id, p_product_id, p_type, p_quantity, trim(p_reason), v_me);
  return v_id;
end $$;

-- p_lines = [{"product_id": "<uuid>", "counted": 12}, ...]
create or replace function public.record_inventory(p_lines jsonb, p_note text default null, p_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public._require_staff(); v_id uuid := coalesce(p_id, gen_random_uuid());
  v_line jsonb; v_pid uuid; v_counted int; v_current int; v_diff int; v_cost int;
  v_nb int := 0; v_ecarts int := 0; v_valeur int := 0;
begin
  if exists (select 1 from public.inventories where id = v_id) then
    return (select to_jsonb(i) from public.inventories i where id = v_id);
  end if;
  insert into public.inventories (id, note, member_id) values (v_id, p_note, v_me);
  for v_line in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
    v_pid := (v_line->>'product_id')::uuid;
    v_counted := (v_line->>'counted')::int;
    continue when v_pid is null or v_counted is null;
    select coalesce(sum(quantity), 0) into v_current from public.stock_movements where product_id = v_pid;
    select purchase_price into v_cost from public.products where id = v_pid;
    v_diff := v_counted - v_current;
    v_nb := v_nb + 1;
    if v_diff <> 0 then
      v_ecarts := v_ecarts + 1;
      v_valeur := v_valeur + v_diff * coalesce(v_cost, 0);
      insert into public.stock_movements (product_id, type, quantity, inventory_id, reason, member_id)
      values (v_pid, 'inventory', v_diff, v_id, 'Inventaire', v_me);
    end if;
  end loop;
  update public.inventories set nb_products = v_nb, nb_ecarts = v_ecarts, ecart_valeur = v_valeur
   where id = v_id;
  return jsonb_build_object('id', v_id, 'nb_products', v_nb, 'nb_ecarts', v_ecarts, 'ecart_valeur', v_valeur);
end $$;

-- ---------------------------------------------------------------------
-- Lectures réservées au patron et au gérant
-- ---------------------------------------------------------------------
-- Stock avec prix d'achat
create or replace function public.stock_overview()
returns table (product_id uuid, category text, name text, quantity int, min_stock int,
               purchase_price int, sale_price int, low boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._require_staff();
  return query
  select p.id, c.name, p.name, coalesce(s.quantity, 0), p.min_stock,
         p.purchase_price, p.sale_price, coalesce(s.quantity, 0) <= p.min_stock
  from public.products p
  left join public.categories c on c.id = p.category_id
  left join public.product_stock s on s.product_id = p.id
  where p.active and p.track_stock
  order by c.sort_order, p.sort_order, p.name;
end $$;

-- Rapport d'une soirée (la soirée en cours si p_night_id est vide)
create or replace function public.night_report(p_night_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_night public.nights; v_id uuid;
begin
  perform public._require_staff();
  v_id := coalesce(p_night_id, public.current_night_id(),
                   (select id from public.nights order by opened_at desc limit 1));
  select * into v_night from public.nights where id = v_id;
  if not found then raise exception 'Soirée introuvable'; end if;

  return jsonb_build_object(
    'night', to_jsonb(v_night),
    'revenue', (select coalesce(sum(total), 0) from public.tabs where night_id = v_id and status = 'paid'),
    'tabs_paid', (select count(*) from public.tabs where night_id = v_id and status = 'paid'),
    'tabs_open', (select count(*) from public.tabs where night_id = v_id and status in ('open', 'to_pay')),
    'tabs_cancelled', (select count(*) from public.tabs where night_id = v_id and status = 'cancelled'),
    'cost', (select coalesce(sum(i.quantity * i.cost_price), 0)
             from public.tab_items i join public.tabs t on t.id = i.tab_id
             where t.night_id = v_id and t.status = 'paid' and i.status = 'served'),
    'payments', (select jsonb_build_object(
                   'cash', coalesce(sum(p.amount) filter (where p.method = 'cash'), 0),
                   'mobile_money', coalesce(sum(p.amount) filter (where p.method = 'mobile_money'), 0))
                 from public.payments p join public.tabs t on t.id = p.tab_id
                 where p.night_id = v_id and t.status = 'paid'),
    'expenses', (select coalesce(sum(amount), 0) from public.expenses where night_id = v_id),
    'by_waitress', (select coalesce(jsonb_agg(w order by w.revenue desc), '[]'::jsonb) from (
        select m.id, m.display_name,
               count(distinct t.id) filter (where t.status = 'paid') as tabs,
               coalesce(sum(i.quantity) filter (where t.status = 'paid' and i.status = 'served'), 0) as items,
               coalesce(sum(i.quantity * i.unit_price) filter (where t.status = 'paid' and i.status = 'served'), 0) as revenue,
               count(distinct t.id) filter (where t.status in ('open', 'to_pay')) as open_tabs,
               coalesce(sum(i.quantity) filter (where i.status = 'removed' and i.served_at is not null), 0) as removed_after_service
        from public.tabs t
        join public.members m on m.id = t.waitress_id
        left join public.tab_items i on i.tab_id = t.id
        where t.night_id = v_id
        group by m.id, m.display_name) w),
    'top_products', (select coalesce(jsonb_agg(x order by x.quantity desc), '[]'::jsonb) from (
        select i.product_name as name, sum(i.quantity) as quantity,
               sum(i.quantity * i.unit_price) as revenue,
               sum(i.quantity * (i.unit_price - i.cost_price)) as margin
        from public.tab_items i join public.tabs t on t.id = i.tab_id
        where t.night_id = v_id and t.status = 'paid' and i.status = 'served'
        group by i.product_name
        order by sum(i.quantity) desc
        limit 15) x)
  );
end $$;

-- ---------------------------------------------------------------------
-- Droits d'exécution
-- ---------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.my_member_id(), public.my_role(), public.is_member(), public.is_patron(), public.is_staff(),
  public.owns_tab(uuid), public.current_night_id(),
  public.open_night(int, uuid), public.close_night(int, int, text),
  public.create_table(text, text, boolean, uuid),
  public.open_tab(uuid, uuid), public.add_items(uuid, jsonb), public.cancel_request(uuid),
  public.request_payment(uuid), public.reopen_tab(uuid),
  public.serve_items(uuid[]), public.refuse_items(uuid[], text), public.remove_item(uuid, text, boolean),
  public.record_payment(uuid, text, int, uuid), public.cancel_tab(uuid, text, boolean),
  public.add_cash_movement(text, int, text, uuid),
  public.record_expense(text, int, text, boolean, text, uuid, uuid),
  public.receive_stock(uuid, int, int, uuid, text, uuid),
  public.adjust_stock(uuid, int, text, text, uuid),
  public.record_inventory(jsonb, text, uuid),
  public.stock_overview(), public.night_report(uuid)
to authenticated;
