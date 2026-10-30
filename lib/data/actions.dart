import 'package:sqlite_async/sqlite_async.dart' show SqliteWriteContext;

import 'base_locale.dart';
import 'membre.dart';

/// Toutes les actions du club.
///
/// Chaque action s'affiche tout de suite sur l'appareil (écriture locale) et
/// part au serveur dans l'ordre, même plus tard si le Wi-Fi est coupé.
/// Le serveur refait les mêmes contrôles : c'est lui qui a le dernier mot.
class Club {
  Club._();

  // ---------------------------------------------------------------- Soirée

  static Future<String?> soireeOuverteId() async {
    final r = await db.getOptional("SELECT id FROM nights WHERE status = 'open' LIMIT 1");
    return r?['id'] as String?;
  }

  static Future<String> ouvrirSoiree(Membre m, int fondDeCaisse) async {
    if (await soireeOuverteId() != null) throw Exception('Une soirée est déjà ouverte.');
    final id = await nouvelId();
    await db.writeTransaction((tx) async {
      await tx.execute(
        "INSERT INTO nights (id, status, opened_by, opened_at, opening_float) VALUES (?, 'open', ?, ?, ?)",
        [id, m.id, maintenantIso(), fondDeCaisse],
      );
      await ajouterOperation(tx, 'open_night', {'p_opening_float': fondDeCaisse, 'p_id': id});
    });
    return id;
  }

  static Future<void> cloturerSoiree(Membre m, int especesComptees, int mobileMoneyCompte, String? note) async {
    final soiree = await soireeOuverteId();
    if (soiree == null) throw Exception('Aucune soirée ouverte.');
    final ouvertes = await db.get(
        "SELECT COUNT(*) AS n FROM tabs WHERE night_id = ? AND status IN ('open', 'to_pay')", [soiree]);
    if (entier(ouvertes['n']) > 0) {
      throw Exception('Des notes sont encore ouvertes : encaissez-les ou annulez-les avant la clôture.');
    }
    await db.writeTransaction((tx) async {
      // Affichage immédiat ; les montants attendus et les écarts arrivent du serveur.
      await tx.execute(
        "UPDATE nights SET status = 'closed', closed_by = ?, closed_at = ?, counted_cash = ?, counted_momo = ?, note = ? WHERE id = ?",
        [m.id, maintenantIso(), especesComptees, mobileMoneyCompte, note, soiree],
      );
      await ajouterOperation(tx, 'close_night',
          {'p_counted_cash': especesComptees, 'p_counted_momo': mobileMoneyCompte, 'p_note': note});
    });
  }

  // ---------------------------------------------------------------- Tables

  static Future<String> creerTable(Membre m, String nom, {String zone = 'salle', bool fixe = false}) async {
    final propre = nom.trim();
    if (propre.isEmpty) throw Exception('Donnez un nom à la table.');
    final existe = await db.getOptional('SELECT id FROM club_tables WHERE lower(name) = lower(?)', [propre]);
    if (existe != null) throw Exception('Une table porte déjà ce nom.');
    final id = await nouvelId();
    final ordre = await db.get('SELECT COALESCE(MAX(sort_order), 0) + 1 AS o FROM club_tables');
    await db.writeTransaction((tx) async {
      await tx.execute(
        'INSERT INTO club_tables (id, name, zone, is_fixed, active, sort_order, created_by, created_at) '
        'VALUES (?, ?, ?, ?, 1, ?, ?, ?)',
        [id, propre, zone, fixe && m.estStaff ? 1 : 0, entier(ordre['o']), m.id, maintenantIso()],
      );
      await ajouterOperation(tx, 'create_table', {'p_name': propre, 'p_zone': zone, 'p_fixed': fixe, 'p_id': id});
    });
    return id;
  }

  // ---------------------------------------------------------------- Notes (serveuse)

