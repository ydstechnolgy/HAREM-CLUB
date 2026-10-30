-- =====================================================================
-- HAREM CLUB · Script 08 · Tables occupées visibles par toutes les serveuses
-- Chaque table du club indique la note en cours (sans montant ni détail).
-- Ainsi une serveuse ne peut plus ouvrir une table déjà prise par une collègue.
-- Peut être relancé sans danger.
-- =====================================================================

alter table public.club_tables add column if not exists current_tab_id uuid;

create or replace function public._maj_table_occupee()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_table uuid;
begin
  foreach v_table in array array[new.table_id, case when tg_op = 'UPDATE' then old.table_id end] loop
    continue when v_table is null;
    update public.club_tables
       set current_tab_id = (select t.id from public.tabs t
                             where t.table_id = v_table and t.status in ('open', 'to_pay')
                             order by t.opened_at desc limit 1)
     where id = v_table;
  end loop;
  return new;
end $$;

drop trigger if exists tabs_table_occupee on public.tabs;
create trigger tabs_table_occupee
  after insert or update of status, table_id on public.tabs
  for each row execute function public._maj_table_occupee();

-- Remise à niveau des tables déjà ouvertes
update public.club_tables ct
   set current_tab_id = (select t.id from public.tabs t
                         where t.table_id = ct.id and t.status in ('open', 'to_pay')
                         order by t.opened_at desc limit 1);

grant select (current_tab_id) on public.club_tables to authenticated;
revoke execute on function public._maj_table_occupee() from public, anon, authenticated;
