-- =====================================================================
-- HAREM CLUB · Script 09 · Remise à zéro (patron seulement)
-- Efface l'activité : soirées, notes, boissons servies, paiements,
-- dépenses, mouvements de caisse, tables provisoires. Les reçus repartent à 1.
-- Option : remettre aussi le stock à zéro (entrées, pertes, inventaires).
-- Toujours gardés : le menu, les prix, les tables fixes, l'équipe, les réglages.
-- Utilisée depuis le logiciel : Réglages > Remettre à zéro.
-- =====================================================================

create or replace function public.reset_club(p_confirmation text, p_stock boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_notes int; v_soirees int;
begin
  if not public.is_patron() then raise exception 'Seul le patron peut remettre le logiciel à zéro'; end if;
  if coalesce(upper(trim(p_confirmation)), '') <> 'EFFACER' then
    raise exception 'Confirmation incorrecte : tapez EFFACER';
  end if;

  select count(*) into v_notes from public.tabs;
  select count(*) into v_soirees from public.nights;

  if p_stock then
    delete from public.stock_movements where true;
    delete from public.stock_entries where true;
    delete from public.inventories where true;
  else
    -- Le stock reste juste : les sorties déjà comptées sont gardées, sans lien vers les notes effacées.
    update public.stock_movements set tab_item_id = null where tab_item_id is not null;
  end if;

  delete from public.payments where true;
  delete from public.tab_items where true;
  delete from public.tabs where true;
  delete from public.cash_movements where true;
  delete from public.expenses where true;
  delete from public.nights where true;

  update public.club_tables set current_tab_id = null where current_tab_id is not null;
  delete from public.club_tables where not is_fixed;

  perform setval('public.ticket_seq', 1, false);

  return jsonb_build_object('notes_effacees', v_notes, 'soirees_effacees', v_soirees, 'stock_remis_a_zero', p_stock);
end $$;

revoke execute on function public.reset_club(text, boolean) from public, anon;
grant execute on function public.reset_club(text, boolean) to authenticated;