  static Future<String> ouvrirNote(Membre m, String tableId) async {
    final soiree = await soireeOuverteId();
    if (soiree == null) throw Exception('La soirée n\'est pas encore ouverte.');
    final occupee = await db.getOptional(
        "SELECT id FROM tabs WHERE table_id = ? AND status IN ('open', 'to_pay') "
        'UNION SELECT current_tab_id FROM club_tables WHERE id = ? AND current_tab_id IS NOT NULL',
        [tableId, tableId]);
    if (occupee != null) throw Exception('Cette table a déjà une note en cours.');
    final id = await nouvelId();
    await db.writeTransaction((tx) async {
      await tx.execute(
        "INSERT INTO tabs (id, night_id, table_id, waitress_id, status, total, paid_amount, opened_at) "
        "VALUES (?, ?, ?, ?, 'open', 0, 0, ?)",
        [id, soiree, tableId, m.id, maintenantIso()],
      );
      await ajouterOperation(tx, 'open_tab', {'p_table_id': tableId, 'p_id': id});
    });
    return id;
  }

  /// [quantites] : identifiant de la boisson → nombre.
  static Future<void> envoyerAuBar(Membre m, String tabId, Map<String, int> quantites) async {
    final choix = {
      for (final e in quantites.entries)
        if (e.value > 0) e.key: e.value
    };
    if (choix.isEmpty) return;
    final note = await db.getOptional('SELECT status FROM tabs WHERE id = ?', [tabId]);
    if (note == null || note['status'] != 'open') throw Exception('Cette note n\'est plus ouverte.');

    final lignes = <Map<String, dynamic>>[];
    await db.writeTransaction((tx) async {
      for (final e in choix.entries) {
        final p = await tx.getOptional('SELECT name, sale_price FROM products WHERE id = ? AND active = 1', [e.key]);
        if (p == null) continue;
        final id = (await tx.get('SELECT uuid() AS id'))['id'] as String;
        await tx.execute(
          'INSERT INTO tab_items (id, tab_id, product_id, product_name, quantity, unit_price, status, requested_at, requested_by) '
          "VALUES (?, ?, ?, ?, ?, ?, 'requested', ?, ?)",
          [id, tabId, e.key, p['name'], e.value, entier(p['sale_price']), maintenantIso(), m.id],
        );
        lignes.add({'id': id, 'product_id': e.key, 'quantity': e.value});
      }
      if (lignes.isNotEmpty) {
        await ajouterOperation(tx, 'add_items', {'p_tab_id': tabId, 'p_items': lignes});
      }
    });
  }

  /// Le gérant enregistre des boissons déjà servies (il les donne en même temps).
  /// Le stock est baissé par le serveur (fonction serve_items), comme pour un service classique.
  /// [quantites] : identifiant de la boisson → nombre.
  static Future<void> ajouterServi(Membre m, String tabId, Map<String, int> quantites) async {
    final choix = {
      for (final e in quantites.entries)
        if (e.value > 0) e.key: e.value
    };
    if (choix.isEmpty) return;
    final note = await db.getOptional('SELECT status FROM tabs WHERE id = ?', [tabId]);
    if (note == null || note['status'] != 'open') throw Exception('Cette note n\'est plus ouverte.');

    final lignes = <Map<String, dynamic>>[];
    final ids = <String>[];
    await db.writeTransaction((tx) async {
      for (final e in choix.entries) {
        final p = await tx.getOptional('SELECT name, sale_price FROM products WHERE id = ? AND active = 1', [e.key]);
        if (p == null) continue;
        final id = (await tx.get('SELECT uuid() AS id'))['id'] as String;
        await tx.execute(
          'INSERT INTO tab_items (id, tab_id, product_id, product_name, quantity, unit_price, status, '
          'requested_at, requested_by, served_by, served_at) '
          "VALUES (?, ?, ?, ?, ?, ?, 'served', ?, ?, ?, ?)",
          [id, tabId, e.key, p['name'], e.value, entier(p['sale_price']), maintenantIso(), m.id, m.id, maintenantIso()],
        );
        lignes.add({'id': id, 'product_id': e.key, 'quantity': e.value});
        ids.add(id);
      }
      if (lignes.isNotEmpty) {
        // Le serveur rejoue l'ajout puis le service (qui baisse le stock), dans l'ordre.
        await ajouterOperation(tx, 'add_items', {'p_tab_id': tabId, 'p_items': lignes});
        await ajouterOperation(tx, 'serve_items', {'p_item_ids': ids});
      }
      await _recalculer(tx, tabId);
    });
  }

