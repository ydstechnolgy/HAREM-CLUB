-- =====================================================================
-- HAREM CLUB · Script 11 · Supprimer définitivement un membre (patron)
-- Retire le compte de l'équipe ET son accès (identifiant libéré).
-- Refusé si le membre a déjà travaillé (notes, paiements, stock…) : dans
-- ce cas, on le désactive pour garder l'historique intact.
-- Utilisé depuis Réglages > Équipe > Supprimer. Relançable sans danger.
-- =====================================================================

create or replace function public.delete_member(p_member_id uuid)
returns void language plpgsql security definer set search_path = public, auth as $$
declare v_m public.members; v_uid uuid;
begin
  if not public.is_patron() then raise exception 'Seul le patron peut supprimer un compte'; end if;
  select * into v_m from public.members where id = p_member_id;
  if not found then return; end if;
  if v_m.user_id = auth.uid() then raise exception 'Vous ne pouvez pas supprimer votre propre compte'; end if;
  if v_m.role = 'patron'
     and (select count(*) from public.members where role = 'patron' and id <> p_member_id) = 0 then
    raise exception 'Il doit toujours rester au moins un patron';
  end if;

  v_uid := v_m.user_id;
  begin
    delete from public.members where id = p_member_id;
  exception when foreign_key_violation then
    raise exception 'Ce membre a déjà travaillé (notes, paiements, stock…). '
                    'Impossible de le supprimer sans effacer cet historique : désactivez-le plutôt.';
  end;

  -- Libère l'identifiant en retirant l'accès de connexion
  if v_uid is not null then
    delete from auth.users where id = v_uid;
  end if;
end $$;

revoke execute on function public.delete_member(uuid) from public, anon;
grant execute on function public.delete_member(uuid) to authenticated;
