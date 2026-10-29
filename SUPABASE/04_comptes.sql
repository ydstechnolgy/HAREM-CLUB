-- =====================================================================
-- HAREM CLUB · Script 04 · Les comptes de l'équipe
-- Connexion par identifiant + code PIN à 6 chiffres.
-- Derrière, Supabase utilise une adresse interne « identifiant@harem-club.invalid »
-- qui ne reçoit jamais d'e-mail.
-- =====================================================================

create or replace function public._login_email(p_login text)
returns text language sql immutable as $$
  select lower(trim(p_login)) || '@harem-club.invalid'
$$;

create or replace function public._check_login_pin(p_login text, p_pin text)
returns void language plpgsql immutable as $$
begin
  if lower(trim(coalesce(p_login, ''))) !~ '^[a-z0-9._-]{3,30}$' then
    raise exception 'Identifiant invalide : 3 à 30 caractères, lettres minuscules, chiffres, point ou tiret';
  end if;
  if coalesce(p_pin, '') !~ '^[0-9]{6}$' then
    raise exception 'Le code PIN doit contenir exactement 6 chiffres';
  end if;
end $$;

-- Crée l'utilisateur Supabase (auth) et renvoie son identifiant
create or replace function public._create_auth_user(p_login text, p_pin text)
returns uuid language plpgsql security definer set search_path = public, extensions, auth as $$
declare v_uid uuid := gen_random_uuid(); v_email text := public._login_email(p_login);
begin
  if exists (select 1 from auth.users where email = v_email) then
    raise exception 'Cet identifiant est déjà utilisé';
  end if;
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                          confirmation_token, email_change, email_change_token_new, recovery_token)
  values ('00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated', v_email,
          extensions.crypt(p_pin, extensions.gen_salt('bf')), now(),
          '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(),
          '', '', '', '');
  insert into auth.identities (id, user_id, provider_id, identity_data, provider,
                               last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_uid, v_uid::text,
          jsonb_build_object('sub', v_uid::text, 'email', v_email, 'email_verified', true),
          'email', now(), now(), now());
  return v_uid;
end $$;

-- ---------------------------------------------------------------------
-- Premier compte patron : à lancer UNE fois dans le SQL Editor
--   select public.setup_patron('roland', '123456', 'Roland');
-- Refusé dès qu'un patron existe.
-- ---------------------------------------------------------------------
create or replace function public.setup_patron(p_login text, p_pin text, p_display_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_uid uuid; v_id uuid;
begin
  if exists (select 1 from public.members where role = 'patron') then
    raise exception 'Un patron existe déjà';
  end if;
  perform public._check_login_pin(p_login, p_pin);
  v_uid := public._create_auth_user(p_login, p_pin);
  insert into public.members (user_id, login, role, display_name)
  values (v_uid, lower(trim(p_login)), 'patron', p_display_name)
  returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- Gestion de l'équipe (patron seulement)
-- ---------------------------------------------------------------------
create or replace function public.create_member(p_login text, p_pin text, p_display_name text,
                                                p_role text default 'serveuse', p_phone text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_uid uuid; v_id uuid;
begin
  if not public.is_patron() then raise exception 'Seul le patron peut créer un compte'; end if;
  if p_role not in ('patron', 'gerant', 'serveuse') then raise exception 'Rôle inconnu'; end if;
  if coalesce(trim(p_display_name), '') = '' then raise exception 'Indiquez le nom'; end if;
  perform public._check_login_pin(p_login, p_pin);
  if exists (select 1 from public.members where login = lower(trim(p_login))) then
    raise exception 'Cet identifiant est déjà utilisé';
  end if;
  v_uid := public._create_auth_user(p_login, p_pin);
  insert into public.members (user_id, login, role, display_name, phone)
  values (v_uid, lower(trim(p_login)), p_role, trim(p_display_name), p_phone)
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.set_member_pin(p_member_id uuid, p_pin text)
returns void language plpgsql security definer set search_path = public, extensions, auth as $$
declare v_uid uuid;
begin
  if not public.is_patron() then raise exception 'Seul le patron peut changer un code PIN'; end if;
  if coalesce(p_pin, '') !~ '^[0-9]{6}$' then raise exception 'Le code PIN doit contenir exactement 6 chiffres'; end if;
  select user_id into v_uid from public.members where id = p_member_id;
  if v_uid is null then raise exception 'Compte introuvable'; end if;
  update auth.users set encrypted_password = extensions.crypt(p_pin, extensions.gen_salt('bf')),
                        updated_at = now()
   where id = v_uid;
end $$;

create or replace function public.update_member(p_member_id uuid, p_display_name text,
                                                p_role text, p_phone text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_old public.members;
begin
  if not public.is_patron() then raise exception 'Seul le patron peut modifier un compte'; end if;
  if p_role not in ('patron', 'gerant', 'serveuse') then raise exception 'Rôle inconnu'; end if;
  select * into v_old from public.members where id = p_member_id for update;
  if not found then raise exception 'Compte introuvable'; end if;
  if v_old.role = 'patron' and p_role <> 'patron'
     and (select count(*) from public.members where role = 'patron' and active) <= 1 then
    raise exception 'Il doit toujours rester au moins un patron';
  end if;
  update public.members set display_name = trim(p_display_name), role = p_role, phone = p_phone
   where id = p_member_id;
end $$;

-- Désactiver un compte : la personne ne peut plus rien faire, son historique reste
create or replace function public.set_member_active(p_member_id uuid, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_m public.members;
begin
  if not public.is_patron() then raise exception 'Seul le patron peut activer ou désactiver un compte'; end if;
  select * into v_m from public.members where id = p_member_id for update;
  if not found then raise exception 'Compte introuvable'; end if;
  if not p_active and v_m.user_id = auth.uid() then
    raise exception 'Vous ne pouvez pas désactiver votre propre compte';
  end if;
  if not p_active and v_m.role = 'patron'
     and (select count(*) from public.members where role = 'patron' and active) <= 1 then
    raise exception 'Il doit toujours rester au moins un patron';
  end if;
  update public.members set active = p_active where id = p_member_id;
end $$;

-- ---------------------------------------------------------------------
-- Droits d'exécution
-- ---------------------------------------------------------------------
revoke execute on function public._login_email(text), public._check_login_pin(text, text),
  public._create_auth_user(text, text), public.setup_patron(text, text, text)
  from public, anon, authenticated;

revoke execute on function public.create_member(text, text, text, text, text),
  public.set_member_pin(uuid, text), public.update_member(uuid, text, text, text),
  public.set_member_active(uuid, boolean)
  from public, anon;
grant execute on function public.create_member(text, text, text, text, text),
  public.set_member_pin(uuid, text), public.update_member(uuid, text, text, text),
  public.set_member_active(uuid, boolean)
  to authenticated;