  static Future<void> annulerDemande(String itemId) async {
    final i = await db.getOptional('SELECT status FROM tab_items WHERE id = ?', [itemId]);
    if (i == null || i['status'] != 'requested') throw Exception('Cette boisson a déjà été traitée par le bar.');
    await db.writeTransaction((tx) async {
      await tx.execute(
        "UPDATE tab_items SET status = 'removed', removed_at = ?, removed_reason = 'Annulée avant service' WHERE id = ?",
        [maintenantIso(), itemId],
      );
      await ajouterOperation(tx, 'cancel_request', {'p_item_id': itemId});
    });
  }

  /// La note part au gérant. Renvoie le montant à annoncer au client.
  static Future<int> demanderEncaissement(String tabId) async {
    final attente = await db.get(
        "SELECT COUNT(*) AS n FROM tab_items WHERE tab_id = ? AND status = 'requested'", [tabId]);
    if (entier(attente['n']) > 0) throw Exception('Des boissons attendent encore le bar.');
    final total = await _total(db, tabId);
    if (total == 0) throw Exception('La note est vide.');
    await db.writeTransaction((tx) async {
      await tx.execute(
        "UPDATE tabs SET status = 'to_pay', total = ?, requested_at = ? WHERE id = ? AND status = 'open'",
        [total, maintenantIso(), tabId],
      );
      await ajouterOperation(tx, 'request_payment', {'p_tab_id': tabId});
    });
    return total;
  }

  static Future<void> rouvrirNote(String tabId) async {
    final t = await db.getOptional('SELECT status, paid_amount FROM tabs WHERE id = ?', [tabId]);
    if (t == null || t['status'] != 'to_pay') return;
    if (entier(t['paid_amount']) > 0) throw Exception('Un paiement a déjà été reçu sur cette note.');
    await db.writeTransaction((tx) async {
      await tx.execute("UPDATE tabs SET status = 'open', requested_at = NULL WHERE id = ?", [tabId]);
      await ajouterOperation(tx, 'reopen_tab', {'p_tab_id': tabId});
    });
  }

  // ---------------------------------------------------------------- Bar (gérant)

  static Future<void> servir(Membre m, List<String> itemIds) async {
    if (itemIds.isEmpty) return;
    await db.writeTransaction((tx) async {
      final notes = <String>{};
      for (final id in itemIds) {
        final i = await tx.getOptional("SELECT tab_id FROM tab_items WHERE id = ? AND status = 'requested'", [id]);
        if (i == null) continue;
        await tx.execute(
            "UPDATE tab_items SET status = 'served', served_by = ?, served_at = ? WHERE id = ?",
            [m.id, maintenantIso(), id]);
        notes.add(i['tab_id'] as String);
      }
      for (final n in notes) {
        await _recalculer(tx, n);
      }
      await ajouterOperation(tx, 'serve_items', {'p_item_ids': itemIds});
    });
  }

  static Future<void> refuser(Membre m, List<String> itemIds, String raison) async {
    if (itemIds.isEmpty) return;
    await db.writeTransaction((tx) async {
      for (final id in itemIds) {
        await tx.execute(
          "UPDATE tab_items SET status = 'refused', removed_by = ?, removed_at = ?, removed_reason = ? "
          "WHERE id = ? AND status = 'requested'",
          [m.id, maintenantIso(), raison, id],
        );
      }
      await ajouterOperation(tx, 'refuse_items', {'p_item_ids': itemIds, 'p_reason': raison});
    });
  }

  static Future<void> retirerBoisson(Membre m, String itemId, String raison, {bool remettreEnStock = false}) async {
    if (raison.trim().isEmpty) throw Exception('Indiquez la raison.');
    final i = await db.getOptional('SELECT tab_id, status FROM tab_items WHERE id = ?', [itemId]);
    if (i == null || i['status'] != 'served') throw Exception('Seule une boisson servie peut être retirée.');
    await db.writeTransaction((tx) async {
      await tx.execute(
        "UPDATE tab_items SET status = 'removed', removed_by = ?, removed_at = ?, removed_reason = ? WHERE id = ?",
        [m.id, maintenantIso(), raison.trim(), itemId],
      );
      await _recalculer(tx, i['tab_id'] as String);
      await ajouterOperation(tx, 'remove_item',
          {'p_item_id': itemId, 'p_reason': raison.trim(), 'p_restock': remettreEnStock});
    });
  }

  // ---------------------------------------------------------------- Encaissement (gérant)

