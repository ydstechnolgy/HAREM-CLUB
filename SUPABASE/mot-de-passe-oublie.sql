-- =====================================================================
-- HAREM CLUB · Identifiant ou code PIN oublié
-- À utiliser dans Supabase > SQL Editor (toi seul y as accès).
-- =====================================================================

-- 1) RETROUVER UN IDENTIFIANT (liste tous les comptes)
select login, role, display_name from public.members order by role, login;

-- 2) RÉINITIALISER UN CODE PIN
--    Remplace 'ydstech' par l'identifiant du compte,
--    et '123456' par le nouveau code PIN à 6 chiffres.
update auth.users
   set encrypted_password = extensions.crypt('123456', extensions.gen_salt('bf')), updated_at = now()
 where email = 'ydstech' || '@harem-club.invalid';

-- La personne se reconnecte avec son identifiant et le nouveau code PIN.
