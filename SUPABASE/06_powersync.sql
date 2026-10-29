-- =====================================================================
-- HAREM CLUB · Script 06 · Accès de PowerSync (synchronisation hors ligne)
-- AVANT de lancer : remplace CHOISIS_UN_MOT_DE_PASSE par un mot de passe
-- long (lettres + chiffres), que tu recopieras ensuite dans PowerSync.
-- Ne le partage avec personne.
-- =====================================================================

do $$
begin
  create role powersync_role with replication bypassrls login password 'CHOISIS_UN_MOT_DE_PASSE';
exception when duplicate_object then
  raise notice 'powersync_role existe déjà';
end $$;

grant select on all tables in schema public to powersync_role;
alter default privileges in schema public grant select on tables to powersync_role;

do $$
begin
  create publication powersync for all tables;
exception when duplicate_object then
  raise notice 'La publication powersync existe déjà';
end $$;