  /// Enregistre un paiement (une partie ou la totalité). Renvoie ce qui reste à payer.
  static Future<int> encaisser(Membre m, String tabId, String methode, int montant) async {
    final t = await db.getOptional('SELECT status, total, paid_amount FROM tabs WHERE id = ?', [tabId]);
    if (t == null || t['status'] != 'to_pay') throw Exception('Cette note n\'attend pas d\'encaissement.');
    final reste = entier(t['total']) - entier(t['paid_amount']);
    if (montant <= 0) throw Exception('Montant invalide.');
    if (montant > reste) throw Exception('Montant trop élevé : il reste $reste FCFA à payer.');
    final id = await nouvelId();
    final nouveauReste = reste - montant;
    await db.writeTransaction((tx) async {
      final soiree = (await tx.get('SELECT night_id FROM tabs WHERE id = ?', [tabId]))['night_id'];
      await tx.execute(
        'INSERT INTO payments (id, tab_id, night_id, method, amount, received_by, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [id, tabId, soiree, methode, montant, m.id, maintenantIso()],
      );
      if (nouveauReste == 0) {
        await tx.execute(
          "UPDATE tabs SET paid_amount = paid_amount + ?, status = 'paid', paid_at = ?, cashier_id = ? WHERE id = ?",
          [montant, maintenantIso(), m.id, tabId],
        );
      } else {
        await tx.execute('UPDATE tabs SET paid_amount = paid_amount + ? WHERE id = ?', [montant, tabId]);
      }
      await ajouterOperation(tx, 'record_payment',
          {'p_tab_id': tabId, 'p_method': methode, 'p_amount': montant, 'p_id': id});
    });
    return nouveauReste;
  }

  static Future<void> annulerNote(Membre m, String tabId, String raison, {bool remettreEnStock = true}) async {
    if (raison.trim().isEmpty) throw Exception('Indiquez la raison.');
    final t = await db.getOptional('SELECT status, paid_amount FROM tabs WHERE id = ?', [tabId]);
    if (t == null) throw Exception('Note introuvable.');
    if ((t['status'] == 'paid' || entier(t['paid_amount']) > 0) && !m.estPatron) {
      throw Exception('Seul le patron peut annuler une note déjà payée.');
    }
    await db.writeTransaction((tx) async {
      await tx.execute(
          "UPDATE tabs SET status = 'cancelled', cancelled_by = ?, cancel_reason = ? WHERE id = ?",
          [m.id, raison.trim(), tabId]);
      await tx.execute(
          "UPDATE tab_items SET status = 'removed', removed_reason = 'Note annulée' WHERE tab_id = ? AND status = 'requested'",
          [tabId]);
      await ajouterOperation(tx, 'cancel_tab',
          {'p_tab_id': tabId, 'p_reason': raison.trim(), 'p_restock': remettreEnStock});
    });
  }

  // ---------------------------------------------------------------- Caisse et dépenses

  static Future<void> mouvementCaisse(Membre m, String type, int montant, String raison) async {
    final soiree = await soireeOuverteId();
    if (soiree == null) throw Exception('Aucune soirée ouverte.');
    if (montant <= 0) throw Exception('Montant invalide.');
    if (raison.trim().isEmpty) throw Exception('Indiquez la raison.');
    final id = await nouvelId();
    await db.writeTransaction((tx) async {
      await tx.execute(
        'INSERT INTO cash_movements (id, night_id, type, amount, reason, member_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [id, soiree, type, montant, raison.trim(), m.id, maintenantIso()],
      );
      await ajouterOperation(tx, 'add_cash_movement',
          {'p_type': type, 'p_amount': montant, 'p_reason': raison.trim(), 'p_id': id});
    });
  }

  static Future<void> depense(Membre m, String libelle, int montant,
      {String methode = 'cash', bool depuisCaisse = true, String? categorie}) async {
    final soiree = await soireeOuverteId();
    if (depuisCaisse && soiree == null) throw Exception('Aucune soirée ouverte pour payer depuis la caisse.');
    if (montant <= 0) throw Exception('Montant invalide.');
    if (libelle.trim().isEmpty) throw Exception('Indiquez ce qui a été payé.');
    final id = await nouvelId();
    await db.writeTransaction((tx) async {
      await tx.execute(
        'INSERT INTO expenses (id, night_id, label, category, amount, method, from_till, member_id, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, soiree, libelle.trim(), categorie, montant, methode, depuisCaisse ? 1 : 0, m.id, maintenantIso()],
      );
      await ajouterOperation(tx, 'record_expense', {
        'p_label': libelle.trim(),
        'p_amount': montant,
        'p_method': methode,
        'p_from_till': depuisCaisse,
        'p_category': categorie,
        'p_id': id,
      });
    });
  }

