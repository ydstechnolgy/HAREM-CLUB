-- =====================================================================
-- HAREM CLUB · Script 10 · Changer son propre identifiant et code PIN
-- La personne connectée change ses propres accès (identifiant + PIN).
-- Le patron s'en sert depuis Réglages > Mon identifiant et mon code PIN.
-- La session en cours reste valable ; les nouveaux accès servent à la
-- prochaine connexion. Peut être relancé sans danger.
-- =====================================================================

create or replace function public.change_my_credentials(p_new_login text default null, p_new_pin text default null)
returns text language plpgsql security definer set search_path = public, extensions, auth as $$
declare v_me public.members; v_login text; v_email text;
begin
  select * into v_me from public.members where user_id = auth.uid() and active;
  if v_me is null then raise exception 'Compte non autorisé'; end if;

  -- Code PIN
  if p_new_pin is not null and p_new_pin <> '' then
    if p_new_pin !~ '^[0-9]{6}$' then
      raise exception 'Le code PIN doit contenir exactement 6 chiffres';
    end if;
    update auth.users
       set encrypted_password = extensions.crypt(p_new_pin, extensions.gen_salt('bf')), updated_at = now()
     where id = v_me.user_id;
  end if;

  -- Identifiant
  v_login := v_me.login;
  if p_new_login is not null and lower(trim(p_new_login)) <> v_me.login then
    v_login := lower(trim(p_new_login));
    if v_login !~ '^[a-z0-9._-]{3,30}$' then
      raise exception 'Identifiant invalide : 3 à 30 caractères, lettres minuscules, chiffres, point ou tiret';
    end if;
    if exists (select 1 from public.members where login = v_login and id <> v_me.id) then
      raise exception 'Cet identifiant est déjà utilisé';
    end if;
    v_email := public._login_email(v_login);
    if exists (select 1 from auth.users where email = v_email and id <> v_me.user_id) then
      raise exception 'Cet identifiant est déjà utilisé';
    end if;
    update auth.users set email = v_email, updated_at = now() where id = v_me.user_id;
    update auth.identities
       set identity_data = jsonb_set(identity_data, '{email}', to_jsonb(v_email)), updated_at = now()
     where user_id = v_me.user_id;
    update public.members set login = v_login where id = v_me.id;
  end if;

  return v_login;
end $$;

revoke execute on function public.change_my_credentials(text, text) from public, anon;
grant execute on function public.change_my_credentials(text, text) to authenticated;
