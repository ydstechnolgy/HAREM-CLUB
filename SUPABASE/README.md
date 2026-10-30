# Base de données Harem Club (Supabase)

Scripts à lancer **dans l'ordre**, une seule fois, dans Supabase > SQL Editor.
Chaque script peut être relancé sans danger s'il y a eu une erreur.

| Script | Contenu |
| --- | --- |
| 01_tables.sql | Les 15 tables : réglages, équipe, tables du club, menu, soirées, notes, boissons, paiements, caisse, dépenses, stock |
| 02_droits.sql | Qui voit quoi : patron (tout), gérant (tout sauf l'équipe), serveuse (ses tables seulement). Prix d'achat cachés |
| 03_fonctions.sql | Soirée, notes, bar (servi / refusé), encaissement en une ou plusieurs fois, caisse, dépenses, stock, inventaire, rapports |
| 04_comptes.sql | Comptes de l'équipe : identifiant + code PIN à 6 chiffres |
| 05_menu_et_tables.sql | Le menu du Harem Club (65 boissons, 8 catégories) et 15 tables de départ |
| 06_powersync.sql | Accès de PowerSync pour la synchronisation (remplacer le mot de passe avant de lancer) |
| 07_synchronisation.sql | Colonne « club » sur chaque table, utilisée par PowerSync. À relancer si le script 02 est relancé |
| 08_tables_occupees.sql | Chaque table indique si une note y est en cours : les serveuses voient les tables prises par leurs collègues |
| 09_remise_a_zero.sql | Remise à zéro par le patron (Réglages > Remettre à zéro) : efface l'activité, garde le menu, les tables et l'équipe |

## Après les scripts

Créer le compte du patron (une seule fois) dans le SQL Editor, avec son propre identifiant et son PIN :

```sql
select public.setup_patron('identifiant', '123456', 'Nom affiché');
```

Ensuite, le patron crée le gérant et les serveuses depuis le logiciel.

## Réglage Supabase

Authentication > Sign In / Providers > Email : désactiver « Allow new users to sign up ».
Les comptes sont créés uniquement par le patron.

## Principales fonctions

| Qui | Fonctions |
| --- | --- |
| Serveuse | open_tab, add_items, cancel_request, request_payment, reopen_tab, create_table |
| Gérant | open_night, close_night, serve_items, refuse_items, remove_item, record_payment, cancel_tab, add_cash_movement, record_expense, receive_stock, adjust_stock, record_inventory, stock_overview, night_report |
| Patron | tout ce que fait le gérant + create_member, set_member_pin, update_member, set_member_active, annuler une note payée |