  // ---------------------------------------------------------------- Stock

  static Future<void> entreeStock(Membre m, String productId, int quantite, {int prixAchat = 0, String? note}) async {
    if (quantite <= 0) throw Exception('Quantité invalide.');
    final id = await nouvelId();
    await db.writeTransaction((tx) async {
      await tx.execute(
        'INSERT INTO stock_entries (id, product_id, quantity, note, member_id, created_at) VALUES (?, ?, ?, ?, ?, ?)',
        [id, productId, quantite, note, m.id, maintenantIso()],
      );
      await tx.execute(
        "INSERT INTO stock_movements (id, product_id, type, quantity, entry_id, member_id, created_at) "
        "VALUES (uuid(), ?, 'purchase', ?, ?, ?, ?)",
        [productId, quantite, id, m.id, maintenantIso()],
      );
      await ajouterOperation(tx, 'receive_stock', {
        'p_product_id': productId,
        'p_quantity': quantite,
        'p_cost_price': prixAchat,
        'p_note': note,
        'p_id': id,
      });
    });
  }

  /// [type] : 'loss' (casse, vol : quantité négative) ou 'adjustment' (correction).
  static Future<void> ajusterStock(Membre m, String productId, int quantite, String type, String raison) async {
    if (quantite == 0) throw Exception('Quantité invalide.');
    if (type == 'loss' && quantite > 0) quantite = -quantite;
    if (raison.trim().isEmpty) throw Exception('Indiquez la raison.');
    final id = await nouvelId();
    await db.writeTransaction((tx) async {
      await tx.execute(
        'INSERT INTO stock_movements (id, product_id, type, quantity, reason, member_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [id, productId, type, quantite, raison.trim(), m.id, maintenantIso()],
      );
      await ajouterOperation(tx, 'adjust_stock', {
        'p_product_id': productId,
        'p_quantity': quantite,
        'p_type': type,
        'p_reason': raison.trim(),
        'p_id': id,
      });
    });
  }

  /// [comptes] : identifiant de la boisson → quantité comptée.
  static Future<int> inventaire(Membre m, Map<String, int> comptes, {String? note}) async {
    if (comptes.isEmpty) throw Exception('Aucune boisson comptée.');
    final id = await nouvelId();
    var ecarts = 0;
    await db.writeTransaction((tx) async {
      for (final e in comptes.entries) {
        final actuel = entier((await tx.get(
            'SELECT COALESCE(SUM(quantity), 0) AS q FROM stock_movements WHERE product_id = ?', [e.key]))['q']);
        final diff = e.value - actuel;
        if (diff != 0) {
          ecarts++;
          await tx.execute(
            "INSERT INTO stock_movements (id, product_id, type, quantity, inventory_id, reason, member_id, created_at) "
            "VALUES (uuid(), ?, 'inventory', ?, ?, 'Inventaire', ?, ?)",
            [e.key, diff, id, m.id, maintenantIso()],
          );
        }
      }
      await tx.execute(
        'INSERT INTO inventories (id, nb_products, nb_ecarts, note, member_id, created_at) VALUES (?, ?, ?, ?, ?, ?)',
        [id, comptes.length, ecarts, note, m.id, maintenantIso()],
      );
      await ajouterOperation(tx, 'record_inventory', {
        'p_lines': [
          for (final e in comptes.entries) {'product_id': e.key, 'counted': e.value}
        ],
        'p_note': note,
        'p_id': id,
      });
    });
    return ecarts;
  }

  // ---------------------------------------------------------------- Outils

  static Future<int> _total(dynamic ctx, String tabId) async {
    final r = await ctx.get(
        "SELECT COALESCE(SUM(quantity * unit_price), 0) AS t FROM tab_items WHERE tab_id = ? AND status = 'served'",
        [tabId]);
    return entier(r['t']);
  }

  static Future<void> _recalculer(SqliteWriteContext tx, String tabId) async {
    final total = await _total(tx, tabId);
    await tx.execute('UPDATE tabs SET total = ? WHERE id = ?', [total, tabId]);
  }
}
